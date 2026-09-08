import AppKit

func runSetupOverviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var config = SafetyConfiguration()
    config.reverseTrackpad = false; config.reverseWheel = false; config.navigation = nil
    config.keepAwake = false; config.targets = []; config.shortcut.enabled = false
    var snapshot = SetupSnapshot(config: config)
    try check(snapshot.checks.allSatisfy { $0.state == .optional }, "Unused optional features demand setup")
    snapshot.config.shortcut.enabled = true
    try check(snapshot.checks.first { $0.id == "agents" }?.state == .checking, "An enabled shortcut was ignored when no agents were selected")
    config.reverseWheel = true
    config.targets = [.init(id: "fixture", name: "Fixture agent", kind: "cli", match: "fixture")]
    config.shortcut.enabled = true; snapshot.config = config
    func item(_ id: String) -> SetupCheck { snapshot.checks.first { $0.id == id }! }
    try check(item("helpers").state == .attention && item("scrolling").state == .checking && item("agents").state == .checking, "Missing helper was confused with lost grants or working protection")
    var guardian = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: false, inputActive: false, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
    snapshot.guardian = guardian; snapshot.input = InputHelperStatus(trusted: false, active: false)
    snapshot.collectorInstalled = true; snapshot.keyboardAccessNeeded = true; snapshot.keyboardSetupWanted = true
    snapshot.monitorConfigured = true; snapshot.monitorAvailable = false; snapshot.monitorDetail = "Desk display is disconnected. Saved input choices are kept."
    try check(item("scrolling").state == .attention && item("scrolling").route == .inputAccess && item("keyboards").state == .attention && item("events").state == .attention && item("displays").state == .attention, "Reset/disconnection recovery does not identify affected features")
    let recovery = snapshot
    snapshot.input = InputHelperStatus(trusted: true, active: true)
    try check(item("scrolling").state == .ready && item("events").state == .attention && item("keyboards").state == .attention, "One restored grant made unrelated features ready")
    snapshot.input?.timestamp = Date().addingTimeInterval(-10)
    try check(item("scrolling").state == .checking && item("helpers").state == .attention, "Stale helper status stayed ready")
    snapshot.input = InputHelperStatus(trusted: true, active: true)
    guardian.eventCoverage = "Process events active"; guardian.eventConnected = true; guardian.eventLastSeen = Date().addingTimeInterval(-60)
    snapshot.guardian = guardian
    try check(item("events").state == .attention, "Stale collector events prove access")
    guardian.eventLastSeen = Date(); snapshot.guardian = guardian
    try check(item("events").state == .ready && item("agents").detail.contains("physical keys"), "Registration and physical key testing are conflated")
    guardian.locked = true; snapshot.guardian = guardian
    try check(item("agents").state == .attention, "Blocked agent activity appeared ready for ordinary use")
    snapshot.lidDisabled = true
    try check(item("awake").state == .attention, "Persistent lid override was hidden by an off Perch preference")

    let host = SettingsWindow.shared
    host.testing = true
    let app = AppDelegate(); app.buildMenu(); app.configureSettings()
    defer { host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)) }
    let rootButtons = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }
    try check(rootButtons.map(\.title) == ["Setup & status…", "Displays…", "Keyboards…", "Scrolling…", "Keep awake…", "Agent Kill Switch…", "App settings…"], "Settings categories mix setup or maintenance with tasks")
    let configBefore = try? Data(contentsOf: SafetyFiles.config)
    let preferencesBefore = UserDefaults.standard.dictionaryRepresentation()
    var current = recovery, rechecks = 0, routed: SetupRoute?
    let page = SetupOverviewPage(firstVisit: false, read: { current }, recheck: { rechecks += 1 }, navigate: { route, _ in
        routed = route
        host.show(.init(title: "Repair fixture", detail: "Injected repair page", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 120))))
    })
    page.show()
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-setup-recovery.png")
    let controls = page.view.subviews.compactMap { $0 as? NSButton }
    let next = controls.first { $0.title == "Fix next issue" }!
    try check(next.visibleRect.height > 0, "Next setup action is below the fold")
    next.performClick(nil)
    try check(routed == .inputAccess && host.pages.count == 3, "Next issue skipped the applicable access repair")
    current.input = InputHelperStatus(trusted: true, active: true)
    host.goBack()
    try check(host.pages.last?.view === page.view && page.checks.first { $0.id == "scrolling" }?.state == .ready, "Returning from repair lost overview or retained stale status")
    controls.first { $0.title == "Recheck" }!.performClick(nil)
    try check(rechecks == 1 && host.pages.count == 2, "Recheck navigated or repeated its request")
    try check((try? Data(contentsOf: SafetyFiles.config)) == configBefore && (UserDefaults.standard.dictionaryRepresentation() as NSDictionary).isEqual(to: preferencesBefore), "Viewing setup or rechecking changed feature choices")
    host.goBack()
    try check(page.timer == nil && host.pages.count == 1, "Leaving setup retained its refresh timer")

    let seen = UserDefaults.standard.object(forKey: SetupOverviewPage.seenKey)
    defer { if let seen { UserDefaults.standard.set(seen, forKey: SetupOverviewPage.seenKey) } else { UserDefaults.standard.removeObject(forKey: SetupOverviewPage.seenKey) } }
    UserDefaults.standard.removeObject(forKey: SetupOverviewPage.seenKey)
    app.showFirstSetupIfNeeded()
    try check(host.pages.last?.title == "Setup & status" && host.detail.stringValue.contains("Welcome"), "First launch did not open a reusable setup overview")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-setup-first-use.png")
    host.goBack(); app.showFirstSetupIfNeeded()
    try check(host.pages.count == 1, "Seen setup became a mandatory tour on every launch")
    app.setupOverview()
    app.advancedSafetySettings(); app.setupOverview()
    try check(host.pages.count == 2, "Returning to setup duplicated its navigation stack")
    try check(!host.detail.stringValue.contains("Welcome"), "Reopened setup did not become a status/recovery page")
    host.goBack()

    for (name, open) in [("displays", app.displaySettings), ("scrolling", app.scrollingSettings), ("awake", app.keepAwakeSettings), ("app", app.appSettings), ("keyboard", app.keyboardSettings), ("navigation", app.navigationSettings), ("maintenance", app.advancedSafetySettings)] {
        open()
        try check(host.pages.count == 2, "Task page lost Settings parent: " + name)
        if name == "awake" {
            let controls = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter { $0.title == "Keep awake" || $0.title == "Including with the lid closed" }
            try check(controls.count == 2 && controls.allSatisfy { $0.state == .mixed && $0.allowsMixedState && !$0.isEnabled }, "Unknown sleep state appears checked or editable")
        }
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-category-" + name + ".png")
        host.goBack()
    }
    app.navigationSettings()
    let navigationButtons = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }
    try check(navigationButtons.contains { $0.title == "Learn or manage layouts…" && $0.isEnabled }, "Unavailable helper hides saved layout management")
    app.navigationExceptions()
    try check(host.back.title == "Cancel", "Compound exception editor does not make draft cancellation explicit")
    host.goBack(); host.goBack()
    app.resetSettingsPage()
    try check(!host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.contains { $0.title.contains("privacy") || $0.title.contains("system") }, "Perch preference reset contains unrelated system permission controls")
    host.goBack()
    print("PASS: observed setup readiness; independent permission recovery; stale helpers/events; first use and re-entry; next repair and Back; read-only Recheck; task categories and draft cancellation")
}
