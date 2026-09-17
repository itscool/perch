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
    /// Apply an identification session received from another Perch in the
    /// same desk. The token makes an old stop event harmless after a newer
    /// identification has started.
    mutating func apply(_ key: String, token: UUID, showing: Bool) {
        if showing {
            active[key] = token
        } else if active[key] == nil || active[key] == token {
            active[key] = nil
        }
    }
    @discardableResult mutating func expire(_ key: String, token: UUID) -> Bool {
        guard active[key] == token else { return false }; active[key] = nil; return true
    }
}
/// The desk as the page sees it: the saved group, the selection, and facts the
/// backend reports (control, cautions, problems, conflicts). Every action goes
/// through the backend; the model only validates drafts and keeps state.
final class DeskModel: ObservableObject {
    let backend: DeskBackend
    @Published var group: KVMGroup
    @Published var selected: UUID?
    @Published var presetIndex = 0
    @Published var online: Set<UUID> = []
    @Published var notice = "Control is local. Press play on a preset to switch."
    /// Actionable failure of the last action; sheets show it and stay open.
    @Published var problem: String?
    @Published var status: String?
    @Published var caution: String?
    @Published var switchingPreset: UUID?
    @Published var activeUnconfirmed = false
    @Published var active: KVMPreset?
    @Published var activeGroup: KVMGroup?
    @Published var activeFocus: String?
    @Published var monitorResults: [UUID: String] = [:]
    @Published var monitorProblems: Set<UUID> = []
    @Published var conflict: KVMGroup?

