import AppKit

/// Never presents a window or native picker. Exercises actual NSButton target /
/// action dispatch against the production host with native responses injected.
/// Physical AppKit modal-loop/keyboard routing is a separate acceptance test.
func runDialogOwnershipTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true
    guard !host.window.isVisible, !host.interactionBusy else { throw AppError(message: "Dialog ownership fixture requires an idle, hidden host") }
    defer { host.modalTestDriver = nil; host.pickerTestDriver = nil; host.externalAppTestDriver = nil; host.pages = [] }
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 150))
    var changes = 0
    let ordinary = SettingsActionButton(title: "Fixture preference") { changes += 1 }
    ordinary.frame = NSRect(x: 0, y: 50, width: 250, height: 32); parent.addSubview(ordinary)
    host.show(.init(title: "Fixture parent", detail: "", view: parent))
    ordinary.performClick(nil)
    try check(changes == 1, "Ordinary target/action failed")
    var oldButton: NSButton?
    var failure: Error?
    for exit in ["confirm", "back", "close", "timer", "protected"] {
        let alert = NSAlert(); alert.messageText = "Fixture " + exit
        alert.addButton(withTitle: "Apply fixture"); alert.addButton(withTitle: "Cancel")
        host.modalTestDriver = { current in
            do {
                try check(host.activeAlert === current && host.modal, "Presented alert has no interaction owner")
                try check(!host.finish(NSAlert()), "An unrelated timer completed the active alert")
                let rendered = host.container.subviews.first!
                let action = rendered.subviews.compactMap { $0 as? NSButton }.first!
                let hit = rendered.hitTest(NSPoint(x: action.frame.midX, y: action.frame.midY))
                try check(hit === action || hit?.isDescendant(of: action) == true, "A view covers the dialog action")
                oldButton?.performClick(nil)
                try check(host.modalResponseRequested == nil, "A previous dialog's button completed this one")
                host.display(.init(title: "Background refresh", detail: "", view: parent))
                try check(host.heading.stringValue == current.messageText && action.isDescendant(of: host.container), "Background display replaced the active dialog buttons")
                if exit == "confirm" { action.performClick(nil) }
                else if exit == "back" { host.back.performClick(nil) }
                else if exit == "close" { try check(!host.windowShouldClose(host.window), "X closed the parent under a confirmation") }
                else if exit == "timer" { try check(host.finish(current), "Matching timer could not finish its dialog") }
                else {
                    host.back.performClick(nil)
                    try check(!host.windowShouldClose(host.window) && host.modalResponseRequested == nil, "Noncancellable cleanup was dismissed by parent navigation")
                    try check(host.finish(current), "Bounded cleanup cannot finish itself")
                }
                let expected: NSApplication.ModalResponse = exit == "confirm" ? .alertFirstButtonReturn : (exit == "back" || exit == "close") ? .alertSecondButtonReturn : .stop
                try check(host.modalResponseRequested == expected, "Dialog action returned the wrong response")
                try check(!host.finish(current), "Dialog completed more than once")
                oldButton = action
                return expected
            } catch { failure = error; return .abort }
        }
        _ = host.run(alert, allowsCancel: exit != "protected")
        if let failure { throw failure }
        try check(!host.interactionBusy && host.activeAlert == nil && host.back.isEnabled && parent.isDescendant(of: host.container), "Returning left a dead parent or stale dialog owner")
        ordinary.performClick(nil)
    }
    try check(changes == 6, "Parent buttons stopped working after a dialog returned")
    host.modalTestDriver = nil
    var pickerPassed = false
    host.pickerTestDriver = { _ in
        host.back.performClick(nil)
        pickerPassed = host.picking && !host.back.isEnabled && !host.windowShouldClose(host.window) && !host.finish(NSAlert())
        return .cancel
    }
    try check(host.open(NSOpenPanel()) == .cancel && pickerPassed && !host.interactionBusy && host.back.isEnabled, "Picker cancellation lost interaction ownership")
    host.externalAppTestDriver = { true }
    host.handoffToExternalApp { false }
    try check(host.externalHandoff, "External handoff fixture did not start")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    try check(!host.interactionBusy, "Closing during external handoff stranded future settings actions")
    host.show(.init(title: "Reopened", detail: "", view: parent))
    ordinary.performClick(nil)
    try check(changes == 7 && host.pages.last?.title == "Reopened", "Settings could not reopen after closing an external handoff")
    try check(!host.window.isVisible && NSApp.modalWindow == nil, "Headless dialog fixture presented native UI")
    print("PASS: hidden dialog hit testing and button dispatch; confirmation/Back/X; stale controls/timers; refresh exclusion; exactly-once completion; bounded cleanup; picker cancellation; close/reopen after external handoff. No native window shown.")
}
