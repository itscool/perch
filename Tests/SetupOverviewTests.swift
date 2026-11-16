import AppKit

func runSetupOverviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    // Which rows Setup shows, and their states, are checked headless in
    // runSettingsHeadlessTests. Here: the page draws them and each opens its step.
    var config = SafetyConfiguration()
    config.reverseTrackpad = false; config.reverseWheel = false; config.navigation = nil
    config.keepAwake = false
    let unused = SetupSnapshot(config: config)
    var snapshot = SetupSnapshot(config: config)
    config.reverseWheel = true; snapshot.config = config
    snapshot.guardian = SafetyStatus(inputTrusted: false, inputActive: false, keepAwakeActive: false, message: "", error: nil)
    snapshot.input = InputHelperStatus(trusted: false, active: false)
    snapshot.keyboardAccessNeeded = true; snapshot.keyboardSetupWanted = true
    try check(snapshot.scrolling.state == .attention && snapshot.keyboardAccess.state == .attention, "Lost access was not shown on its steps")
    var opened: [SetupRoute] = []
    let overview = SetupOverviewPage(firstVisit: false, read: { snapshot }, navigate: { opened.append($0) })
    overview.refresh()
    let overviewScroll = overview.view.subviews.compactMap { $0 as? NSScrollView }.first!
    let overviewButtons = overviewScroll.documentView!.subviews.compactMap { $0 as? SettingsActionButton }
    try check(overviewButtons.count == 5 && overviewButtons.allSatisfy { $0.title == "Open" }, "Setup does not show one Open per step")
    for button in overviewButtons { button.performClick(nil) }
    try check(opened == [.maintenance, .keyboardAccess, .inputAccess, .sharingAccess, .lidSetup], "A Setup row opened another step: \(opened)")
    let retired: Set<String> = ["Recheck", "Fix next issue", "Continue setup", "App settings"]
    let pageButtons: [String] = overview.view.subviews.compactMap { ($0 as? NSButton)?.title }
    try check(retired.isDisjoint(with: pageButtons), "Setup still has Recheck or a next-issue button: \(pageButtons)")
    let recovery = snapshot

    let host = SettingsWindow.shared
    host.testing = true
    let app = AppDelegate(); app.buildMenu(); app.configureSettings()
    defer { host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)) }
    try check(host.pages.last?.title == "Setup & status" && host.sidebar.destinations.first?.id == "overview", "Settings must start with its reusable overview and persistent categories")
    try check(Set(host.sidebar.destinations.map(\.id)).count == host.sidebar.destinations.count, "Sidebar destination identities must be unique")
    let configBefore = try? Data(contentsOf: SafetyFiles.config)
    let preferencesBefore = UserDefaults.standard.dictionaryRepresentation()
    var current = recovery, routed: SetupRoute?
    let page = SetupOverviewPage(firstVisit: false, read: { current }, navigate: { route in
        routed = route
        host.show(.init(title: "Repair fixture", detail: "Injected repair page", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 120))))
    })
    page.show()
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-setup-recovery.png")
    let rowButtons = page.view.subviews.compactMap { $0 as? NSScrollView }.first!.documentView!.subviews.compactMap { $0 as? SettingsActionButton }
    let scrolling = rowButtons[page.checks.firstIndex { $0.id == "input-access" }!]
    try check(scrolling.visibleRect.height > 0, "A Setup step's Open is below the fold")
    scrolling.performClick(nil)
    try check(routed == .inputAccess && host.pages.count == 2, "Scrolling & navigation's row did not open its step")
    current.input = InputHelperStatus(trusted: true, active: true)
    host.goBack()
    try check(host.pages.last?.view === page.view && page.checks.first { $0.id == "input-access" }?.state == .ready, "Returning from repair lost overview or retained stale status")
    try check((try? Data(contentsOf: SafetyFiles.config)) == configBefore && (UserDefaults.standard.dictionaryRepresentation() as NSDictionary).isEqual(to: preferencesBefore), "Viewing setup changed feature choices")
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
    print("PASS: Setup draws its five steps, each opening its own; no Recheck or next-issue button; repair and Back; first use and re-entry; task categories and draft cancellation")
}
