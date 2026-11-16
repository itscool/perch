import AppKit

/// Settings, Setup and menu checks that need no window, so they run in the
/// headless self-test and in CI.
///
/// Which Setup rows appear, what a page contains and how the menu is laid out
/// are data and views built in memory; none of it needs a screen. These checks
/// used to live beside window-driving tests in the functional suite, so they
/// only ran with the AGENT MODE banner on Scott's own screen. The window suite
/// keeps what genuinely needs a real window: a click landing, focus, dialogs.
func runSettingsHeadlessTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    // Setup lists exactly its five steps, with the sidebar's ids, names and
    // order, and every row opens its own step (Scott, November 16, 2026).
    var snapshot = SetupSnapshot(config: SafetyConfiguration())
    let stepIDs: [String] = ["maintenance", "keyboard-access", "input-access", "sharing-access", "lid-setup"]
    let stepTitles: [String] = ["Background helpers", "Keyboard access", "Scrolling & navigation", "Shared input access", "Lid protection"]
    let stepRoutes: [SetupRoute] = [.maintenance, .keyboardAccess, .inputAccess, .sharingAccess, .lidSetup]
    let rowIDs: [String] = snapshot.checks.map { $0.id }
    let rowTitles: [String] = snapshot.checks.map { $0.title }
    let rowRoutes: [SetupRoute] = snapshot.checks.map { $0.route }
    try check(rowIDs == stepIDs, "Setup's rows are not its five steps in the sidebar's order: \(rowTitles)")
    try check(rowTitles == stepTitles, "Setup's rows are not named as in the sidebar: \(rowTitles)")
    try check(rowRoutes == stepRoutes, "A Setup row opens another step: \(rowRoutes)")
    let navigationApp = AppDelegate()
    let destinations: [SettingsDestination] = navigationApp.settingsDestinations()
    let sidebarSteps: [SettingsDestination] = destinations.filter { $0.setupStage }
    let sidebarIDs: [String] = sidebarSteps.map { $0.id }
    let sidebarTitles: [String] = sidebarSteps.map { $0.title }
    try check(sidebarIDs == stepIDs, "The sidebar's Setup steps differ from the page's rows: \(sidebarTitles)")
    try check(sidebarTitles == stepTitles, "The sidebar's Setup names differ from the page's: \(sidebarTitles)")
    let flagged: [String] = destinations.filter { $0.flagsAttention }.map { $0.id }
    try check(flagged == ["keyboard", "desk"], "Only Keyboards and Desk should flag attention outside Setup: \(flagged)")
    let allOptional: Bool = snapshot.checks.allSatisfy { $0.state == .optional }
    let sidebarKeys: Set<String> = Set(snapshot.sidebar.keys)
    try check(allOptional, "A Mac using no features was asked to set something up")
    try check(sidebarKeys == Set(stepIDs), "The sidebar flagged a feature with nothing wrong: \(sidebarKeys.sorted())")
    // The old process watcher and the login approval belong to Background
    // helpers; that row says so while they apply, and stops after.
    snapshot.watcherInstalled = true
    try check(snapshot.helpers.state == .attention && snapshot.helpers.detail.contains("process watcher") && snapshot.sidebar["maintenance"] == .attention,
              "An installed process watcher was not shown on Background helpers: \(snapshot.helpers.detail)")
    snapshot.watcherInstalled = false; snapshot.loginNeedsApproval = true
    try check(snapshot.helpers.state == .attention && snapshot.helpers.detail.contains("Login Items"), "A login approval was not shown on Background helpers")
    snapshot.loginNeedsApproval = false
    try check(snapshot.helpers.state == .optional, "Background helpers kept a problem after it went")
    // Restored access is shown on the step that grants it.
    snapshot.accessRestoreNeeded = [.inputMonitoring]
    try check(snapshot.keyboardAccess.state == .attention && snapshot.keyboardAccess.detail.contains("Input Monitoring") && snapshot.sharing.state == .optional,
              "Removed Input Monitoring was not shown on Keyboard access alone")
    snapshot.accessRestoreNeeded = [.accessibility]
    try check(snapshot.sharing.state == .attention && snapshot.sharing.detail.contains("Accessibility") && snapshot.keyboardAccess.state == .optional,
              "Removed Accessibility was not shown on Shared input access alone")
    snapshot.accessRestoreNeeded = []
    // Turning sharing on makes both of its permissions needed; granting them makes both ready.
    snapshot.deskInputEnabled = true
    try check(snapshot.sharing.state == .attention && snapshot.keyboardAccess.state == .attention, "Sharing on without access did not ask for it")
    snapshot.sharingAccessGranted = true; snapshot.keyboardAccessGranted = true
    try check(snapshot.sharing.state == .ready && snapshot.keyboardAccess.state == .ready, "Granted access was not ready")
    // Lid protection: an update in progress checks, an unfinished one needs
    // attention, sleep disabled outside Perch is named, a helper error shows.
    snapshot.lidHelperBusy = true; snapshot.lidHelperUpdatePending = true
    try check(snapshot.lid.state == .checking, "A lid helper update in progress was a warning")
    snapshot.lidHelperBusy = false
    try check(snapshot.lid.state == .attention, "An unfinished lid helper update was hidden")
    snapshot.lidHelperUpdatePending = false; snapshot.lidDisabled = true
    try check(snapshot.lid.state == .optional && snapshot.lid.detail.contains("outside Perch"), "Sleep disabled outside Perch was not named")
    snapshot.lidWanted = true
    try check(snapshot.lid.state == .attention, "A saved lid choice hid the missing helper")
    snapshot.lidHelperInstalled = true; snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: false, detail: "Stopped", error: "Readback failed")
    try check(snapshot.lid.state == .attention && snapshot.lid.detail == "Readback failed", "A current lid helper error was hidden")
    snapshot.lidGuard?.updatedAt -= 20
    try check(snapshot.lid.state == .ready, "A stale lid helper error was shown as current")
    // Keyboards and Desk show a warning only while they need attention.
    snapshot.keyboardsNeedAttention = true; snapshot.deskNeedsAttention = true
    try check(snapshot.sidebar["keyboard"] == .attention && snapshot.sidebar["desk"] == .attention, "Keyboards or Desk needing attention showed nothing in the sidebar")
    // Setup opens at launch only for a step that needs the person.
    var checking = SetupSnapshot(config: SafetyConfiguration()); checking.config.keepAwake = true
    try check(checking.helpers.state == .checking && !checking.checks.contains { $0.state == .attention }, "A helper still being checked counted as needing the person")

    // The menu: no kill switch, a disk line, and the peer update only when a
    // Mac is behind.
    let app = AppDelegate(); app.buildMenu()
    let sections = app.menu.items.filter { ($0.view as? MenuRowView)?.kind == .section }.map(\.title)
    try check(!sections.contains("Agent Kill Switch") && sections.first == "System" && sections.last == "Perch",
              "Menu sections changed or the Agent Kill Switch came back: \(sections)")
    let removed = ["globalPrivacyReset", "stopAgents", "resumeAgents", "configurePanic"].map(NSSelectorFromString)
    try check(!app.menu.items.contains { item in item.action.map(removed.contains) == true },
              "The menu still offers a kill switch action")
    try check(app.diskItems.first.map { app.menu.items.contains($0) } == true, "The System section has no disk line")
    try check(app.peerUpdateItem?.isHidden == true, "Update Perch on another Mac showed with no Mac behind")

    // The Reset page offers only Perch's own privacy decisions.
    let operation = ResetBatchOperation(execute: { _, _, finish in finish(.success("Fixture")) })
    let page = ResetChecklistPage(highlight: nil, operation: operation, readLayouts: { [] })
    let views = all(page.view)
    try check(!views.contains { $0.identifier?.rawValue == "reset.all-apps" }, "The Reset page still offers resetting every app's privacy")
    try check(!views.compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.contains("every app in your macOS account") },
              "The Reset page still describes resetting every app")

    // Hotkeys lists ⌃⌥⌘V among the fixed shortcuts, and says when it is off.
    let fixed = HotkeySettings.fixedShortcuts(pasteActive: true)
    try check(fixed.first?.keys == "⌃⌥⌘V" && fixed.first?.name.hasPrefix("Paste") == true, "Hotkeys does not list ⌃⌥⌘V: \(fixed.map(\.keys))")
    try check(HotkeySettings.fixedShortcuts(pasteActive: false).first?.keys.contains("off") == true, "Hotkeys did not say ⌃⌥⌘V is off when another shortcut holds it")

    // Versions across the desk, on Scott's desk: the MacBook on a local build,
    // the Studio on the published release.
    let macBook = DeskVersionNote.Peer(name: "Scott’s MacBook Pro", build: 305, version: "2.0.305")
    let studio = DeskVersionNote.Peer(name: "HQ-KP40Y76PT6", build: 301, version: "2.0.301")
    let current = PerchRelease(build: 301, version: "2.0.301"), newer = PerchRelease(build: 306, version: "2.0.306")
    let onStudio = DeskVersionNote.here(own: 301, published: current, peers: [macBook])
    try check(onStudio == .newerElsewhere(on: macBook.name, version: "2.0.305", released: false) && onStudio?.hint(own: "2.0.301") == "2.0.305 · not released" && onStudio?.actionable == false,
              "The Studio did not say the MacBook runs an unreleased Perch, or offered to install it: \(String(describing: onStudio))")
    try check(DeskVersionNote.updatable([studio], published: current).isEmpty && DeskVersionNote.updatable([studio], published: nil).isEmpty,
              "The MacBook offered the Studio an update it cannot fetch")
    let released = DeskVersionNote.here(own: 301, published: newer, peers: [macBook])
    try check(released == .install(version: "2.0.306") && released?.hint(own: "2.0.301") == "2.0.301 → 2.0.306" && released?.actionable == true,
              "A published update did not read as from → to, or could not be installed: \(String(describing: released))")
    try check(DeskVersionNote.updatable([studio], published: newer) == [studio] && DeskVersionNote.peerHint([studio], to: newer) == "2.0.301 → 2.0.306",
              "The MacBook's row for the Studio did not read as from → to")
    try check(DeskVersionNote.here(own: 305, published: current, peers: [studio]) == nil && DeskVersionNote.here(own: 301, published: nil, peers: [])  == nil,
              "A Mac with nothing newer anywhere showed a version note")
    try check(app.updateHereItem?.isHidden == true, "The version note showed with nothing newer")

    // Restarting and updating with the lid closed.
    try check(AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: false, sleepDisabled: false), "Confirmed inactive closed-lid restart was blocked")
    try check(!AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: true, sleepDisabled: false) &&
              !AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: true, sleepDisabled: true), "An unowned lid session was dropped by restart")
    try check(!AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: false, sleepDisabled: nil), "Unknown override state allowed closed-lid restart")
    // Scott's MacBook, November 13: lid closed, sleep disabled outside Perch,
    // no Perch session or override. Restart and updates were refused, and the
    // menu's Restart Perch seemed to do nothing.
    try check(AppUpdate.canRestart(active: false, lidOpen: false, recordedSession: false, sleepDisabled: true),
              "Sleep disabled outside Perch blocked restarting Perch with the lid closed")

    // Window tests skip the AGENT MODE banner only inside a virtual machine
    // nobody is using; a flag alone never does it on a physical Mac.
    try check(DesktopTestSession.unattended(flag: "1", virtualMachine: true), "Window tests could not run unattended in a virtual machine")
    try check(!DesktopTestSession.unattended(flag: "1", virtualMachine: false), "A flag alone let window tests skip the banner on a physical Mac")
    try check(!DesktopTestSession.unattended(flag: nil, virtualMachine: true) && !DesktopTestSession.unattended(flag: "yes", virtualMachine: true),
              "Window tests skipped the banner without being asked to")

    print("PASS: settings without windows: Setup lists no kill switch rows and shows the old process watcher only while it is installed; the menu has no kill switch, a disk line, and the peer update only when a Mac is behind; the Reset page offers only Perch's own privacy; Hotkeys lists ⌃⌥⌘V; versions across the desk read from → to and offer only updates that can happen; restart works with the lid closed unless Perch has a lid session to keep; window tests skip the banner only when asked inside a virtual machine")
}
