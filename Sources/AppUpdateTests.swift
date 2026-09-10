import AppKit

func runAppUpdateTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-update-fixture-" + UUID().uuidString)
    let target = root.appendingPathComponent("Perch.app")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try check(AppUpdate.sameLocation(target, URL(fileURLWithPath: target.path, isDirectory: true)), "Trailing directory slash changed app identity")
    var fail = false
    do { _ = try AppUpdate.identity(target, requirement: "identifier \"local.scott.perch\"") } catch { fail = true }
    try check(fail, "An unsigned restart was accepted")
    fail = false; do { _ = try AppUpdate.readRecord(root.appendingPathComponent("restart.json").path) } catch { fail = true }
    try check(fail, "A restart record outside private storage was accepted")
    try runDisposableUpdateWorkerTest()
    try runDisposableUpdateWorkerTest(cancel: true)
    let current: [String: Any] = ["PerchLidProtocolVersion": LidGuardCompatibility.protocolVersion, "PerchLidHelperVersion": LidGuardCompatibility.helperVersion, "CFBundleVersion": "1"]
    try check(!LidHelperUpdateState(info: current, lidOpen: false).pending, "App build changes unnecessarily replace the lid helper")
    let pending = LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: false)
    try check(pending.pending && pending.notice.contains("queued"), "Mismatched helper did not queue a visible update")
    try check(LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: true).notice.contains("ready"), "Opening the lid did not expose the next helper action")
    try check(!LidHelperUpdateState(info: [:], lidOpen: true).pending, "Optional uninstalled helper became a required update")
    let command = try LidGuardInstall.installationCommand(source: URL(fileURLWithPath: "/fixture/Perch.app"), requirement: "identifier \"fixture\"", owner: 501, requireOpenLid: true)
    try check(command.range(of: "--check-lid-update")!.lowerBound < command.range(of: "/bin/launchctl bootout")!.lowerBound, "Open-lid check occurs after stopping the old helper")
    let cleanupIndex = command.range(of: " --lid-cleanup")!.lowerBound
    let stopRecoveryIndex = command.range(of: "/bin/launchctl bootout system/" + LidGuardInstall.recoveryName)!.lowerBound
    try check(cleanupIndex < stopRecoveryIndex, "A failed cleanup could remove independent recovery during helper replacement")
    try check(AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: false, overrideOff: true), "Confirmed inactive closed-lid restart was blocked")
    try check(!AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: true, overrideOff: true), "An unowned lid session was dropped by restart")
    try check(!AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: false, overrideOff: false), "Unknown override state allowed closed-lid restart")
    var snapshot = SetupSnapshot(config: SafetyConfiguration()); snapshot.lidHelperUpdatePending = true
    try check(snapshot.checks.first(where: { $0.id == "awake" })?.route == .awake, "Queued helper update has no feature recovery route")
    let app = AppDelegate(); app.buildMenu()
    var helper = LidHelperSettingsSnapshot(helper: pending)
    app.configureSettings()
    let parentCount = SettingsWindow.shared.pages.count
    app.presentKeepAwakeSettings(readHelper: { helper })
    let host = SettingsWindow.shared, page = host.pages.last!
    let buttons = page.view.subviews.compactMap { $0 as? NSButton }
    let finish = buttons.first(where: { $0.title == "Finish lid helper update…" })!
    try check(!finish.isEnabled && !buttons.contains(where: { $0.title == "Updates…" || $0.title == "Done" }), "Closed-lid helper update allowed or retired Updates page retained")
    helper.helper = LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: true)
    host.pages.last?.refresh?()
    try check(finish.isEnabled, "Opening the lid did not expose helper completion")
    helper.busy = true; host.pages.last?.refresh?()
    try check(!finish.isEnabled, "Busy helper update allowed competing installation")
    helper.busy = false; helper.result = "Helper update is still queued. Administrator authorization was canceled."
    host.pages.last?.refresh?()
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-helper-update-recovery.png")
    host.goBack()
    try check(host.pages.count == parentCount, "Keep awake lost its parent route")
    app.presentKeepAwakeSettings(readHelper: { helper })
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.first!.stringValue.contains("canceled"), "Returning hid the failed helper result")
    host.goBack()
    var restartState = RestartSettingsSnapshot()
    var restarts = 0
    app.presentAppSettings(readRestart: { restartState }, restart: { restarts += 1; restartState.busy = true; restartState.message = "Preparing to restart…" })
    let restart = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Restart Perch" }!
    restart.performClick(nil)
    try check(restarts == 1 && !restart.isEnabled && host.pages.last?.title == "App settings", "Restart added another page or allowed duplicate requests")
    restartState.busy = false; restartState.message = "Restart did not confirm readiness. Perch is still running. Try Restart Perch again."
    host.pages.last?.refresh?()
    try check(restart.isEnabled, "Restart failure did not allow retry")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-restart-recovery.png")
    host.goBack()
    app.presentAppSettings(readRestart: { restartState }, restart: {})
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.first!.stringValue.contains("still running"), "Restart result was lost on Back/re-entry")
    host.goBack()
    print("PASS: verified restart worker; cancellation, unchanged bundle, closed-lid eligibility; helper update and restart busy/failure/retry/return routes")
}

