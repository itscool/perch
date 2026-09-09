import AppKit

/// Hidden native controls: no UI presentation, clipboard writes or OS settings.
func runSettingsAccessibilityTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true
    guard !host.window.isVisible, !host.interactionBusy else { throw AppError(message: "Accessibility fixture needs a hidden idle window") }
    host.pages = []
    defer { host.pages = []; host.modalTestDriver = nil }
    func makePage() -> (NSView, NSTextField) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 160))
        let name = NSTextField(string: "Keep this draft")
        name.identifier = .init("fixture.name"); name.setAccessibilityLabel("Fixture name")
        name.frame = NSRect(x: 0, y: 60, width: 320, height: 28); view.addSubview(name)
        return (view, name)
    }
    let (view, name) = makePage()
    host.show(.init(title: "Focus fixture", detail: "", view: view))
    try check(host.window.makeFirstResponder(name), "Text field did not accept focus")
    (name.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 5, length: 4))
    let alert = NSAlert(); alert.messageText = "Harmless child"; alert.addButton(withTitle: "OK")
    host.present(alert); host.finish(alert)
    try check(name.currentEditor() != nil && host.pages.last?.focusView === name, "Closing a child lost the parent field focus")
    try check((name.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 5, length: 4), "Closing a child lost the field selection")
    let (replacement, nextName) = makePage()
    host.show(.init(title: "Focus fixture", detail: "Refreshed", view: replacement))
    try check(nextName.currentEditor() != nil && (nextName.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 5, length: 4), "Refreshing a page lost focus/selection instead of matching the control identifier")
    let child = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 120))
    host.show(.init(title: "Ordinary child", detail: "", view: child)); host.goBack()
    try check(nextName.currentEditor() != nil, "Back from a child lost the parent field focus")
    host.display(host.pages.last!)
    try check(nextName.currentEditor() != nil, "Refreshing the retained page detached its focused field")

    var copied: [String] = []
    let path = URL(fileURLWithPath: "/usr/bin/true")
    let permission = PermissionDragItem(title: "Fixture permission file", file: { path }, copyPath: { copied.append($0) })
    permission.frame = NSRect(x: 0, y: 10, width: 300, height: 38); replacement.addSubview(permission)
    try check(permission.accessibilityRole() == .button && permission.acceptsFirstResponder, "Permission drag control has no keyboard/accessibility action")
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    permission.keyDown(with: key)
    try check(copied == [path.path] && permission.accessibilityValue() as? String != nil, "Keyboard copy path had no result")
    try check(permission.accessibilityPerformPress() && copied.count == 2, "Accessible permission action did not use the same path")
    try check(!host.window.isVisible, "Hidden accessibility checks presented a window")
    print("PASS: focus/selection across alert, refresh and Back; keyboard/accessibility permission path with injected clipboard")
}
