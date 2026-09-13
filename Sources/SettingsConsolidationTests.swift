import AppKit
import Carbon

/// Unattached native controls only. No SettingsWindow, timers, registration,
/// hardware reads, system handoffs, file writes or presented windows.
func runSettingsConsolidationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var stored = SafetyConfiguration(), writes = 0, fail = false, conflict = false
    stored.shortcut.enabled = false
    let shortcut = AgentSettingsPage(mode: .shortcut, load: { stored }, save: { value in
        if fail { throw AppError(message: "Fixture failure") }; stored = value; writes += 1
    }, conflicts: { _ in conflict }, readStatus: { nil })
    try check(shortcut.enabled.superview === shortcut.view && shortcut.reset.superview == nil, "Hotkeys includes agent configuration")
    shortcut.enabled.performClick(nil)
    try check(stored.shortcut.enabled && writes == 1, "Emergency enable did not save")
    let saved = stored.shortcut
    conflict = true; shortcut.keys.selectItem(withTitle: "F8")
    NSApp.sendAction(shortcut.keys.action!, to: shortcut.keys.target, from: shortcut.keys)
    try check(stored.shortcut == saved && shortcut.status.stringValue.contains("not saved"), "Conflict overwrote saved shortcut")
    conflict = false; fail = true
    NSApp.sendAction(shortcut.keys.action!, to: shortcut.keys.target, from: shortcut.keys)
    try check(stored.shortcut == saved && !shortcut.retry.isHidden, "Failed save lost working shortcut or retry")
    fail = false; shortcut.retry.performClick(nil)
    try check(stored.shortcut.key == UInt32(kVK_F8) && shortcut.retry.isHidden, "Shortcut retry failed")
    let agents = AgentSettingsPage(mode: .agents, load: { stored }, save: { stored = $0 }, conflicts: { _ in false }, readStatus: { nil })
    try check(agents.enabled.superview == nil && agents.keys.superview == nil && agents.reset.superview === agents.view, "Agent page still edits shortcuts")
    agents.agents[0].1.performClick(nil)
    try check(stored.shortcut.key == UInt32(kVK_F8) && !stored.targets[0].enabled, "Agent edit damaged shortcut")

    let sidebar = SettingsSidebar(frame: NSRect(x: 0, y: 0, width: 220, height: 250))
    var status: SettingsSetupStatus = .checking, navigations = 0
    sidebar.readSetupStatus = { ["access": status] }
    sidebar.choose = { _ in navigations += 1 }
    sidebar.configure([.init(id: "access", title: "Keyboard access", pageTitles: [], depth: 1, setupStage: true, open: {})])
    sidebar.layoutSubtreeIfNeeded()
    sidebar.update(selected: "access", busy: false)
    let cell = sidebar.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
    cell.layoutSubtreeIfNeeded()
    try check(cell.imageView?.image != nil && cell.bounds.contains(cell.imageView!.frame), "Sidebar readiness icon is outside its actual row")
    try check(cell.bounds.contains(cell.textField!.frame) && !cell.textField!.frame.intersects(cell.imageView!.frame), "Sidebar label clips or covers the indicator")
    for value: SettingsSetupStatus in [.ready, .attention, .optional, .checking] {
        status = value; sidebar.refreshSetupStatus()
        try check(sidebar.table.selectedRow == 0 && navigations == 0, "Status refresh navigated or lost selection")
        try check(sidebar.table.view(atColumn: 0, row: 0, makeIfNecessary: false) === cell && cell.accessibilityValue() as? String == value.rawValue, "Status replaced cell or failed to announce state")
    }
    let group = KVMGroup(name: "Fixture", computers: [.init(name: "Mac")])
    try check(group.presets.map(\.shortcut) == (1...3).map { KVMShortcut(key: "F\($0)") } && group.presets.allSatisfy { $0.shortcut.control && $0.shortcut.option && $0.shortcut.command && !$0.shortcut.shift }, "New desk shortcut defaults changed")
    try check(NSApp.windows.isEmpty, "Offscreen fixture opened a window")
    print("PASS: isolated shortcut edits/conflict/retry, agent separation, sidebar in-place readiness and stable selection, F1–F3 defaults; no windows or external writes")
}
