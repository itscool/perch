import AppKit

/// Desired monitor input is not evidence of desktop ownership. Only fresh,
/// generation-matched monitor readback can temporarily remove desktop space.
final class DeskDesktopHandoff {
    private let local: UUID
    private let group: () -> KVMGroup
    private let inputs: () -> [UUID: UInt16]
    private let online: () -> Set<UUID>
    private let suspended: () -> Bool
    private var timer: Timer?
    private var holds: Set<String> = []
    private(set) var problem: String?
    private(set) var disconnected: Set<String> = []
    init(local: UUID, group: @escaping () -> KVMGroup, inputs: @escaping () -> [UUID: UInt16], online: @escaping () -> Set<UUID>, suspended: @escaping () -> Bool) {
        self.local = local; self.group = group; self.inputs = inputs; self.online = online; self.suspended = suspended
    }
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.reconcile() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
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
    func reconcile() {
        guard !SettingsWindow.shared.testing else { return }
        let helper = HelperStatusIPC.guardianClient.value
        let ready = helper?.fresh == true && helper?.compatible == true && helper?.desktopRecoverySupported == true && !suspended()
        let requested = Self.awayDisplays(group: group(), local: local, inputs: inputs(), online: online()).subtracting(holds)
        let wanted = ready ? requested : []
        problem = !ready && !requested.isEmpty ? "Desktop handoff needs a matching background helper. Open Setup → Background helpers." : nil
        do {
            try DeskDesktopRecovery.locked { records in
                guard let owner = ProcessTable.inspect(getpid())?.identity else { throw KVMError("Desktop recovery cannot identify this Perch process.") }
                // Take over no previous process's lease. Restore it before making
                // another handoff, even when that display is still wanted away.
                for record in records where record.owner != owner || !wanted.contains(record.identity) || DeskDesktopRecovery.expired(record, now: ProcessInfo.processInfo.systemUptime, owner: owner) {
                    if try DeskDesktopRecovery.restore(record) { records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records) }
                }
                let now = ProcessInfo.processInfo.systemUptime
                for index in records.indices where records[index].owner == owner && wanted.contains(records[index].identity) { records[index].expires = now + DeskDesktopRecovery.lifetime }
                if !records.isEmpty { try DeskDesktopRecovery.save(records) }
                let candidates = DeskDesktopRecovery.displays().filter { id in
                    CGDisplayIsBuiltin(id) == 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0 &&
                    DeskDesktopRecovery.identity(id).map(wanted.contains) == true
                }
                for id in candidates {
                    guard let identity = DeskDesktopRecovery.identity(id), !records.contains(where: { $0.identity == identity }) else { continue }
                    // Keep a usable display. A closed built-in display never counts,
                    // and other screens being handed away cannot be the fallback.
                    let remaining = DeskDesktopRecovery.displays().filter { other in
                        guard other != id, CGDisplayIsActive(other) != 0, CGDisplayIsAsleep(other) == 0,
                              let identity = DeskDesktopRecovery.identity(other), !wanted.contains(identity) else { return false }
                        return CGDisplayIsBuiltin(other) == 0 || MacLidGuardHardware().observe().closed == false
                    }
                    guard !remaining.isEmpty else { problem = "Desktop kept connected: no other usable display remains on this Mac."; continue }
                    guard let mode = CGDisplayCopyDisplayMode(id), let physical = DeskDesktopRecovery.physicalIdentity(id) else { problem = "Desktop kept connected: this display has no stable recovery identity."; continue }
                    let origin = CGDisplayBounds(id).origin
                    let record = DeskDesktopRecord(identity: identity, display: id, mode: mode.ioDisplayModeID,
                                                   x: Int32(origin.x), y: Int32(origin.y), owner: owner, expires: now + DeskDesktopRecovery.lifetime, physical: physical)
                    records.append(record); try DeskDesktopRecovery.save(records) // Durable recovery BEFORE mutation.
                    try DeskDesktopRecovery.setEnabled(id, false)
                }
                disconnected = Set(records.map(\.identity))
            }
        } catch { problem = "Desktop handoff needs attention: " + error.localizedDescription }
    }
    func restoreAll() {
        do {
            try DeskDesktopRecovery.locked { records in
                for record in records { if try DeskDesktopRecovery.restore(record) { records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records) } }
                disconnected = Set(records.map(\.identity))
            }
        } catch { problem = "Desktop reconnection needs attention: " + error.localizedDescription }
    }
    /// Explicit monitor commands may need their local video/DDC path restored.
    /// Ordinary observation never reconnects a display just to poll it.
    func prepareCommand(_ identity: String) -> Bool {
        holds.insert(identity)
        do {
            try DeskDesktopRecovery.locked { records in
                for record in records where record.identity == identity {
                    guard try DeskDesktopRecovery.restore(record) else { throw KVMError("Reconnect this display before switching its input.") }
                    records.removeAll { $0 == record }; try DeskDesktopRecovery.save(records)
                }
                disconnected = Set(records.map(\.identity))
            }
            return true
        } catch { problem = error.localizedDescription; holds.remove(identity); return false }
    }
    func finishCommand(_ identity: String) { holds.remove(identity) }
}
