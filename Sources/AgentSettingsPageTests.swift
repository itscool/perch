import AppKit
import Carbon

func runAgentSettingsPageTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    let initialPages = host.pages
    defer { host.pages = initialPages; if let page = host.pages.last { host.display(page) } }
    var stored = SafetyConfiguration(), writes = 0, failWrite = false, conflict = false
    stored.shortcut.enabled = false
    let makePage = {
        AgentSettingsPage(load: { stored }, save: { value in
            if failWrite { throw AppError(message: "Fixture write failure") }
            stored = value; writes += 1
        }, conflicts: { _ in conflict })
    }
    let page = makePage(); page.show()
    try check(!host.modal && NSApp.modalWindow == nil && host.pages.last?.view === page.view, "Agent page entered a modal session")
    func click(_ button: NSButton) throws {
        button.scrollToVisible(button.bounds)
        let root = host.window.contentView!
        let point = root.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        try check(root.hitTest(point) === button && button.isEnabled, "Agent control cannot receive a click: \(button.title)")
        button.performClick(nil)
    }
    try click(page.enabled)
    try check(stored.shortcut.enabled && writes == 1, "Enable shortcut did not save immediately")
    let enabledShortcut = stored.shortcut
    try click(page.modifiers[1].0) // Three modifiers -> two: valid replacement.
    try check(stored.shortcut.modifiers != enabledShortcut.modifiers, "Modifier click did not save")
    let validShortcut = stored.shortcut
    try click(page.modifiers[3].0) // Two -> one: keep working shortcut.
    try check(stored.shortcut == validShortcut && page.status.stringValue.contains("not saved"), "Incomplete shortcut replaced the working shortcut")
    stored.keepAwake = true // Simulate an independent settings change.
    try click(page.agents[0].1)
    try check(!stored.targets[0].enabled && stored.keepAwake && stored.shortcut == validShortcut, "Agent choice lost unrelated state or committed an invalid shortcut")
    host.goBack()
    let reopened = makePage(); reopened.show()
    try check(reopened.enabled.state == .on && reopened.modifiers[3].0.state == .on && reopened.agents[0].1.state == .off, "Reopen did not show saved choices")
    conflict = true
    reopened.keys.selectItem(withTitle: "F8")
    _ = NSApp.sendAction(reopened.keys.action!, to: reopened.keys.target, from: reopened.keys)
    try check(stored.shortcut == validShortcut && reopened.status.stringValue.contains("already switch displays"), "Conflicting monitor shortcut was saved")
    conflict = false
    failWrite = true
    _ = NSApp.sendAction(reopened.keys.action!, to: reopened.keys.target, from: reopened.keys)
    try check(!reopened.retry.isHidden && stored.shortcut == validShortcut && reopened.keys.titleOfSelectedItem == "F8", "Failed shortcut write lost draft or had no retry")
    failWrite = false
    try click(reopened.retry)
    try check(stored.shortcut.key == UInt32(kVK_F8) && reopened.retry.isHidden, "Retry failed to save the retained shortcut")
    try click(reopened.enabled)
    try check(!stored.shortcut.enabled, "Disable shortcut did not save immediately")
    reopened.reset.selectItem(at: 0)
    _ = NSApp.sendAction(reopened.reset.action!, to: reopened.reset.target, from: reopened.reset)
    try check(!stored.resetAgentPermissions && stored.keepAwake, "Privacy scope failed to save independently")
    failWrite = true
    try click(reopened.agents[0].1)
    try check(reopened.agents[0].1.state == .off && !stored.targets[0].enabled && !reopened.retry.isHidden, "Failed agent write did not restore saved state")
    failWrite = false
    try click(reopened.retry)
    try check(stored.targets[0].enabled && reopened.agents[0].1.state == .on, "Retry did not restore the requested agent choice")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-agent-settings.png")
    try check(!reopened.view.subviews.compactMap { $0 as? NSButton }.contains { ["Save", "Cancel", "Done"].contains($0.title) }, "Agent page retained redundant acceptance")
    print("PASS: nonmodal agent controls receive clicks; immediate independent saving; invalid/conflicting shortcuts retain working settings; Back/reopen; failed writes and retry; no live shortcut registered or action fired")
    try runShortcutMenuPresentationTests()
}

func runShortcutMenuPresentationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let defaultsName = "perch-shortcut-display-test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: defaultsName)!
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let controller = MonitorInputController(displays: [], defaults: defaults)
    let app = AppDelegate(monitorInputs: controller); app.buildMenu()
    controller.plan.shortcut.enabled = true
    app.refreshMonitorInputItem()
    let monitorRow = app.monitorInputItem.view as! MenuRowView
    try check(monitorRow.shortcutHint == "⌃⌥F8" && app.monitorInputItem.keyEquivalent.isEmpty, "Monitor shortcut missing or double registered as a menu equivalent")
    controller.plan.shortcut.key = UInt32(kVK_F12)
    app.refreshMonitorInputItem()
    try check(monitorRow.shortcutHint == "⌃⌥F12", "Changed monitor shortcut stayed stale")
    controller.plan.shortcut.enabled = false
    app.refreshMonitorInputItem()
    try check(monitorRow.shortcutHint.isEmpty, "Disabled shortcut remained displayed")
    let displayID = UUID().uuidString
    let group = MonitorGroup(name: "Both displays", members: [.init(display: displayID, name: "Fixture")], destinations: [.init(name: "Mac", inputs: [displayID: 15]), .init(name: "Other", inputs: [displayID: 17])], shortcut: .init(key: UInt32(kVK_F10), modifiers: UInt32(controlKey | shiftKey), enabled: true))
    try check(group.valid, "Invalid shortcut group fixture")
    defaults.set(try JSONEncoder().encode(MonitorGroupSettings(groups: [group], activeID: group.id)), forKey: MonitorGroupController.preferenceKey)
    let grouped = AppDelegate(monitorInputs: MonitorInputController(displays: [], defaults: defaults))
    grouped.buildMenu(); grouped.refreshMonitorInputItem()
    try check((grouped.monitorInputItem.view as! MenuRowView).shortcutHint == "⌃⇧F10", "Selected group's shortcut was not shown")
    let row = app.safetyItem.view as! MenuRowView
    var safetyConfig = SafetyConfiguration()
    safetyConfig.shortcut.enabled = true
    app.refreshSafety(status: nil, config: safetyConfig)
    try check(row.shortcutHint == "⌃⌥⌘⎋" && row.text.string.contains("Watcher offline"), "Configured Panic shortcut lost offline status")
    safetyConfig.shortcut.enabled = false
    app.refreshSafety(status: nil, config: safetyConfig)
    try check(row.shortcutHint.isEmpty, "Disabled Panic shortcut remained displayed")
    safetyConfig.shortcut.enabled = true
    app.refreshSafety(status: nil, config: safetyConfig)
    row.text = NSAttributedString(string: "Panic…  12 tracked  Immediate Kill", attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    try check(row.displayedShortcut == "⌃⌥⌘⎋" && app.safetyItem.keyEquivalent.isEmpty && row.accessibilityHelp()?.contains("⌃⌥⌘⎋") == true, "Panic shortcut formatting or accessible label failed")
    let required = row.text.size().width + (row.displayedShortcut as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 13)]).width + 45
    try check(row.frame.width > required, "Shortcut overlaps status text")
    let quit = app.menu.items.first { $0.keyEquivalent == "q" }!.view as! MenuRowView
    try check(quit.displayedShortcut == "⌘Q", "Native Quit shortcut changed")
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: max(row.frame.width, monitorRow.frame.width), height: 88))
    controller.plan.shortcut.enabled = true; app.refreshMonitorInputItem()
    for (index, item) in [app.safetyItem!, app.monitorInputItem!, quit.item!].enumerated() {
        let original = item.view as! MenuRowView
        let rendered = MenuRowView(item: item, kind: original.kind, text: original.text)
        rendered.shortcutHint = original.shortcutHint
        rendered.frame = NSRect(x: 0, y: 60-index*28, width: Int(canvas.frame.width), height: 24)
        canvas.addSubview(rendered)
    }
    try renderReleaseView(canvas, path: "/private/tmp/perch-menu-shortcuts.png")
    print("PASS: right-aligned configured shortcuts for monitor and selected group; change/disable refresh; Escape and F keys; accessible text; spacing; native Quit preserved; no new key equivalents or hardware requests")
}
