import AppKit


func runSettingsJourneyFixTests() throws {
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    defer { host.modalTestDriver = nil; host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); host.pages = [] }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    try check(SettingsWindow.boundedScrollFromTop(900, contentHeight: 700, viewportHeight: 500) == 200,
               "Saved settings scroll offset was not bounded after shrinking")
    try check(SettingsWindow.boundedScrollFromTop(-5, contentHeight: 700, viewportHeight: 500) == 0,
               "Saved settings scroll offset accepted a negative value")
    func flush() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
    func button(_ title: String) -> NSButton? {
        let result = host.pages.last?.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == title }
        if result == nil { fputs("Fixture missing button: " + title + " on " + (host.pages.last?.title ?? "no page") + "\n", stderr) }
        return result
    }
    let app = AppDelegate(); app.buildMenu(); app.configureSettings()
    var callbacks: [(Result<String, Error>) -> Void] = [], scopes: [Bool] = []
    let reset = PrivacyResetOperation { scope, complete in scopes.append(scope); callbacks.append(complete) }
    app.privacyOnlyReset(global: false, operation: reset)
    button("Reset Perch’s privacy permissions")!.performClick(nil)
    try check(scopes == [false] && reset.runningScope == false && !host.detail.stringValue.contains("Back cancels"), "Reset start or running copy is incorrect")
    host.goBack(); app.privacyOnlyReset(global: true, operation: reset)
    try check(button("Reset all apps’ privacy permissions")?.isEnabled == false, "A second reset can overlap the first")
    host.goBack()
    callbacks[0](.failure(AppError(message: "Fixture partial failure")))
    app.privacyOnlyReset(global: false, operation: reset)
    try check(button("Retry privacy reset")?.isEnabled == true, "Failure was lost on leaving/reopening")
    button("Retry privacy reset")!.performClick(nil)
    callbacks[0](.success("Stale completion"))
    try check(reset.runningScope == false, "An old completion ended a new reset")
    host.goBack(); callbacks[1](.success("✓ Fixture reset completed"))
    app.privacyOnlyReset(global: false, operation: reset); flush()
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "✓ Fixture reset completed" }, "Completed reset disappeared on return")
    try check(button("Start another reset…") != nil && host.heading.stringValue == "Privacy reset completed", "Success did not transition to a result")
    button("Start another reset…")!.performClick(nil)
    try check(scopes.count == 2 && button("Reset Perch’s privacy permissions") != nil, "Starting another proposal immediately repeated the reset")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-privacy-result.png")
    host.goBack()

    for titles in [["OK"], ["Apply Updates", "Cancel"], ["Cancel", "Terminate agents"], ["Check setup & status", "Back"], ["Do something"]] {
        let alert = NSAlert(); alert.messageText = "Fixture alert"
        titles.forEach { alert.addButton(withTitle: $0) }
        var correct = false
        host.modalTestDriver = { _ in
            let controls = host.container.subviews.first!.subviews.compactMap { $0 as? NSButton }
            let expected = titles.enumerated().filter { !["OK", "Cancel", "Back"].contains($0.element) }
            correct = controls.map(\.title) == expected.map(\.element) && controls.map(\.tag) == expected.map { 1000 + $0.offset }
            return host.cancelCode
        }
        let response = host.run(alert)
        try check(correct, "Shared alert duplicated navigation or changed action indices")
        if titles == ["Do something"] { try check(response == .abort, "Closing an action-only alert approved its action") }
    }
    host.modalTestDriver = nil

    app.keyboardSettings(); app.keyboardDetails()
    for open in [app.keyboardSettings, app.keyboardDetails, app.navigationSettings] {
        open()
        let toggles = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter {
            ["F1–F12 directly", "Swap Control and Command", "Home/End move to line edges", "Page Up/Down move the cursor"].contains($0.title)
        }
        try check(toggles.isEmpty, "Settings duplicated the main-menu behavior switches")
    }
    host.goBack(); host.goBack()

    UserDefaults.standard.set(false, forKey: SleepPreferences.lidPreferenceKey); app.observedSleep = SleepStatus(perchActive: false, caffeinateProcesses: []); app.observedLidDisabled = false; app.applyLidSleepPresentation(); app.menu.update()
    try check(!app.lidItem.isEnabled, "Native menu validation re-enabled a disabled lid row")
    app.observedSleep = nil; app.observedLidDisabled = nil; app.applyLidSleepPresentation(); app.menu.update()
    try check(!app.lidItem.isEnabled && !app.awakeItem.isEnabled, "Native validation re-enabled unknown sleep controls")
    app.trackpadItem.state = .off; app.wheelItem.state = .on
    app.refreshScrolling(input: .init(trusted: true, active: false), checking: false)
    app.menu.update()
    try check(app.trackpadItem.action == #selector(AppDelegate.toggleTrackpad) && app.wheelItem.isEnabled && app.menuTitleSources[app.wheelItem]?.string.contains("not running") == true, "Scrolling used guardian readiness or hid inactive input")
    app.refreshScrolling(input: nil, checking: true); app.menu.update()
    try check(!app.trackpadItem.isEnabled && app.wheelItem.isEnabled && app.wheelItem.action == #selector(AppDelegate.toggleWheel), "Pending input allows a new choice or prevents turning off a saved one")
    app.refreshSafety(status: nil, config: SafetyConfiguration(), checking: true)
    app.menu.update()
    try check(!app.safetyResumeItem.isHidden && !app.safetyResumeItem.isEnabled, "Cold helper check prematurely hid or enabled Resume")
    try check(app.currentProtectionIssue == nil && app.menuTitleSources[app.safetyItem]?.string.contains("Checking") == true, "Cold helper read was reported offline")
    app.refreshSafety(status: nil, config: SafetyConfiguration(), checking: false)
    try check(app.currentProtectionIssue != nil && app.menuTitleSources[app.safetyItem]?.string.contains("offline") == true, "Failed helper read remained checking")
    print("PASS: privacy leave/result/retry and cross-scope exclusion; shared alert exits/action indices; four keyboard detail routes; group scroll/draft preservation; monitor stop/retry/fresh token and saved mapping; native sleep and scrolling validation; cold/failed helper presentation. All mutations injected.")
}
