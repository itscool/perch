import AppKit
import Carbon

/// Production shortcut flow and shared buttons, with status/clock/commands
/// injected. No response driver, visible window, global shortcut or native modal.
func runShortcutDialogBackTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true; host.modalTestDriver = nil
    guard !host.window.isVisible, !host.interactionBusy else { throw AppError(message: "Shortcut Back tests need a hidden idle host") }
    let defaults = PanicShortcut()
    try check(defaults.key == UInt32(kVK_Escape) && defaults.modifiers == UInt32(controlKey | optionKey | cmdKey) && defaults.title == "⌃⌥⌘Esc", "New-machine shortcut or shared spelling changed")
    let app = AppDelegate()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 150))
    var parentPresses = 0
    let parentButton = SettingsActionButton(title: "Parent fixture") { parentPresses += 1 }
    parent.addSubview(parentButton)
    host.show(.init(title: "Agent Kill Switch", detail: "Fixture", view: parent))
    func until(_ condition: () -> Bool) throws {
        let limit = Date().addingTimeInterval(2)
        while !condition(), Date() < limit { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.03)) }
        try check(condition(), "Shortcut flow did not reach expected state")
        try check(NSApp.modalWindow == nil && !host.window.isVisible, "Shortcut fixture presented native UI")
    }
    for scenario in ["success", "timeout", "cancel", "success", "close"] {
        var now = Date()
        var state = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: false, inputTrusted: true, inputActive: true, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
        var commands: [String] = []
        app.runShortcutTest(readStatus: { state.timestamp = Date(); return state }, send: { command in
            commands.append(command)
            if command == "test" { state.testUntil = now.addingTimeInterval(30) }
            if command == "finish-test" { state.testUntil = nil }
        }, keepAlive: {}, now: { now })
        try check(host.activeAlert?.messageText == "Test shortcut", "Shortcut flow did not return after presenting preparation")
        try check(host.container.subviews.first?.subviews.compactMap({ $0 as? NSButton }).isEmpty == true, "Test page duplicated header navigation with Cancel")
        try until { host.activeAlert?.informativeText.hasPrefix("Press ") == true }
        if scenario == "cancel" { host.back.performClick(nil) }
        else {
            let original = host.activeAlert!
            if scenario == "timeout" { now = now.addingTimeInterval(11) }
            else { state.testResultID = UUID().uuidString }
            try until { host.activeAlert !== original }
            try check(host.activeAlert?.messageText == (scenario == "timeout" ? "No shortcut received" : "Shortcut worked"), "Wrong shortcut result")
            let root = host.window.contentView!
            let hit = root.hitTest(NSPoint(x: host.back.frame.midX, y: host.back.frame.midY))
            try check(hit === host.back || hit?.isDescendant(of: host.back) == true, "Result page covers Back")
            try check(host.back.isEnabled && !host.finish(original), "Result Back disabled or stale test timer still owns result")
            if scenario == "close" { try check(!host.windowShouldClose(host.window), "Result X closed the parent") }
            else { host.back.performClick(nil) }
        }
        try check(host.activeAlert?.messageText == "Ending shortcut test…" && !host.back.isEnabled, "Back did not enter bounded cleanup")
        try until { !host.interactionBusy }
        try check(commands == ["test", "finish-test"] && host.pages.last?.view === parent && host.back.isEnabled, "Cleanup did not restore parent ownership")
        parentButton.performClick(nil)
    }
    try check(parentPresses == 5, "Parent stopped responding across repeated tests")
    host.pages = []
    print("PASS: real shared Back dispatch after shortcut success/timeout, preparation Back, result X, bounded cleanup, repeated entry, parent interaction and default Esc spelling; no modal response driver or visible UI")
}
