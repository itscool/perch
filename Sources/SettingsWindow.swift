import AppKit

/// All Perch settings pages share this window. OS authorization and file pickers are the only sheets.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let back = NSButton(title: "Back", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let container = NSView(frame: NSRect(x: 24, y: 24, width: 572, height: 490))
    struct Page {
        let title: String
        let detail: String
        let view: NSView
        var leave: (() -> Void)?
        var refresh: (() -> Void)?
    }
    var pages: [Page] = []
    var feedback: String?
    var testing = false
    var modalTestDriver: ((NSAlert) -> NSApplication.ModalResponse)?
    var modal = false
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
        detail.frame = NSRect(x: 24, y: 540, width: 572, height: 100)
        detail.textColor = .secondaryLabelColor
        [back,heading,detail,container].forEach { window.contentView?.addSubview($0) }
    }
    func display(_ page: Page) {
        heading.stringValue = page.title; detail.stringValue = feedback ?? page.detail
        let issue = page.title == "Perch settings" ? ProtectionIssue.assess(GuardianInstall.status, config: SafetyConfiguration.load()) : nil
        detail.textColor = issue.map { $0.severity == .critical ? StatusColors.critical : StatusColors.warning } ?? (detail.stringValue.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor)
        detail.font = .systemFont(ofSize: 13, weight: issue == nil ? .regular : .semibold)
        container.subviews.forEach { $0.removeFromSuperview() }
        page.view.setFrameOrigin(NSPoint(x: max(0,(container.bounds.width-page.view.frame.width)/2), y: max(0,container.bounds.height-page.view.frame.height)))
        container.addSubview(page.view)
        back.title = pages.count > 1 ? "Back" : "Close"
        if !testing && !window.isVisible { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func show(_ page: Page) {
        feedback = nil
        if pages.last?.title == page.title { let previous = pages.removeLast(); if previous.view !== page.view { previous.leave?() } }
        pages.append(page); display(page)
    }
    @objc func goBack() {
        if modal { NSApp.stopModal(withCode: cancelCode); return }
        guard pages.count > 1 else { window.close(); return }
        pages.removeLast().leave?()
        if let page = pages.last { display(page); page.refresh?() }
    }
    func list(title: String, detail: String, options: [(String,String,Selector)], delegate: AppDelegate) {
        let isRoot = title == "Perch settings"
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: CGFloat(options.count*68 + (isRoot ? 68 : 0))))
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
        if isRoot {
            let box = NSButton(checkboxWithTitle: "Show top process and Perch CPU usage", target: delegate, action: #selector(AppDelegate.toggleProcessCPU(_:)))
            box.state = CPUDisplaySettings.enabled() ? .on : .off
            box.frame = NSRect(x: 8, y: 36, width: 556, height: 28)
            box.identifier = NSUserInterfaceItemIdentifier(CPUDisplaySettings.key)
            let explanation = NSTextField(wrappingLabelWithString: "Updates every 10 seconds while the menu is open. Includes Perch’s helpers and eslogger. Percentages use total CPU capacity.")
            explanation.font = .systemFont(ofSize: 12); explanation.textColor = .secondaryLabelColor
            explanation.frame = NSRect(x: 8, y: 0, width: 556, height: 32)
            view.addSubview(box); view.addSubview(explanation)
        }
        let selector: Selector? = title == "Perch settings" ? #selector(AppDelegate.configureSettings) : title == "Agent Kill Switch" ? #selector(AppDelegate.configurePanic) : title == "Advanced settings" ? #selector(AppDelegate.advancedSafetySettings) : nil
        show(Page(title: title, detail: detail, view: view, refresh: { [weak delegate] in if let selector { _ = delegate?.perform(selector) } }))
    }
    @discardableResult
    func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        guard window.isVisible || (testing && modalTestDriver != nil) else { return alert.runModal() }
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
        if let accessory = alert.accessoryView {
            accessory.removeFromSuperview()
            accessory.setFrameOrigin(NSPoint(x: max(0,(572-accessory.frame.width)/2),y: 490-accessory.frame.height))
            view.addSubview(accessory)
        }
        for (index, original) in alert.buttons.enumerated() {
            let button = NSButton(title: original.title,target: self,action: #selector(modalChoice(_:)))
            button.bezelStyle = .rounded; button.tag = 1000+index
            button.frame = NSRect(x: 572-CGFloat(index+1)*190,y: 0,width: 180,height: 32)
            view.addSubview(button)
        }
        cancelCode = NSApplication.ModalResponse(rawValue: 1000 + (alert.buttons.firstIndex(where: { $0.title == "Cancel" }) ?? max(0,alert.buttons.count-1)))
        display(Page(title: alert.messageText, detail: alert.informativeText, view: view))
        if testing, let driver = modalTestDriver {
            let result = driver(alert)
            if let page = pages.last { display(page) }
            return result
        }
        let timer = Timer(timeInterval: 0.1,repeats: true) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            self.heading.stringValue = alert.messageText; self.detail.stringValue = alert.informativeText
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
        if modal { NSApp.stopModal(withCode: cancelCode); return false }
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
