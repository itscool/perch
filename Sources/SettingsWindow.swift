import AppKit

/// All Perch settings pages share this window. OS authorization and file pickers are the only sheets.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    let window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let back = NSButton(title: "Back", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let detail = SettingsStatusField(wrappingLabelWithString: "")
    let detailHint = NSTextField(labelWithString: "Scroll to review the full message")
    let detailScroll = SettingsExplanationScroll(frame: NSRect(x: 24, y: 532, width: 572, height: 108))
    let container = NSView(frame: NSRect(x: 24, y: 24, width: 572, height: 490))
    let contentScroll = NSScrollView(frame: NSRect(x: 14, y: 24, width: 592, height: 490))
    let sidebar = SettingsSidebar(frame: .zero)
    var hasSidebar: Bool { !sidebar.destinations.isEmpty }
    private var sidebarWidth: CGFloat { hasSidebar ? 228 : 0 }
    struct Page {
        let title: String
        let detail: String
        let view: NSView
        var leave: (() -> Void)?
        var refresh: (() -> Void)?
        var backTitle: String? = nil
        var preferredBodyHeight: CGFloat = 490
        var beforeBack: (() -> Bool)? = nil
        var scrollFromTop: CGFloat = 0
        var focusIdentifier: NSUserInterfaceItemIdentifier? = nil
        weak var focusView: NSView? = nil
        var selection: NSRange? = nil
    }
    var pages: [Page] = []
    private(set) var announcedPage: String?
    var feedback: String?
    var testing = false
    var modalTestDriver: ((NSAlert) -> NSApplication.ModalResponse)?
    var pickerTestDriver: ((NSOpenPanel) -> NSApplication.ModalResponse)?
    var externalAppTestDriver: (() -> Bool)?
    private(set) var activeAlert: NSAlert?
    private var alertCompletion: ((NSApplication.ModalResponse) -> Void)?
    private var alertRefresh: Timer?
    private var drivingAlertFixture = false
    private var restoreSidebarAfterAlert = false
    private var activePicker: NSOpenPanel?
    private var needsPageDisplay = false
    private(set) var modalResponseRequested: NSApplication.ModalResponse?
    private(set) var modal = false { didSet { updateSidebar() } }
    private(set) var picking = false { didSet { updateSidebar() } }
    private(set) var externalHandoff = false { didSet { updateSidebar() } }
    var interactionBusy: Bool { authorizing || modal || picking || externalHandoff }
    private(set) var authorizing = false { didSet { updateSidebar() } }
    private var authorizationDepth = 0
    private var authorizationRestore: (() -> Void)?
    private var authorizationCompletions: [() -> Void] = []
    private var externalRestore: (() -> Void)?
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
        window.keyboardNavigationAllowed = { [weak self] in
            guard let self else { return false }
            return !self.authorizing && !self.picking && !self.externalHandoff
        }
        heading.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading")) // macOS 26 heading role; also builds with older SDK overlays.
        contentScroll.setAccessibilityLabel("Settings controls")
        detailScroll.setAccessibilityLabel("Page explanation")
        NotificationCenter.default.addObserver(self, selector: #selector(returnedToApp), name: NSApplication.didBecomeActiveNotification, object: nil)
        back.target = self; back.action = #selector(goBack); back.bezelStyle = .rounded
        back.keyEquivalent = "\u{1b}"
        back.frame = NSRect(x: 20, y: 653, width: 75, height: 28)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.frame = NSRect(x: 108, y: 652, width: 486, height: 30)
        detailScroll.focusRingType = .exterior
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
        sidebar.isHidden = true
        sidebar.choose = { [weak self] destination in self?.navigate(to: destination) }
        [sidebar,back,heading,detailScroll,detailHint,contentScroll].forEach { window.contentView?.addSubview($0) }
    }
    func configureNavigation(_ destinations: [SettingsDestination]) {
        sidebar.configure(destinations); sidebar.isHidden = destinations.isEmpty
        updateSidebar()
    }
    func updateSidebar() {
        let selected = pages.reversed().compactMap { page in
            sidebar.destinations.first(where: { $0.pageTitles.contains(page.title) })?.id
        }.first
        sidebar.update(selected: selected, busy: interactionBusy)
    }
    func navigate(to destination: SettingsDestination) {
        guard !interactionBusy else { updateSidebar(); return }
        if pages.count == 1, destination.pageTitles.contains(pages[0].title) { updateSidebar(); return }
        // A destination change must respect the same draft validation as Back.
        // Check before removing any pages so a refused exit retains its context.
        for page in pages.reversed() {
            guard page.beforeBack?() != false else { updateSidebar(); return }
        }
        if pages.contains(where: { $0.backTitle == "Cancel" }) {
            let alert = NSAlert()
            alert.messageText = "Discard this draft?"
            alert.informativeText = "Your saved setup will be kept. Discard the unfinished draft to open \(destination.title)."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard draft")
            present(alert) { [weak self] response in
                if response == .alertSecondButtonReturn { self?.openDestination(destination) }
                else { self?.updateSidebar() }
            }
            return
        }
        openDestination(destination)
    }
    private func openDestination(_ destination: SettingsDestination) {
        pages.reversed().forEach { $0.leave?() }; pages.removeAll()
        feedback = nil
        destination.open()
        updateSidebar()
        // Arrow navigation in the category list must remain in that list.
        window.makeFirstResponder(sidebar.table)
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
        if externalHandoff { returnedToApp() }
        if authorizationDepth == 0 {
            let level = window.level, floating = window.isFloatingPanel
            let visible = window.isVisible, key = window.isKeyWindow
            authorizing = true
            // Lowering a key floating panel is not a keyboard-focus handoff.
            // Withdraw it, retaining the page/draft, and do not queue activation
            // that could arrive after macOS has opened its password prompt.
            window.orderOut(nil); window.isFloatingPanel = false; window.level = .normal
            authorizationRestore = { [weak self] in
                guard let self else { return }
                self.window.isFloatingPanel = floating; self.window.level = level
                guard visible, !self.pages.isEmpty else { return }
                self.window.orderFront(nil)
                if key && NSApp.isActive && !self.testing { self.window.makeKey() }
            }
        }
        authorizationDepth += 1
        var finished = false
        return { [weak self] in
            guard let self, !finished else { return }; finished = true
            self.authorizationDepth -= 1
            guard self.authorizationDepth == 0 else { return }
            self.authorizing = false
            let restore = self.authorizationRestore; self.authorizationRestore = nil
            restore?()
            self.drainPresentationQueue()
        }
    }
    func afterAuthorization(_ action: @escaping () -> Void) {
        afterInteraction(action)
    }
    func afterInteraction(_ action: @escaping () -> Void) {
        if interactionBusy { authorizationCompletions.append(action) }
        else { action() }
    }
    private func drainPresentationQueue() {
        guard !interactionBusy else { return }
        if needsPageDisplay {
            needsPageDisplay = false
            if let page = pages.last { render(page) }
        }
        let pending = authorizationCompletions; authorizationCompletions.removeAll()
        for action in pending {
            DispatchQueue.main.async { [weak self] in self?.afterInteraction(action) }
        }
    }
    // Keep permission drag instructions visible, but below the destination app.
    // Completion is the user's return, not NSWorkspace accepting the open request.
    func handoffToExternalApp(_ open: @escaping () -> Bool) {
        guard !interactionBusy else { afterInteraction { [weak self] in self?.handoffToExternalApp(open) }; return }
        let level = window.level, floating = window.isFloatingPanel
        externalHandoff = true
        window.isFloatingPanel = false; window.level = .normal
        externalRestore = { [weak self] in self?.window.isFloatingPanel = floating; self?.window.level = level }
        let opened = testing ? externalAppTestDriver?() ?? false : open()
        if !opened { returnedToApp() }
    }
    @objc func returnedToApp() {
        guard externalHandoff else { return }
        externalHandoff = false
        let restore = externalRestore; externalRestore = nil; restore?()
        drainPresentationQueue()
    }
    func windowDidBecomeKey(_ notification: Notification) { returnedToApp() }
    func display(_ page: Page) {
        guard !interactionBusy else { needsPageDisplay = true; return }
        if pages.last?.view === page.view, page.view.isDescendant(of: container) {
            rememberScroll()
            render(pages.last!)
        } else { render(page) }
    }
    /// Only the owner of an active confirmation may replace its controls.
    private func render(_ page: Page) {
        window.title = page.title + " — Perch"
        heading.stringValue = page.title; detail.stringValue = feedback ?? page.detail
        let issue: ProtectionIssue? = nil
        detail.textColor = issue.map { $0.severity == .critical ? StatusColors.critical : StatusColors.warning } ?? (detail.stringValue.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor)
        detail.font = .systemFont(ofSize: 13, weight: issue == nil ? .regular : .semibold)
        let explanationHeight: CGFloat = min(200, max(48, ceil(detail.attributedStringValue.boundingRect(with: NSSize(width: 556, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8))
        let availableHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let stableHeight = min(760, max(460, availableHeight - 54))
        let bodyHeight = hasSidebar ? max(96, stableHeight-explanationHeight-114) : max(96, min(page.preferredBodyHeight, page.view.frame.height, availableHeight - explanationHeight - 174))
        let height = hasSidebar ? stableHeight : 72 + explanationHeight + 18 + bodyHeight + 24
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 620 + sidebarWidth, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top-window.frame.height))
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: height)
        back.frame.origin = NSPoint(x: sidebarWidth+20, y: height-47)
        heading.frame.origin = NSPoint(x: sidebarWidth+108, y: height-48)
        detailScroll.frame = NSRect(x: sidebarWidth+24, y: 24+bodyHeight+18, width: 572, height: explanationHeight)
        contentScroll.frame = NSRect(x: sidebarWidth+14, y: 24, width: 592, height: bodyHeight)
        contentScroll.autohidesScrollers = page.view.frame.height <= bodyHeight
        contentScroll.tile()
        layoutDetail()
        window.defaultButtonCell = nil
        if container.subviews.count != 1 || container.subviews.first !== page.view { container.subviews.forEach { $0.removeFromSuperview() } }
        container.frame = NSRect(x: 0, y: 0, width: contentScroll.contentSize.width, height: max(contentScroll.contentSize.height, page.view.frame.height))
        page.view.setFrameOrigin(NSPoint(x: max(0,(container.bounds.width-page.view.frame.width)/2), y: max(0,container.bounds.height-page.view.frame.height)))
        if page.view.superview !== container { container.addSubview(page.view) }
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, container.frame.height-contentScroll.contentSize.height-page.scrollFromTop)))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        func find(_ view: NSView, identifier: NSUserInterfaceItemIdentifier) -> NSView? {
            if view.identifier == identifier { return view }
            return view.subviews.lazy.compactMap { find($0, identifier: identifier) }.first
        }
        let retained = page.focusView.flatMap { $0.isDescendant(of: page.view) ? $0 : nil }
        let target = retained ?? page.focusIdentifier.flatMap { find(page.view, identifier: $0) }
        if let target, !target.isHiddenOrHasHiddenAncestor, (target as? NSControl)?.isEnabled != false {
            window.makeFirstResponder(target)
            if let selection = page.selection, let editor = (target as? NSTextField)?.currentEditor() as? NSTextView,
               NSMaxRange(selection) <= (editor.string as NSString).length { editor.setSelectedRange(selection) }
        } else if let focused = window.firstResponder as? NSView,
                  focused !== back, focused !== sidebar.table, !focused.isDescendant(of: page.view) { window.makeFirstResponder(back) }
        if window.firstResponder === window || window.firstResponder == nil { window.makeFirstResponder(back) }
        window.recalculateKeyViewLoop()
        back.title = page.backTitle ?? (pages.count > 1 ? "Back" : "Close")
        updateSidebar()
        if !testing && !interactionBusy && !window.isVisible { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        notifyAccessibilityPage()
    }
    func notifyAccessibilityPage() {
        let title = heading.stringValue
        guard announcedPage != title else { return }
        if !testing {
            guard window.isVisible, window.isKeyWindow else { return }
            NSAccessibility.post(element: window, notification: .layoutChanged, userInfo: [.uiElements: [heading, container]])
            SettingsAccessibility.announce(title + ". " + detail.stringValue)
        }
        announcedPage = title
    }
    func rememberScroll() {
        guard let page = pages.last, page.view.isDescendant(of: container), !modal else { return }
        let focused = (window.firstResponder as? NSTextView)?.delegate as? NSView ?? window.firstResponder as? NSView
        if let focused, focused.isDescendant(of: page.view) {
            pages[pages.count-1].focusIdentifier = focused.identifier
            pages[pages.count-1].focusView = focused
            pages[pages.count-1].selection = (window.firstResponder as? NSTextView)?.selectedRange()
        }
        pages[pages.count-1].scrollFromTop = max(0, container.frame.height-contentScroll.contentSize.height-contentScroll.contentView.bounds.minY)
    }
    func show(_ proposed: Page) {
        var page = proposed
        guard !interactionBusy else { afterInteraction { [weak self] in self?.show(page) }; return }
        rememberScroll()
        if let previous = pages.last, previous.title == page.title { page.scrollFromTop = previous.scrollFromTop; page.focusIdentifier = previous.focusIdentifier; page.focusView = previous.focusView; page.selection = previous.selection }
        feedback = nil
        if page.title == "Perch settings" {
            pages.reversed().forEach { $0.leave?() }
            pages.removeAll()
        }
        if pages.last?.title == page.title { let previous = pages.removeLast(); if previous.view !== page.view { previous.leave?() } }
        pages.append(page); display(page)
    }
    @objc func goBack() {
        guard !picking, !authorizing else { return }
        if modal { if modalAllowsCancel, let activeAlert { finish(activeAlert, response: cancelCode) }; return }
        guard pages.last?.beforeBack?() != false else { return }
        guard pages.count > 1 else { window.close(); return }
        pages.removeLast().leave?()
        if let page = pages.last { display(page); page.refresh?() }
    }
    @discardableResult
    func returnToPage(at index: Int) -> Bool {
        guard !interactionBusy, pages.indices.contains(index) else { return false }
        while pages.count > index + 1 {
            let count = pages.count
            goBack()
            // A draft may refuse Back. Preserve its error instead of spinning
            // on the main thread or silently discarding the user's edits.
            guard pages.count < count else { return false }
        }
        return true
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
            button.identifier = .init("settings.action." + NSStringFromSelector(option.2))
            button.toolTip = option.1
            button.setAccessibilityHelp(option.1)
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
    /// Synchronous response adapter for existing isolated fixtures only. Product
    /// dialogs use present and return to the ordinary application event loop.
    @discardableResult
    func run(_ alert: NSAlert, allowsCancel: Bool = true) -> NSApplication.ModalResponse {
        guard testing, modalTestDriver != nil else { return .abort }
        var response = NSApplication.ModalResponse.abort
        present(alert, allowsCancel: allowsCancel) { response = $0 }
        return response
    }
    func present(_ alert: NSAlert, allowsCancel: Bool = true,
                 completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        guard !interactionBusy else { completion(.abort); return }
        restoreSidebarAfterAlert = hasSidebar && window.firstResponder === sidebar.table
        rememberScroll()
        modal = true; activeAlert = alert; modalResponseRequested = nil
        alertCompletion = completion; modalAllowsCancel = allowsCancel
        alert.layout()
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
        if let accessory = alert.accessoryView {
            accessory.removeFromSuperview()
            accessory.setFrameOrigin(NSPoint(x: max(0,(572-accessory.frame.width)/2),y: 490-accessory.frame.height))
            view.addSubview(accessory)
        }
        let navigationTitles = ["Cancel", "Back", "Close"]
        let exitIndex = alert.buttons.firstIndex { navigationTitles.contains($0.title) || (alert.buttons.count == 1 && $0.title == "OK") }
        cancelCode = exitIndex.map { NSApplication.ModalResponse(rawValue: 1000 + $0) } ?? .abort
        var buttonX: CGFloat = 572, buttonY: CGFloat = 0
        for (index, original) in alert.buttons.enumerated() {
            if allowsCancel && index == exitIndex { continue }
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
        render(Page(title: alert.messageText, detail: alert.informativeText, view: view))
        back.title = pages.isEmpty ? "Close" : "Back"
        back.isEnabled = allowsCancel
        window.defaultButtonCell = view.subviews.compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\r" }?.cell as? NSButtonCell
        if testing, let driver = modalTestDriver {
            drivingAlertFixture = true
            let result = driver(alert)
            drivingAlertFixture = false
            completeAlert(alert, response: modalResponseRequested ?? result)
            return
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self, weak alert] _ in
            guard let self, let alert, self.activeAlert === alert else { return }
            self.heading.stringValue = alert.messageText
            self.window.title = alert.messageText + " — Perch"
            if self.detail.stringValue != alert.informativeText { self.detail.stringValue = alert.informativeText; self.layoutDetail(); if self.window.isKeyWindow && !self.testing { NSAccessibility.post(element: self.detail, notification: .valueChanged) } }
            self.notifyAccessibilityPage()
        }
        alertRefresh = timer
        RunLoop.main.add(timer, forMode: .common)
        if !testing {
            if !window.isVisible { window.center() }
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            notifyAccessibilityPage()
        }
    }
    @discardableResult
    func finish(_ alert: NSAlert, response: NSApplication.ModalResponse = .stop) -> Bool {
        guard modal, activeAlert === alert, !picking, !authorizing, modalResponseRequested == nil else { return false }
        // These are ordinary shared-window pages, never native modal loops.
        guard testing || NSApp.modalWindow == nil else { return false }
        modalResponseRequested = response
        if drivingAlertFixture { return true }
        if testing { completeAlert(alert, response: response) }
        else {
            // Let the initiating button action unwind before displaying a result
            // or cleanup page in the same window.
            DispatchQueue.main.async { [weak self] in self?.completeAlert(alert, response: response) }
        }
        return true
    }
    private func completeAlert(_ alert: NSAlert, response: NSApplication.ModalResponse) {
        guard activeAlert === alert else { return }
        alertRefresh?.invalidate(); alertRefresh = nil
        let completion = alertCompletion; alertCompletion = nil
        let restoreSidebar = restoreSidebarAfterAlert; restoreSidebarAfterAlert = false
        activeAlert = nil; modalResponseRequested = nil
        back.isEnabled = true; modalAllowsCancel = true
        // Restore before releasing presentation ownership. The completion may
        // immediately present the next step without a queued refresh replacing it.
        if let page = pages.last { render(page) }
        else { window.defaultButtonCell = nil; window.orderOut(nil) }
        modal = false
        if restoreSidebar && hasSidebar { window.makeFirstResponder(sidebar.table) }
        completion?(response)
        drainPresentationQueue()
    }
    @objc func modalChoice(_ sender: NSButton) {
        guard sender.window === window, sender.isEnabled,
              sender.isDescendant(of: container), let activeAlert else { return }
        finish(activeAlert, response: NSApplication.ModalResponse(rawValue: sender.tag))
    }
    func open(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
        guard !interactionBusy else { return .cancel }
        picking = true; activePicker = panel
        let previousBack = back.isEnabled; back.isEnabled = false
        defer { back.isEnabled = previousBack; activePicker = nil; picking = false; drainPresentationQueue() }
        if testing { return pickerTestDriver?(panel) ?? .cancel }
        guard window.isVisible else { return panel.runModal() }
        var result = NSApplication.ModalResponse.cancel
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self, let panel, self.activePicker === panel else { return }
            result = response
            if NSApp.modalWindow === self.window { NSApp.stopModal() }
        }
        NSApp.runModal(for: window)
        return result
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !picking, !authorizing else { return false }
        if modal { if modalAllowsCancel, let activeAlert { finish(activeAlert, response: cancelCode) }; return false }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        pages.reversed().forEach { $0.leave?() }; pages.removeAll()
        announcedPage = nil
        needsPageDisplay = false
        // Closing the parent while working in Settings/Finder ends that handoff.
        // Otherwise a later menu action can remain queued with no window to return to.
        returnedToApp()
    }
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

final class SettingsActionPopup: NSPopUpButton {
    var callback: (() -> Void)?
    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        target = self; action = #selector(changed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changed() { callback?() }
}
