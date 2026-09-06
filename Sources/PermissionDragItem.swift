import AppKit

/// Drags the actual signed app/executable URL into a macOS privacy list.
/// It does not write TCC settings or grant permission itself.
final class PermissionDragItem: NSView, NSDraggingSource {
    let file: () -> URL
    let caption: String
    init(title: String, file: @escaping () -> URL) {
        self.file = file; caption = title
        super.init(frame: .zero)
        toolTip = "Drag this item into System Settings, then enable its switch. " + file().path
        setAccessibilityElement(true)
        setAccessibilityLabel(title)
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { drawContents() }
    }
    private func drawContents() {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).stroke()
        NSWorkspace.shared.icon(forFile: file().path).draw(in: NSRect(x: 6,y: (bounds.height-28)/2,width: 28,height: 28))
        (caption as NSString).draw(in: NSRect(x: 40,y: (bounds.height-16)/2,width: bounds.width-44,height: 18), withAttributes: [.font:NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor:NSColor.labelColor])
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        let url = file()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: 6,y: (bounds.height-32)/2,width: 32,height: 32), contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .outsideApplication ? .copy : [] }
}
