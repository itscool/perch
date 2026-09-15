import SwiftUI

/// The Desk Lab's backend: one desk saved to a JSON file, with switching,
/// membership and conflicts simulated in memory. It never discovers devices or
/// requests permissions; every outcome here is explicitly staged.
final class DeskSimulation: DeskBackend {
    let wording = DeskWording(badge: "DESK LAB",
                              addComputerHelp: "Add a simulated computer to this demo desk.",
                              presetActivationHelp: "Switch to this preset now. The Desk Lab simulates the switch.")
    let store: URL
    private(set) var loaded: KVMGroup
    private(set) var loadProblem: String?
    /// Stage a failed monitor confirmation on the next preset switch.
    var failNextSwitch = false
    private(set) weak var model: DeskModel?
    private var identifying: UUID?
    private var identifyGeneration = UUID()

    init(store: URL) {
        self.store = store
        loaded = KVMGroup.sample()
        if FileManager.default.fileExists(atPath: store.path) {
            do {
                let size = try store.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 512 * 1024 else { throw KVMError("The saved demo is too large.") }
                loaded = try JSONDecoder().decode(KVMGroup.self, from: Data(contentsOf: store)).validated()
            } catch { loadProblem = "Could not open the saved demo: \(error.localizedDescription). The original file has been preserved." }
        }
    }
    /// The page model over this simulation. The model owns the simulation.
    func makeModel() -> DeskModel {
        let model = DeskModel(backend: self, group: loaded)
        model.problem = loadProblem
        self.model = model
        return model
    }

