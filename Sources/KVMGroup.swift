import Foundation

struct KVMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct KVMComputer: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var platform = "macOS"
}

struct KVMPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

enum KVMRotation: Int, Codable, CaseIterable {
    case normal = 0, clockwise = 90, upsideDown = 180, counterclockwise = 270
}

struct KVMGeometry: Codable, Equatable {
    // Top-left origin, y down. Native panel dimensions before rotation, in mm.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: KVMRotation = .normal
    var displayedWidth: Double { rotation == .clockwise || rotation == .counterclockwise ? height : width }
    var displayedHeight: Double { rotation == .clockwise || rotation == .counterclockwise ? width : height }
    var right: Double { x + displayedWidth }
    var bottom: Double { y + displayedHeight }
    func contains(_ p: KVMPoint) -> Bool { p.x >= x && p.x <= right && p.y >= y && p.y <= bottom }
    func overlaps(_ other: Self) -> Bool {
        min(right, other.right) > max(x, other.x) && min(bottom, other.bottom) > max(y, other.y)
    }
    func nativePoint(_ p: KVMPoint, pixelWidth: Int, pixelHeight: Int) throws -> KVMPoint {
        guard [x, y, width, height, p.x, p.y].allSatisfy(\.isFinite), width > 0, height > 0,
              contains(p), pixelWidth > 0, pixelHeight > 0 else { throw KVMError("The pointer is outside this screen.") }
        let u = (p.x - x) / displayedWidth, v = (p.y - y) / displayedHeight
        let native: (Double, Double)
        switch rotation {
        case .normal: native = (u, v)
        case .clockwise: native = (v, 1 - u)
        case .upsideDown: native = (1 - u, 1 - v)
        case .counterclockwise: native = (1 - v, u)
        }
        return KVMPoint(x: native.0 * Double(pixelWidth - 1), y: native.1 * Double(pixelHeight - 1))
    }
}

struct KVMMonitorControl: Codable, Equatable {
    var computer: UUID
    var localDisplay: String
    var mode = "standard"
}

struct KVMMonitor: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var geometry: KVMGeometry
    var control: KVMMonitorControl? = nil
}

struct KVMConnection: Codable, Equatable, Identifiable {
    var id = UUID()
    var monitor: UUID
    var computer: UUID?
    // Host-local identifier is deliberately NOT the physical monitor's identity.
    var localDisplay: String?
    var inputName: String
    var inputCode: UInt16? = nil
}

struct KVMAssignment: Codable, Equatable {
    var monitor: UUID
    var connection: UUID
}

struct KVMShortcut: Codable, Equatable {
    var key: String
    var control = true
    var option = true
    var command = true
    var shift = false
    var label: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key }
}

struct KVMPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var slot: Int
    var name: String
    var shortcut: KVMShortcut
    var assignments: [KVMAssignment] = []
    static func empty(_ slot: Int) -> Self { Self(slot: slot, name: "Preset \(slot)", shortcut: KVMShortcut(key: "F\(slot)")) }
}

struct KVMGroup: Codable, Equatable, Identifiable {
    var schema = 1
    var id = UUID()
    var name: String
    var computers: [KVMComputer]
    var monitors: [KVMMonitor] = []
    var connections: [KVMConnection] = []
    var presets: [KVMPreset] = (1...3).map(KVMPreset.empty)

    func validated() throws -> Self {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw KVMError(message) } }
        func nameOK(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 100 &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
        try require(schema == 1, "This desk needs a compatible version of Perch.")
        try require(nameOK(name), "Give this desk a name of up to 100 bytes without control characters.")
        try require((1...16).contains(computers.count), "A desk can contain up to 16 computers.")
        try require(monitors.count <= 16, "A desk can contain up to 16 physical screens.")
        try require(connections.count <= 256, "This desk has too many screen connections.")
        try require(presets.count == 3 && Set(presets.map(\.slot)) == Set(1...3), "A desk has three preset slots.")
        try require(Set(computers.map(\.id)).count == computers.count && Set(monitors.map(\.id)).count == monitors.count &&
                    Set(connections.map(\.id)).count == connections.count && Set(presets.map(\.id)).count == presets.count, "Desk identifiers must be unique.")
        try require(computers.allSatisfy { nameOK($0.name) && nameOK($0.platform) } && monitors.allSatisfy { nameOK($0.name) }, "Each computer and screen needs a valid name.")
        for monitor in monitors {
            if let control = monitor.control {
                try require(computers.contains { $0.id == control.computer } && UUID(uuidString: control.localDisplay) != nil && control.mode.utf8.count <= 2048 && (control.mode == "standard" || control.mode == "lg" || control.mode.hasPrefix("route:")), "Choose a valid monitor control connection.")
            }
            let g = monitor.geometry
            try require([g.x, g.y, g.width, g.height].allSatisfy(\.isFinite) && abs(g.x) <= 100_000 && abs(g.y) <= 100_000 &&
                        (1...10_000).contains(g.width) && (1...10_000).contains(g.height), "Screen positions and physical sizes must be valid.")
            try require(!monitors.contains { $0.id != monitor.id && $0.geometry.overlaps(g) }, "Screens overlap. Place them side by side or leave a gap.")
        }
        for connection in connections {
            try require(monitors.contains { $0.id == connection.monitor } && (connection.computer == nil || computers.contains { $0.id == connection.computer }), "A screen connection refers to a removed device.")
            try require(nameOK(connection.inputName) && connection.inputCode != 0, "A screen connection needs a valid input.")
            try require(connections.filter { $0.monitor == connection.monitor && $0.inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == connection.inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.count == 1,
                        "This screen already has an input with that name. Edit its computer mapping instead.")
            if let code = connection.inputCode { try require(connections.filter { $0.monitor == connection.monitor && $0.inputCode == code }.count == 1, "This monitor input code is already configured.") }
            try require((connection.computer == nil) == (connection.localDisplay == nil), "Map a connection to both a computer and its local display, or leave it unassigned.")
            if let local = connection.localDisplay {
                try require(!local.isEmpty && local.utf8.count <= 1024, "A mapped connection needs a valid local display.")
                try require(connections.filter { $0.computer == connection.computer && $0.localDisplay == local }.count == 1, "A local display cannot represent two physical screens.")
            }
        }
        for preset in presets {
            try require(nameOK(preset.name) && (1...24).map { "F\($0)" }.contains(preset.shortcut.key) &&
                        [preset.shortcut.control, preset.shortcut.option, preset.shortcut.command, preset.shortcut.shift].filter { $0 }.count >= 2,
                        "A preset needs a name and a shortcut with at least two modifiers.")
            try require(presets.filter { $0.shortcut == preset.shortcut }.count == 1, "Each preset needs a different shortcut.")
            try require(preset.assignments.count <= 16 && Set(preset.assignments.map(\.monitor)).count == preset.assignments.count, "A preset may assign each screen once.")
            for assignment in preset.assignments {
                try require(connections.contains { $0.id == assignment.connection && $0.monitor == assignment.monitor }, "Choose an existing connection for this screen.")
            }
        }
        return self
    }

    mutating func removeMonitor(_ id: UUID) {
        monitors.removeAll { $0.id == id }
        connections.removeAll { $0.monitor == id }
        for i in presets.indices { presets[i].assignments.removeAll { $0.monitor == id } }
    }
    mutating func removeComputer(_ id: UUID) throws {
        guard computers.count > 1 else { throw KVMError("Keep at least one computer in the desk.") }
        computers.removeAll { $0.id == id }
        for i in monitors.indices where monitors[i].control?.computer == id { monitors[i].control = nil }
        // Physical inputs remain selectable when their computer leaves the group.
        for i in connections.indices where connections[i].computer == id { connections[i].computer = nil; connections[i].localDisplay = nil }
    }
}