    init(backend: DeskBackend, group: KVMGroup) {
        self.backend = backend
        self.group = group; selected = group.monitors.first?.id; online = Set(group.computers.map(\.id))
    }
    var preset: KVMPreset { group.presets[presetIndex] }
    var selectedMonitor: KVMMonitor? { group.monitors.first { $0.id == selected } }
    var unsent: Int { group.computers.filter { !online.contains($0.id) }.count }
    var saveStatus: String { unsent == 0 ? "Saved" : "Saved here · waiting for other computers" }
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
    var readinessIssue: String? { readinessIssue(for: presetIndex) }
    func readinessIssue(for index: Int) -> String? { backend.readiness(preset: group.presets[index].id) }
    var canUse: Bool { readinessIssue == nil }
    func activatePreset(_ index: Int) { presetIndex = index; usePreset() }
    func usePreset() { backend.activate(preset: preset.id) }
    func identify() { backend.identify(monitor: selected) }
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
        backend.mappingOptions().filter { $0.computer == computer }
    }
    func cableConflict(_ option: DeskMappingOption, port: UUID) -> String? {
        guard let target = group.connections.first(where: { $0.id == port }),
              let existing = group.connections.first(where: { $0.computer == option.computer && $0.localDisplay == option.display && $0.monitor != target.monitor }) else { return nil }
        return "Already connected to " + (group.monitors.first { $0.id == existing.monitor }?.name ?? "another screen")
    }
    /// Move a detached connection's monitor end to another input. Its computer
    /// and every preset route go with it; a different computer already on the
    /// target input is replaced, taking that input's routes with it.
    func moveWire(from sourceID: UUID, to targetID: UUID) {
        guard let source = group.connections.first(where: { $0.id == sourceID }),
              let target = group.connections.first(where: { $0.id == targetID }), sourceID != targetID else { return }
        edit { g in
            if let owner = target.computer, owner != source.computer {
                for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == targetID } }
            }
            try DeskCableBinding.rewire(source, to: target, in: &g)
            for p in g.presets.indices where g.presets[p].assignments.contains(where: { $0.connection == sourceID }) {
                g.presets[p].assignments.removeAll { $0.connection == sourceID || $0.monitor == target.monitor }
                g.presets[p].assignments.append(.init(monitor: target.monitor, connection: targetID))
            }
        }
        if problem == nil { selected = target.monitor }
    }
    /// A detached connection dropped in empty space disappears: the input loses
    /// its computer and no preset uses it any more.
    func removeWire(_ portID: UUID) {
        edit { g in
            for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == portID } }
            try DeskCableBinding.apply(connection: portID, computer: nil, display: nil, to: &g)
        }
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
    /// Validate a draft, hand it to the backend to save, then adopt it. A
    /// refused or invalid draft leaves the desk as it was and names the reason.
    func edit(_ change: (inout KVMGroup) throws -> Void) {
        guard conflict == nil else { problem = "Resolve the two versions of this desk before editing it."; return }
        var draft = group
        do {
            try change(&draft); _ = try draft.validated()
            try backend.edit(draft); group = draft; problem = nil
        } catch { problem = error.localizedDescription }
    }
    func renameMonitor(_ name: String) { guard let id = selected else { return }; edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) { g.monitors[i].name = name } } }
    func move(_ id: UUID, x: Double, y: Double) {
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) {
            g.monitors[i].geometry.x = KVMGeometry.millimetres(x)
            g.monitors[i].geometry.y = KVMGeometry.millimetres(y)
        } }
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
        edit { g in if let i = g.monitors.firstIndex(where: { $0.id == id }) {
            g.monitors[i].geometry.width = KVMGeometry.millimetres(width)
            g.monitors[i].geometry.height = KVMGeometry.millimetres(height)
        } }
    }
    func assign(_ connection: UUID?, preset index: Int? = nil, monitor explicitMonitor: UUID? = nil) {
        guard let monitor = explicitMonitor ?? selected else { return }
        let index = index ?? presetIndex
        edit { g in g.presets[index].assignments.removeAll { $0.monitor == monitor }; if let connection { g.presets[index].assignments.append(.init(monitor: monitor, connection: connection)) } }
    }
    /// A wire from a computer's numbered connector to a monitor input: that preset
    /// uses the input. A different computer already on the input is replaced,
    /// taking its routes with it. Claiming the input for this computer and
    /// matching its display is the page's next step, so a drawn wire never ends
    /// up saved but invisible on an input that belongs to no computer.
    func drawWire(slot: Int, computer: UUID, port portID: UUID) {
        guard (1...3).contains(slot), let port = group.connections.first(where: { $0.id == portID }),
              group.computers.contains(where: { $0.id == computer }) else { return }
        edit { g in
            if let owner = port.computer, owner != computer {
                for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == portID } }
                try DeskCableBinding.apply(connection: portID, computer: nil, display: nil, to: &g)
            }
            g.presets[slot - 1].assignments.removeAll { $0.monitor == port.monitor }
            g.presets[slot - 1].assignments.append(.init(monitor: port.monitor, connection: portID))
        }
        if problem == nil { selected = port.monitor }
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
        if active?.assignments.contains(where: { $0.monitor == id }) == true { active = nil; activeGroup = nil; activeFocus = nil; notice = "Screen removed. Control returned locally." }
    }
    /// Clear a preset: it stops switching any screen. Screens, inputs and cables stay.
    func clearPreset(_ index: Int) {
        guard group.presets.indices.contains(index) else { return }
        edit { $0.presets[index].assignments = [] }
    }
    /// Start the desk layout over on every Mac in the desk: all screens, inputs,
    /// cables and preset routes go. Paired Macs stay paired and preset names stay.
    func resetLayout() {
        edit { g in
            g.monitors = []; g.connections = []; g.sharedKeyboards = nil
            for p in g.presets.indices { g.presets[p].assignments = [] }
        }
        guard problem == nil else { return }
        selected = nil; active = nil; activeGroup = nil; activeFocus = nil
        notice = "Desk reset. Add your screens again to set it up."
    }
    func removeComputer(_ id: UUID) {
        edit { try $0.removeComputer(id) }
        guard problem == nil else { return }
        online.remove(id); active = nil; activeGroup = nil; activeFocus = nil
        notice = "Computer removed. Control returned locally."
    }
}
