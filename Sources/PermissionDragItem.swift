import AppKit

/// Drags the actual signed app/executable URL into a macOS privacy list.
/// It does not write TCC settings or grant permission itself.
final class PermissionDragItem: NSView, NSDraggingSource {
    let file: () -> URL
    let caption: String
    private let copyPath: (String) -> Void
    private var copied = false
    init(title: String, file: @escaping () -> URL, copyPath: ((String) -> Void)? = nil) {
        self.file = file; caption = title
        self.copyPath = copyPath ?? { path in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
        super.init(frame: .zero)
        toolTip = "Drag into System Settings, or press Space to copy this path. In the permission list, choose +, press Command–Shift–G, paste the path, then choose Open and enable the entry. " + file().path
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title + ": copy path for permission setup")
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode) { _ = accessibilityPerformPress() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard FileManager.default.fileExists(atPath: file().path) else { return false }
        copyPath(file().path); copied = true; needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
        return true
    }
    override func accessibilityValue() -> Any? { copied ? "Path copied. Paste it in the permission file picker." : nil }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { drawContents() }
    }
    private func drawContents() {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).stroke()
        NSWorkspace.shared.icon(forFile: file().path).draw(in: NSRect(x: 6,y: (bounds.height-28)/2,width: 28,height: 28))
        ((copied ? "Path copied · paste in file picker" : caption) as NSString).draw(in: NSRect(x: 40,y: (bounds.height-16)/2,width: bounds.width-44,height: 18), withAttributes: [.font:NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor:NSColor.labelColor])
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        copied = false; needsDisplay = true
        let url = file()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: 6,y: (bounds.height-32)/2,width: 32,height: 32), contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .outsideApplication ? .copy : [] }
}
