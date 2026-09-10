import SwiftUI

struct DeskMappingOption: Identifiable { let id: String; let label: String }
struct DeskLiveActions {
    let edit: (KVMGroup) throws -> Void
    let activate: (UUID) -> Void
    let readiness: (UUID) -> String?
    let mappingOptions: () -> [DeskMappingOption]
    let map: (UUID, String) -> Void
    let identify: (UUID?) -> Void
    let sheet: (String, UUID?, @escaping () -> Void) -> AnyView
    var openSettings: (() -> Void)? = nil
}

// Interactive product prototype. Never discovers devices or requests permissions.
// All names, readiness, input routes and pairing outcomes are explicitly simulated.
final class DeskModel: ObservableObject {
    static let presetActivationHelp = "Switch the physical monitor inputs. If keyboard and mouse sharing is enabled, resume it only after the selected screen confirms."
    @Published var live: DeskLiveActions?
    @Published var group: KVMGroup
    @Published var selected: UUID?
    @Published var presetIndex = 0
    @Published var online: Set<UUID> = []
    @Published var notice = "Control is local. Press play on a preset to switch."
    @Published var problem: String?
    @Published var failNextSwitch = false
    @Published var active: KVMPreset?
    @Published var activeGroup: KVMGroup?
    @Published var activeFocus: String?
    @Published var monitorResults: [UUID: String] = [:]
    @Published var identifying: UUID?
    @Published var conflict: KVMGroup?
    let store: URL
    private var loadFailed = false
    private var identifyGeneration = UUID()

    static func sample() -> KVMGroup {
        let mac = KVMComputer(name: "MacBook Pro"), studio = KVMComputer(name: "Mac Studio")
        let left = KVMMonitor(name: "Left screen", geometry: .init(x: 0, y: 30, width: 550, height: 310))
        let main = KVMMonitor(name: "Main screen", geometry: .init(x: 550, y: 0, width: 610, height: 343))
        let side = KVMMonitor(name: "Portrait screen", geometry: .init(x: 1160, y: 0, width: 530, height: 300, rotation: .clockwise))
        var g = KVMGroup(name: "My desk", computers: [mac, studio], monitors: [left, main, side])
        for screen in g.monitors {
            g.connections += [KVMConnection(monitor: screen.id, computer: mac.id, localDisplay: screen.id.uuidString, inputName: "USB-C"),
                              KVMConnection(monitor: screen.id, computer: studio.id, localDisplay: screen.id.uuidString, inputName: "DisplayPort", inputCode: 15)]
        }
        g.connections.append(KVMConnection(monitor: left.id, computer: nil, localDisplay: nil, inputName: "HDMI 1", inputCode: 17))
        g.presets[0].name = "Together"; g.presets[1].name = "All on MacBook"; g.presets[2].name = "All on Studio"
        for i in 0..<3 {
            for (n, screen) in g.monitors.enumerated() {
                let computer = i == 1 || (i == 0 && n == 2) ? mac : studio
                let route = g.connections.first { $0.monitor == screen.id && $0.computer == computer.id }!
                g.presets[i].assignments.append(.init(monitor: screen.id, connection: route.id))
            }
        }
        return g
    }