/// Actual signed worker and launch acknowledgment, using only
/// copied isolated-test bundles and a disposable parent process. No helper or
/// lid session is involved. The production app does not enter this harness.
private func runDisposableUpdateWorkerTest(cancel: Bool = false) throws {
    guard Bundle.main.bundleIdentifier == "local.perch.functional-review" else { return }
    try DesktopTestSession.check()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("perch-worker-test-" + UUID().uuidString)
    let directory = AppUpdate.base.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        // Clean up only the completion subprocess this fixture recorded, with
        // birth-time validation so a reused PID is never signalled.
        if let data = try? Data(contentsOf: directory.appendingPathComponent("fixture-completer.json")),
           let process = try? JSONDecoder().decode([String: UInt64].self, from: data),
           let rawPID = process["pid"], rawPID > 1, rawPID <= UInt64(Int32.max),
           let birth = process["birth"], ProcessCPUReader.birth(Int32(rawPID)) == birth {
            kill(Int32(rawPID), SIGTERM)
        }
        try? fm.removeItem(at: root); try? fm.removeItem(at: directory)
    }
    let target = root.appendingPathComponent("Perch.app")
    try fm.copyItem(at: Bundle.main.bundleURL, to: target)
    let originalInode = try fm.attributesOfItem(atPath: target.path)[.systemFileNumber] as! NSNumber
    let identity = try AppUpdate.identity(target, requirement: HelperStatusIPC.requirement!)
    let candidate = AppUpdateCandidate(directory: directory, target: target, identity: identity)
    let parent = Process(); parent.executableURL = URL(fileURLWithPath: "/bin/sleep"); parent.arguments = ["25"]
    try parent.run()
    defer { if parent.isRunning { parent.terminate(); parent.waitUntilExit() } }
    guard let birth = ProcessCPUReader.birth(parent.processIdentifier) else { throw AppError(message: "Disposable parent has no birth identity") }
    let record = AppUpdateRecord(protocolVersion: 1, candidate: candidate, oldPID: parent.processIdentifier, oldBirth: birth, ticket: nil, expires: LidGuardClock.now + 30, attempt: UUID().uuidString)
    var incomplete = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
    incomplete.removeValue(forKey: "protocolVersion")
    try JSONSerialization.data(withJSONObject: incomplete).write(to: candidate.record, options: .atomic)
    var rejected = false
    do { _ = try AppUpdate.readRecord(candidate.record.path) } catch { rejected = true }
    try checkWorker(rejected, "An unversioned restart record was accepted")
    try JSONEncoder().encode(record).write(to: candidate.record, options: .atomic)
    let worker = Process(); worker.executableURL = target.appendingPathComponent("Contents/MacOS/Perch")
    worker.arguments = ["--restart-worker", candidate.record.path]
    try worker.run()
    defer { if worker.isRunning { worker.terminate(); worker.waitUntilExit() } }
    let ready = directory.appendingPathComponent("ready-" + record.attempt)
    let startDeadline = LidGuardClock.now + 5
    while worker.isRunning && LidGuardClock.now < startDeadline && !fm.fileExists(atPath: ready.path) { Thread.sleep(forTimeInterval: 0.05) }
    guard (try? String(contentsOf: ready, encoding: .utf8)) == identity else { throw AppError(message: "Signed update worker did not verify/acknowledge preparation") }
    try checkWorker(!fm.fileExists(atPath: directory.appendingPathComponent("fixture-completer.json").path), "Restart launched before the old process exited")
    if cancel { try Data().write(to: directory.appendingPathComponent("cancel-" + record.attempt)) }
    else { parent.terminate(); parent.waitUntilExit() } // Only this test's own /bin/sleep.
    let end = LidGuardClock.now + 20
    while worker.isRunning && LidGuardClock.now < end { Thread.sleep(forTimeInterval: 0.05) }
    if cancel {
        try checkWorker(!worker.isRunning && worker.terminationStatus == 0 && parent.isRunning && !fm.fileExists(atPath: directory.appendingPathComponent("result.json").path), "Canceled restart exited the parent or launched a replacement")
        return
    }
    do {
        try checkWorker(try fm.attributesOfItem(atPath: target.path)[.systemFileNumber] as? NSNumber == originalInode, "Plain restart replaced the app bundle")
        try checkWorker(try fm.contentsOfDirectory(atPath: root.path) == ["Perch.app"], "Plain restart created an update backup")
    }
    guard !worker.isRunning, worker.terminationStatus == 0,
          let data = try? Data(contentsOf: directory.appendingPathComponent("result.json")),
          let receipt = try? JSONDecoder().decode(AppUpdateReceipt.self, from: data), receipt.resumed, receipt.identity == identity,
          try AppUpdate.identity(target, requirement: HelperStatusIPC.requirement!) == identity else {
        if let info = try? Data(contentsOf: directory.appendingPathComponent("fixture-completer.json")),
           let process = try? JSONDecoder().decode([String: UInt64].self, from: info), let pid = process["pid"], let birth = process["birth"],
           pid <= UInt64(Int32.max), ProcessCPUReader.birth(Int32(pid)) == birth {
            let sample = Process(); sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            sample.arguments = [String(pid), "1", "1", "-file", "/private/tmp/perch-update-completion-stack.txt"]
            try? sample.run(); sample.waitUntilExit()
        }
        throw AppError(message: "Disposable signed worker restart/launch/acknowledgment failed")
    }
    print("PASS: signed restart worker acknowledged preparation, waited for its disposable parent and received launch completion; no live helper or lid session")
}

private func checkWorker(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
