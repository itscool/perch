import SwiftUI

struct DeskMappingOption: Identifiable {
    let id: String
    let label: String
    var computer: UUID? { id.split(separator: "|").first.flatMap { UUID(uuidString: String($0)) } }
    var display: String? { let parts = id.split(separator: "|"); return parts.count == 2 ? String(parts[1]) : nil }
}

/// Control paths are scoped to one physical monitor, never the global list of
/// detected displays. A saved control path can precede its port mapping.
enum DeskControlPaths {
    static func options(group: KVMGroup, monitor: UUID, detected: Set<String>) -> [DeskMappingOption] {
        guard let screen = group.monitors.first(where: { $0.id == monitor }) else { return [] }
        func key(_ computer: UUID, _ display: String) -> String { computer.uuidString + "|" + display }
        var paths: [String: (UUID, [String])] = [:]
        for cable in group.connections where cable.monitor == monitor {
            guard let computer = cable.computer, let display = cable.localDisplay else { continue }
            let id = key(computer, display)
            // Refuse an ambiguous identity also assigned to another physical screen.
            guard !group.connections.contains(where: { $0.monitor != monitor && $0.computer == computer && $0.localDisplay == display }) else { continue }
            var path = paths[id] ?? (computer, [])
            path.1.append(cable.inputName); paths[id] = path
        }
        if let control = screen.control,
           !group.connections.contains(where: { $0.monitor != monitor && $0.computer == control.computer && $0.localDisplay == control.localDisplay }) {
            let id = key(control.computer, control.localDisplay)
            if paths[id] == nil { paths[id] = (control.computer, []) }
        }
        return paths.map { id, path in
            let name = group.computers.first { $0.id == path.0 }?.name ?? "Computer"
            let ports = path.1.isEmpty ? "Port not mapped" : path.1.sorted().joined(separator: " / ")
            return DeskMappingOption(id: id, label: name + " · " + ports + (detected.contains(id) ? "" : " (not currently detected)"))
        }.sorted { $0.label == $1.label ? $0.id < $1.id : $0.label < $1.label }
    }
}

/// A cable changes its computer/port association, never the identity or geometry of a screen.
enum DeskCableBinding {
    /// Move one cable atomically. A display identity belongs to its physical
    /// screen, so crossing to another screen needs fresh identity matching.
    static func rewire(_ source: KVMConnection, to target: KVMConnection, in group: inout KVMGroup) throws {
        guard group.connections.first(where: { $0.id == source.id }) == source,
              group.connections.first(where: { $0.id == target.id }) == target,
              let computer = source.computer else { throw KVMError("This cable changed on another computer. Try moving it again.") }
        guard source.id != target.id else { return }
        var draft = group
        try apply(connection: source.id, computer: nil, display: nil, to: &draft)
        try apply(connection: target.id, computer: computer,
                  display: source.monitor == target.monitor ? source.localDisplay : nil, to: &draft)
        group = draft
    }
    static func apply(connection: UUID, computer: UUID?, display: String?, to group: inout KVMGroup) throws {
        guard let target = group.connections.firstIndex(where: { $0.id == connection }) else { throw KVMError("This port was removed. Select another port.") }
        var draft = group
        if let computer, let display {
            for i in draft.connections.indices where draft.connections[i].computer == computer && draft.connections[i].localDisplay == display && i != target {
                guard draft.connections[i].monitor == draft.connections[target].monitor else {
                    let name = draft.monitors.first { $0.id == draft.connections[i].monitor }?.name ?? "another screen"
                    throw KVMError("That display is already connected to \(name). Disconnect that cable before connecting it to this screen.")
                }
                draft.connections[i].computer = nil; draft.connections[i].localDisplay = nil
            }
        }
        draft.connections[target].computer = computer; draft.connections[target].localDisplay = display
        _ = try draft.validated(); group = draft
    }
}
/// A user-drawn cable may precede display discovery. Resolve only an evidenced,
/// unique cross-computer match for that already chosen physical monitor.
enum DeskPendingCableResolver {
    static func resolve(_ group: KVMGroup, observations: [KVMDisplayObservation]) -> KVMGroup {
        var draft = group
        for index in draft.connections.indices {
            let cable = draft.connections[index]
            guard let computer = cable.computer, cable.localDisplay == nil,
                  draft.connections.filter({ $0.monitor == cable.monitor && $0.computer == computer && $0.localDisplay == nil }).count == 1 else { continue }
            let candidates = observations.filter { observation in
                guard observation.computer == computer,
                      !draft.connections.contains(where: { $0.computer == computer && $0.localDisplay == observation.localDisplay }) else { return false }
                let matches = observation.suggestedMatches(in: observations)
                let physicalScreens = Set(draft.connections.filter { connection in matches.contains { $0.computer == connection.computer && $0.localDisplay == connection.localDisplay } }.map(\.monitor))
                return physicalScreens == [cable.monitor]
            }
            if candidates.count == 1 { draft.connections[index].localDisplay = candidates[0].localDisplay }
        }
        return (try? draft.validated()) == nil ? group : draft
    }
}
struct DeskPortDefinition { let name: String; let code: UInt16 }
enum DeskMonitorConfiguration {
    static func apply(monitor: UUID, profile: String, ports: [DeskPortDefinition], mode: String, to group: inout KVMGroup) throws {
        guard let index = group.monitors.firstIndex(where: { $0.id == monitor }), group.monitors[index].control != nil else { throw KVMError("Choose a monitor control path first.") }
        func key(_ name: String) -> String { name.lowercased().filter { !$0.isWhitespace && $0 != "-" } }
        var draft = group
        guard ports.count <= 16, Set(ports.map { key($0.name) }).count == ports.count else { throw KVMError("The profile has duplicate or too many ports.") }
        for port in ports {
            if let i = draft.connections.firstIndex(where: { $0.monitor == monitor && key($0.inputName) == key(port.name) }) {
                draft.connections[i].inputCode = port.code
            } else {
                draft.connections.append(.init(monitor: monitor, computer: nil, localDisplay: nil, inputName: port.name, inputCode: port.code))
            }
        }
        draft.monitors[index].control?.mode = mode; draft.monitors[index].defaultControlMode = mode; draft.monitors[index].inputProfile = profile
        _ = try draft.validated(); group = draft
    }
}
struct DeskIdentificationState {
    private(set) var active: [String: UUID] = [:]
    mutating func toggle(_ key: String) -> (token: UUID, showing: Bool) {
        if let token = active.removeValue(forKey: key) { return (token, false) }
        let token = UUID(); active[key] = token; return (token, true)
    }
    @discardableResult mutating func expire(_ key: String, token: UUID) -> Bool {
        guard active[key] == token else { return false }; active[key] = nil; return true
    }
}
struct DeskLiveActions {
    let edit: (KVMGroup) throws -> Void
    let activate: (UUID) -> Void
    let readiness: (UUID) -> String?
    let mappingOptions: () -> [DeskMappingOption]
    let map: (UUID, String) -> Void
    let identify: (UUID?) -> Void
    let sheet: (String, UUID?, @escaping () -> Void) -> AnyView
    var identifyDisplay: ((UUID, String) -> Void)? = nil
    var identifyComputer: ((UUID) -> Void)? = nil
    var peerActionReadiness: ((UUID, String) -> String?)? = nil
    var testRemoteControl: ((UUID, UUID) -> Void)? = nil
    var remoteControlReadiness: ((UUID, UUID) -> String?)? = nil
    var localComputer: UUID? = nil
    var identifyingDisplay: ((UUID, String) -> Bool)? = nil
    var identifyingComputer: ((UUID) -> Bool)? = nil
    var identifyingMonitor: ((UUID) -> Bool)? = nil
    var refreshScreens: (() -> Void)? = nil
    var removalIssue: ((UUID) -> String?)? = nil
    var mapComputer: ((UUID, UUID) -> Void)? = nil
    var displayStatus: ((UUID) -> String?)? = nil
    var panelAspect: ((UUID) -> Double?)? = nil
    var switchConnection: ((UUID) -> Void)? = nil
    var forceSwitchConnection: ((UUID) -> Void)? = nil
    var connectionReadiness: ((UUID) -> String?)? = nil
    var refreshMonitorStatus: (() -> Void)? = nil
    var retryMonitorConnection: ((UUID) -> UUID?)? = nil
}

