import AppKit

func runAppUpdateTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-update-fixture-" + UUID().uuidString)
    let target = root.appendingPathComponent("Perch.app"), staged = root.appendingPathComponent("Next.app"), backup = root.appendingPathComponent("Backup.app")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: target.appendingPathComponent("fixture"))
    try Data("new".utf8).write(to: staged.appendingPathComponent("fixture"))
    try AppUpdate.validateTarget(target)
    try check(AppUpdate.sameLocation(target, URL(fileURLWithPath: target.path, isDirectory: true)), "Trailing directory slash changed app identity")
    var fail = false
    do {
        try AppUpdate.replace(staged: staged, target: target, backup: backup) { from, to in
            if from == staged { throw AppError(message: "injected destination failure") }
            try FileManager.default.moveItem(at: from, to: to)
        }
    } catch { fail = true }
    try check(fail && (try? Data(contentsOf: target.appendingPathComponent("fixture"))) == Data("old".utf8), "Failed replacement lost the previous app")
    try AppUpdate.replace(staged: staged, target: target, backup: backup)
    try check((try? Data(contentsOf: target.appendingPathComponent("fixture"))) == Data("new".utf8) && (try? Data(contentsOf: backup.appendingPathComponent("fixture"))) == Data("old".utf8), "Successful replacement lost its recovery copy")
    let link = root.appendingPathComponent("Linked.app")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    fail = false; do { try AppUpdate.validateTarget(link) } catch { fail = true }
    try check(fail, "A symbolic-link update target was accepted")
    fail = false; do { _ = try AppUpdate.identity(target, requirement: "identifier \"local.scott.perch\"") } catch { fail = true }
    try check(fail, "An unsigned update was accepted")
    fail = false; do { _ = try AppUpdate.readRecord(root.appendingPathComponent("restart.json").path) } catch { fail = true }
    try check(fail, "An update record outside private staging was accepted")
    try runDisposableUpdateWorkerTest()
    let current: [String: Any] = ["PerchLidProtocolVersion": LidGuardCompatibility.protocolVersion, "PerchLidHelperVersion": LidGuardCompatibility.helperVersion, "CFBundleVersion": "1"]
    try check(!LidHelperUpdateState(info: current, lidOpen: false).pending, "App build changes unnecessarily replace the lid helper")
    let pending = LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: false)
    try check(pending.pending && pending.notice.contains("queued"), "Legacy helper did not queue a visible update")
    try check(LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: true).notice.contains("ready"), "Opening the lid did not expose the next helper action")
    try check(!LidHelperUpdateState(info: [:], lidOpen: true).pending, "Optional uninstalled helper became a required update")
    let command = try LidGuardInstall.installationCommand(source: URL(fileURLWithPath: "/fixture/Perch.app"), requirement: "identifier \"fixture\"", owner: 501, requireOpenLid: true)
    try check(command.range(of: "--check-lid-update")!.lowerBound < command.range(of: "/bin/launchctl bootout")!.lowerBound, "Open-lid check occurs after stopping the old helper")
    let cleanupIndex = command.range(of: " --lid-cleanup")!.lowerBound
    let stopRecoveryIndex = command.range(of: "/bin/launchctl bootout system/" + LidGuardInstall.recoveryName)!.lowerBound
    try check(cleanupIndex < stopRecoveryIndex, "A failed cleanup could remove independent recovery during helper replacement")
    var snapshot = SetupSnapshot(config: SafetyConfiguration()); snapshot.lidHelperUpdatePending = true
    try check(snapshot.checks.first(where: { $0.id == "awake" })?.route == .updates, "Queued helper update has no overview recovery route")
    let app = AppDelegate()
    var snapshotUI = UpdateSettingsSnapshot(message: "Choose a newer signed Perch app to prepare an update.", helper: pending)
    app.configureSettings(); app.appSettings()
    let parentCount = SettingsWindow.shared.pages.count
    app.presentUpdateSettings(read: { snapshotUI })
    let host = SettingsWindow.shared, page = host.pages.last!
    let buttons = page.view.subviews.compactMap { $0 as? NSButton }
    let restart = buttons.first(where: { $0.title == "Update & restart" })!
    let finish = buttons.first(where: { $0.title.contains("finish helper") })!
    try check(!buttons.contains(where: { $0.title == "Done" }) && !restart.isEnabled && !finish.isEnabled, "Updates allowed restart without staging, a closed-lid helper replacement, or an extra exit")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-updates-queued.png")
    snapshotUI.prepared = true; snapshotUI.message = "Build 999 is ready. Your saved choices will be kept."
    snapshotUI.helper = LidHelperUpdateState(info: ["CFBundleVersion": "63"], lidOpen: true)
    host.pages.last?.refresh?()
    try check(restart.isEnabled && finish.isEnabled && finish.title == "Finish helper update…", "Opening the lid did not expose queued completion without re-entering the page")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-updates-ready.png")
    snapshotUI.busy = true; host.pages.last?.refresh?()
    try check(!restart.isEnabled && !finish.isEnabled && !buttons[0].isEnabled, "An active update allowed competing operations")
    snapshotUI.busy = false; snapshotUI.prepared = false
    snapshotUI.message = "Restart preparation was not confirmed. Perch is still running; review Keep awake because the lid session may end if the helper connection was lost."
    host.pages.last?.refresh?()
    let status = page.view.subviews.compactMap { $0 as? NSTextField }.first!
    let size = status.attributedStringValue.boundingRect(with: NSSize(width: status.frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
    try check(ceil(size.height) <= status.frame.height, "Update recovery status is clipped")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-updates-recovery.png")
    host.goBack()
    try check(host.pages.count == parentCount, "Updates lost its parent route")
    app.presentUpdateSettings(read: { snapshotUI })
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.first!.stringValue.contains("not confirmed"), "Returning hid the failed update result")
    host.goBack(); host.goBack()
    print("PASS: transactional app replacement and rollback; symlink/unsigned/invalid record rejection; independent helper revision, queued/open-lid/busy/recovery states, pre-stop installer guard and Updates navigation; temporary files only")
}

