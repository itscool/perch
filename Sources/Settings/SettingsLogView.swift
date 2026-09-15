import AppKit

/// A read-only, selectable text pane in a scroll view: the shared body of
/// every log and report page. Replacing the text keeps the reader's place.
final class SettingsLogView: NSScrollView {
    let text: NSTextView
    init(frame: NSRect, monospaced: Bool = false, bordered: Bool = true, accessibilityLabel: String? = nil) {
        text = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        text.isEditable = false; text.isSelectable = true
        text.font = monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        text.textColor = .labelColor; text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isVerticallyResizable = true; text.autoresizingMask = .width; text.textContainer?.widthTracksTextView = true
        if let accessibilityLabel { text.setAccessibilityLabel(accessibilityLabel) }
        hasVerticalScroller = true; autohidesScrollers = false
        if bordered { borderType = .bezelBorder }
        documentView = text
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// Replace the content without losing the reader's place: an unscrolled
    /// view stays at the top, a scrolled one keeps its distance from the end.
    func replace(_ content: String) {
        guard text.string != content else { return }
        let oldHeight = text.frame.height, offset = contentView.bounds.origin
        text.string = content; text.layoutManager?.ensureLayout(for: text.textContainer!)
        if offset.y > 1 { contentView.scroll(to: NSPoint(x: 0, y: max(0, offset.y + text.frame.height - oldHeight))) }
        else { contentView.scroll(to: .zero) }
        reflectScrolledClipView(contentView)
    }
}
