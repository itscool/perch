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
/// A screen found by what it is rather than by the ID macOS gave it.
///
/// macOS renames a display when the monitor is replugged, switches inputs or
/// changes mode, and each Mac has its own name for the same monitor. Stored
/// names went stale without anyone noticing, and a Mac given control of a screen
/// it could no longer find gave control straight back. So each screen remembers
/// its maker, model and serial, and any Mac's current displays are matched to it
/// by those.
enum DeskIdentityCableResolver {
    struct Display: Equatable { let id: String; let vendor: UInt32; let model: UInt32; let serial: UInt32 }
    /// The one display in `live` that is this monitor, or nil when none or
    /// several are. Used at the moment of a command, from the Mac's own list.
    static func display(for identity: KVMScreenIdentity?, among live: [Display]) -> String? {
        guard let identity else { return nil }
        let found = live.filter { identity.matches(vendor: $0.vendor, model: $0.model, serial: $0.serial) }
        return found.count == 1 ? found[0].id : nil
    }
    static func resolve(_ group: KVMGroup, displays: [UUID: [Display]]) -> KVMGroup {
        var draft = group
        // Learn what each screen is from any Mac that currently sees it under the
        // ID recorded for it.
        for index in draft.monitors.indices where draft.monitors[index].identity == nil {
            let monitor = draft.monitors[index].id
            let seen = draft.connections.compactMap { connection -> Display? in
                guard connection.monitor == monitor, let computer = connection.computer, let local = connection.localDisplay else { return nil }
                return displays[computer]?.first { $0.id == local && $0.vendor != 0 && $0.model != 0 }
            }
            // Learn only from evidence that agrees: a record already attached to
            // the wrong screen must not teach that screen the wrong identity.
            if let first = seen.first {
                let learned = KVMScreenIdentity(vendor: first.vendor, model: first.model, serial: first.serial)
                if seen.allSatisfy({ learned.matches(vendor: $0.vendor, model: $0.model, serial: $0.serial) }) {
                    draft.monitors[index].identity = learned
                }
            }
        }
        // A record that Mac still has, but for a monitor that is clearly not this
        // screen, is wrong: a serial that differs proves it. On this desk the
        // Studio's view of screen 2 had been recorded against screen 1, so the
        // pointer was placed on the wrong screen's record.
        for index in draft.connections.indices {
            let connection = draft.connections[index]
            guard let computer = connection.computer, let local = connection.localDisplay,
                  let shown = displays[computer]?.first(where: { $0.id == local }), shown.vendor != 0,
                  let identity = draft.monitors.first(where: { $0.id == connection.monitor })?.identity,
                  !identity.matches(vendor: shown.vendor, model: shown.model, serial: shown.serial) else { continue }
            draft.connections[index].localDisplay = nil
        }
        // Re-find a screen whose recorded ID a Mac no longer has, or never had.
        for index in draft.connections.indices {
            let connection = draft.connections[index]
            guard let computer = connection.computer, let current = displays[computer], !current.isEmpty,
                  let identity = draft.monitors.first(where: { $0.id == connection.monitor })?.identity else { continue }
            if let local = connection.localDisplay, current.contains(where: { $0.id == local }) { continue }
            let used = Set(draft.connections.filter { $0.computer == computer && $0.id != connection.id }.compactMap(\.localDisplay))
            let candidates = current.filter { !used.contains($0.id) && identity.matches(vendor: $0.vendor, model: $0.model, serial: $0.serial) }
            // One display on that Mac is this monitor. Two identical monitors
            // without serials cannot be told apart this way, so leave them.
            guard candidates.count == 1 else { continue }
            var candidate = draft
            candidate.connections[index].localDisplay = candidates[0].id
            guard (try? candidate.validated()) != nil else { continue }
            draft = candidate
        }
        return draft
    }
}

/// Two Macs cannot see one monitor at the same time: while the screen shows one
/// input, the other Mac's video output is gone. So a cable can never be matched
/// by comparing what both Macs see, and it stayed "display matching pending"
/// for ever, which is what stopped keyboard and mouse sharing on a desk whose
/// screens were perfectly set up.
///
/// The showing input is the evidence instead. When Perch knows a monitor is
/// showing a particular input, the computer on that input is the one feeding
/// that screen, so the one display it reports that nothing else is using is
/// that screen.
enum DeskShowingCableResolver {
    /// - Parameters:
    ///   - showing: the input code each monitor is showing, as far as Perch knows.
    ///   - displays: the display identifiers each computer currently reports.
    static func resolve(_ group: KVMGroup, showing: [UUID: UInt16], displays: [UUID: [String]]) -> KVMGroup {
        var draft = group
        for (monitor, input) in showing.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let index = draft.connections.firstIndex(where: { $0.monitor == monitor && $0.inputCode == input }),
                  let computer = draft.connections[index].computer else { continue }
            // A recorded display that Mac no longer has is as good as none: an
            // adapter between Mac and monitor re-enumerates it under a new ID, and
            // may hide the monitor's own model, so this is the evidence left.
            if let recorded = draft.connections[index].localDisplay {
                guard let current = displays[computer], !current.isEmpty, !current.contains(recorded) else { continue }
            }
            let connectionID = draft.connections[index].id
            let used = Set(draft.connections.filter { $0.computer == computer && $0.id != connectionID }.compactMap(\.localDisplay))
            let free = (displays[computer] ?? []).filter { !used.contains($0) }
            // One unused display is this screen. More than one is a guess, and
            // Perch does not guess which screen a person is looking at.
            guard free.count == 1 else { continue }
            var candidate = draft
            candidate.connections[index].localDisplay = free[0]
            guard (try? candidate.validated()) != nil else { continue }
            draft = candidate
        }
        return draft
    }
}

