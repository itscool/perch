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

    // Setup rows are the list the page draws.
    var snapshot = SetupSnapshot(config: SafetyConfiguration())
    let ids = Set(snapshot.checks.map(\.id))
    try check(!ids.contains("agents") && !ids.contains("events"), "Setup still lists the Agent Kill Switch or its process events: \(ids.sorted())")
    // The old process watcher has a row only while it is installed, with its
    // one removal action, and the row goes when it does.
    try check(!ids.contains("watcher"), "Setup showed the old process watcher on a Mac without it")
    snapshot.watcherInstalled = true
    let watcher = snapshot.checks.first { $0.id == "watcher" }
    try check(watcher?.state == .attention && watcher?.route == .retireWatcher && watcher?.action == "Remove…",
              "The old process watcher was not offered for removal: \(String(describing: watcher))")
    snapshot.watcherInstalled = false
    try check(!snapshot.checks.contains { $0.id == "watcher" }, "The old process watcher's row stayed after it was removed")

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
