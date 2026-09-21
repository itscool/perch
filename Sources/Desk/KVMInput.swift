import Foundation
import CryptoKit

/// Keyboard and mouse sharing has its own version, separate from the app version
/// and from the desk protocol. Two Macs pair, sync the desk and switch monitors
/// across versions; only sharing the pointer needs both sides to agree on how
/// events, leases and focus behave. Bump this whenever that changes, and a
/// mismatch is named on both Macs instead of quietly doing nothing.
enum KVMInputProtocol {
    /// A var so tests can pretend to be another version; never written in the app.
    /// 2: typing follows the last click rather than the pointer, and the status
    /// exchange carries where typing goes.
    static var version = 2
}

enum KVMInputConfiguration {
    private struct Keyboard: Encodable {
        let id: UUID
        let follow: Bool
        let kind: KVMSharedInputKind?
        let bindings: [String: String]
    }
    private struct Snapshot: Encodable {
        let group: KVMGroup
        let keyboards: [Keyboard]
        /// What goes into this hash is part of the sharing version: a release
        /// that changes the recipe must not look like a desk that differs.
        let version: Int
    }
    /// Cosmetic edits must not interrupt someone typing into remote Settings.
    /// Geometry, mappings, control paths and keyboard-follow policy still fence
    /// a session. Membership is additionally checked through the signed epoch.
    static func revision(_ group: KVMGroup) -> String? {
        var value = group
        value.name = ""
        for index in value.computers.indices { value.computers[index].name = "" }
        // A screen's identity says what the monitor is, not where input may go,
        // and a Perch older than it cannot read it: left in, the two Macs'
        // fingerprints differ and every handoff is quietly refused. Any change to
        // what this fingerprint covers must bump KVMInputProtocol.version, so the
        // difference is named instead.
        for index in value.monitors.indices { value.monitors[index].name = ""; value.monitors[index].identity = nil }
        for index in value.connections.indices { value.connections[index].inputName = "" }
        for index in value.presets.indices {
            value.presets[index].name = ""
            value.presets[index].shortcut = .init(key: "F\(value.presets[index].slot)")
            value.presets[index].assignments.sort { $0.monitor.uuidString < $1.monitor.uuidString }
        }
        let keyboards = (value.sharedKeyboards ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            Keyboard(id: $0.id, follow: $0.follow, kind: $0.kind, bindings: Dictionary(uniqueKeysWithValues: $0.bindings.map { ($0.key.uuidString, $0.value) }))
        }
        // UUID-keyed dictionaries encode as unordered arrays. Convert their
        // keys to strings for canonical hashing across separate processes.
        value.sharedKeyboards = nil
        value.computers.sort { $0.id.uuidString < $1.id.uuidString }
        value.monitors.sort { $0.id.uuidString < $1.id.uuidString }
        value.connections.sort { $0.id.uuidString < $1.id.uuidString }
        value.presets.sort { $0.slot < $1.slot }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(Snapshot(group: value, keyboards: keyboards, version: KVMInputProtocol.version)) else { return nil }
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
    /// Where the source's own pointer is, in desk millimetres, when the source
    /// has focus itself. The coordinator follows the hardware cursor instead
    /// of integrating raw deltas, which drift under pointer acceleration.
    var absolute: KVMPoint? = nil
    /// Scroll: pixel deltas from a trackpad/continuous device, or wheel notches.
    var continuous = true
    /// The sender's own uptime when it captured this, used only to measure how
    /// much the travel time varies. The two Macs' clocks need not agree: the
    /// difference between them is constant and cancels out.
    var sentAt: Double = 0
    /// CGScrollPhase / CGMomentumScrollPhase raw values so the destination sees
    /// gesture boundaries and inertia instead of an endless stream of deltas.
    var phase: Int = 0
    var momentum: Int = 0
    static let flagMask: UInt64 = 0x00FF_0000
    var valid: Bool {
        guard sentAt.isFinite, sentAt >= 0, sentAt < 1e12 else { return false }
        guard flags & ~Self.flagMask == 0, (0...3).contains(clickCount), x.isFinite, y.isFinite, abs(x) <= 10_000, abs(y) <= 10_000,
              [0, 1, 2, 4, 8, 128].contains(phase), (0...3).contains(momentum) else { return false }
        if let absolute { guard absolute.x.isFinite, absolute.y.isFinite, abs(absolute.x) <= 100_000, abs(absolute.y) <= 100_000 else { return false } }
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
    /// Absent from a grant made by a Perch that predates input versioning, which
    /// reads as version 0 and is refused with a named reason.
    var version: Int = KVMInputProtocol.version
    init(id: UUID, epoch: UUID, revision: String, preset: UUID, participants: Set<UUID>, focus: KVMInputFocus, version: Int = KVMInputProtocol.version) {
        self.id = id; self.epoch = epoch; self.revision = revision; self.preset = preset
        self.participants = participants; self.focus = focus; self.version = version
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        epoch = try values.decode(UUID.self, forKey: .epoch)
        revision = try values.decode(String.self, forKey: .revision)
        preset = try values.decode(UUID.self, forKey: .preset)
        participants = try values.decode(Set<UUID>.self, forKey: .participants)
        focus = try values.decode(KVMInputFocus.self, forKey: .focus)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }
    func valid(group: KVMGroup, epoch: UUID, revision: String) -> Bool {
        guard version == KVMInputProtocol.version else { return false }
        guard self.epoch == epoch, self.revision == revision, (try? group.validated()) != nil,
              !participants.isEmpty, participants.isSubset(of: Set(group.computers.map(\.id))), participants.contains(focus.computer),
              let screen = group.monitors.first(where: { $0.id == focus.monitor }), screen.geometry.contains(focus.position),
              let preset = group.presets.first(where: { $0.id == preset }),
              let assignment = preset.assignments.first(where: { $0.monitor == focus.monitor }),
              let connection = group.connections.first(where: { $0.id == assignment.connection }), connection.computer == focus.computer, connection.localDisplay != nil else { return false }
        return true
    }
}

/// Challenge-bound leases use only this process's monotonic clock. Delayed
/// renewals cannot extend a lease from their arrival time or resurrect it.
struct KVMInputLease {
    /// Renewed by 0.5-second heartbeats. Three seconds tolerates a Wi-Fi power
    /// save burst or a display reconfiguration on the main thread; a genuinely
    /// dead peer is still fenced within that window.
    static let duration: Double = 3
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
        // The challenge proves this state was requested within the bounded
        // window. Once received, grant a full local lease interval so normal
        // round-trip latency cannot make focus flicker at the deadline.
        grant = value; expires = max(expires, now + Self.duration)
        return true
    }
    /// The owner installs its own participant lease at the same instant that
    /// it grants authority. It cannot wait for a poll round trip: the owner’s
    /// event tap is also suppressed while a grant is preparing, so leaving
    /// this lease empty would drop local input and let it leak through as a
    /// second, unsynchronized local cursor.
    mutating func acceptLocally(_ value: KVMInputGrant, now: Double) {
        grant = value
        expires = now + Self.duration
        challenges = [:]
        receivedSequence = [:]
    }
    func alive(now: Double) -> Bool {
        grant != nil && now.isFinite && now >= expires - Self.duration && now < expires
    }
    mutating func renew(grant id: UUID, now: Double) {
        guard grant?.id == id, alive(now: now) else { return }
        expires = max(expires, now + Self.duration)
    }
    mutating func accepts(source: UUID, grant id: UUID, sequence: UInt64, now: Double) -> Bool {
        guard alive(now: now), let grant, grant.id == id, grant.participants.contains(source),
              sequence > receivedSequence[source, default: 0] else { return false }
        receivedSequence[source] = sequence; return true
    }
    mutating func release() { grant = nil; expires = 0; challenges = [:]; receivedSequence = [:] }
    /// A poll answered without a grant can never be accepted, so its challenge is
    /// dropped at once. Left in place, answered challenges fill this small table
    /// and a grant arriving on a later poll fails to install.
    mutating func discard(challenge: UUID) { challenges.removeValue(forKey: challenge) }
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
            // A repeat from a source whose down was never seen (a key already
            // held when the lease started) becomes a fresh down; a second
            // down from the source that already holds the key means its up
            // was lost, so it is delivered again rather than swallowed forever.
            if value.repeated, !own { event.repeated = false }
            else if value.repeated { return event }
            keys[value.code, default: []].insert(source)
            return wasDown && !own ? nil : event
        case .keyUp:
            guard keys[value.code]?.remove(source) != nil else { return nil }
            guard keys[value.code]?.isEmpty == true else { return nil }; keys[value.code] = nil
        case .buttonDown:
            let wasDown = buttons[value.code]?.isEmpty == false
            let own = buttons[value.code]?.contains(source) == true
            buttons[value.code, default: []].insert(source)
            return wasDown && !own ? nil : event
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
            (modifiers.values.contains(where: { $0 != 0 }) ? [54,55,56,57,58,59,60,61,62,63].map { KVMInputEvent(kind: .modifiers, code: UInt16($0)) } : [])
        keys = [:]; buttons = [:]; modifiers = [:]
        return releases
    }
}
