import AppKit

extension NSMenuItem {
    /// Custom rows own their hover geometry. Do not also register native-item
    /// tooltips over a menu whose rows and section heights are custom views.
    var menuHelp: String? {
        get { (view as? MenuRowView)?.toolTip ?? toolTip }
        set {
            if let row = view as? MenuRowView {
                if toolTip != nil { toolTip = nil }
                if row.toolTip != newValue { row.toolTip = newValue }
            } else if toolTip != newValue { toolTip = newValue }
        }
    }
}

/// One renderer for every menu row. Semantic colors are resolved only inside the
/// view's drawing appearance; title updates never enter AppKit's attributed-title
/// cache. NSMenu still owns placement, type selection and outside-click dismissal.
final class MenuRowView: NSView {
    enum Kind { case toggle, command, information, section }
    enum PanelPart { case top, middle, bottom }
    var panelPart: PanelPart? { didSet { needsDisplay = true } }
    var panelSection: String? { didSet { if oldValue != panelSection { needsDisplay = true } } }
    weak var item: NSMenuItem?
    let kind: Kind
    var opensAnotherInterface: () -> Bool = { false }
    var hover = false { didSet { if hover != oldValue { needsDisplay = true } } }
    var keyboardHighlight = false { didSet { if keyboardHighlight != oldValue { needsDisplay = true } } }
    var text: NSAttributedString { didSet { if !oldValue.isEqual(to: text) { resizeForText(); needsDisplay = true } } }
    private(set) var preferredWidth: CGFloat = 430
    var holdsMenuWidth = false {
        didSet {
            if oldValue && !holdsMenuWidth && frame.width != preferredWidth {
                setFrameSize(NSSize(width: preferredWidth, height: frame.height))
            }
        }
    }
    // Display existing global shortcuts without registering a competing menu action.
    var shortcutHint = "" { didSet { if shortcutHint != oldValue { resizeForText(); needsDisplay = true } } }
    var displayedShortcut: String {
        if !shortcutHint.isEmpty { return shortcutHint }
        guard let item, !item.keyEquivalent.isEmpty else { return "" }
        var value = ""
        let flags: [(NSEvent.ModifierFlags, String)] = [(.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")]
        for (flag, symbol) in flags {
            if item.keyEquivalentModifierMask.contains(flag) { value += symbol }
        }
        return value + item.keyEquivalent.uppercased()
    }
    private let sectionSymbol: NSImage?
    private var commandPending = false
    private var hoverTrackingArea: NSTrackingArea?
    init(item: NSMenuItem, kind: Kind, text: NSAttributedString? = nil) {
        self.item = item; self.kind = kind
        let symbols = ["System":"gauge.with.dots.needle.50percent", "Sleep":"moon", "Display":"display", "Audio":"speaker.wave.2", "Scrolling":"computermouse", "Built-in keyboard":"keyboard", "External keyboards":"keyboard", "Agent Kill Switch":"shield", "Perch":"bird"]
        sectionSymbol = kind == .section ? NSImage(systemSymbolName: symbols[item.title] ?? (item.title.hasPrefix("External keyboard") ? "keyboard" : "circle"), accessibilityDescription: nil) : nil
        self.text = text ?? NSAttributedString(string: item.title, attributes: [
            .font: kind == .section ? NSFont.systemFont(ofSize: 11, weight: .semibold) : NSFont.menuFont(ofSize: 13),
            .foregroundColor: kind == .section ? NSColor.secondaryLabelColor : NSColor.labelColor])
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: kind == .section ? 22 : 24))
        autoresizingMask = .width
        // Preserve help when replacing a command renderer with a toggle renderer.
        toolTip = item.menuHelp
        item.toolTip = nil
        setAccessibilityElement(true)
        setAccessibilityRole(kind == .toggle ? .checkBox : kind == .command ? .button : .staticText)
        resizeForText()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var actionable: Bool { kind == .toggle || kind == .command }
    var enabled: Bool {
        guard actionable, let item, !item.isHidden, item.isEnabled else { return false }
        return (item.target as? NSMenuItemValidation)?.validateMenuItem(item) ?? true
    }
    var highlighted: Bool { enabled && (hover || keyboardHighlight) }
    private func resizeForText() {
        let shortcutWidth: CGFloat = displayedShortcut.isEmpty ? 0 : ceil((displayedShortcut as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 13)]).width) + 16
        let width = max(430, ceil(text.size().width) + (kind == .section ? 58 : 45) + shortcutWidth)
        // AppKit stretches every row to the menu's common width. That allocated
        // width is not the row's preferred width: do not repeatedly shrink it
        // back on refresh. While tracking, defer size changes until dismissal.
        guard preferredWidth != width else { return }
        preferredWidth = width
        if !holdsMenuWidth && frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
    }
    var textDrawingRect: NSRect {
        let x: CGFloat = kind == .section ? 44 : 25
        let shortcutWidth: CGFloat = displayedShortcut.isEmpty ? 0 : ceil((displayedShortcut as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 13)]).width) + 16
        return NSRect(x: x, y: 4, width: max(0, bounds.width - x - 14 - shortcutWidth), height: min(ceil(text.size().height), bounds.height - 4))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hover = false; keyboardHighlight = false
    }
    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = nil
        if actionable {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            hoverTrackingArea = area; addTrackingArea(area)
        }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        for sibling in item?.menu?.items ?? [] {
            (sibling.view as? MenuRowView)?.keyboardHighlight = false
            (sibling.view as? MenuRowView)?.hover = false
        }
        hover = true
    }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) { hover = bounds.contains(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { activate() } }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode) { activate() }
        else if event.keyCode == 53 { item?.menu?.cancelTracking() }
        else { super.keyDown(with: event) }
    }
    @discardableResult func activate() -> Bool {
        guard enabled, !commandPending, let item, let action = item.action else { return false }
        if kind == .command || opensAnotherInterface() {
            let target = item.target
            commandPending = true
            item.menu?.cancelTracking()
            // Open a settings/confirmation window only once tracking has ended.
            DispatchQueue.main.async { [self, item] in
                commandPending = false
                guard enabled, item.action == action, item.target === target else { return }
                NSApp.sendAction(action, to: target, from: item)
            }
        } else {
            NSApp.sendAction(action, to: item.target, from: item)
            needsDisplay = true
        }
        return true
    }
    override func accessibilityPerformPress() -> Bool { activate() }
    override func accessibilityLabel() -> String? { text.string }
    override func accessibilityHelp() -> String? {
        let detail = toolTip ?? ""
        return shortcutHint.isEmpty ? toolTip : detail + "\nConfigured shortcut: " + shortcutHint
    }
    override func isAccessibilityEnabled() -> Bool { !actionable || enabled }
    override func accessibilityValue() -> Any? {
        guard kind == .toggle else { return nil }
        return item?.state == .mixed ? 2 : item?.state == .on ? 1 : 0
    }
    /// Shared by drawing and the appearance regression tests. It keeps dynamic
    /// colors intact, including hints; selection and actual disabling are explicit.
    private var sectionTint: NSColor { Self.tint(for: item?.title ?? "") }
    static func tint(for section: String) -> NSColor {
        switch section {
        case "System": return .systemTeal
        case "Sleep": return .systemPurple
        case "Display": return .systemOrange
        case "Audio": return .systemYellow
        case "Scrolling": return .systemGreen
        case "Built-in keyboard": return .systemBlue
        case let title where title.hasPrefix("External keyboard"): return .systemIndigo
        case "Agent Kill Switch": return .systemRed
        case "Perch": return StatusColors.perchPink
        default: return .systemPurple
        }
    }
    func displayedText() -> NSAttributedString {
        if kind == .information {
            let result = NSMutableAttributedString(attributedString:text)
            let length = min((item?.title as NSString?)?.length ?? 0, result.length)
            result.addAttribute(.foregroundColor,value:NSColor.secondaryLabelColor,range:NSRange(location:0,length:length))
            return result
        }
        if kind == .section {
            let result = NSMutableAttributedString(attributedString:text)
            let tint = sectionTint.blended(withFraction:0.55,of:.labelColor) ?? NSColor.labelColor
            result.addAttribute(.foregroundColor,value:tint,range:NSRange(location:0,length:result.length))
            return result
        }
        guard (actionable && !enabled) || highlighted else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        result.addAttribute(.foregroundColor, value: highlighted ? NSColor.selectedMenuItemTextColor : NSColor.disabledControlTextColor, range: NSRange(location: 0, length: result.length))
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if kind == .section, let panelSection {
                // Keep the existing three-point gap; decorate only the title.
                let title = NSRect(x: 4, y: 0, width: bounds.width - 8, height: bounds.height - 3)
                let tint = Self.tint(for: panelSection)
                tint.withAlphaComponent(0.075).setFill()
                title.fill()
                (tint.blended(withFraction: 0.25, of: .labelColor) ?? tint).setFill()
                NSRect(x: title.minX, y: title.maxY - 2, width: title.width, height: 2).fill()
            }
            if highlighted {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
            }
            let color: NSColor = actionable && !enabled ? .disabledControlTextColor : highlighted ? .selectedMenuItemTextColor : .labelColor
            if kind == .toggle {
                let mark = item?.state == .on ? "✓" : item?.state == .mixed ? "−" : ""
                (mark as NSString).draw(at: NSPoint(x: 7, y: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
            }
            if let sectionSymbol {
                let tinted = sectionSymbol.copy() as! NSImage
                tinted.isTemplate = false
                tinted.lockFocus()
                let tint = sectionTint
                tint.setFill()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: 25, y: 5, width: 12, height: 12))
            }
            let title = NSMutableAttributedString(attributedString: displayedText())
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
            title.draw(in: textDrawingRect)
            if !displayedShortcut.isEmpty {
                let title = NSAttributedString(string: displayedShortcut, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: color])
                title.draw(at: NSPoint(x: bounds.width - title.size().width - 14, y: 4))
            }
        }
    }
}

