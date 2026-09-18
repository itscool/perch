import Foundation

struct KVMComputer: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var platform = "macOS"
}

enum KVMSharedInputKind: String, Codable, CaseIterable { case keyboard, mouse }

struct KVMSharedKeyboard: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    // Confirmed independently on each host; a host-local settings key is not
    // itself a cross-host physical identity. Ambiguous attachments are blocked.
    var bindings: [UUID: String] = [:]
    var follow = false
    var kind: KVMSharedInputKind? = nil
    var deviceKind: KVMSharedInputKind { kind ?? .keyboard }
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
    var x: Double { didSet { x = Self.millimetres(x) } }
    var y: Double { didSet { y = Self.millimetres(y) } }
    var width: Double { didSet { width = Self.millimetres(width) } }
    var height: Double { didSet { height = Self.millimetres(height) } }
    var rotation: KVMRotation = .normal
    var displayedWidth: Double { rotation == .clockwise || rotation == .counterclockwise ? height : width }
    var displayedHeight: Double { rotation == .clockwise || rotation == .counterclockwise ? width : height }
    var right: Double { x + displayedWidth }
    var bottom: Double { y + displayedHeight }
    private enum CodingKeys: String, CodingKey { case x, y, width, height, rotation }
    init(x: Double, y: Double, width: Double, height: Double, rotation: KVMRotation = .normal) {
        self.x = Self.millimetres(x); self.y = Self.millimetres(y)
        self.width = Self.millimetres(width); self.height = Self.millimetres(height)
        self.rotation = rotation
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.x = Self.millimetres(try values.decode(Double.self, forKey: .x))
        self.y = Self.millimetres(try values.decode(Double.self, forKey: .y))
        self.width = Self.millimetres(try values.decode(Double.self, forKey: .width))
        self.height = Self.millimetres(try values.decode(Double.self, forKey: .height))
        self.rotation = try values.decodeIfPresent(KVMRotation.self, forKey: .rotation) ?? .normal
    }
    func contains(_ p: KVMPoint) -> Bool { p.x >= x && p.x <= right && p.y >= y && p.y <= bottom }
    func overlaps(_ other: Self) -> Bool {
        // Geometry is stored in millimetres but edited through scaled pixel
        // drags and decimal fields. Ignore sub-tenth-millimetre noise so a
        // screen placed exactly beside another one is not rejected as an
        // overlap because of a binary floating-point remainder.
        let epsilon = 0.1
        return (min(right, other.right) - max(x, other.x) > epsilon) && (min(bottom, other.bottom) - max(y, other.y) > epsilon)
    }
    static func millimetres(_ value: Double) -> Double { (value * 10).rounded() / 10 }
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
    var inputProfile: String? = nil
    var defaultControlMode: String? = nil
    var panelAspect: Double? = nil
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
    var sharedKeyboards: [KVMSharedKeyboard]? = nil

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
        let keyboards = sharedKeyboards ?? []
        try require(keyboards.count <= 16 && Set(keyboards.map(\.id)).count == keyboards.count, "A desk can follow up to 16 named keyboards and mice.")
        for keyboard in keyboards {
            try require(nameOK(keyboard.name) && keyboard.bindings.count <= 16 && keyboard.bindings.allSatisfy { computer, key in
                computers.contains { $0.id == computer } && !key.isEmpty && key.utf8.count <= 1024
            }, "Give the shared device a name and choose its attachment on each computer.")
        }
        for computer in computers {
            let bindings = keyboards.compactMap { $0.bindings[computer.id] }
            try require(Set(bindings).count == bindings.count, "This device attachment is already assigned to another shared device.")
        }
        try require(presets.count == 3 && Set(presets.map(\.slot)) == Set(1...3), "A desk has three preset slots.")
        try require(Set(computers.map(\.id)).count == computers.count && Set(monitors.map(\.id)).count == monitors.count &&
                    Set(connections.map(\.id)).count == connections.count && Set(presets.map(\.id)).count == presets.count, "Desk identifiers must be unique.")
        try require(computers.allSatisfy { nameOK($0.name) && nameOK($0.platform) } && monitors.allSatisfy { nameOK($0.name) }, "Each computer and screen needs a valid name.")
        for monitor in monitors {
            if let control = monitor.control {
                try require(computers.contains { $0.id == control.computer } && UUID(uuidString: control.localDisplay) != nil && control.mode.utf8.count <= 2048 && (control.mode == "standard" || control.mode == "lg" || control.mode.hasPrefix("route:")), "Choose a valid monitor control connection.")
            }
            if let mode = monitor.defaultControlMode { try require(["standard", "lg"].contains(mode), "Invalid default monitor protocol.") }
            if let aspect = monitor.panelAspect { try require(aspect.isFinite && (0.1...10).contains(aspect), "Invalid panel aspect ratio.") }
            let g = monitor.geometry
            try require([g.x, g.y, g.width, g.height].allSatisfy(\.isFinite) && abs(g.x) <= 100_000 && abs(g.y) <= 100_000 &&
                        (1...10_000).contains(g.width) && (1...10_000).contains(g.height), "Screen positions and physical sizes must be valid.")
            try require(!monitors.contains { $0.id != monitor.id && $0.geometry.overlaps(g) }, "Screens overlap. Auto-snap them edge to edge before saving.")
        }
        try require(monitors.allSatisfy { $0.inputProfile.map { !$0.isEmpty && $0.utf8.count <= 200 } ?? true }, "Monitor profile names must be valid.")
        for connection in connections {
            try require(monitors.contains { $0.id == connection.monitor } && (connection.computer == nil || computers.contains { $0.id == connection.computer }), "A screen connection refers to a removed device.")
            try require(nameOK(connection.inputName) && connection.inputCode != 0, "A screen connection needs a valid input.")
            try require(connections.filter { $0.monitor == connection.monitor && $0.inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == connection.inputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.count == 1,
                        "This screen already has an input with that name. Edit its computer mapping instead.")
            if let code = connection.inputCode { try require(connections.filter { $0.monitor == connection.monitor && $0.inputCode == code }.count == 1, "This monitor input code is already configured.") }
            try require(connection.localDisplay == nil || connection.computer != nil, "A display identity needs a connected computer.")
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
        if sharedKeyboards != nil { for index in sharedKeyboards!.indices { sharedKeyboards![index].bindings[id] = nil } }
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

/// What a screen is showing, as far as Perch knows: a fresh monitor readback
/// where there is one, and otherwise the input Perch's own accepted command
/// selected. Used for desktop reconciliation and for matching a cable whose
/// display no other Mac can see while that input is the one showing.
enum KVMShowingInput {
    static func effective(reported: [UUID: UInt16], optimistic: [UUID: UInt16]) -> [UUID: UInt16] {
        var result = optimistic
        for (monitor, input) in reported { result[monitor] = input }
        return result
    }
}

enum KVMEdge {
    private static let alignmentToleranceMM = 0.1
    // Canonical tenths-of-a-millimetre values can still differ by one ULP
    // after addition/subtraction. Keep an exactly one-tenth edge aligned
    // instead of rejecting it because of that representation noise.
    private static func aligned(_ distance: Double) -> Bool {
        abs(distance) <= alignmentToleranceMM + 0.000001
    }
    enum Crossing: Equatable { case blocked, native, remote(monitor: UUID, computer: UUID, entry: KVMPoint) }

    /// Whether this preset actually places two computers' screens against each
    /// other. With no shared edge there is nowhere for the pointer to cross, so
    /// Perch must not take virtual control of the mouse at all. This is decided
    /// from the monitor arrangement, never from whether a preset merely names
    /// another Mac.
    static func sharesDeskSpace(group: KVMGroup, preset: KVMPreset) -> Bool {
        let placed = preset.assignments.compactMap { assignment -> (KVMGeometry, UUID)? in
            guard let monitor = group.monitors.first(where: { $0.id == assignment.monitor }),
                  let connection = group.connections.first(where: { $0.id == assignment.connection }),
                  connection.localDisplay != nil, let computer = connection.computer else { return nil }
            return (monitor.geometry, computer)
        }
        for (index, one) in placed.enumerated() {
            for other in placed.dropFirst(index + 1) where other.1 != one.1 {
                if touching(one.0, other.0) { return true }
            }
        }
        return false
    }

    /// Two screens share desk space when an edge of one meets an edge of the
    /// other and they overlap along it by more than the alignment tolerance,
    /// so a pointer has somewhere to pass through rather than a single corner.
    static func touching(_ a: KVMGeometry, _ b: KVMGeometry) -> Bool {
        if aligned(b.x - a.right) || aligned(a.x - b.right) {
            return min(a.bottom, b.bottom) - max(a.y, b.y) > alignmentToleranceMM
        }
        if aligned(b.y - a.bottom) || aligned(a.y - b.bottom) {
            return min(a.right, b.right) - max(a.x, b.x) > alignmentToleranceMM
        }
        return false
    }
    /// Why the pointer cannot cross in this preset, in the person's terms, or
    /// nil when it can. A screen whose cable has no matched display is left out
    /// of the arrangement, so saying the screens are not side by side would be
    /// wrong: name the screen Perch cannot place yet instead.
    static func sharedSpaceIssue(group: KVMGroup, preset: KVMPreset) -> String? {
        guard !sharesDeskSpace(group: group, preset: preset) else { return nil }
        let unmatched = preset.assignments.compactMap { assignment -> (screen: String, mac: String)? in
            guard let connection = group.connections.first(where: { $0.id == assignment.connection }),
                  let computer = connection.computer, connection.localDisplay == nil,
                  let screen = group.monitors.first(where: { $0.id == assignment.monitor }) else { return nil }
            return (screen.name, group.computers.first { $0.id == computer }?.name ?? "that Mac")
        }.sorted { $0.screen < $1.screen }
        if let first = unmatched.first {
            return "Perch does not know which display on \(first.mac) shows \(first.screen) yet, so it cannot place that screen. Switch to that input once so Perch can match it, or choose its display in Desk. The picture still switches."
        }
        let computers = Set(preset.assignments.compactMap { assignment in
            group.connections.first { $0.id == assignment.connection }?.computer
        })
        if computers.count < 2 {
            return "This preset shows one Mac on every screen, so there is nowhere to move the pointer across to."
        }
        return "These screens do not sit next to each other in Desk, so there is no edge to move the pointer across. Place them side by side to share the keyboard and mouse."
    }
    static func crossing(group: KVMGroup, preset: KVMPreset, source: UUID, from: KVMPoint, to: KVMPoint) -> Crossing {
        guard (try? group.validated()) != nil, group.presets.contains(preset), let screen = group.monitors.first(where: { $0.id == source }),
              screen.geometry.contains(from), !screen.geometry.contains(to),
              let assignment = preset.assignments.first(where: { $0.monitor == source }),
              let sourceConnection = group.connections.first(where: { $0.id == assignment.connection }), sourceConnection.localDisplay != nil,
              let owner = sourceConnection.computer else { return .blocked }
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
            case 0: return aligned(h.x - g.right) && p.y >= h.y && p.y <= h.bottom
            case 1: return aligned(h.right - g.x) && p.y >= h.y && p.y <= h.bottom
            case 2: return aligned(h.y - g.bottom) && p.x >= h.x && p.x <= h.right
            default: return aligned(h.bottom - g.y) && p.x >= h.x && p.x <= h.right
            }
        }
        guard targets.count == 1, let target = targets.first,
              let a = preset.assignments.first(where: { $0.monitor == target.id }),
              let targetConnection = group.connections.first(where: { $0.id == a.connection }), targetConnection.localDisplay != nil,
              let computer = targetConnection.computer else { return .blocked }
        // Clamp the crossing point into the destination’s edge when the two
        // saved millimetre rectangles differ by rounding noise. This avoids a
        // focus handoff immediately bouncing back at a sub-pixel gap.
        let entry = KVMPoint(x: min(target.geometry.right, max(target.geometry.x, p.x)),
                             y: min(target.geometry.bottom, max(target.geometry.y, p.y)))
        return computer == owner ? .native : .remote(monitor: target.id, computer: computer, entry: entry)
    }
}
