import AppKit
import IOKit.hidsystem

final class NavigationProbePage: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
    let session = NavigationProbeSession()
    let picker = NSPopUpButton(frame: NSRect(x: 8, y: 450, width: 352, height: 30), pullsDown: false)
    let registration = NSTextField(wrappingLabelWithString: "")
    let permission = NSTextField(labelWithString: "")
    let instruction = NSTextField(wrappingLabelWithString: "")
    let status = NSTextField(wrappingLabelWithString: "")
    let rows = NavigationKey.allCases.map { _ in NSTextField(labelWithString: "") }
    private(set) var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var keyboards: [NavigationProbeKeyboard] = []
    private var disconnected: [NavigationKeyboardIdentity] = []
    private let enumerate: () -> [NavigationProbeKeyboard]
    private let hasAccess: () -> Bool
    private let saveProfile: (NavigationKeyboardProfile) throws -> Void
    private let readProfiles: () throws -> [NavigationKeyboardProfile]
    private let resetProfiles: (NavigationKeyboardIdentity?) throws -> Void
    private var profiles: [NavigationKeyboardProfile] = []
    private var profileReadError: String?
    private var saveAttempted = false
    private var saveResult: String?
    private var saved = false
    var setupIdentity: NavigationKeyboardIdentity?
    private var recheck: SettingsActionButton!
    private var start: SettingsActionButton!
    private var skip: SettingsActionButton!
    private var cancel: SettingsActionButton!
    private var reset: SettingsActionButton!
    private var open: SettingsActionButton!
    private var drag: PermissionDragItem!
    private var accept: SettingsActionButton!

    init(enumerate: @escaping () -> [NavigationProbeKeyboard] = NavigationProbeKeyboard.connected,
         hasAccess: @escaping () -> Bool = { NavigationProbeHID.hasAccess },
         saveProfile: @escaping (NavigationKeyboardProfile) throws -> Void = { try KeyboardNavigationProfiles.save($0) },
         readProfiles: @escaping () throws -> [NavigationKeyboardProfile] = { try KeyboardNavigationProfiles.read() },
         resetProfiles: @escaping (NavigationKeyboardIdentity?) throws -> Void = { try KeyboardNavigationProfiles.reset($0) }) {
        self.enumerate = enumerate; self.hasAccess = hasAccess; self.saveProfile = saveProfile
        self.readProfiles = readProfiles; self.resetProfiles = resetProfiles
        super.init()
        view.addSubview(picker)
        picker.setAccessibilityLabel("External keyboard to set up")
        picker.target = self; picker.action = #selector(selectedKeyboard)
        recheck = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.reload() }
        recheck.frame = NSRect(x: 368, y: 450, width: 196, height: 30); view.addSubview(recheck)
        registration.frame = NSRect(x: 8, y: 407, width: 556, height: 38)
        registration.font = .systemFont(ofSize: 13, weight: .semibold); view.addSubview(registration)
        permission.frame = NSRect(x: 8, y: 378, width: 556, height: 24)
        permission.font = .systemFont(ofSize: 12); view.addSubview(permission)
        drag = PermissionDragItem(title: "Drag Perch → Input Monitoring") { Bundle.main.bundleURL }
        drag.frame = NSRect(x: 8, y: 327, width: 332, height: 42); view.addSubview(drag)
        open = SettingsActionButton(title: "Open Input Monitoring") {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
        open.frame = NSRect(x: 344, y: 333, width: 220, height: 30); view.addSubview(open)
        reset = SettingsActionButton(title: "Reset saved layout…") { [weak self] in self?.resetProfile() }
        reset.frame = NSRect(x: 8, y: 333, width: 230, height: 30); view.addSubview(reset)
        instruction.font = .systemFont(ofSize: 16, weight: .semibold); instruction.textColor = .labelColor
        instruction.frame = NSRect(x: 8, y: 265, width: 556, height: 54); view.addSubview(instruction)
        for (index, row) in rows.enumerated() {
            row.font = .systemFont(ofSize: 13)
            row.frame = NSRect(x: 16, y: 229 - CGFloat(index*34), width: 540, height: 28)
            view.addSubview(row)
        }
        status.font = .systemFont(ofSize: 13)
        status.frame = NSRect(x: 8, y: 48, width: 556, height: 72); view.addSubview(status)
        start = SettingsActionButton(title: "Start setup") { [weak self] in self?.begin() }
        start.frame = NSRect(x: 8, y: 5, width: 179, height: 32); view.addSubview(start)
        skip = SettingsActionButton(title: "No navigation keys") { [weak self] in
            guard let self else { return }
            if self.session.state.listening { self.session.skipCurrent() }
            else if let keyboard = self.selected, keyboard.identity.canRemember {
                self.setupIdentity = keyboard.identity; self.session.markAllAbsent(deviceID: keyboard.id)
            }
        }
        skip.frame = NSRect(x: 195, y: 5, width: 182, height: 32); view.addSubview(skip)
        cancel = SettingsActionButton(title: "Cancel setup") { [weak self] in
            guard let self else { return }
            if self.session.state.listening { self.session.stop("Setup cancelled. Your saved layout was kept.") }
        }
        cancel.frame = NSRect(x: 385, y: 5, width: 179, height: 32); view.addSubview(cancel)
        accept = SettingsActionButton(title: "Use this layout") { [weak self] in self?.acceptLayout() }
        accept.frame = skip.frame; accept.isHidden = true; view.addSubview(accept)
        session.changed = { [weak self] in self?.update() }
        reload()
    }
    func show() {
        let host = SettingsWindow.shared
        host.show(.init(title: "Set up navigation keys", detail: "Learn four keys, review the result, then choose Use this layout. Your previous layout stays saved until you accept the replacement. Saved disconnected keyboards can also be selected to forget their layout. Built-in Fn+arrows stay unchanged.", view: view, leave: { [self] in close() }))
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: host.window, queue: .main) { [weak self] _ in
            self?.session.stop("Setup stopped because you left this window. Your saved layout was kept.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: host.window, queue: .main) { [weak self] _ in self?.update() })
    }
    private func reload() {
        guard !session.state.listening else { return }
        let previousIdentity = selectedIdentity
        do { profiles = try readProfiles(); profileReadError = nil }
        catch { profiles = []; profileReadError = error.localizedDescription }
        keyboards = enumerate(); picker.removeAllItems()
        for keyboard in keyboards {
            picker.menu?.addItem(NSMenuItem(title: "\(keyboard.name) · \(keyboard.transport)", action: nil, keyEquivalent: ""))
            picker.lastItem?.toolTip = "Device identity: \(keyboard.id)"
        }
        disconnected = profiles.map(\.identity).filter { identity in !keyboards.contains { $0.identity == identity } }
        for identity in disconnected { picker.addItem(withTitle: "\(identity.name) · Saved, disconnected") }
        let identities = keyboards.map(\.identity) + disconnected
        if identities.isEmpty { picker.addItem(withTitle: "No connected or saved external keyboard") }
        picker.selectItem(at: identities.firstIndex(where: { $0 == previousIdentity }) ?? 0)
        if previousIdentity != selectedIdentity { session.reset(); setupIdentity = nil }
        update()
    }
    private var selected: NavigationProbeKeyboard? { keyboards.indices.contains(picker.indexOfSelectedItem) ? keyboards[picker.indexOfSelectedItem] : nil }
    private var selectedIdentity: NavigationKeyboardIdentity? {
        if let selected { return selected.identity }
        let index = picker.indexOfSelectedItem - keyboards.count
        return disconnected.indices.contains(index) ? disconnected[index] : nil
    }
    @objc private func selectedKeyboard() {
        guard !session.state.listening else { return }
        session.reset(); setupIdentity = nil; update()
    }
    private func begin() {
        guard SettingsWindow.shared.window.isKeyWindow, hasAccess(), let keyboard = selected,
              keyboard.identity.canRemember, !session.state.listening else { return }
        setupIdentity = keyboard.identity
        session.start(deviceID: keyboard.id, source: NavigationProbeHID(keyboard: keyboard, learning: true), guided: true)
    }
    private func resetProfile() {
        let alert = NSAlert()
        alert.messageText = "Reset saved navigation layout?"
        alert.informativeText = "Forget this keyboard’s learned layout, or all saved layouts. Its keys and all Fn/modifier settings keep working as before. Bundled profiles remain available."
        alert.addButton(withTitle: "Reset this keyboard"); alert.addButton(withTitle: "Reset all saved layouts"); alert.addButton(withTitle: "Cancel")
        let result = SettingsWindow.shared.run(alert)
        guard result == .alertFirstButtonReturn || result == .alertSecondButtonReturn else { return }
        do {
            guard result == .alertSecondButtonReturn || selectedIdentity != nil else { return }
            try resetProfiles(result == .alertSecondButtonReturn ? nil : selectedIdentity)
            session.reset(); setupIdentity = nil; reload()
        } catch { status.stringValue = "⚠ " + error.localizedDescription; status.textColor = StatusColors.warning }
    }
    private func tick() {
        if !hasAccess() { session.stop("Input Monitoring became unavailable. Setup stopped; your saved layout was kept.") }
        else { session.tick() }
    }
    private func acceptLayout() {
        if session.state.phase == .complete && !saved {
            saveAttempted = true
            if let identity = setupIdentity, let keys = session.state.learnedKeys {
                do {
                    let profile = NavigationKeyboardProfile(identity: identity, keys: keys)
                    try saveProfile(profile)
                    profiles.removeAll { $0.identity == identity }; profiles.append(profile)
                    saved = true; saveResult = "✓ Layout saved. Setup stopped. Perch will recognize this keyboard when it reconnects."
                } catch { saveResult = "⚠ " + error.localizedDescription }
            } else { saveResult = "⚠ Keyboard identity unavailable. The layout was not saved." }
        }
        update()
    }
    private func update() {
        let active = session.state.listening, access = hasAccess()
        if session.state.phase != .complete { saveAttempted = false; saveResult = nil; saved = false }
        let recognized = selectedIdentity.map { KeyboardRegistrationStatus.assess($0, saved: profiles) }
        let offline = selected == nil && selectedIdentity != nil
        registration.stringValue = profileReadError.map { "⚠ " + $0 } ?? recognized?.detail ?? "Connect an external keyboard, then recheck."
        registration.textColor = profileReadError == nil && recognized?.needsSetup == false ? StatusColors.success : StatusColors.warning
        permission.stringValue = offline ? "Saved keyboard · disconnected" : access ? "✓ Input Monitoring granted to Perch" : "⚠ Input Monitoring required to learn a layout"
        permission.textColor = offline ? .secondaryLabelColor : access ? StatusColors.success : StatusColors.warning
        drag.isHidden = access || profileReadError != nil || offline; open.isHidden = access || offline
        reset.isHidden = !access && profileReadError == nil && !offline
        reset.isEnabled = !active && (!profiles.isEmpty || profileReadError != nil)
        picker.isEnabled = !active && (!keyboards.isEmpty || !disconnected.isEmpty); recheck.isEnabled = !active
        start.isEnabled = !active && access && selected?.identity.canRemember == true && profileReadError == nil
        start.title = active ? "Setup in progress…" : session.state.phase == .idle ? "Start setup" : "Set up again"
        skip.title = active ? "This key is absent" : "No navigation keys"
        skip.isHidden = session.state.phase == .complete
        accept.isHidden = session.state.phase != .complete
        accept.isEnabled = !saved
        accept.title = saveAttempted && !saved ? "Retry saving layout" : "Use this layout"
        skip.isEnabled = active ? session.state.guided && !session.state.keys.contains { $0.held } : selected?.identity.canRemember == true && profileReadError == nil
        cancel.isHidden = !active
        for (index, key) in NavigationKey.allCases.enumerated() {
            let state = session.state.keys[index]
            rows[index].stringValue = state.absent ? "✓ \(key.name) — marked absent" : state.complete ? "✓ \(key.name) — identified" : state.held ? "\(key.name) — pressed; release it" : "\(key.name) — not identified yet"
            rows[index].textColor = state.complete ? StatusColors.success : state.held ? StatusColors.information : .secondaryLabelColor
        }
        switch session.state.phase {
        case .idle:
            instruction.stringValue = "Start setup to identify one key at a time."
            status.stringValue = selected == nil && selectedIdentity != nil ? "This keyboard is disconnected. You can forget its saved layout here; connect it to learn a replacement." : recognized?.needsSetup == false ? "This keyboard is recognized. Learn a replacement only if its navigation keys behave differently." : "Learn a layout if you want to change navigation behavior. Fn and modifier controls work independently. Mark any missing key with “This key is absent.”"
            status.textColor = .secondaryLabelColor
        case .listening:
            let key = session.state.currentKey?.name ?? "next key"
            instruction.stringValue = "Press and release \(key) on this keyboard."
            let remaining = max(0, Int(ceil(session.state.deadline - session.now())))
            status.stringValue = session.state.notice ?? "Keep this window focused · \(remaining) seconds left. Only function/navigation keys are observed. Letters and numbers are excluded."
            status.textColor = session.state.notice == nil ? StatusColors.information : StatusColors.warning
        case .complete:
            instruction.stringValue = saved ? "✓ Keyboard layout registered" : saveAttempted ? "The layout could not be saved" : "Review your keyboard layout"
            status.stringValue = saveResult ?? "Choose Use this layout to save these four results. Back or closing this window keeps your previous layout."
            status.textColor = saved ? StatusColors.success : saveAttempted ? StatusColors.warning : .secondaryLabelColor
        case .incomplete:
            instruction.stringValue = "Setup timed out"
            status.stringValue = "⚠ Setup ended before all four prompts were completed. Your saved layout was kept. Start again when ready."
            status.textColor = StatusColors.warning
        case .stopped(let reason):
            instruction.stringValue = "Setup stopped"
            status.stringValue = reason; status.textColor = StatusColors.warning
        }
        if active && timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.05; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        } else if !active { timer?.invalidate(); timer = nil }
    }
    func close() {
        session.stop("Setup stopped. Your saved layout was kept.")
        timer?.invalidate(); timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
    }
    deinit { close() }
}

extension AppDelegate {
    @objc func testNavigationKeys() { NavigationProbePage().show() }
}