// Interactive product prototype. Never discovers devices or requests permissions.
// All names, readiness, input routes and pairing outcomes are explicitly simulated.
final class DeskModel: ObservableObject {
    static let presetActivationHelp = "Switch the physical monitor inputs. If keyboard and mouse sharing is enabled on the participating Macs, control starts automatically when the preset is ready."
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
    @Published var monitorProblems: Set<UUID> = []
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
        if preset.assignments.isEmpty { return "Click a monitor input to include a screen in this preset." }
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
    func cableOptions(for computer: UUID) -> [DeskMappingOption] {
        live?.mappingOptions().filter { $0.computer == computer } ?? []
    }
    func cableConflict(_ option: DeskMappingOption, port: UUID) -> String? {
        guard let target = group.connections.first(where: { $0.id == port }),
              let existing = group.connections.first(where: { $0.computer == option.computer && $0.localDisplay == option.display && $0.monitor != target.monitor }) else { return nil }
        return "Already connected to " + (group.monitors.first { $0.id == existing.monitor }?.name ?? "another screen")
    }
    func rewireCable(_ source: KVMConnection, to target: KVMConnection) {
        edit { try DeskCableBinding.rewire(source, to: target, in: &$0) }
        if problem == nil { selected = target.monitor }
    }
    func disconnectCable(_ port: UUID) {
        edit { try DeskCableBinding.apply(connection: port, computer: nil, display: nil, to: &$0) }
    }
    func connectionLabel(_ connection: KVMConnection) -> String {
        let computer = group.computers.first { $0.id == connection.computer }
        return connection.inputName + " — " + (computer?.name ?? "Unassigned") + (computer != nil && connection.localDisplay == nil ? " · Display matching pending" : "")
    }
    func owner(_ monitor: UUID, in preset: KVMPreset? = nil) -> String {
        guard let a = (preset ?? self.preset).assignments.first(where: { $0.monitor == monitor }),
              let route = group.connections.first(where: { $0.id == a.connection }) else { return "" }
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
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].geometry.x = x; g.monitors[i].geometry.y = y } }
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
    func assign(_ connection: UUID?, preset index: Int? = nil, monitor explicitMonitor: UUID? = nil) {
        guard let monitor = explicitMonitor ?? selected else { return }
        let index = index ?? presetIndex
        edit { g in g.presets[index].assignments.removeAll { $0.monitor == monitor }; if let connection { g.presets[index].assignments.append(.init(monitor: monitor, connection: connection)) } }
    }
    func assignPresetPort(slot: Int, computer: UUID, connection: UUID) {
        guard (1...3).contains(slot), let port = group.connections.first(where: { $0.id == connection }) else { return }
        guard port.computer == nil || port.computer == computer else {
            problem = "This monitor input belongs to another computer. Choose that computer’s preset port or change the cable first."
            return
        }
        assign(connection, preset: slot - 1, monitor: port.monitor)
    }
    func identify() {
        if let live { live.identify(selected); return }
        if identifying == selected, identifying != nil { identifyGeneration = UUID(); identifying = nil; return }
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