struct KVMDisplayObservation: Equatable {
    var computer: UUID
    var localDisplay: String
    var vendor: UInt32
    var model: UInt32
    var numericSerial: UInt32?
    var textSerial: String?
    private var serial: String? {
        if let text = textSerial?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
           !text.isEmpty, !["0", "00000000", "UNKNOWN", "N/A", "NONE"].contains(text) { return "text:" + text }
        if let number = numericSerial, number != 0, number != UInt32.max { return "number:\(number)" }
        return nil
    }
    // A suggestion always needs confirmation. Two observations on the same host
    // with the same serial establish a collision, not another automatic match.
    func suggestedMatches(in observations: [Self]) -> [Self] {
        guard vendor != 0, model != 0, let serial else { return [] }
        let matches = observations.filter { $0.vendor == vendor && $0.model == model && $0.serial == serial }
        let all = matches + (matches.contains(self) ? [] : [self])
        guard Dictionary(grouping: all, by: \.computer).values.allSatisfy({ Set($0.map(\.localDisplay)).count == 1 }) else { return [] }
        return matches.filter { $0.computer != computer }
    }
}

enum KVMEdge {
    enum Crossing: Equatable { case blocked, native, remote(monitor: UUID, computer: UUID, entry: KVMPoint) }
    static func crossing(group: KVMGroup, preset: KVMPreset, source: UUID, from: KVMPoint, to: KVMPoint) -> Crossing {
        guard (try? group.validated()) != nil, group.presets.contains(preset), let screen = group.monitors.first(where: { $0.id == source }),
              screen.geometry.contains(from), !screen.geometry.contains(to),
              let assignment = preset.assignments.first(where: { $0.monitor == source }),
              let owner = group.connections.first(where: { $0.id == assignment.connection })?.computer else { return .blocked }
        let g = screen.geometry, dx = to.x - from.x, dy = to.y - from.y
        var exits: [(Double, Int)] = []
        if dx > 0 { exits.append(((g.right - from.x) / dx, 0)) }
        if dx < 0 { exits.append(((g.x - from.x) / dx, 1)) }
        if dy > 0 { exits.append(((g.bottom - from.y) / dy, 2)) }
        if dy < 0 { exits.append(((g.y - from.y) / dy, 3)) }
        let valid = exits.filter { $0.0 >= 0 && $0.0 <= 1 }.sorted { $0.0 < $1.0 }
        guard let exit = valid.first, valid.count < 2 || abs(valid[1].0 - exit.0) > 0.000001 else { return .blocked }
        let p = KVMPoint(x: from.x + dx * exit.0, y: from.y + dy * exit.0)
        let targets = group.monitors.filter { other in
            guard other.id != source else { return false }
            let h = other.geometry
            switch exit.1 {
            case 0: return abs(h.x - g.right) < 0.001 && p.y > h.y && p.y < h.bottom
            case 1: return abs(h.right - g.x) < 0.001 && p.y > h.y && p.y < h.bottom
            case 2: return abs(h.y - g.bottom) < 0.001 && p.x > h.x && p.x < h.right
            default: return abs(h.bottom - g.y) < 0.001 && p.x > h.x && p.x < h.right
            }
        }
        guard targets.count == 1, let target = targets.first,
              let a = preset.assignments.first(where: { $0.monitor == target.id }),
              let computer = group.connections.first(where: { $0.id == a.connection })?.computer else { return .blocked }
        return computer == owner ? .native : .remote(monitor: target.id, computer: computer, entry: p)
    }
}