    init(store: URL) {
        self.store = store
        var loaded = Self.sample()
        if FileManager.default.fileExists(atPath: store.path) {
            do {
                let size = try store.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 512 * 1024 else { throw KVMError("The saved demo is too large.") }
                loaded = try JSONDecoder().decode(KVMGroup.self, from: Data(contentsOf: store)).validated()
            } catch { loadFailed = true; problem = "Could not open the saved demo: \(error.localizedDescription). The original file has been preserved." }
        }
        group = loaded; selected = loaded.monitors.first?.id; online = Set(loaded.computers.map(\.id))
    }
    var preset: KVMPreset { group.presets[presetIndex] }
    var selectedMonitor: KVMMonitor? { group.monitors.first { $0.id == selected } }
    var unsent: Int { group.computers.filter { !online.contains($0.id) }.count }
    var saveStatus: String {
        if live != nil { return unsent == 0 ? "Saved" : "Saved here · waiting for other computers" }
        if loadFailed { return "Could not open saved demo" }
        return unsent == 0 ? "Saved in this demo" : "Saved here · waiting for \(unsent) offline computer\(unsent == 1 ? "" : "s") (simulated)"
    }
    var changedSinceUse: Bool {
        guard let active, let previous = activeGroup else { return false }
        guard let saved = group.presets.first(where: { $0.id == active.id }) else { return true }
        if saved.assignments != active.assignments { return true }
        return active.assignments.contains { a in
            guard let old = previous.connections.first(where: { $0.id == a.connection }), let new = group.connections.first(where: { $0.id == a.connection }) else { return true }
            return previous.monitors.first { $0.id == a.monitor }?.geometry != group.monitors.first { $0.id == a.monitor }?.geometry ||
                old.monitor != new.monitor || old.computer != new.computer || old.localDisplay != new.localDisplay || old.inputCode != new.inputCode
        }
    }
    var readinessIssue: String? {
        readinessIssue(for: presetIndex)
    }
    func readinessIssue(for index: Int) -> String? {
        let preset = group.presets[index]
        if let live { return live.readiness(preset.id) }
        if loadFailed { return "The saved demo couldn't be opened. Its original file is preserved." }
        if conflict != nil { return "Review the competing desk changes before using a preset." }
        if preset.assignments.isEmpty { return "Choose this preset's connections in the screen details." }
        if preset.assignments.count != group.monitors.count { return "Choose a connection for every screen in this preset before using it." }
        var needed = Set(preset.assignments.compactMap { a in group.connections.first { $0.id == a.connection }?.computer })
        needed.insert(group.computers[0].id)
        let missing = group.computers.filter { needed.contains($0.id) && !online.contains($0.id) }.map(\.name)
        return missing.isEmpty ? nil : "\(missing.joined(separator: ", ")) is offline. Reconnect it or choose another preset. Your current control stays as it is."
    }
    var canUse: Bool { readinessIssue == nil }
    func activatePreset(_ index: Int) { presetIndex = index; usePreset() }
    func displayedOwner(_ monitor: UUID) -> String {
        guard let snapshot = activeGroup, let active,
              let assignment = active.assignments.first(where: { $0.monitor == monitor }),
              let route = snapshot.connections.first(where: { $0.id == assignment.connection }) else { return "Not switched" }
        guard let computer = snapshot.computers.first(where: { $0.id == route.computer }) else { return route.inputName + " · Picture only" }
        return computer.name + (online.contains(computer.id) ? "" : " · Offline")
    }
    var unassignedWarning: String? {
        let inputs = preset.assignments.compactMap { a in group.connections.first { $0.id == a.connection && $0.computer == nil }?.inputName }
        return inputs.isEmpty ? nil : "\(inputs.joined(separator: ", ")) has no computer mapped. The picture can switch there; mouse and keyboard stay local for that screen."
    }
    func connectionLabel(_ connection: KVMConnection) -> String {
        let computer = group.computers.first { $0.id == connection.computer }
        return connection.inputName + " — " + (computer?.name ?? "Unassigned")
    }
    func owner(_ monitor: UUID, in preset: KVMPreset? = nil) -> String {
        guard let a = (preset ?? self.preset).assignments.first(where: { $0.monitor == monitor }),
              let route = group.connections.first(where: { $0.id == a.connection }) else { return "Choose connection" }
        guard let computer = group.computers.first(where: { $0.id == route.computer }) else { return route.inputName + " · Unassigned" }
        return computer.name + (online.contains(computer.id) ? "" : " · Offline")
    }
    func edit(_ change: (inout KVMGroup) throws -> Void) {
        guard !loadFailed else { problem = "Use a new demo file before editing; the unreadable original is preserved."; return }
        guard conflict == nil else { problem = "Resolve the two versions of this desk before editing it."; return }
        var draft = group
        do {
            try change(&draft); _ = try draft.validated()
            if let live { try live.edit(draft); group = draft; problem = nil; return }
            let bytes = try JSONEncoder().encode(draft)
            try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: store, options: [.atomic])
            group = draft; problem = nil
        } catch { problem = error.localizedDescription }
    }
    func renameMonitor(_ name: String) { guard let id = selected else { return }; edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].name = name } } }
    func move(_ id: UUID, x: Double, y: Double) {
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].geometry.x = x.rounded(); g.monitors[i].geometry.y = y.rounded() } }
    }
    func rotate(_ rotation: KVMRotation) {
        guard let id = selected else { return }
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].geometry.rotation = rotation } }
    }
    func rotateScreen(_ id: UUID) {
        selected = id
        guard let screen = selectedMonitor else { return }
        rotate(KVMRotation(rawValue: (screen.geometry.rotation.rawValue + 90) % 360)!)
    }
    func resize(width: Double, height: Double) {
        guard let id = selected else { return }
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].geometry.width = width; g.monitors[i].geometry.height = height } }
    }
    func assign(_ connection: UUID?, preset index: Int? = nil) {
        guard let monitor = selected else { return }
        let index = index ?? presetIndex
        edit { g in g.presets[index].assignments.removeAll { $0.monitor == monitor }; if let connection { g.presets[index].assignments.append(.init(monitor: monitor, connection: connection)) } }
    }
    func identify() {
        if let live { live.identify(selected); return }
        let token = UUID(); identifyGeneration = token; identifying = selected
        notice = "The numbered screen is highlighted in the demo only."
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.identifyGeneration == token else { return }; self.identifying = nil
        }
    }
    func usePreset() {
        if let live { live.activate(preset.id); return }
        guard canUse else { problem = readinessIssue; return }
        let focus = selected.flatMap { id in preset.assignments.contains { $0.monitor == id } ? id : nil } ?? preset.assignments.first!.monitor
        var handoff = KVMHandoff()
        do {
            let observers = Dictionary(uniqueKeysWithValues: preset.assignments.filter { a in group.connections.contains { $0.id == a.connection && $0.computer == nil } }.map { ($0.monitor, group.computers[0].id) })
            let r = try handoff.begin(group: group, presetID: preset.id, focusMonitor: focus, inputSources: [group.computers[0].id], online: online, session: UUID(), now: 100, monitorObservers: observers)
            for peer in r.participants { handoff.participantPrepared(peer, request: r.id, session: r.session, releasedInput: true, now: 101) }
            if failNextSwitch {
                failNextSwitch = false; active = nil; activeGroup = nil; activeFocus = nil
                throw KVMError("\(group.monitors.first { $0.id == focus }?.name ?? "A screen") did not confirm its picture. Control is local in this simulation. Check its input, then try this preset again.")
            }
            for route in r.routes { handoff.observedVisible(connection: route.connection, by: handoff.routeObservers[route.connection]!, request: r.id, session: r.session, now: 102) }
            try handoff.commit(request: r.id, session: r.session, now: 102)
            active = preset; activeGroup = group; activeFocus = r.focusComputer == nil ? nil : owner(focus)
            notice = activeFocus.map { "\(preset.name) is active in the demo. Input goes to \($0)." } ?? "\(preset.name) switched the demo picture. Its selected screen has an unassigned connection, so input stays local."; problem = nil
        } catch { problem = error.localizedDescription }
    }
    func toggleOnline(_ id: UUID) {
        if online.contains(id) { online.remove(id) } else { online.insert(id) }
        if let activeGroup, let active, active.assignments.contains(where: { a in activeGroup.connections.contains { $0.id == a.connection && $0.computer == id } }), !online.contains(id) {
            self.active = nil; self.activeGroup = nil; activeFocus = nil; problem = "A computer in the active arrangement went offline. Control returned locally in the demo."
        }
    }
    func addComputer(_ name: String) { let c = KVMComputer(name: name); edit { $0.computers.append(c) }; if group.computers.contains(c) { online.insert(c.id) } }
    func addScreen(_ name: String, computer: UUID) {
        let screen = KVMMonitor(name: name, geometry: .init(x: (group.monitors.map { $0.geometry.right }.max() ?? 0), y: 0, width: 550, height: 310))
        edit { g in g.monitors.append(screen); g.connections.append(KVMConnection(monitor: screen.id, computer: computer, localDisplay: UUID().uuidString, inputName: "USB-C")) }
        if group.monitors.contains(screen) { selected = screen.id; notice = "\(name) is saved. Choose its computer in each preset; existing presets haven't changed." }
    }
    func addConnection(screen: UUID, computer: UUID?, name: String) {
        edit { $0.connections.append(KVMConnection(monitor: screen, computer: computer, localDisplay: computer == nil ? nil : UUID().uuidString, inputName: name)) }
    }
    func mapConnection(_ id: UUID, computer: UUID?) {
        guard group.connections.first(where: { $0.id == id })?.computer != computer else { return }
        edit { g in if let i = g.connections.firstIndex(where: { $0.id == id }) {
            g.connections[i].computer = computer; g.connections[i].localDisplay = computer == nil ? nil : UUID().uuidString
        } }
    }
    func changeConnection(_ id: UUID, input: String) {
        edit { g in if let i = g.connections.firstIndex(where: { $0.id == id }) { g.connections[i].inputName = input } }
    }
    func correctConnection(_ id: UUID, physicalScreen: UUID?) {
        edit { g in
            guard let i = g.connections.firstIndex(where: { $0.id == id }) else { throw KVMError("This connection was removed.") }
            let target: UUID
            if let physicalScreen { target = physicalScreen }
            else {
                let screen = KVMMonitor(name: "Separate screen", geometry: .init(x: g.monitors.map { $0.geometry.right }.max() ?? 0, y: 0, width: 550, height: 310))
                g.monitors.append(screen); target = screen.id
            }
            g.connections[i].monitor = target
            // No implicit ownership decision if the target already belongs to a preset.
            for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == id } }
        }
        if problem == nil { notice = "The physical screen was corrected. Choose its assignment in each preset; other connections are kept." }
    }
    func removeConnection(_ id: UUID) {
        edit { g in g.connections.removeAll { $0.id == id }; for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == id } } }
    }
    func removeScreen(_ id: UUID) {
        edit { $0.removeMonitor(id) }
        guard problem == nil else { return }
        selected = group.monitors.first?.id
        if active?.assignments.contains(where: { $0.monitor == id }) == true { active = nil; activeGroup = nil; activeFocus = nil; notice = "Screen removed. Control returned locally in the demo." }
    }
    func removeComputer(_ id: UUID) {
        edit { try $0.removeComputer(id) }
        guard problem == nil else { return }
        online.remove(id); active = nil; activeGroup = nil; activeFocus = nil
        notice = "Computer removed. Control returned locally in the demo."
    }
    func newDesk(_ name: String) {
        let c = KVMComputer(name: "This Mac")
        edit { $0 = KVMGroup(name: name, computers: [c]) }
        guard problem == nil else { return }
        online = [c.id]; selected = nil; active = nil; activeGroup = nil; activeFocus = nil; presetIndex = 0
        notice = "Your desk is saved. Add another computer, then identify the screens you want to share."
    }
    func simulateConflict() { var other = group; other.name = "Studio desk"; conflict = other }
    func resolve(useOther: Bool) {
        guard let other = conflict else { return }; conflict = nil
        edit { if useOther { $0 = other } }
        if problem != nil { conflict = other }
    }
}
