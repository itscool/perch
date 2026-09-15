import AppKit

/// Reconciles desktop participation with the monitor input Perch accepted.
/// Fresh readback wins when available; an accepted command is the fallback
/// when the monitor cannot report its input. A contradictory readback removes
/// that fallback before the next reconciliation pass.
final class DeskDesktopHandoff {
    private let local: UUID
    private let group: () -> KVMGroup
    private let inputs: () -> [UUID: UInt16]
    private let optimisticInputs: () -> [UUID: UInt16]
    private let online: () -> Set<UUID>
    private let suspended: () -> Bool
    private var timer: Timer?
    private var holds: Set<String> = []
    private var awaySince: [String: TimeInterval] = [:]
    private var working = false
    /// File-lock, journal fsync and display reconfiguration take seconds; they
    /// never run on the main thread, whose stalls would expire input leases.
    private let queue = DispatchQueue(label: "Perch.desk.desktop", qos: .userInitiated)
    private(set) var problem: String?
    private(set) var disconnected: Set<String> = []
    /// How long a monitor must be known to belong to another Mac before this
    /// Mac gives up its desktop on it. A wrong optimistic guess then costs a
    /// flicker, not a black screen while input has already moved.
    static let awayGrace: TimeInterval = 2
    init(local: UUID, group: @escaping () -> KVMGroup, inputs: @escaping () -> [UUID: UInt16], optimisticInputs: @escaping () -> [UUID: UInt16] = { [:] }, online: @escaping () -> Set<UUID>, suspended: @escaping () -> Bool) {
        self.local = local; self.group = group; self.inputs = inputs; self.optimisticInputs = optimisticInputs; self.online = online; self.suspended = suspended
    }
    func start() {
        guard timer == nil else { return }
        let timer = MainTimer.every(1) { [weak self] in self?.reconcile() }
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil; restoreAll() }
    deinit { timer?.invalidate() } // Guardian handles abnormal destruction/exit.
    static func awayDisplays(group: KVMGroup, local: UUID, inputs: [UUID: UInt16], online: Set<UUID>) -> Set<String> {
        var away: Set<String> = []
        for monitor in group.monitors {
            guard let code = inputs[monitor.id] else { continue }
            let matching = group.connections.filter { $0.monitor == monitor.id && $0.inputCode == code }
            guard matching.count == 1, let owner = matching.first?.computer, owner != local, online.contains(owner) else { continue }
            for connection in group.connections where connection.monitor == monitor.id && connection.computer == local {
                if let identity = connection.localDisplay { away.insert(identity) }
            }
        }
        return away
    }
    static func effectiveInputs(reported: [UUID: UInt16], optimistic: [UUID: UInt16]) -> [UUID: UInt16] {
        var result = optimistic
        for (monitor, input) in reported { result[monitor] = input }
        return result
    }
    /// Main thread: decide what should be away, then do the slow work off main.
    func reconcile() {
        guard !SettingsWindow.shared.testing, !working else { return }
        let helper = HelperStatusIPC.guardianClient.value
        let ready = helper?.fresh == true && helper?.compatible == true && helper?.desktopRecoverySupported == true && !suspended()
        // A fresh observation is stronger than the accepted-command fallback.
        let knownInputs = Self.effectiveInputs(reported: inputs(), optimistic: optimisticInputs())
        let requested = Self.awayDisplays(group: group(), local: local, inputs: knownInputs, online: online()).subtracting(holds)
        let now = ProcessInfo.processInfo.systemUptime
        awaySince = awaySince.filter { requested.contains($0.key) }
        for identity in requested where awaySince[identity] == nil { awaySince[identity] = now }
        let stable = requested.filter { now - (awaySince[$0] ?? now) >= Self.awayGrace }
        let wanted = ready ? stable : []
        let helperProblem = !ready && !requested.isEmpty ? "Desktop handoff needs a matching background helper. Open Setup → Background helpers." : nil
        working = true
        queue.async { [weak self] in
            var problem = helperProblem
            var disconnected: Set<String> = []
            do { disconnected = try Self.apply(wanted: wanted, problem: &problem) }
            catch { problem = "Desktop handoff needs attention: " + error.localizedDescription }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working = false; self.problem = problem
                if self.disconnected != disconnected { self.disconnected = disconnected }
            }
        }
    }
    /// Background: restore what is no longer wanted, renew leases, disconnect
    /// what is newly wanted. Returns the identities still disconnected.
    private static func apply(wanted: Set<String>, problem: inout String?) throws -> Set<String> {
        var note: String?
        let result = try DeskDesktopRecovery.locked { records -> Set<String> in
            guard let owner = ProcessTable.inspect(getpid())?.identity else { throw KVMError("Desktop recovery cannot identify this Perch process.") }
            // Take over no previous process's lease. Restore it before making
            // another handoff, even when that display is still wanted away.
            for record in records where record.owner != owner || !wanted.contains(record.identity) || DeskDesktopRecovery.expired(record, now: ProcessInfo.processInfo.systemUptime, owner: owner) {
                if try DeskDesktopRecovery.restore(record) { records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records) }
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Renew well inside the lease, but not on every tick: each save is an fsync.
            var renewed = false
            for index in records.indices where records[index].owner == owner && wanted.contains(records[index].identity) && records[index].expires - now < DeskDesktopRecovery.lifetime - 3 {
                records[index].expires = now + DeskDesktopRecovery.lifetime; renewed = true
            }
            if renewed { try DeskDesktopRecovery.save(records) }
            let candidates = DisplayIdentity.online().filter { display in
                !display.isBuiltin && display.isActive && !display.isMirrored &&
                DeskDesktopRecovery.identity(display.id).map(wanted.contains) == true
            }
            for display in candidates {
                let id = display.id
                guard let identity = DeskDesktopRecovery.identity(id), !records.contains(where: { $0.identity == identity }) else { continue }
                // Keep a usable display. A closed built-in display never counts,
                // and other screens being handed away cannot be the fallback.
                let remaining = DisplayIdentity.online().filter { other in
                    guard other.id != id, other.isActive, !other.isAsleep,
                          let identity = DeskDesktopRecovery.identity(other.id), !wanted.contains(identity) else { return false }
                    return !other.isBuiltin || MacLidGuardHardware().observe().closed == false
                }
                guard !remaining.isEmpty else { note = "Desktop kept connected: no other usable display remains on this Mac."; continue }
                guard let mode = CGDisplayCopyDisplayMode(id), let physical = DeskDesktopRecovery.physicalIdentity(id) else { note = "Desktop kept connected: this display has no stable recovery identity."; continue }
                let origin = CGDisplayBounds(id).origin
                let record = DeskDesktopRecord(identity: identity, display: id, mode: mode.ioDisplayModeID,
                                               x: Int32(origin.x), y: Int32(origin.y), owner: owner, expires: now + DeskDesktopRecovery.lifetime, physical: physical)
                records.append(record); try DeskDesktopRecovery.save(records) // Durable recovery BEFORE mutation.
                try DeskDesktopRecovery.setEnabled(id, false)
            }
            return Set(records.map(\.identity))
        }
        if problem == nil { problem = note }
        return result
    }
    func restoreAll() {
        do {
            try DeskDesktopRecovery.locked { records in
                for record in records { if try DeskDesktopRecovery.restore(record) { records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records) } }
                disconnected = Set(records.map(\.identity))
            }
        } catch { problem = "Desktop reconnection needs attention: " + error.localizedDescription }
    }
    /// Main thread: keep reconciliation from disconnecting this display while
    /// a command (or an incoming picture) needs it.
    func hold(_ identity: String) { holds.insert(identity); awaySince[identity] = nil }
    func finishCommand(_ identity: String) { holds.remove(identity) }
    /// Any thread: reconnect a software-disconnected display so its video/DDC
    /// path exists. Explicit monitor commands need this; ordinary observation
    /// never reconnects a display just to poll it.
    func restoreHeld(_ identity: String) throws {
        let remaining = try DeskDesktopRecovery.locked { records -> Set<String> in
            for record in records where record.identity == identity {
                guard try DeskDesktopRecovery.restore(record) else { throw KVMError("Reconnect this display before switching its input.") }
                records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records)
            }
            return Set(records.map(\.identity))
        }
        DispatchQueue.main.async { [weak self] in if self?.disconnected != remaining { self?.disconnected = remaining } }
    }
    /// A monitor is about to be switched onto this display: make sure the
    /// display is connected before the picture arrives. Best effort.
    func prepareDestination(_ identity: String) {
        hold(identity)
        queue.async { [weak self] in
            try? self?.restoreHeld(identity)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.finishCommand(identity) }
        }
    }
}
