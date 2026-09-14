import Foundation

func runDeskDesktopTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw KVMError(message) } }
    let status = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: false, inputTrusted: nil, inputActive: false, keepAwakeActive: false, trackedCount: 0, targets: [], message: "Fixture")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
    legacy.removeValue(forKey: "desktopRecoverySupported")
    let oldHelper = try JSONDecoder().decode(SafetyStatus.self, from: JSONSerialization.data(withJSONObject: legacy))
    try check(status.desktopRecoverySupported == true && oldHelper.desktopRecoverySupported == nil, "A helper without recovery support was treated as capable")
    let group = DeskModel.sample(), local = group.computers[0].id
    let all = Set(group.computers.map(\.id))
    let monitor = group.monitors[0].id
    let own = group.connections.first { $0.monitor == monitor && $0.computer == local }!
    let other = group.connections.first { $0.monitor == monitor && $0.computer != nil && $0.computer != local }!
    for connected in [Set<UUID>(), Set([local]), all] {
        for code in [nil, own.inputCode, other.inputCode, UInt16(65535)] {
            let inputs = code.map { [monitor: $0] } ?? [:]
            let result = DeskDesktopHandoff.awayDisplays(group: group, local: local, inputs: inputs, online: connected)
            let allowed = code == other.inputCode && connected.contains(other.computer!)
            try check(result.contains(own.localDisplay!) == allowed, "Desktop ownership trusted an unknown/local/offline destination")
        }
    }
    var unassigned = group
    let index = unassigned.connections.firstIndex { $0.id == other.id }!
    unassigned.connections[index].computer = nil
    try check(DeskDesktopHandoff.awayDisplays(group: unassigned, local: local, inputs: [monitor: other.inputCode!], online: all).isEmpty, "Unassigned input authorized disconnect")
    var ambiguous = group
    ambiguous.connections.append(.init(monitor: monitor, computer: local, localDisplay: own.localDisplay, inputName: "Duplicate", inputCode: other.inputCode))
    try check(DeskDesktopHandoff.awayDisplays(group: ambiguous, local: local, inputs: [monitor: other.inputCode!], online: all).isEmpty, "Ambiguous input authorized disconnect")
    let owner = ProcessIdentity(pid: 100, uid: getuid(), seconds: 1, microseconds: 0)
    let replacement = ProcessIdentity(pid: 100, uid: getuid(), seconds: 2, microseconds: 0)
    let record = DeskDesktopRecord(identity: UUID().uuidString, display: 3, mode: 48, x: 2560, y: 0, owner: owner, expires: 108)
    try check(!DeskDesktopRecovery.expired(record, now: 100, owner: owner), "Fresh recovery lease expired")
    for now in [108, 109, 99, Double.nan, Double.infinity] {
        try check(DeskDesktopRecovery.expired(record, now: now, owner: owner), "Expired/reset/invalid clock retained desktop disconnection")
    }
    try check(DeskDesktopRecovery.expired(record, now: 100, owner: nil) && DeskDesktopRecovery.expired(record, now: 100, owner: replacement), "Dead/reused PID retained desktop disconnection")
    try check(try JSONDecoder().decode(DeskDesktopRecord.self, from: JSONEncoder().encode(record)) == record, "Recovery record lost display configuration")
    print("PASS: desktop ownership unknown/local/remote/offline/unassigned/ambiguous; exact lease expiry, clock reset, process death/PID reuse and recovery record round trip; no display writes")
}
