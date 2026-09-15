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
    // Route through the production panel's key handler with native controls,
    // including when macOS would normally omit buttons from its Tab loop.
    let controls = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 300))
    var presses = 0
    let first = SettingsActionButton(title: "First") { presses += 1 }
    first.frame = NSRect(x: 0, y: 220, width: 150, height: 30)
    let disabled = SettingsActionButton(title: "Disabled") { presses += 100 }
    disabled.frame = NSRect(x: 170, y: 220, width: 150, height: 30); disabled.isEnabled = false
    let hidden = SettingsActionButton(title: "Hidden") { presses += 100 }
    hidden.frame = NSRect(x: 0, y: 170, width: 150, height: 30); hidden.isHidden = true
    let field = NSTextField(string: "Editable"); field.frame = NSRect(x: 0, y: 120, width: 300, height: 30)
    let multiline = NSTextView(frame: NSRect(x: 0, y: 10, width: 300, height: 70)); multiline.string = "Two lines"
    [multiline, hidden, field, disabled, first].forEach { controls.addSubview($0) } // intentionally not visual order
    host.show(.init(title: "Keyboard controls", detail: "", view: controls))
    let panel = host.window
    func keystroke(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    panel.makeFirstResponder(host.back)
    try check(panel.handleSettingsKey(keystroke(48)) && panel.firstResponder === first, "Tab skipped the first button or used construction order")
    try check(panel.handleSettingsKey(keystroke(49)) && presses == 1, "Space failed to activate focused button")
    try check(panel.handleSettingsKey(keystroke(36)) && presses == 2, "Return failed to activate focused button")
    panel.defaultButtonCell = first.cell as? NSButtonCell
    try check(!panel.handleSettingsKey(keystroke(36)), "Native default Return was intercepted")
    panel.defaultButtonCell = nil
    try check(panel.handleSettingsKey(keystroke(48)) && field.currentEditor() != nil, "Tab did not skip hidden/disabled actions")
    try check(!panel.handleSettingsKey(keystroke(36)), "Return in text field was intercepted")
    try check(panel.handleSettingsKey(keystroke(48, [.shift])) && panel.firstResponder === first, "Shift-Tab failed from field editor")
    try check(!panel.handleSettingsKey(keystroke(49, [.control, .option])) && presses == 2, "VoiceOver chord was intercepted")
    panel.makeFirstResponder(multiline)
    try check(!panel.handleSettingsKey(keystroke(48)) && !panel.handleSettingsKey(keystroke(36)), "Multiline text editing was intercepted")
    try check(panel.handleSettingsKey(keystroke(48, [.control])) && panel.firstResponder === host.back, "Control-Tab could not leave multiline editor or wrap")
    let endAuthorization = host.beginAuthorization()
    try check(!panel.handleSettingsKey(keystroke(48)), "Perch took keyboard input during authorization")
    endAuthorization()
    try check(host.announcedPage == "Keyboard controls" && panel.title.contains("Keyboard controls"), "Current page identity was not exposed to accessibility")
    host.notifyAccessibilityPage()
    host.show(.init(title: "Long explanation", detail: String(repeating: "Read this explanation. ", count: 200), view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 120))))
    panel.makeFirstResponder(host.back)
    let movedLong = panel.handleSettingsKey(keystroke(48))
    try check(movedLong && panel.firstResponder === host.detailScroll, "Long explanation cannot receive keyboard reading/selection focus")

    let oldScroll = host.detailScroll.contentView.bounds.origin.y
    host.detailScroll.keyDown(with: keystroke(121))
    try check(host.detailScroll.contentView.bounds.origin.y > oldScroll, "Page Down did not scroll the long explanation")
    host.detailScroll.keyDown(with: keystroke(115))
    try check(host.detailScroll.contentView.bounds.origin.y == 0, "Home did not return to the start of the explanation")
    try check(!host.window.isVisible, "Hidden accessibility checks presented a window")
    print("PASS: focus/selection across alert, refresh and Back; keyboard/accessibility permission path with injected clipboard; Tab/Shift-Tab, Space/Return, disabled/hidden controls, multiline escape route and VoiceOver chord preservation")
}
