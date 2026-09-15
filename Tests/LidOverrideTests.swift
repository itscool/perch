import Foundation
import Darwin

/// Invoked only by the isolated test runner, with a fixture-owned directory.
func runLidLockFixture(_ directory: String) throws {
    let folder = URL(fileURLWithPath: directory).resolvingSymlinksInPath()
    guard folder.lastPathComponent.hasPrefix("perch-lid-override-test-"),
          folder.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        throw AppError(message: "Invalid lock fixture directory")
    }
    let fd = try LidOverrideLock.acquire(path: folder.appendingPathComponent("lock").path, owner: getuid(), recover: false, mayStop: { _ in false })
    defer { close(fd) }
    try Data("ready".utf8).write(to: folder.appendingPathComponent("ready"))
    raise(SIGSTOP) // Only this disposable fixture process; never a live helper.
    try Data("late write".utf8).write(to: folder.appendingPathComponent("late"))
}

func runLidOverrideTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func rejected(_ operation: () throws -> Void) -> Bool { do { try operation(); return false } catch { return true } }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("perch-lid-override-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LidOverrideStore(directory: directory, lockPath: directory.appendingPathComponent("lock").path,
                                 leasePath: directory.appendingPathComponent("lease").path, owner: getuid())
    let token = UUID().uuidString, other = UUID().uuidString
    try check(rejected { try store.reserve(token: token, disabled: true) } && !store.ownsOverride, "Took ownership of an existing system override")
    try store.reserve(token: token, disabled: false)
    try check(store.ownsOverride && (try store.record()) == LidOverrideRecord(token: token), "Durable ownership was not saved before the write")
    // Reconstructing the store after a crash/reboot must retain recovery intent.
    let reopened = LidOverrideStore(directory: directory, lockPath: store.lockPath, leasePath: store.leasePath, owner: getuid())
    try check(try reopened.record().token == token, "Recovery intent did not survive process reconstruction")
    try check(rejected { try reopened.reserve(token: other, disabled: true) }, "A newer session overwrote unfinished recovery")
    try check(rejected { try reopened.finish(disabled: true) } && reopened.ownsOverride, "Cleanup erased ownership before confirming restoration")
    try reopened.finish(disabled: false)
    try check(!reopened.ownsOverride, "Successful restoration retained its ownership marker")
    let outside = directory.appendingPathComponent("outside")
    try Data("untouched".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(atPath: store.recordPath, withDestinationPath: outside.path)
    try check(rejected { try store.reserve(token: token, disabled: false) }, "Symlink ownership was followed")
    try check(try String(contentsOf: outside, encoding: .utf8) == "untouched", "Invalid ownership touched another file")
    try FileManager.default.removeItem(atPath: store.recordPath)
    let lease = LidOverrideRecoveryLease(token: token, boot: "boot-1", expires: 13, pid: 123, birth: 8)
    try check(lease.fresh(token: token, boot: "boot-1", now: 11, birth: 8), "Healthy recovery lease was rejected")
    for value in [(token, "boot-2", 11.0, UInt64(8)), (other, "boot-1", 11.0, UInt64(8)),
                  (token, "boot-1", 13.0, UInt64(8)), (token, "boot-1", 11.0, UInt64(9)),
                  (token, "boot-1", 1.0, UInt64(8))] {
        try check(!lease.fresh(token: value.0, boot: value.1, now: value.2, birth: value.3), "Reboot, expiry, future lease or reused process retained a persistent override")
    }
    // Replay the newly requested physical ordering, independently of the adapter.
    var policy = LidGuardPolicy()
    _ = policy.step(.init(closed: false, power: .battery), now: 0, authorized: true)
    try check(policy.step(.init(closed: true, power: .battery), now: 1, authorized: true).remaining == 60, "Closing while already unplugged lost its 60-second grace")
    try check(!policy.step(.init(closed: true, power: .external), now: 6, authorized: true).requestSleep, "Plugging in during the grace interval requested sleep")
    _ = policy.step(.init(closed: false, power: .external), now: 8, authorized: true)
    try check(policy.step(.init(closed: true, power: .battery), now: 20, authorized: true).remaining == 60, "Opening after reconnect did not reset the next interval")
    try check(policy.step(.init(closed: true, power: .battery), now: 80, authorized: true).requestSleep, "Persistent adapter bypassed the normal 60-second policy")

    let fixture = Process(), ended = DispatchSemaphore(value: 0)
    fixture.executableURL = Bundle.main.executableURL
    fixture.arguments = ["--lid-lock-fixture", directory.path]
    fixture.standardOutput = FileHandle.nullDevice; fixture.standardError = FileHandle.nullDevice
    fixture.terminationHandler = { _ in ended.signal() }
    try fixture.run()
    let fixturePID = fixture.processIdentifier, fixtureBirth = ProcessCPUReader.birth(fixturePID)
    defer { if fixture.isRunning { _ = kill(fixturePID, SIGKILL) }; _ = ended.wait(timeout: .now() + 1) }
    let until = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path), Date() < until { usleep(10_000) }
    try check(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path), "Disposable lock holder did not start")
    // A denied identity must not kill even this disposable process.
    try check(rejected { _ = try LidOverrideLock.acquire(path: store.lockPath, owner: getuid(), recover: true, mayStop: { _ in false }) } && fixture.isRunning, "Lock recovery ignored identity validation")
    let fd = try LidOverrideLock.acquire(path: store.lockPath, owner: getuid(), recover: true, mayStop: {
        $0 == fixturePID && fixtureBirth != nil && ProcessCPUReader.birth($0) == fixtureBirth
    })
    close(fd)
    try check(ended.wait(timeout: .now() + 1) == .success && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("late").path), "Stopped writer could mutate after cleanup acquired its lock")
    print("PASS: durable override ownership, previous-setting refusal, failed-cleanup retention, reboot/lease/PID recovery, unplugged-open/close/plug/open policy and revocation of an isolated stopped writer; no live power changes")
}