struct DeskPortDefinition { let name: String; let code: UInt16; var command: String? = nil }
enum DeskMonitorConfiguration {
    /// Replace a screen's input list. Each existing input carries over to the
    /// new input with the same name, or the same kind when each list has only
    /// one of that kind ("DisplayPort" and "DisplayPort 1"), keeping its cable
    /// and preset routes. Leftover inputs nothing uses are removed, so changing
    /// profile never stacks a second copy of a port. A leftover input in use
    /// stays only while the switching protocol is unchanged, because its code
    /// means nothing under the other protocol.
    static func apply(monitor: UUID, profile: String, ports: [DeskPortDefinition], mode: String, to group: inout KVMGroup) throws {
        guard let index = group.monitors.firstIndex(where: { $0.id == monitor }), group.monitors[index].control != nil else { throw KVMError("Choose a monitor control path first.") }
        func key(_ name: String) -> String { name.lowercased().filter { !$0.isWhitespace && $0 != "-" } }
        func kind(_ name: String) -> String { key(name).filter { !$0.isNumber } }
        var draft = group
        guard ports.count <= 16, Set(ports.map { key($0.name) }).count == ports.count else { throw KVMError("The profile has duplicate or too many ports.") }
        let existing = draft.connections.indices.filter { draft.connections[$0].monitor == monitor }
        var carried: [Int: Int] = [:]  // port index → connection index
        for (p, port) in ports.enumerated() {
            if let i = existing.first(where: { !carried.values.contains($0) && key(draft.connections[$0].inputName) == key(port.name) }) { carried[p] = i }
        }
        for (p, port) in ports.enumerated() where carried[p] == nil {
            let newOfKind = ports.indices.filter { carried[$0] == nil && kind(ports[$0].name) == kind(port.name) }
            let oldOfKind = existing.filter { !carried.values.contains($0) && kind(draft.connections[$0].inputName) == kind(port.name) }
            if newOfKind.count == 1, oldOfKind.count == 1 { carried[p] = oldOfKind[0] }
        }
        for (p, port) in ports.enumerated() {
            if let i = carried[p] {
                draft.connections[i].inputName = port.name; draft.connections[i].inputCode = port.code
                draft.connections[i].inputProtocol = port.command
            } else {
                draft.connections.append(.init(monitor: monitor, computer: nil, localDisplay: nil, inputName: port.name, inputCode: port.code, inputProtocol: port.command))
            }
        }
        let protocolChanged = group.monitors[index].control?.mode != mode
        var removed = Set<UUID>()
        for i in existing where !carried.values.contains(i) {
            let leftover = draft.connections[i]
            let inUse = leftover.computer != nil || draft.presets.contains { $0.assignments.contains { $0.connection == leftover.id } }
            if !inUse { removed.insert(leftover.id); continue }
            guard protocolChanged else { continue }
            let user = draft.computers.first { $0.id == leftover.computer }?.name
            throw KVMError("This input list has no \(leftover.inputName)" + (user.map { ", which \($0) uses" } ?? ", which a preset uses") + ". Keep the current profile, or remove that connection first.")
        }
        draft.connections.removeAll { removed.contains($0.id) }
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
    /// Move a detached connection's monitor end to another input. The change is
    /// to the preset being edited. A cable can only be in one input, so unless
    /// that computer is already connected to the input it was dropped on, the
    /// cable moves and the other presets that used it follow it there rather
    /// than being left pointing at an input with nothing plugged into it. A
    /// different computer already on that input is replaced, losing its routes.
    func moveWire(from sourceID: UUID, to targetID: UUID) {
        guard let source = group.connections.first(where: { $0.id == sourceID }),
              let target = group.connections.first(where: { $0.id == targetID }), sourceID != targetID,
              let computer = source.computer, group.presets.indices.contains(presetIndex) else { return }
        let slot = presetIndex, plugged = target.computer == computer
        edit { g in
            if !plugged {
                if let owner = target.computer, owner != computer {
                    for p in g.presets.indices { g.presets[p].assignments.removeAll { $0.connection == targetID } }
                }
                try DeskCableBinding.rewire(source, to: target, in: &g)
            }
            for p in g.presets.indices where p == slot || (!plugged && g.presets[p].assignments.contains { $0.connection == sourceID }) {
                g.presets[p].assignments.removeAll { $0.connection == sourceID || $0.monitor == target.monitor }
                g.presets[p].assignments.append(.init(monitor: target.monitor, connection: targetID))
            }
        }
        if problem == nil { selected = target.monitor }
    }
    /// A detached connection dropped in empty space leaves the preset being
    /// edited. The cable is unplugged only once no preset uses that input, so a
    /// wire never disappears from a preset the person was not looking at.
    func removeWire(_ portID: UUID) {
        guard group.presets.indices.contains(presetIndex) else { return }
        let slot = presetIndex
        edit { g in
            g.presets[slot].assignments.removeAll { $0.connection == portID }
            guard !g.presets.contains(where: { $0.assignments.contains { $0.connection == portID } }) else { return }
            try DeskCableBinding.apply(connection: portID, computer: nil, display: nil, to: &g)
        }
    }
    func disconnectCable(_ port: UUID) {
        edit { try DeskCableBinding.apply(connection: port, computer: nil, display: nil, to: &$0) }
    }
    func connectionLabel(_ connection: KVMConnection) -> String {
        let computer = group.computers.first { $0.id == connection.computer }
        return connection.inputName + " — " + (computer?.name ?? "Unassigned") + (computer != nil && connection.localDisplay == nil ? " · Perch has not seen this screen from that Mac yet" : "")
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
