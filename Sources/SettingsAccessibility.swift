import AppKit

/// Per-window navigation, independent of the system preference that excludes
/// buttons from Tab. Native sheets, text editing and VoiceOver chords stay native.
final class SettingsPanel: NSPanel {
    var keyboardNavigationAllowed: () -> Bool = { true }
    override func sendEvent(_ event: NSEvent) {
        if handleSettingsKey(event) { return }
        super.sendEvent(event)
    }
    @discardableResult func handleSettingsKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, attachedSheet == nil, keyboardNavigationAllowed(),
              !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else { return false }
        if event.keyCode == 48 {
            if let text = firstResponder as? NSTextView, text.isEditable, !text.isFieldEditor,
               !event.modifierFlags.contains(.control) { return false } // literal Tab in a multiline editor
            return moveSettingsFocus(backwards: event.modifierFlags.contains(.shift))
        }
        if [36, 76].contains(event.keyCode), defaultButtonCell != nil { return false } // Native Return/default action wins.
        guard !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.shift),
              [36, 49, 76].contains(event.keyCode), let button = firstResponder as? NSButton,
              !(button is NSPopUpButton), button.isEnabled, !button.isHiddenOrHasHiddenAncestor else { return false }
        button.performClick(nil)
        return true
    }
    func settingsKeyViews() -> [NSView] {
        func walk(_ view: NSView) -> [NSView] {
            guard !view.isHiddenOrHasHiddenAncestor else { return [] }
            if let control = view as? NSControl, !control.isEnabled { return [] }
            if view is NSButton { return [view] }
            if let text = view as? NSTextField { return text.isEditable ? [text] : [] }
            if let text = view as? NSTextView { return text.isSelectable && !text.isFieldEditor ? [text] : [] }
            if view.accessibilityRole() == .button && view.acceptsFirstResponder { return [view] }
            let children = view.subviews.sorted { a, b in
                let ay = ((view.isFlipped ? a.frame.midY : -a.frame.midY) / 8).rounded()
                let by = ((view.isFlipped ? b.frame.midY : -b.frame.midY) / 8).rounded()
                return ay != by ? ay < by : a.frame.minX < b.frame.minX
            }.flatMap(walk)
            if let scroll = view as? SettingsExplanationScroll, children.isEmpty,
               let doc = scroll.documentView, doc.frame.height > scroll.contentSize.height + 1 { return [scroll] }
            return children
        }
        return contentView.map(walk) ?? []
    }
    @discardableResult func moveSettingsFocus(backwards: Bool) -> Bool {
        let views = settingsKeyViews()
        guard !views.isEmpty else { return false }
        let focused = (firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : $0 } ?? firstResponder as? NSView
        let index = focused.flatMap { focus in views.firstIndex { $0 === focus } }
        let start = index ?? (backwards ? 0 : -1)
        for step in 1...views.count {
            let next = (start + (backwards ? -step : step) + views.count * 2) % views.count
            let target = views[next]
            if target.acceptsFirstResponder && makeFirstResponder(target) {
                target.scrollToVisible(target.bounds)
                NSAccessibility.post(element: target, notification: .focusedUIElementChanged)
                return true
            }
        }
        return false
    }
}

/// Long, read-only explanations need a real keyboard scroll target, not a
/// noneditable text field which silently refuses first-responder ownership.
final class SettingsExplanationScroll: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty,
              [115, 119, 116, 121, 125, 126].contains(event.keyCode), let doc = documentView else { super.keyDown(with: event); return }
        let maximum = max(0, doc.frame.height - contentSize.height)
        var y = contentView.bounds.origin.y
        switch event.keyCode {
        case 115: y = doc.isFlipped ? 0 : maximum
        case 119: y = doc.isFlipped ? maximum : 0
        default:
            let down = event.keyCode == 121 || event.keyCode == 125
            let distance: CGFloat = event.keyCode == 125 || event.keyCode == 126 ? 24 : max(24, contentSize.height * 0.9)
            y += (down == doc.isFlipped ? 1 : -1) * distance
        }
        contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: min(maximum, max(0, y))))
        reflectScrolledClipView(contentView)
    }
}

/// Read-only, changing text remains observable without narrating every poll.
final class SettingsStatusField: NSTextField {
    var announcesChanges = false
    override var stringValue: String {
        didSet {
            guard oldValue != stringValue, !isHiddenOrHasHiddenAncestor,
                  let window, window.isVisible, window.isKeyWindow else { return }
            NSAccessibility.post(element: self, notification: .valueChanged)
            if announcesChanges { SettingsAccessibility.announce(stringValue) }
        }
    }
}

enum SettingsAccessibility {
    static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        NSAccessibility.post(element: NSApp!, notification: .announcementRequested,
            userInfo: [.announcement: String(text.prefix(400)), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
