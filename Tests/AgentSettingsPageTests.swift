import AppKit
import Carbon

func runAgentSettingsPageTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    let initialPages = host.pages
    defer { host.pages = initialPages; if let page = host.pages.last { host.display(page) } }
    var stored = SafetyConfiguration(), writes = 0, failWrite = false, conflict = false
    try check(stored.shortcut.key == UInt32(kVK_Escape) && stored.shortcut.modifiers == .standard && stored.shortcut.enabled, "Fresh configuration has the wrong emergency shortcut default")
    stored.shortcut.enabled = false
    let compact = AgentSettingsPage(mode: .shortcut, load: { stored }, save: { _ in }, conflicts: { _ in false })
    let compactHeight = compact.layoutShortcut(width: 640)
    try check(compactHeight < 180, "Healthy emergency shortcut retained its blank status area")
    compact.status.stringValue = String(repeating: "Registration or saving needs attention; the previous shortcut is kept. ", count: 12)
    compact.retry.isHidden = false
    let expandedHeight = compact.layoutShortcut(width: 572)
    try check(expandedHeight > compactHeight && compact.view.subviews.allSatisfy { $0.isHidden || compact.view.bounds.contains($0.frame) }, "Compact editor clipped wrapped errors or Retry")
    try check(compact.status.frame.maxY < compact.keys.frame.minY && compact.status.frame.minY > compact.retry.frame.maxY, "Shortcut error overlaps key controls or Retry")
    let makePage = {
        AgentSettingsPage(mode: .fixtureCombined, load: { stored }, save: { value in
            if failWrite { throw AppError(message: "Fixture write failure") }
            stored = value; writes += 1
        }, conflicts: { _ in conflict })
    }
    let adapter = makePage()
    var changed = adapter.shortcut; changed.key = UInt32(kVK_F9)
    adapter.editShortcut(changed)
    try check(stored.shortcut.key == UInt32(kVK_F9), "Shared shortcut adapter bypassed saving")
    conflict = true; changed.enabled = true; changed.key = UInt32(kVK_F8)
    adapter.editShortcut(changed)
    try check(stored.shortcut.key == UInt32(kVK_F9) && adapter.shortcut.key == UInt32(kVK_F8) && adapter.feedbackKind == .warning, "Shared editor lost rejected draft or replaced saved shortcut")
    conflict = false; writes = 0; stored = SafetyConfiguration(); stored.shortcut.enabled = false
    let page = makePage(); page.show()
    try check(!host.modal && NSApp.modalWindow == nil && host.pages.last?.view === page.view, "Agent page entered a modal session")
    func click(_ button: NSButton) throws {
        // This page has a list inside the page scroller. Revealing in only the
        // inner list leaves it clipped when a previous click scrolled the page.
        var ancestor: NSView? = button
        while let view = ancestor {
            view.scrollToVisible(view.convert(button.bounds, from: button))
            ancestor = view.superview
        }
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
    try check(stored.shortcut == validShortcut && reopened.status.stringValue.contains("already used by another Perch action"), "Conflicting monitor shortcut was saved")
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
    reopened.reset.selectItem(at: 2)
    _ = NSApp.sendAction(reopened.reset.action!, to: reopened.reset.target, from: reopened.reset)
    try check(stored.privacyResetScope == .allAppsExcludingPerch, "All-app privacy reset did not preserve Perch exclusion")
    reopened.reset.selectItem(at: 3)
    _ = NSApp.sendAction(reopened.reset.action!, to: reopened.reset.target, from: reopened.reset)
    try check(stored.privacyResetScope == .allAppsIncludingPerch, "All-app privacy reset did not include Perch when selected")
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
    let app = AppDelegate(); app.buildMenu()
    let row = app.safetyItem.view as! MenuRowView
    var safetyConfig = SafetyConfiguration()
    safetyConfig.shortcut.enabled = true
    app.refreshSafety(status: nil, config: safetyConfig)
    try check(row.shortcutHint == "⌃⌥⌘Esc" && row.text.string.contains("Watcher offline"), "Configured Panic shortcut lost offline status")
    safetyConfig.shortcut.enabled = false
    app.refreshSafety(status: nil, config: safetyConfig)
    try check(row.shortcutHint.isEmpty, "Disabled Panic shortcut remained displayed")
    safetyConfig.shortcut.enabled = true
    app.refreshSafety(status: nil, config: safetyConfig)
    row.text = NSAttributedString(string: "Panic…  12 tracked  Immediate Kill", attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    try check(row.displayedShortcut == "⌃⌥⌘Esc" && app.safetyItem.keyEquivalent.isEmpty && row.accessibilityHelp()?.contains("⌃⌥⌘Esc") == true, "Panic shortcut formatting or accessible label failed")
    let required = row.text.size().width + (row.displayedShortcut as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 13)]).width + 45
    try check(row.frame.width > required, "Shortcut overlaps status text")
    let quit = app.menu.items.first { $0.keyEquivalent == "q" }!.view as! MenuRowView
    try check(quit.displayedShortcut == "⌘Q", "Native Quit shortcut changed")
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: row.frame.width, height: 88))
    app.refreshDeskSharingMenu()
    for (index, item) in [app.safetyItem!, app.shareInputItem!, quit.item!].enumerated() {
        let original = item.view as! MenuRowView
        let rendered = MenuRowView(item: item, kind: original.kind, text: original.text)
        rendered.shortcutHint = original.shortcutHint
        rendered.frame = NSRect(x: 0, y: 60-index*28, width: Int(canvas.frame.width), height: 24)
        canvas.addSubview(rendered)
    }
    try renderReleaseView(canvas, path: "/private/tmp/perch-menu-shortcuts.png")
    print("PASS: right-aligned configured shortcuts for the kill switch and desk sharing; change/disable refresh; Escape and F keys; accessible text; spacing; native Quit preserved; no new key equivalents or hardware requests")
}
