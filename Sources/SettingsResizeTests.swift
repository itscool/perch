import AppKit

func runSettingsResizeTests() throws {
    let domain = "perch.window-resize." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let host = SettingsWindow(defaults: defaults); host.testing = true
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: "Settings resize: " + message) } }
    var available: NSSize = .zero
    let a = SettingsDestination(id: "a", title: "First", pageTitles: ["First"]) {
        host.show(.init(title: "First", detail: "Resizable fixture", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 100)), layout: { available = $0 }))
    }
    let b = SettingsDestination(id: "b", title: "Second", pageTitles: ["Second"]) {
        host.show(.init(title: "Second", detail: "Another page", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 900))))
    }
    host.configureNavigation([a,b]); host.navigate(to: a)
    try check(host.window.styleMask.contains(.resizable), "window cannot resize")
    let old = host.window.contentView!.bounds.size
    host.window.setContentSize(NSSize(width: old.width + 140, height: old.height + 60))
    host.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: host.window))
    let chosen = host.window.contentView!.bounds.size
    try check(available.width == chosen.width - 228 - 48 && available.height > 96, "content did not receive available space")
    host.navigate(to: b)
    try check(host.window.contentView!.bounds.size == chosen && host.pages.last!.view.frame.width == available.width, "page change reset size or wasted added width")
    let alert = NSAlert(); alert.messageText = "Resize confirmation"; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Continue")
    host.present(alert)
    host.window.setContentSize(NSSize(width: chosen.width + 20, height: chosen.height))
    host.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: host.window))
    try check(host.activeAlert === alert && host.heading.stringValue == "Resize confirmation", "resize replaced active confirmation")
    host.finish(alert, response: .alertFirstButtonReturn)
    let saved = host.window.contentView!.bounds.size
    host.window.close()
    let reopened = SettingsWindow(defaults: defaults); reopened.testing = true
    reopened.configureNavigation([SettingsDestination(id: "a", title: "First", pageTitles: ["First"], open: {})])
    reopened.show(.init(title: "First", detail: "Restored", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 100))))
    try check(reopened.window.contentView!.bounds.size == saved, "preferred size was not restored")
    try check(reopened.window.contentMinSize.width > 500 && reopened.window.contentMinSize.height >= 320, "minimum size lost usable controls")
    reopened.window.close()
    print("PASS: resizable Settings, usable minimum, content width, stable page transitions, active confirmation ownership and persisted size; isolated preferences")
}
