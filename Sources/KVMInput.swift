import Foundation
import CryptoKit

enum KVMInputConfiguration {
    private struct Keyboard: Encodable {
        let id: UUID
        let follow: Bool
        let bindings: [String: String]
    }
    private struct Snapshot: Encodable {
        let group: KVMGroup
        let keyboards: [Keyboard]
    }
    /// Cosmetic edits must not interrupt someone typing into remote Settings.
    /// Geometry, mappings, control paths and keyboard-follow policy still fence
    /// a session. Membership is additionally checked through the signed epoch.
    static func revision(_ group: KVMGroup) -> String? {
        var value = group
        value.name = ""
        for index in value.computers.indices { value.computers[index].name = "" }
        for index in value.monitors.indices { value.monitors[index].name = "" }
        for index in value.connections.indices { value.connections[index].inputName = "" }
        for index in value.presets.indices {
            value.presets[index].name = ""
            value.presets[index].shortcut = .init(key: "F\(value.presets[index].slot)")
            value.presets[index].assignments.sort { $0.monitor.uuidString < $1.monitor.uuidString }
        }
        let keyboards = (value.sharedKeyboards ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            Keyboard(id: $0.id, follow: $0.follow, bindings: Dictionary(uniqueKeysWithValues: $0.bindings.map { ($0.key.uuidString, $0.value) }))
        }
        // UUID-keyed dictionaries encode as unordered arrays. Convert their
        // keys to strings for canonical hashing across separate processes.
        value.sharedKeyboards = nil
        value.computers.sort { $0.id.uuidString < $1.id.uuidString }
        value.monitors.sort { $0.id.uuidString < $1.id.uuidString }
        value.connections.sort { $0.id.uuidString < $1.id.uuidString }
        value.presets.sort { $0.slot < $1.slot }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(Snapshot(group: value, keyboards: keyboards)) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Deliberately small wire vocabulary, never an archived native CGEvent.
/// No text, clipboard contents, passwords or input history are persisted.
struct KVMInputEvent: Codable, Equatable {
    enum Kind: String, Codable { case motion, buttonDown, buttonUp, keyDown, keyUp, modifiers, scroll }
    var kind: Kind
    var code: UInt16 = 0
    var flags: UInt64 = 0
    var x: Double = 0
    var y: Double = 0
    var repeated = false
    var clickCount: Int = 1
    static let flagMask: UInt64 = 0x00FF_0000
    var valid: Bool {
        guard flags & ~Self.flagMask == 0, (0...3).contains(clickCount), x.isFinite, y.isFinite, abs(x) <= 10_000, abs(y) <= 10_000 else { return false }
        switch kind {
        case .keyDown, .keyUp: return code <= 127 && (kind == .keyDown || !repeated)
        case .modifiers: return [54,55,56,57,58,59,60,61,62,63].contains(code) && !repeated
        case .buttonDown, .buttonUp: return code <= 4 && !repeated
        case .motion, .scroll: return code == 0 && !repeated
        }
    }
}

struct KVMInputFocus: Codable, Equatable {
    var monitor: UUID
    var computer: UUID
    var position: KVMPoint
}

struct KVMInputGrant: Codable, Equatable {
    let id: UUID
    let epoch: UUID
    let revision: String
    let preset: UUID
    let participants: Set<UUID>
    let focus: KVMInputFocus
    func valid(group: KVMGroup, epoch: UUID, revision: String) -> Bool {
        guard self.epoch == epoch, self.revision == revision, (try? group.validated()) != nil,
              !participants.isEmpty, participants.isSubset(of: Set(group.computers.map(\.id))), participants.contains(focus.computer),
              let screen = group.monitors.first(where: { $0.id == focus.monitor }), screen.geometry.contains(focus.position),
              let preset = group.presets.first(where: { $0.id == preset }),
              let assignment = preset.assignments.first(where: { $0.monitor == focus.monitor }),
              let connection = group.connections.first(where: { $0.id == assignment.connection }), connection.computer == focus.computer else { return false }
        return true
    }
}

/// Challenge-bound leases use only this process's monotonic clock. Delayed
/// renewals cannot extend a lease from their arrival time or resurrect it.
struct KVMInputLease {
    static let duration: Double = 1
    private(set) var grant: KVMInputGrant?
    private(set) var expires: Double = 0
    private var challenges: [UUID: Double] = [:]
    private var receivedSequence: [UUID: UInt64] = [:]
    mutating func challenge(now: Double) -> UUID {
        challenges = challenges.filter { now >= $0.value && now - $0.value < Self.duration }
        let id = UUID()
        if now.isFinite && now >= 0 && challenges.count < 8 { challenges[id] = now }
        return id
    }
    mutating func accept(_ value: KVMInputGrant, challenge: UUID, now: Double) -> Bool {
        guard let sent = challenges.removeValue(forKey: challenge), now.isFinite, now >= sent,
              now - sent < Self.duration else { return false }
        // New focus always goes through the release/prepare path first.
        if let grant, grant != value { return false }
        guard grant == nil || alive(now: now) else { return false }
        grant = value; expires = max(expires, sent + Self.duration)
        return true
    }
    func alive(now: Double) -> Bool {
        grant != nil && now.isFinite && now >= expires - Self.duration && now < expires
    }
    mutating func accepts(source: UUID, grant id: UUID, sequence: UInt64, now: Double) -> Bool {
        guard alive(now: now), let grant, grant.id == id, grant.participants.contains(source),
              sequence > receivedSequence[source, default: 0] else { return false }
        receivedSequence[source] = sequence; return true
    }
    mutating func release() { grant = nil; expires = 0; challenges = [:]; receivedSequence = [:] }
}

/// Per-source held state prevents one keyboard's release from releasing another
/// keyboard's held key. Reset produces bounded releases and drops all history.
struct KVMInputHeld {
    private var keys: [UInt16: Set<UUID>] = [:]
    private var buttons: [UInt16: Set<UUID>] = [:]
    private var modifiers: [UUID: UInt64] = [:]
    var flags: UInt64 { modifiers.values.reduce(0, |) }
    var count: Int { keys.count + buttons.count + modifiers.count }
    mutating func apply(_ value: KVMInputEvent, source: UUID) -> KVMInputEvent? {
        guard value.valid else { return nil }
        var event = value
        modifiers[source] = value.flags
        event.flags = flags
        switch value.kind {
        case .keyDown:
            let wasDown = keys[value.code]?.isEmpty == false
            let own = keys[value.code]?.contains(source) == true
            if value.repeated { return own ? event : nil }
            keys[value.code, default: []].insert(source)
            return wasDown ? nil : event
        case .keyUp:
            guard keys[value.code]?.remove(source) != nil else { return nil }
            guard keys[value.code]?.isEmpty == true else { return nil }; keys[value.code] = nil
        case .buttonDown:
            let wasDown = buttons[value.code]?.isEmpty == false
            buttons[value.code, default: []].insert(source)
            return wasDown ? nil : event
        case .buttonUp:
            guard buttons[value.code]?.remove(source) != nil else { return nil }
            guard buttons[value.code]?.isEmpty == true else { return nil }; buttons[value.code] = nil
        default: break
        }
        return event
    }
    mutating func releaseAll() -> [KVMInputEvent] {
        let releases = keys.keys.sorted().map { KVMInputEvent(kind: .keyUp, code: $0) } +
            buttons.keys.sorted().map { KVMInputEvent(kind: .buttonUp, code: $0) } +
            (modifiers.values.contains(where: { $0 != 0 }) ? [54,55,56,58,59,60,61,62,63].map { KVMInputEvent(kind: .modifiers, code: UInt16($0)) } : [])
        keys = [:]; buttons = [:]; modifiers = [:]
        return releases
    }
}

struct KVMKeyboardFollow {
    private(set) var hosts: [UUID: Set<UUID>] = [:]
    private var lastHost: [UUID: UUID] = [:]
    private var detachedFrom: [UUID: UUID] = [:]
    /// Requires explicit detach and one unique arrival; either message order is
    /// allowed. A peer disappearing is not evidence of a hardware host switch.
    mutating func observe(keyboard: UUID, computer: UUID, attached: Bool, online: Set<UUID>) -> UUID? {
        guard online.contains(computer) else { return nil }
        if attached {
            hosts[keyboard, default: []].insert(computer)
            if lastHost[keyboard] == nil { lastHost[keyboard] = computer }
        } else {
            guard hosts[keyboard]?.remove(computer) != nil else { return nil }
            if lastHost[keyboard] == computer { detachedFrom[keyboard] = computer }
        }
        guard hosts[keyboard]?.count == 1, let destination = hosts[keyboard]?.first,
              online.contains(destination), let previous = detachedFrom[keyboard], previous != destination else { return nil }
        detachedFrom[keyboard] = nil; lastHost[keyboard] = destination
        return destination
    }
}
