import AppKit

/// All Perch settings pages share this window. OS authorization and file pickers are the only sheets.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let back = NSButton(title: "Back", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let detailHint = NSTextField(labelWithString: "Scroll to review the full message")
    let detailScroll = NSScrollView(frame: NSRect(x: 24, y: 532, width: 572, height: 108))
    let container = NSView(frame: NSRect(x: 24, y: 24, width: 572, height: 490))
    let contentScroll = NSScrollView(frame: NSRect(x: 14, y: 24, width: 592, height: 490))
    struct Page {
        let title: String
        let detail: String
        let view: NSView
        var leave: (() -> Void)?
        var refresh: (() -> Void)?
        var backTitle: String? = nil
        var preferredBodyHeight: CGFloat = 490
    }
    var pages: [Page] = []
    var feedback: String?
    var testing = false
    var modalTestDriver: ((NSAlert) -> NSApplication.ModalResponse)?
    var modal = false
    var authorizing = false
    private var modalAllowsCancel = true
    var cancelCode = NSApplication.ModalResponse.abort
    override init() {
        super.init()
        window.title = "Perch Settings"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        back.target = self; back.action = #selector(goBack); back.bezelStyle = .rounded
        back.frame = NSRect(x: 20, y: 653, width: 75, height: 28)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.frame = NSRect(x: 108, y: 652, width: 486, height: 30)
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.scrollerStyle = .legacy
        detailScroll.drawsBackground = false
        detailScroll.documentView = detail
        detail.textColor = .secondaryLabelColor
        detailHint.font = .systemFont(ofSize: 11); detailHint.textColor = .secondaryLabelColor
        detailHint.isHidden = true
        contentScroll.hasVerticalScroller = true; contentScroll.autohidesScrollers = true
        contentScroll.scrollerStyle = .legacy
        contentScroll.drawsBackground = false; contentScroll.documentView = container
        [back,heading,detailScroll,detailHint,contentScroll].forEach { window.contentView?.addSubview($0) }
    }
    func layoutDetail() {
        let width: CGFloat = 556
        let height = ceil(detail.attributedStringValue.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
        let overflow = height > detailScroll.frame.height
        detailScroll.autohidesScrollers = !overflow
        detailScroll.borderType = overflow ? .lineBorder : .noBorder
        detailHint.isHidden = !overflow
        detailHint.frame = NSRect(x: detailScroll.frame.minX + 2, y: detailScroll.frame.minY - 17, width: 556, height: 16)
        detail.frame = NSRect(x: 0, y: 0, width: width, height: max(detailScroll.contentSize.height, height))
        detailScroll.tile()
        detailScroll.contentView.scroll(to: .zero) // NSTextField uses a flipped document coordinate system.
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
    }
    func beginAuthorization() -> () -> Void {
        let previousLevel = window.level, previousState = authorizing
        // Let the system prompt take focus and suppress any delayed setup notice.
        window.level = .normal; authorizing = true
        if !testing { NSApp.activate(ignoringOtherApps: true) }
        return { [weak self] in self?.authorizing = previousState; self?.window.level = previousLevel }
    }
    func display(_ page: Page) {
        heading.stringValue = page.title; detail.stringValue = feedback ?? page.detail
        let issue: ProtectionIssue? = nil
        detail.textColor = issue.map { $0.severity == .critical ? StatusColors.critical : StatusColors.warning } ?? (detail.stringValue.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor)
        detail.font = .systemFont(ofSize: 13, weight: issue == nil ? .regular : .semibold)
        let explanationHeight: CGFloat = min(200, max(48, ceil(detail.attributedStringValue.boundingRect(with: NSSize(width: 556, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8))
        let availableHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let bodyHeight = max(96, min(page.preferredBodyHeight, page.view.frame.height, availableHeight - explanationHeight - 174))
        let height = 72 + explanationHeight + 18 + bodyHeight + 24
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 620, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top-window.frame.height))
        back.frame.origin.y = height-47; heading.frame.origin.y = height-48
        detailScroll.frame = NSRect(x: 24, y: 24+bodyHeight+18, width: 572, height: explanationHeight)
        contentScroll.frame = NSRect(x: 14, y: 24, width: 592, height: bodyHeight)
        contentScroll.autohidesScrollers = page.view.frame.height <= bodyHeight
        contentScroll.tile()
        layoutDetail()
        window.defaultButtonCell = nil
        container.subviews.forEach { $0.removeFromSuperview() }
        container.frame = NSRect(x: 0, y: 0, width: contentScroll.contentSize.width, height: max(contentScroll.contentSize.height, page.view.frame.height))
        page.view.setFrameOrigin(NSPoint(x: max(0,(container.bounds.width-page.view.frame.width)/2), y: max(0,container.bounds.height-page.view.frame.height)))
        container.addSubview(page.view)
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, container.frame.height-contentScroll.contentSize.height)))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        back.title = page.backTitle ?? (pages.count > 1 ? "Back" : "Close")
        if !testing && !authorizing && !window.isVisible { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func show(_ page: Page) {
        feedback = nil
        if page.title == "Perch settings" {
            pages.reversed().forEach { $0.leave?() }
            pages.removeAll()
        }
        if pages.last?.title == page.title { let previous = pages.removeLast(); if previous.view !== page.view { previous.leave?() } }
        pages.append(page); display(page)
    }
    @objc func goBack() {
        if modal { if modalAllowsCancel { NSApp.stopModal(withCode: cancelCode) }; return }
        guard pages.count > 1 else { window.close(); return }
        pages.removeLast().leave?()
        if let page = pages.last { display(page); page.refresh?() }
    }
    func list(title: String, detail: String, options: [(String,String,Selector)], delegate: AppDelegate) {
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: CGFloat(options.count*68)))
        // Each button retains its own action; parent pages remain usable after navigating back.
        for (index, option) in options.enumerated() {
            let y = view.frame.height - CGFloat((index+1)*68)
            let button = SettingsActionButton(title: option.0) { [weak self, weak delegate] in
                guard let self, let delegate else { return }
                _ = delegate.perform(option.2)
                if let current = self.pages.last { self.display(current) }
            }
            if option.0.hasPrefix("⛔") || option.0.hasPrefix("⚠") || option.0.hasPrefix("✓") {
                button.attributedTitle = NSAttributedString(string: option.0, attributes: [.foregroundColor: option.0.hasPrefix("⛔") ? StatusColors.critical : (option.0.hasPrefix("✓") ? StatusColors.success : StatusColors.warning), .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
            }
            button.frame = NSRect(x: 0,y: y+35,width: 572,height: 30)
            let label = NSTextField(wrappingLabelWithString: option.1)
            label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 8,y: y,width: 556,height: 32)
            view.addSubview(button); view.addSubview(label)
        }
        let selector: Selector? = title == "Perch settings" ? #selector(AppDelegate.configureSettings) : title == "Agent Kill Switch" ? #selector(AppDelegate.configurePanic) : title == "Maintenance" ? #selector(AppDelegate.advancedSafetySettings) : nil
        show(Page(title: title, detail: detail, view: view, refresh: { [weak delegate] in if let selector { _ = delegate?.perform(selector) } }))
    }
    @discardableResult
    func run(_ alert: NSAlert, allowsCancel: Bool = true) -> NSApplication.ModalResponse {
        alert.layout()
        guard window.isVisible || (testing && modalTestDriver != nil) else { return alert.runModal() }
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
        if let accessory = alert.accessoryView {
            accessory.removeFromSuperview()
            accessory.setFrameOrigin(NSPoint(x: max(0,(572-accessory.frame.width)/2),y: 490-accessory.frame.height))
            view.addSubview(accessory)
        }
        var buttonX: CGFloat = 572, buttonY: CGFloat = 0
        for (index, original) in alert.buttons.enumerated() {
            let button = NSButton(title: original.title,target: self,action: #selector(modalChoice(_:)))
            button.bezelStyle = .rounded; button.tag = 1000+index
            button.keyEquivalent = original.keyEquivalent
            button.keyEquivalentModifierMask = original.keyEquivalentModifierMask
            button.isEnabled = original.isEnabled
            let width = min(572, max(110, ceil((original.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width) + 36))
            if buttonX < width { buttonX = 572; buttonY += 42 }
            buttonX -= width
            button.frame = NSRect(x: buttonX,y: buttonY,width: width,height: 32)
            buttonX -= 10
            view.addSubview(button)
        }
        let accessoryHeight = alert.accessoryView?.frame.height ?? 0
        let contentHeight = max(96, accessoryHeight + buttonY + 50)
        view.setFrameSize(NSSize(width: 572, height: contentHeight))
        if let accessory = alert.accessoryView { accessory.frame.origin.y = contentHeight-accessoryHeight }
        cancelCode = NSApplication.ModalResponse(rawValue: 1000 + (alert.buttons.firstIndex(where: { $0.title == "Cancel" }) ?? max(0,alert.buttons.count-1)))
        display(Page(title: alert.messageText, detail: alert.informativeText, view: view))
        back.isEnabled = allowsCancel
        let oldAllowsCancel = modalAllowsCancel
        modalAllowsCancel = allowsCancel
        defer { back.isEnabled = true; modalAllowsCancel = oldAllowsCancel }
        window.defaultButtonCell = view.subviews.compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\r" }?.cell as? NSButtonCell
        if testing, let driver = modalTestDriver {
            let result = driver(alert)
            if let page = pages.last { display(page) }
            return result
        }
        let timer = Timer(timeInterval: 0.1,repeats: true) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            self.heading.stringValue = alert.messageText
            if self.detail.stringValue != alert.informativeText { self.detail.stringValue = alert.informativeText; self.layoutDetail() }
        }
        RunLoop.main.add(timer,forMode: .modalPanel)
        modal = true
        let result = NSApp.runModal(for: window)
        modal = false; timer.invalidate()
        if let page = pages.last { display(page) }
        return result
    }
    @objc func modalChoice(_ sender: NSButton) { NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: sender.tag)) }
    func open(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
        guard window.isVisible else { return panel.runModal() }
        var result = NSApplication.ModalResponse.cancel
        panel.beginSheetModal(for: window) { response in result = response; NSApp.stopModal() }
        NSApp.runModal(for: window)
        return result
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if modal { if modalAllowsCancel { NSApp.stopModal(withCode: cancelCode) }; return false }
        return true
    }
    func windowWillClose(_ notification: Notification) { pages.reversed().forEach { $0.leave?() }; pages.removeAll() }
}

final class SettingsActionButton: NSButton {
    let callback: () -> Void
    init(title: String, action: @escaping () -> Void) {
        callback = action
        super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; target = self; self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func invoke() { callback() }
}
