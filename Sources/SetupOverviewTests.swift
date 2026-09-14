import AppKit

func runSetupOverviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var config = SafetyConfiguration()
    config.reverseTrackpad = false; config.reverseWheel = false; config.navigation = nil
    config.keepAwake = false; config.targets = []; config.shortcut.enabled = false
    let unused = SetupSnapshot(config: config)
    var snapshot = SetupSnapshot(config: config)
    try check(snapshot.checks.allSatisfy { $0.state == .optional }, "Unused optional features demand setup")
    snapshot.lidWanted = true
    try check(snapshot.checks.first { $0.id == "lid-setup" }?.state == .attention, "Saved lid choice hid unfinished helper setup")
    snapshot.lidWanted = false
    snapshot.keyboardCount = 1; snapshot.keyboardAccessNeeded = true
    try check(snapshot.checks.first { $0.id == "keyboards" }?.state == .attention && snapshot.checks.first { $0.id == "keyboards" }?.route == .keyboardAccess, "First-use keyboard access was hidden as optional")
    snapshot.keyboardCount = 0; snapshot.keyboardAccessNeeded = false
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: true, detail: "Lid session requested.")
    try check(snapshot.checks.first { $0.id == "awake" }?.state == .ready && snapshot.checks.first { $0.id == "awake" }!.detail.contains("cannot guarantee"), "A fresh active helper session was reported as unfinished setup or lost its macOS limitation")
    snapshot.lidGuard = nil
    snapshot.config.shortcut.enabled = true
    try check(snapshot.checks.first { $0.id == "agents" }?.state == .checking, "An enabled shortcut was ignored when no agents were selected")
    config.reverseWheel = true
    config.targets = [.init(id: "fixture", name: "Fixture agent", kind: "cli", match: "fixture")]
    config.shortcut.enabled = true; snapshot.config = config
    func item(_ id: String) -> SetupCheck { snapshot.checks.first { $0.id == id }! }
    try check(item("helpers").state == .checking && item("scrolling").state == .checking && item("agents").state == .checking, "Missing helper was confused with lost grants or working protection")
    snapshot.helperRecoveryFailure = "Recovery failed"
    try check(item("helpers").state == .attention, "Failed automatic recovery remained progress")
    snapshot.helperRecoveryFailure = nil
    snapshot.collectorChecking = true
    try check(item("events").state == .checking, "Collector verification was a warning")
    snapshot.collectorChecking = false
    snapshot.lidHelperBusy = true; snapshot.lidHelperUpdatePending = true
    try check(item("lid-setup").state == .checking && item("awake").state == .checking, "In-flight lid update was a warning")
    snapshot.lidHelperBusy = false
    try check(item("awake").state == .attention, "Incomplete lid update lost its recovery warning")
    snapshot.lidHelperUpdatePending = false
    var guardian = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: false, inputActive: false, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
    snapshot.guardian = guardian; snapshot.input = InputHelperStatus(trusted: false, active: false)
    snapshot.collectorInstalled = true; snapshot.keyboardAccessNeeded = true; snapshot.keyboardSetupWanted = true
    snapshot.monitorConfigured = true; snapshot.monitorAvailable = false; snapshot.monitorDetail = "Desk display is disconnected. Saved input choices are kept."
    try check(item("scrolling").state == .attention && item("scrolling").route == .inputAccess && item("keyboards").state == .attention && item("events").state == .attention && item("displays").state == .attention, "Reset/disconnection recovery does not identify affected features")
    var overviewRoute = ""
    let overview = SetupOverviewPage(firstVisit: false, read: { snapshot }, recheck: {}, navigate: { _, id in overviewRoute = id })
    overview.refresh()
    let overviewScroll = overview.view.subviews.compactMap { $0 as? NSScrollView }.first!
    let overviewButtons = overviewScroll.documentView!.subviews.compactMap { $0 as? SettingsActionButton }
    try check(overviewButtons.count == snapshot.checks.count, "Setup overview has a fixed row capacity instead of every feature")
    try check(overviewScroll.documentView!.frame.height > overviewScroll.contentSize.height, "Expanded setup lost scrolling to its last feature")
    overviewButtons.last!.performClick(nil)
    try check(overviewRoute == snapshot.checks.last?.id, "Last setup row navigates to the wrong feature")
    let recovery = snapshot
    snapshot.deskInputEnabled = true
    try check(item("desk-input").state == .ready && item("desk-input").detail.contains("select a confirmed screen"), "Idle sharing was reported as broken setup or as an active session")
    snapshot.deskInputActive = true
    try check(item("desk-input").state == .ready, "Active desk input was not reported")
    snapshot.deskInputProblem = "Secure entry is active"
    try check(item("desk-input").state == .attention, "Input recovery was hidden by enabled preference")
    snapshot.deskInputEnabled = false; snapshot.deskInputActive = false; snapshot.deskInputProblem = nil
    snapshot.monitorAvailable = true; snapshot.monitorNeedsVerification = true
    try check(item("displays").state == .unverified && item("displays").detail.contains("inputs are saved"), "Configured display with unknown input was counted as ready before visiting monitor settings")
    snapshot.monitorBusy = true
    try check(item("displays").state == .checking, "Pending display check was presented as a settled result")
    snapshot.monitorBusy = false; snapshot.monitorWarning = true
    try check(item("displays").state == .attention, "Failed current-input read was hidden by saved setup")
    snapshot.monitorWarning = false; snapshot.monitorNeedsVerification = false
    try check(item("displays").state == .ready, "Verified input or explicit named destination still demanded cycling setup")
    snapshot.monitorAvailable = false
    try check(item("displays").state == .attention, "Disconnect retained a ready display state")
    snapshot.input = InputHelperStatus(trusted: true, active: true)
    try check(item("scrolling").state == .ready && item("events").state == .attention && item("keyboards").state == .attention, "One restored grant made unrelated features ready")
    snapshot.input?.timestamp = Date().addingTimeInterval(-10)
    try check(item("scrolling").state == .checking && item("helpers").state == .checking, "Stale helper status stayed ready")
    snapshot.input = InputHelperStatus(trusted: true, active: true)
    guardian.eventCoverage = "Process events active"; guardian.eventConnected = true; guardian.eventLastSeen = Date().addingTimeInterval(-60)
    snapshot.guardian = guardian
    try check(item("events").state == .attention, "Stale collector events prove access")
    guardian.eventLastSeen = Date(); snapshot.guardian = guardian
    try check(item("events").state == .ready && item("agents").detail.contains("physical keys"), "Registration and physical key testing are conflated")
    snapshot.collectorNeedsRepair = true
    try check(item("events").state == .attention, "Setup declared a collector requiring repair ready")
    try check(!EventCollectorSetup.collectionReady(guardian, installed: true, needsRepair: true, waitingForSession: false), "Collector page hid its required repair behind Ready")
    snapshot.collectorNeedsRepair = false; snapshot.collectorWaitingForSession = true
    try check(item("events").state == .attention, "Setup ignored a pending replacement observation session")
    snapshot.collectorWaitingForSession = false
    guardian.eventConnected = false; snapshot.guardian = guardian
    try check(item("events").state == .attention && !EventCollectorSetup.collectionReady(guardian, installed: true, needsRepair: false, waitingForSession: false), "Disconnected stream remained ready")
    guardian.eventConnected = true; guardian.eventLastSeen = Date().addingTimeInterval(-60); snapshot.guardian = guardian
    try check(!EventCollectorSetup.collectionReady(guardian, installed: true, needsRepair: false, waitingForSession: false), "Collector page kept stale event readiness")
    guardian.eventLastSeen = Date(); snapshot.guardian = guardian
    try check(item("events").state == .ready && EventCollectorSetup.collectionReady(guardian, installed: true, needsRepair: false, waitingForSession: false), "Recovered collector did not return to Ready")
    guardian.locked = true; snapshot.guardian = guardian
    try check(item("agents").state == .attention, "Blocked agent activity appeared ready for ordinary use")
    snapshot.lidDisabled = true
    try check(item("awake").state == .attention, "Persistent lid override was hidden by an off Perch preference")

    let host = SettingsWindow.shared
    host.testing = true
    let app = AppDelegate(); app.buildMenu(); app.configureSettings()
    defer { host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)) }
    try check(host.pages.last?.title == "Setup & status" && host.sidebar.destinations.first?.id == "overview", "Settings must start with its reusable overview and persistent categories")
    try check(Set(host.sidebar.destinations.map(\.id)).count == host.sidebar.destinations.count, "Sidebar destination identities must be unique")
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
    try check(routed == .inputAccess && host.pages.count == 2, "Next issue skipped the applicable access repair")
    current.input = InputHelperStatus(trusted: true, active: true)
    host.goBack()
    try check(host.pages.last?.view === page.view && page.checks.first { $0.id == "scrolling" }?.state == .ready, "Returning from repair lost overview or retained stale status")
    controls.first { $0.title == "Recheck" }!.performClick(nil)
    try check(rechecks == 1 && host.pages.count == 1, "Recheck navigated or repeated its request")
    try check((try? Data(contentsOf: SafetyFiles.config)) == configBefore && (UserDefaults.standard.dictionaryRepresentation() as NSDictionary).isEqual(to: preferencesBefore), "Viewing setup or rechecking changed feature choices")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    try check(page.timer == nil && host.pages.isEmpty, "Leaving setup retained its refresh timer")

    let seen = UserDefaults.standard.object(forKey: SetupOverviewPage.seenKey)
    defer { if let seen { UserDefaults.standard.set(seen, forKey: SetupOverviewPage.seenKey) } else { UserDefaults.standard.removeObject(forKey: SetupOverviewPage.seenKey) } }
    UserDefaults.standard.removeObject(forKey: SetupOverviewPage.seenKey)
    app.showFirstSetupIfNeeded(snapshot: unused)
    try check(host.pages.last?.title == "Setup & status" && host.detail.stringValue.contains("Welcome"), "First launch did not open a reusable setup overview")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-setup-first-use.png")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)); app.showFirstSetupIfNeeded(snapshot: unused)
    try check(host.pages.isEmpty, "Seen setup became a mandatory tour on every launch")
    app.showFirstSetupIfNeeded(snapshot: recovery)
    try check(host.pages.last?.title == "Setup & status", "Seen setup hid missing required access on the next launch")
    app.setupOverview()
    app.advancedSafetySettings(); app.setupOverview()
    try check(host.pages.count == 1, "Returning to setup duplicated its navigation stack")
    try check(!host.detail.stringValue.contains("Welcome"), "Reopened setup did not become a status/recovery page")
    var canLeave = false, checks = 0
    let invalidDraft = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 150))
    host.show(.init(title: "Invalid draft fixture", detail: "Correct or discard the draft.", view: invalidDraft, beforeBack: { checks += 1; return canLeave }))
    app.setupOverview()
    try check(checks == 1 && host.pages.last?.view === invalidDraft, "Setup return ignored refused Back or repeatedly invoked validation")
    canLeave = true; app.setupOverview()
    try check(host.pages.count == 1 && host.pages.last?.title == "Setup & status", "Setup return did not recover after valid Back")

    for (name, open) in [("displays", app.displaySettings), ("scrolling", app.scrollingSettings), ("awake", app.keepAwakeSettings), ("app", app.appSettings), ("keyboard", app.keyboardSettings), ("navigation", app.navigationSettings), ("maintenance", app.advancedSafetySettings)] {
        open()
        try check(host.pages.count == 2, "Task page lost Settings parent: " + name)
        if name == "awake" { try check(host.pages.last?.title == "Lid activity", "Retired sleep page did not route to history") }
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-category-" + name + ".png")
        host.goBack()
    }
    app.navigationSettings()
    let navigationButtons = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }
    try check(navigationButtons.contains { $0.title == "Learn or change a layout…" || $0.title == "Set up keyboard layout…" && $0.isEnabled }, "Unavailable helper hides saved layout management")
    app.navigationExceptions()
    try check(!host.back.isHidden && host.pages.count == 3 && host.back.title == "Back" && host.pages.last?.detail.contains("save automatically") == true, "Exception choices do not explain immediate saving and return to Keyboards")
    host.goBack(); host.goBack()
    app.resetHub()
    try check(host.pages.last?.title == "Reset Settings", "Reset index missing")
    host.goBack()
    print("PASS: observed setup readiness; independent permission recovery; stale helpers/events; first use and re-entry; next repair and Back; read-only Recheck; task categories and draft cancellation")
}