/// Actual signed worker + replacement + launch acknowledgment, using only
/// copied isolated-test bundles and a disposable parent process. No helper or
/// lid session is involved. The production app does not enter this harness.
private func runDisposableUpdateWorkerTest() throws {
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
    let target = root.appendingPathComponent("Perch.app"), staged = directory.appendingPathComponent("Perch.app")
    try fm.copyItem(at: Bundle.main.bundleURL, to: target)
    try fm.copyItem(at: Bundle.main.bundleURL, to: staged)
    let identity = try AppUpdate.identity(staged, requirement: HelperStatusIPC.requirement!)
    let candidate = AppUpdateCandidate(directory: directory, target: target, identity: identity, oldIdentity: identity, build: 999)
    let parent = Process(); parent.executableURL = URL(fileURLWithPath: "/bin/sleep"); parent.arguments = ["25"]
    try parent.run()
    defer { if parent.isRunning { parent.terminate(); parent.waitUntilExit() } }
    guard let birth = ProcessCPUReader.birth(parent.processIdentifier) else { throw AppError(message: "Disposable parent has no birth identity") }
    let record = AppUpdateRecord(candidate: candidate, oldPID: parent.processIdentifier, oldBirth: birth, ticket: nil, expires: LidGuardClock.now + 30, attempt: UUID().uuidString)
    try JSONEncoder().encode(record).write(to: candidate.record, options: .atomic)
    let worker = Process(); worker.executableURL = staged.appendingPathComponent("Contents/MacOS/Perch")
    worker.arguments = ["--apply-update", candidate.record.path]
    try worker.run()
    defer { if worker.isRunning { worker.terminate(); worker.waitUntilExit() } }
    let ready = directory.appendingPathComponent("ready-" + record.attempt)
    let startDeadline = LidGuardClock.now + 5
    while worker.isRunning && LidGuardClock.now < startDeadline && !fm.fileExists(atPath: ready.path) { Thread.sleep(forTimeInterval: 0.05) }
    guard (try? String(contentsOf: ready, encoding: .utf8)) == identity else { throw AppError(message: "Signed update worker did not verify/acknowledge preparation") }
    parent.terminate(); parent.waitUntilExit() // Only this test's own /bin/sleep.
    let end = LidGuardClock.now + 20
    while worker.isRunning && LidGuardClock.now < end { Thread.sleep(forTimeInterval: 0.05) }
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
        throw AppError(message: "Disposable signed worker replacement/launch/acknowledgment failed")
    }
    print("PASS: actual signed updater worker acknowledged preparation, waited for its disposable parent, replaced copied fixture app, launched fixture completion and received acknowledgment; no live helper or lid session")
}
