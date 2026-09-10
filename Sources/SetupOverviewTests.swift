import AppKit

func runSetupOverviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var config = SafetyConfiguration()
    config.reverseTrackpad = false; config.reverseWheel = false; config.navigation = nil
    config.keepAwake = false; config.targets = []; config.shortcut.enabled = false
    var snapshot = SetupSnapshot(config: config)
    try check(snapshot.checks.allSatisfy { $0.state == .optional }, "Unused optional features demand setup")
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: true, detail: "Lid session requested.")
    try check(snapshot.checks.first { $0.id == "awake" }?.state == .unverified && snapshot.summary.contains("1 unverified"), "An accepted lid command was counted as ready or as a repairable missing setup step")
    snapshot.lidGuard = nil
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
    try check(item("scrolling").state == .checking && item("helpers").state == .attention, "Stale helper status stayed ready")
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
    app.showFirstSetupIfNeeded()
    try check(host.pages.last?.title == "Setup & status" && host.detail.stringValue.contains("Welcome"), "First launch did not open a reusable setup overview")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-setup-first-use.png")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)); app.showFirstSetupIfNeeded()
    try check(host.pages.isEmpty, "Seen setup became a mandatory tour on every launch")
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
        if name == "awake" {
            let controls = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter { $0.title == "Keep awake" || $0.title == "Including with the lid closed" }
            try check(controls.count == 2 && controls.allSatisfy { !$0.isEnabled } && controls.first { $0.title == "Keep awake" }?.state == .mixed, "Unknown actual sleep state became editable or ready")
            try check(controls.first { $0.title == "Including with the lid closed" }?.state == (UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey) ? .on : .off), "Unknown session erased the saved lid choice")
        }
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-category-" + name + ".png")
        host.goBack()
    }
    app.navigationSettings()
    let navigationButtons = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }
    try check(navigationButtons.contains { $0.title == "Learn or manage layouts…" && $0.isEnabled }, "Unavailable helper hides saved layout management")
    app.navigationExceptions()
    try check(host.back.title == "Back" && host.pages.last?.detail.contains("save automatically") == true, "Exception choices do not explain immediate saving and Back navigation")
    host.goBack(); host.goBack()
    app.resetSettingsPage()
    try check(!host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.contains { $0.title.contains("privacy") || $0.title.contains("system") }, "Perch preference reset contains unrelated system permission controls")
    host.goBack()
    print("PASS: observed setup readiness; independent permission recovery; stale helpers/events; first use and re-entry; next repair and Back; read-only Recheck; task categories and draft cancellation")
}
