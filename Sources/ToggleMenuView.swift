import AppKit

// Custom menu rows dispatch ordinary toggle actions without ending mouse tracking.
// Command rows (Settings, Panic, display off, Quit) keep native dismissal behavior.
final class ToggleMenuView: NSView {
    weak var item: NSMenuItem?
    var hover = false
    init(item: NSMenuItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 24))
        autoresizingMask = .width
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited,.activeAlways,.inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    var enabled: Bool {
        guard let item else { return false }
        return (item.target as? NSMenuItemValidation)?.validateMenuItem(item) ?? item.isEnabled
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { activate() } }
    func activate() {
        guard enabled, let item, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        needsDisplay = true
    }
    override func accessibilityPerformPress() -> Bool { guard enabled else { return false }; activate(); return true }
    override func accessibilityLabel() -> String? { item?.title }
    override func accessibilityValue() -> Any? { item?.state == .on ? 1 : 0 }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { drawContents() }
    }
    private func drawContents() {
        guard let item else { return }
        if hover && enabled {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = !enabled ? .disabledControlTextColor : (hover ? .selectedMenuItemTextColor : .labelColor)
        let mark = item.state == .on ? "✓" : item.state == .mixed ? "−" : ""
        (mark as NSString).draw(at: NSPoint(x: 7,y: 4), withAttributes: [.font:NSFont.systemFont(ofSize: 13),.foregroundColor:color])
        let title = NSMutableAttributedString(attributedString: item.attributedTitle ?? NSAttributedString(string: item.title, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
        if !enabled || hover { title.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0,length: title.length)) }
        title.draw(at: NSPoint(x: 25,y: 4))
    }
}