    // MARK: DeskBackend
    func edit(_ group: KVMGroup) throws {
        guard loadProblem == nil else { throw KVMError("Use a new demo file before editing; the unreadable original is preserved.") }
        let bytes = try JSONEncoder().encode(group)
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: store, options: [.atomic])
    }
    func readiness(preset id: UUID) -> String? {
        guard let model, let preset = model.group.presets.first(where: { $0.id == id }) else { return "This preset was removed." }
        if loadProblem != nil { return "The saved demo couldn't be opened. Its original file is preserved." }
        if model.conflict != nil { return "Review the competing desk changes before using a preset." }
        if preset.assignments.isEmpty { return "Click a monitor input to include a screen in this preset." }
        let group = model.group
        var needed = Set(preset.assignments.compactMap { a in group.connections.first { $0.id == a.connection }?.computer })
        needed.insert(group.computers[0].id)
        let missing = group.computers.filter { needed.contains($0.id) && !model.online.contains($0.id) }.map(\.name)
        return missing.isEmpty ? nil : "\(missing.joined(separator: ", ")) is offline. Reconnect it or choose another preset. Your current control stays as it is."
    }
    func activate(preset id: UUID) {
        guard let model, let preset = model.group.presets.first(where: { $0.id == id }) else { return }
        guard readiness(preset: id) == nil else { model.problem = readiness(preset: id); return }
        let group = model.group
        let focus = model.selected.flatMap { id in preset.assignments.contains { $0.monitor == id } ? id : nil } ?? preset.assignments.first!.monitor
        var handoff = KVMHandoff()
        do {
            let observers = Dictionary(uniqueKeysWithValues: preset.assignments.filter { a in group.connections.contains { $0.id == a.connection && $0.computer == nil } }.map { ($0.monitor, group.computers[0].id) })
            let r = try handoff.begin(group: group, presetID: preset.id, focusMonitor: focus, inputSources: [group.computers[0].id], online: model.online, session: UUID(), now: 100, monitorObservers: observers)
            for peer in r.participants { handoff.participantPrepared(peer, request: r.id, session: r.session, releasedInput: true, now: 101) }
            if failNextSwitch {
                failNextSwitch = false; model.active = nil; model.activeGroup = nil; model.activeFocus = nil
                throw KVMError("\(group.monitors.first { $0.id == focus }?.name ?? "A screen") did not confirm its picture. Control is local in this simulation. Check its input, then try this preset again.")
            }
            for route in r.routes { handoff.observedVisible(connection: route.connection, by: handoff.routeObservers[route.connection]!, request: r.id, session: r.session, now: 102) }
            try handoff.commit(request: r.id, session: r.session, now: 102)
            model.active = preset; model.activeGroup = group; model.activeFocus = r.focusComputer == nil ? nil : model.owner(focus)
            model.notice = model.activeFocus.map { "\(preset.name) is active in the demo. Input goes to \($0)." } ?? "\(preset.name) switched the demo picture. Its selected screen has an unassigned connection, so input stays local."
            model.problem = nil
        } catch { model.problem = error.localizedDescription }
    }
    func retryActive() { if let model { activate(preset: model.preset.id) } }
    func revertSwitch() { model?.activeUnconfirmed = false }
    func switchConnection(_ connection: UUID) { model?.notice = "Switching a single monitor input is not simulated. Use a preset." }

    func mappingOptions() -> [DeskMappingOption] { [] }
    func map(port: UUID, option: String) {}
    /// A simulated computer reports its display as soon as a cable is saved.
    func mapComputer(port: UUID, computer: UUID) {
        guard let model, model.group.connections.first(where: { $0.id == port })?.computer != computer else { return }
        model.edit { g in if let i = g.connections.firstIndex(where: { $0.id == port }) {
            g.connections[i].computer = computer; g.connections[i].localDisplay = UUID().uuidString
        } }
    }
    func displayStatus(computer: UUID) -> String? { nil }
    func refreshScreens() {}
    func panelAspect(monitor: UUID) -> Double? { nil }

    func identify(monitor: UUID?) {
        guard let model else { return }
        model.objectWillChange.send()
        if identifying == monitor, identifying != nil { identifyGeneration = UUID(); identifying = nil; return }
        let token = UUID(); identifyGeneration = token; identifying = monitor
        model.notice = "The numbered screen is highlighted in the demo only."
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.identifyGeneration == token else { return }
            self.model?.objectWillChange.send(); self.identifying = nil
        }
    }
    func identifyDisplay(_ display: String, computer: UUID) {}
    func identifyComputer(_ computer: UUID) {}
    func isIdentifying(monitor: UUID) -> Bool { identifying == monitor }
    func isIdentifying(display: String, computer: UUID) -> Bool { false }
    func isIdentifying(computer: UUID) -> Bool { false }
    func peerActionReadiness(computer: UUID, action: String) -> String? { "The Desk Lab does not \(action.lowercased()) on other computers." }

    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView? {
        guard let model else { return nil }
        switch sheet {
        case .cable, .port, .removeScreen, .dimensions: return nil
        default: return AnyView(LabSheet(model: model, simulation: self, sheet: sheet, close: close))
        }
    }

    // MARK: Simulated events
    func toggleOnline(_ id: UUID) {
        guard let model else { return }
        if model.online.contains(id) { model.online.remove(id) } else { model.online.insert(id) }
        if let activeGroup = model.activeGroup, let active = model.active, active.assignments.contains(where: { a in activeGroup.connections.contains { $0.id == a.connection && $0.computer == id } }), !model.online.contains(id) {
            model.active = nil; model.activeGroup = nil; model.activeFocus = nil
            model.problem = "A computer in the active arrangement went offline. Control returned locally in the demo."
        }
    }
    func addComputer(_ name: String) {
        guard let model else { return }
        let c = KVMComputer(name: name); model.edit { $0.computers.append(c) }
        if model.group.computers.contains(c) { model.online.insert(c.id) }
    }
    func addScreen(_ name: String, computer: UUID) {
        guard let model else { return }
        let screen = KVMMonitor(name: name, geometry: .init(x: (model.group.monitors.map { $0.geometry.right }.max() ?? 0), y: 0, width: 550, height: 310))
        model.edit { g in g.monitors.append(screen); g.connections.append(KVMConnection(monitor: screen.id, computer: computer, localDisplay: UUID().uuidString, inputName: "USB-C")) }
        if model.group.monitors.contains(screen) { model.selected = screen.id; model.notice = "\(name) is saved. Choose its computer in each preset; existing presets haven't changed." }
    }
    func addConnection(screen: UUID, computer: UUID?, name: String) {
        model?.edit { $0.connections.append(KVMConnection(monitor: screen, computer: computer, localDisplay: computer == nil ? nil : UUID().uuidString, inputName: name)) }
    }
    func newDesk(_ name: String) {
        guard let model else { return }
        let c = KVMComputer(name: "This Mac")
        model.edit { $0 = KVMGroup(name: name, computers: [c]) }
        guard model.problem == nil else { return }
        model.online = [c.id]; model.selected = nil; model.active = nil; model.activeGroup = nil; model.activeFocus = nil; model.presetIndex = 0
        model.notice = "Your desk is saved. Add another computer, then identify the screens you want to share."
    }
    func simulateConflict() { guard let model else { return }; var other = model.group; other.name = "Studio desk"; model.conflict = other }
    func resolve(useOther: Bool) {
        guard let model, let other = model.conflict else { return }; model.conflict = nil
        model.edit { if useOther { $0 = other } }
        if model.problem != nil { model.conflict = other }
    }
}
