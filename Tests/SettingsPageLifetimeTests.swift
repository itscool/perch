import AppKit

/// Setup & status, Reset Settings and plain task pages are created in a local
/// scope. Each must stay alive while shown, so its buttons respond, and be
/// released when it leaves. Runs headlessly with the shared window in testing mode.
func runSettingsPageLifetimeTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    let wasTesting = host.testing
    host.testing = true
    defer {
        host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
        host.testing = wasTesting
    }
    guard !host.window.isVisible, !host.interactionBusy else { throw AppError(message: "Page lifetime test needs a hidden, idle Settings window") }
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))

    // Back pops a page only when a parent is below it; a single page closes the
    // window instead. Each case opens a parent first so Back really leaves.
    func showParent() { host.show(.init(title: "Lifetime parent", detail: "", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 80)))) }
    func buttons(in view: NSView) -> [SettingsActionButton] {
        view.subviews.flatMap { ($0 as? SettingsActionButton).map { [$0] } ?? buttons(in: $0) }
    }

    // Setup & status: Recheck must reach the live page.
    weak var setup: SetupOverviewPage?
    var rechecks = 0
    showParent()
    do {
        let page = SetupOverviewPage(firstVisit: false, read: { SetupSnapshot(config: SafetyConfiguration()) },
                                     recheck: { rechecks += 1 }, navigate: { _, _ in })
        setup = page; page.show()
    }
    try check(setup != nil, "Setup & status was released while shown; its buttons would do nothing")
    if let view = setup?.view { buttons(in: view).first { $0.title == "Recheck" }?.performClick(nil) }
    try check(rechecks == 1, "Setup & status Recheck did not reach the page")
    try check(setup?.timer != nil, "Setup & status is not polling while shown")
    host.goBack()
    try check(setup == nil, "Setup & status stayed alive after leaving")

    // A plain task page keeps refreshing while shown.
    weak var task: SettingsTaskPage?
    var updates = 0
    showParent()
    do {
        let page = SettingsTaskPage(title: "Lifetime task", detail: "", height: 200)
        page.update = { updates += 1 }
        _ = page.add("Row", detail: "Fixture row") {}
        task = page; page.show()
    }
    try check(task != nil, "A task page was released while shown; its status would never refresh")
    let before = updates
    host.pollTimer(for: task!.view)?.fire()
    try check(updates > before, "A shown task page did not refresh on its poll")
    host.goBack()
    try check(task == nil, "A task page stayed alive after leaving")

    // Reset Settings: the checklist page stays alive while shown.
    weak var reset: ResetChecklistPage?
    showParent()
    do {
        let operation = ResetBatchOperation(execute: { _, _, completion in completion(.success("fixture")) })
        let page = ResetChecklistPage(highlight: nil, operation: operation, readLayouts: { [] }, allApps: {})
        reset = page; page.show()
    }
    try check(reset != nil, "Reset Settings was released while shown; its checkboxes and Reset button would do nothing")
    host.goBack()
    try check(reset == nil, "Reset Settings stayed alive after leaving")
    try check(!host.window.isVisible, "Page lifetime test presented the Settings window")
    print("PASS: Setup & status, Reset Settings and task pages stay alive and responsive while shown and release after leaving")
}
