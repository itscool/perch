import Foundation
import IOKit

private final class FakeLidHardware: LidGuardHardware {
    var observation = LidObservation(closed: false, power: .external)
    var calls: [String] = []
    var rejectOverride = false
    var rejectSleep = false
    func observe() -> LidObservation { observation }
    func preventLidSleep(_ enabled: Bool) throws {
        calls.append(enabled ? "prevent lid" : "release lid")
        if rejectOverride { throw AppError(message: "Fixture authorization/control failure") }
    }
    func requestSleep() throws { calls.append("request sleep"); if rejectSleep { throw AppError(message: "Fixture sleep failure") } }
}

func runLidGuardTests() throws {
    try runLidOverrideTests()
    try runLidRestartTests()
    try runAppUpdateTests()
    try runLidActivityTests()
    try runLidGuardSessionTests()
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    for observation in [LidObservation(closed: true, power: .external), .init(closed: false, power: .external), .init(closed: false, power: .battery)] {
        try LidGuardStart.validate(observation)
    }
    for observation in [LidObservation(closed: true, power: .battery), .init(closed: nil, power: .external), .init(closed: nil, power: .battery), .init(closed: false, power: .unknown), .init(closed: true, power: .unknown), .init(closed: nil, power: .unknown)] {
        var rejected = false
        do { try LidGuardStart.validate(observation) } catch { rejected = true }
        try check(rejected, "A new closed-battery or unknown-state session was accepted")
    }
    // Revalidation during the handshake must catch unplugging before activation.
    try LidGuardStart.validate(.init(closed: true, power: .external))
    var rejectedAfterUnplugging = false
    do { try LidGuardStart.validate(.init(closed: true, power: .battery)) } catch { rejectedAfterUnplugging = true }
    try check(rejectedAfterUnplugging, "A startup power change escaped revalidation")
    // Exercise the production connection setup, which the mutation mocks used
    // to hide. No power method or sleep request is sent over this connection.
    let connection = try MacLidGuardHardware.openPowerConnection()
    try check(IOServiceClose(connection) == KERN_SUCCESS, "Power connection did not close cleanly")
    // Read the real persistent and live keys without issuing any power command.
    try LidSleepOverride.verify(LidSleepOverride.systemDisabled())
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("perch-lid-upgrade-" + UUID().uuidString)
    let contents = fixture.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }
    let executable = contents.appendingPathComponent("MacOS/Perch")
    let current: [String: Any] = ["CFBundleIdentifier": "fixture.perch", "CFBundleVersion": "44"]
    var installed = current; installed["CFBundleVersion"] = "43"
    try PropertyListSerialization.data(fromPropertyList: installed, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try check(LidGuardInstall.cleanupRequiresUpdate(appInfo: current, executable: executable), "Cleanup would retry the older helper instead of upgrading it")
    try PropertyListSerialization.data(fromPropertyList: current, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try check(!LidGuardInstall.cleanupRequiresUpdate(appInfo: current, executable: executable), "Matching helper unnecessarily requires installation for cleanup")
    installed["CFBundleVersion"] = "63"
    try PropertyListSerialization.data(fromPropertyList: installed, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try check(!LidGuardInstall.cleanupRequiresUpdate(appInfo: current, executable: executable), "Explicit cleanup unnecessarily installed a queued app-only helper update")
    let closedBattery = LidObservation(closed: true, power: .battery), closedAC = LidObservation(closed: true, power: .external)
    var policy = LidGuardPolicy()
    try check(policy.step(closedAC, now: 0, authorized: true).preventLidSleep, "Closed powered operation failed")
    try check(policy.step(closedAC, now: 86_400, authorized: true).remaining == nil, "Powered operation gained a battery deadline")
    try check(policy.step(closedBattery, now: 86_401, authorized: true).remaining == 60, "Undocking did not give 60 seconds to open the lid")
    try check(policy.step(closedBattery, now: 86_460.9, authorized: true).preventLidSleep, "Battery grace ended before 60 seconds")
    let expiry = policy.step(closedBattery, now: 86_461, authorized: true)
    try check(expiry.requestSleep && !expiry.preventLidSleep && expiry.remaining == 0, "60-second expiry did not demand actual sleep")
    try check(!policy.step(closedAC, now: 86_470, authorized: true).preventLidSleep, "A late power connection revived an expired session")
    policy = LidGuardPolicy()
    _ = policy.step(closedBattery, now: 0, authorized: true)
    try check(policy.step(.init(closed: false, power: .battery), now: 59, authorized: true).remaining == nil, "Opening did not cancel countdown")
    try check(policy.step(closedBattery, now: 100, authorized: true).remaining == 60, "A new close did not get its own full interval")
    _ = policy.step(closedAC, now: 120, authorized: true)
    try check(policy.step(closedBattery, now: 121, authorized: true).remaining == 39, "A brief power flap restarted the clock")
    _ = policy.step(closedAC, now: 130, authorized: true); _ = policy.step(closedAC, now: 135, authorized: true)
    try check(policy.step(closedBattery, now: 200, authorized: true).remaining == 60, "Stable docking failed to reset the next undocking interval")
    for observation in [closedBattery, LidObservation(closed: nil, power: .battery), LidObservation(closed: true, power: .unknown)] {
        policy = LidGuardPolicy(); _ = policy.step(closedBattery, now: 0, authorized: true)
        let result = policy.step(observation, now: 2, authorized: false)
        try check(!result.preventLidSleep && result.requestSleep, "Lost authorization/unknown sensor allowed indefinite closed-battery operation")
        try check(!policy.step(closedBattery, now: 3, authorized: true).preventLidSleep, "Late lease renewal resurrected a stopped session")
    }
    policy = LidGuardPolicy(); _ = policy.step(closedBattery, now: 100, authorized: true)
    try check(policy.step(closedBattery, now: 90, authorized: true).requestSleep, "Stale/reversed time extended grace")
    policy = LidGuardPolicy(); _ = policy.step(closedBattery, now: 0, authorized: true)
    try check(policy.step(closedBattery, now: 3600, authorized: true).requestSleep, "Time spent asleep or a stalled helper reset the deadline")
    let hardware = FakeLidHardware(), enforcer = LidGuardEnforcer(hardware)
    try enforcer.apply(.init(preventLidSleep: true, requestSleep: false, remaining: 60, detail: ""), now: 0)
    try enforcer.apply(expiry, now: 60)
    try check(hardware.calls == ["prevent lid", "release lid", "request sleep"], "Release-before-sleep sequence was \(hardware.calls)")
    hardware.rejectSleep = true
    var rejected = false
    do { try enforcer.apply(expiry, now: 70) } catch { rejected = error.localizedDescription == "Fixture sleep failure" }
    try check(rejected, "Sleep rejection was not reported")
    hardware.rejectSleep = false; try enforcer.apply(expiry, now: 71)
    try check(hardware.calls.suffix(2) == ["request sleep", "request sleep"], "A failed sleep request suppressed retry")
    // A macOS sleep transition invalidates the session independently of a
    // healthy transport. No second sleep command or automatic re-arm on wake.
    var interrupted = LidGuardPolicy()
    let interruptedHardware = FakeLidHardware(), interruptedEnforcer = LidGuardEnforcer(interruptedHardware)
    try interruptedEnforcer.apply(interrupted.step(closedAC, now: 0, authorized: true), now: 0)
    _ = interrupted.step(closedBattery, now: 1, authorized: true)
    interrupted.systemSleepBegan()
    try interruptedEnforcer.apply(interrupted.step(closedBattery, now: 2, authorized: true), now: 2)
    let afterWake = interrupted.step(closedAC, now: 31.7, authorized: true)
    try check(!afterWake.preventLidSleep && !afterWake.requestSleep && interrupted.sleepInterruption != nil, "Wake cleared the sleep interruption or revived the session")
    try check(interruptedHardware.calls == ["prevent lid", "release lid"], "Sleep notification sent another sleep command or retained prevention")
    try check(LidGuardStatus(updatedAt: LidGuardClock.now, armed: true, detail: "Lid closed on power.").displayDetail.contains("unverified"), "Command acceptance still claims verified sleep prevention")
    let session = UUID().uuidString
    var watcher = LidGuardWatchdogState()
    try check(watcher.receive(.init(token: session, expires: 3, deadline: 60), now: 0), "Valid watchdog lease rejected")
    try check(watcher.evaluate(closedBattery, now: 0, channelAlive: true).preventLidSleep, "Watchdog rejected a fresh authorized session")
    try check(watcher.evaluate(closedBattery, now: 3, channelAlive: true).requestSleep, "Supervisor stall did not expire the independent watchdog lease")
    _ = watcher.receive(.init(token: session, expires: 6, deadline: 60), now: 3)
    try check(!watcher.evaluate(closedBattery, now: 3, channelAlive: true).preventLidSleep, "A late supervisor heartbeat revived a stopped session")
    _ = watcher.receive(.init(token: UUID().uuidString, expires: 6, deadline: 60), now: 3)
    try check(watcher.evaluate(closedBattery, now: 4, channelAlive: false).requestSleep, "Supervisor pipe closure left control enabled")
    try check(!watcher.receive(.init(token: session, expires: 1000, deadline: nil), now: 4), "Unbounded watchdog lease accepted")
    let lease = LidGuardLease(token: session, expires: 5, deadline: 60)
    try check(!lease.acceptsRenewal(UUID().uuidString, now: 1) && !lease.acceptsRenewal(session, now: 5) && lease.acceptsRenewal(session, now: 4), "Wrong or expired menu-app renewal was accepted")
    let unsupported = FakeLidHardware(); unsupported.rejectOverride = true
    let unavailable = LidGuardEnforcer(unsupported)
    do { try unavailable.apply(.init(preventLidSleep: true, requestSleep: false, remaining: nil, detail: ""), now: 1); throw AppError(message: "Unsupported control appeared armed") }
    catch { try check(!unavailable.preventing && unsupported.calls == ["prevent lid", "release lid"], "Failed control readback did not attempt cleanup") }
    let now = LidGuardClock.now
    let failedStart = LidGuardStatus(updatedAt: now, armed: false, detail: "Control rejected", error: "Control rejected")
    try check(LidGuardClient.controlState(legacyDisabled: false, status: failedStart, recordedSession: false) == .off, "A cleaned-up failed lid start blocks ordinary Keep awake controls")
    try check(LidGuardClient.controlState(legacyDisabled: false, status: failedStart, recordedSession: true) == .mixed, "An unfinished lid session appeared off")
    try check(LidGuardClient.controlState(legacyDisabled: nil, status: nil, recordedSession: false) == .mixed, "Unknown legacy override appeared off")
    try check(LidGuardClient.controlState(legacyDisabled: false, status: .init(updatedAt: now, armed: true, detail: "Enabled"), recordedSession: true) == .on, "A current active session did not appear enabled")
    try check(LidGuardStatus(updatedAt: now, armed: false, detail: "Off").fresh, "The current signed helper identity was not recognized")
    var older = LidGuardStatus(updatedAt: now, armed: true, detail: "Ready"); older.codeIdentity = "older-executable"
    try check(older.fresh, "A compatible helper required replacement for an app-only update")
    older.revision = 1
    try check(!older.fresh, "An incompatible helper protocol was accepted")
    try check(!LidGuardStatus(updatedAt: now - 10, armed: true, detail: "Ready").fresh && !LidGuardStatus(updatedAt: now + 10, armed: true, detail: "Ready").fresh, "Stale or future status appeared ready")
    let command = try LidGuardInstall.installationCommand(source: URL(fileURLWithPath: "/fixture/Perch ' $(literal).app"), requirement: "identifier \"fixture.perch\"", owner: 501)
    let script = FileManager.default.temporaryDirectory.appendingPathComponent("perch-lid-script-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: script) }
    try command.write(to: script, atomically: true, encoding: .utf8)
    let parser = Process(); parser.executableURL = URL(fileURLWithPath: "/bin/sh"); parser.arguments = ["-n", script.path]
    try parser.run(); parser.waitUntilExit()
    try check(parser.terminationStatus == 0 && command.contains("'=identifier") && command.contains("/Contents/MacOS/Perch' --lid-cleanup"), "Installer quoting or complete-bundle path is invalid")
    print("PASS: powered closed-lid startup; rejected closed-battery/unknown startup and power-change revalidation; real read-only power connection; stale cleanup helper upgrade; full 60-second undock/close grace; powered operation; open/power cancellation; flapping; continuous deadlines; late renewals; failed observations/authorization; release-before-sleep and rejected-sleep retry; all power mutations injected")
}