extension AppDelegate {
    /// Neutral System readings first; highlighted titles with colored overlines.
    /// Re-evaluate visible boundaries when optional keyboard/protection rows change.
    func styleMenuSections() {
        var section = "System", rows: [MenuRowView] = []
        func finish() {
            for (index, row) in rows.enumerated() {
                let part: MenuRowView.PanelPart? = section == "System" ? nil : index == 0 ? .top : index == rows.count-1 ? .bottom : .middle
                if row.panelPart != part { row.panelPart = part }
                row.panelSection = section == "System" ? nil : section
                if row.kind == .section {
                    let height: CGFloat = section == "System" ? 22 : 25
                    if row.frame.height != height { row.setFrameSize(NSSize(width: row.frame.width, height: height)) }
                }
            }
            rows.removeAll()
        }
        for item in menu.items {
            guard let row = item.view as? MenuRowView else { continue }
            if row.kind == .section { finish(); section = item.title }
            if !item.isHidden { rows.append(row) }
        }
        finish()
    }
}


/// A single template image lets macOS provide menu-bar contrast in either theme.
func perchStatusImage(awake: Bool) -> NSImage? {
    guard let bird = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch") else { return nil }
    guard awake else { return bird }
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
        bird.draw(in: NSRect(x: 0, y: 2, width: 17, height: 16))
        if let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) {
            cup.draw(in: NSRect(x: 12, y: 0, width: 10, height: 8))
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Perch — keeping Mac awake"
    return image
}
