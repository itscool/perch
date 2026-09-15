import AppKit

/// A log page: a status line, the log pane and a Copy button, with room for
/// one extra control on the right. The page that shows it owns its polling.
final class SettingsLogPage {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
    let status = NSTextField(wrappingLabelWithString: "")
    let log: SettingsLogView
    var text: NSTextView { log.text }
    private(set) var copyButton: SettingsActionButton!
    /// What Copy log puts on the pasteboard; defaults to the visible text.
    var copy: () -> String
    init(placeholder: String, accessibilityLabel: String? = nil, copy: (() -> String)? = nil) {
        log = SettingsLogView(frame: NSRect(x: 0, y: 42, width: 572, height: 398), accessibilityLabel: accessibilityLabel)
        let text = log.text
        self.copy = copy ?? { text.string }
        status.stringValue = placeholder
        status.font = .systemFont(ofSize: 12); status.frame = NSRect(x: 4, y: 448, width: 564, height: 40)
        copyButton = SettingsActionButton(title: "Copy log") { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(self.copy(), forType: .string)
        }
        copyButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32); copyButton.isEnabled = false
        [status, log, copyButton].forEach { view.addSubview($0) }
    }
    /// One extra control, placed on the bottom right.
    func addControl(_ button: NSButton, width: CGFloat = 174) {
        button.frame = NSRect(x: 572 - width, y: 0, width: width, height: 32); view.addSubview(button)
    }
    /// Show content with its status line. Empty content disables copying.
    func present(_ content: String, empty: Bool, status statusText: String, kind: SettingsFeedbackKind = .information) {
        log.replace(content); copyButton.isEnabled = !empty
        status.stringValue = statusText; status.textColor = kind.color
    }
}
