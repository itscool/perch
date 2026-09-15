import AppKit

/// Fast regression tests from the September 15 focused review: Core services,
/// app entry, menu, agent kill switch and updates. Each runs in well under a
/// second without windows, helpers, launchd jobs or privileges.
func runCoreEntryReviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    _ = NSApplication.shared

    // Commands never spin the caller's run loop, including a timeout whose
    // child ignores SIGTERM and has to be killed.
    do {
        var fired = 0
        let timer = Timer(timeInterval: 0.005, repeats: true) { _ in fired += 1 }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        _ = try Subprocess.run("/bin/sleep", ["0.05"], timeout: 2)
        var timedOut = false
        do { _ = try Subprocess.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 5"], timeout: 0.1) } catch is Subprocess.Timeout { timedOut = true }
        let output = try Subprocess.run("/bin/sh", ["-c", "exit 3"], timeout: 2)
        try check(fired == 0, "A command spun the main run loop and ran \(fired) timer callbacks mid-command")
        try check(timedOut && output.status == 3, "Command timeout or exit status handling changed")
    }

    // The launchd unload wait keeps a real deadline even when each check is slow.
    do {
        let job = LaunchdJob.user("a.b", uid: 501), plist = URL(fileURLWithPath: "/fixture/a.b.plist")
        var clock = 0.0, prints = 0, bootstraps = 0
        let result = job.replace(with: plist, unloadDeadline: 5, run: { arguments in
            switch arguments[0] {
            case "print": prints += 1; clock += 1; return .ok
            case "bootstrap": bootstraps += 1; return .ok
            default: return .ok
            }
        }, pause: { clock += $0 }, now: { clock })
        try check(result == .ok && prints <= 5 && bootstraps == 1 && clock < 7,
                  "A slow launchctl held the unload wait past its deadline: \(prints) checks, \(clock) s")
    }

    // Helper repair that needs no authorization retries with backoff; one that
    // needed authorization never prompts again by itself.
    do {
        var policy = BackgroundHelperRecoveryPolicy()
        try check(!policy.shouldRecover(healthy: false, busy: false, now: 0) && policy.shouldRecover(healthy: false, busy: false, now: 10),
                  "Helper repair did not start after ten seconds missing")
        policy.failed(now: 11, retryable: true)
        try check(policy.retryScheduled && !policy.shouldRecover(healthy: false, busy: false, now: 40), "A failed repair retried before its backoff")
        try check(!policy.shouldRecover(healthy: false, busy: true, now: 41) && policy.shouldRecover(healthy: false, busy: false, now: 41),
                  "A failed repair was left for the person to fix by quitting and reopening")
        policy.failed(now: 42, retryable: true)
        try check(!policy.shouldRecover(healthy: false, busy: false, now: 101) && policy.shouldRecover(healthy: false, busy: false, now: 102),
                  "Repair retry backoff did not double")
        policy.failed(now: 103)
        try check(!policy.retryScheduled && !policy.shouldRecover(healthy: false, busy: false, now: 100_000), "A repair needing authorization prompted again by itself")
        try check(!policy.shouldRecover(healthy: true, busy: false, now: 100_001) && !policy.shouldRecover(healthy: false, busy: false, now: 100_002) &&
                  policy.shouldRecover(healthy: false, busy: false, now: 100_012), "A later outage could not recover after helpers were healthy")
    }

    // Every menu row and Command-Q reach a responder, and Quit stays available
    // while a Settings alert is open while other commands keep its exclusive scope.
    do {
        let host = SettingsWindow.shared
        let wasTesting = host.testing
        host.testing = true
        defer { host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)); host.testing = wasTesting }
        let app = AppDelegate(); app.buildMenu()
        let actionable = app.menu.items.filter { $0.action != nil }
        let unwired = actionable.filter { item in !((item.target as AnyObject?)?.responds(to: item.action!) ?? false) }
        try check(actionable.count >= 15 && unwired.isEmpty, "Menu rows would do nothing: \(unwired.map(\.title))")
        let appMenu = AppDelegate.applicationMenu(quitTarget: app, quitAction: #selector(AppDelegate.quit))
        guard let commandQ = appMenu.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "q" }),
              (commandQ.target as AnyObject?)?.responds(to: commandQ.action!) == true else { throw AppError(message: "Command-Q is not wired to Quit") }
        guard let quitItem = actionable.first(where: { $0.action == #selector(AppDelegate.quit) }),
              let other = actionable.first(where: { $0.action == #selector(AppDelegate.toggleAudio) }) else { throw AppError(message: "Menu is missing Quit or Mute audio") }
        let alert = NSAlert(); alert.messageText = "Fixture alert"; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        host.present(alert)
        try check(host.modal, "Fixture alert did not open")
        try check(app.validateMenuItem(quitItem) && app.validateMenuItem(commandQ), "Quit was disabled while a Settings alert was open")
        try check(!app.validateMenuItem(other), "Other menu commands lost the alert's exclusive scope")
        _ = host.finish(alert, response: .alertSecondButtonReturn)
        try check(!host.modal && app.validateMenuItem(other), "Menu commands stayed disabled after the alert closed")
        try check(!host.window.isVisible, "Menu review test presented Settings")
    }

    // A terminate request made inside a main-queue block runs afterwards, so a
    // main-queue completion its gate waits for can arrive.
    do {
        var completed = false, finished = false, ranInsideBlock = true
        DispatchQueue.main.async {
            var insideBlock = true
            AppTermination.request {
                ranInsideBlock = insideBlock
                DispatchQueue.main.async { completed = true }
                let deadline = Date().addingTimeInterval(1)
                while !completed, Date() < deadline { _ = RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.02)) }
                finished = true
            }
            insideBlock = false
        }
        let deadline = Date().addingTimeInterval(3)
        while !finished, Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        try check(finished && !ranInsideBlock && completed, "A terminate request ran inside a main-queue block, where its gate's completion can never arrive")
    }

    // Launch allows helpers before loading them and copies the app only when needed.
    do {
        var steps: [String] = []
        try HelperLifecycle.startForLaunch(allow: { steps.append("allow") }, loaded: { steps.append("loaded"); return true },
                                           startIfCurrent: { steps.append("start"); return true }, install: { steps.append("install") })
        try check(steps == ["allow", "loaded"], "Loaded helpers were checked before launchd allowed them or were restarted: \(steps)")
        steps = []
        try HelperLifecycle.startForLaunch(allow: { steps.append("allow") }, loaded: { false },
                                           startIfCurrent: { steps.append("start"); return false }, install: { steps.append("install") })
        try check(steps == ["allow", "start", "install"], "An outdated helper copy was not reinstalled: \(steps)")
        steps = []
        try HelperLifecycle.startForLaunch(allow: { steps.append("allow") }, loaded: { false },
                                           startIfCurrent: { steps.append("start"); return true }, install: { steps.append("install") })
        try check(steps == ["allow", "start"], "A current helper copy was copied again at launch: \(steps)")
    }

    // Only a confirmed manual Quit turns features off, and it replies only after.
    do {
        var events: [String] = []
        let plan = QuitPlan(.init(scrolling: true))
        var answer = AppDelegate.terminationReply(plan: plan, updater: { _ in events.append("updater"); return .terminateCancel },
            shutdown: { events.append("shutdown") }, turnOff: { _, done in events.append("turnOff"); done() }, reply: { events.append("reply") })
        try check(answer == .terminateCancel && events == ["updater"], "A pending update's answer was overridden: \(events)")
        events = []
        answer = AppDelegate.terminationReply(plan: nil, updater: { _ in nil }, shutdown: { events.append("shutdown") },
            turnOff: { _, done in events.append("turnOff"); done() }, reply: { events.append("reply") })
        try check(answer == .terminateLater && events == ["shutdown", "reply"], "A restart or reset turned features off: \(events)")
        events = []
        var finish: (() -> Void)?
        answer = AppDelegate.terminationReply(plan: plan, updater: { _ in nil }, shutdown: { events.append("shutdown") },
            turnOff: { _, done in events.append("turnOff"); finish = done }, reply: { events.append("reply") })
        try check(answer == .terminateLater && events == ["shutdown", "turnOff"], "Manual Quit replied before turning features off: \(events)")
        finish?()
        try check(events == ["shutdown", "turnOff", "reply"], "Manual Quit never replied after turning features off")
    }
    print("PASS: commands never spin the run loop; launchd unload wait keeps its deadline; helper repair retries without prompting again; menu rows and Command-Q are wired and Quit survives a Settings alert; terminate requests leave main-queue blocks; launch allows helpers first; only manual Quit turns features off")
}
