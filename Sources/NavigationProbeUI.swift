import AppKit
import IOKit.hidsystem

final class NavigationProbePage: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
    let session: NavigationProbeSession
    let picker = NSPopUpButton(frame: NSRect(x: 8, y: 450, width: 352, height: 30), pullsDown: false)
    let registration = SettingsStatusField(wrappingLabelWithString: "")
    let permission = NSTextField(labelWithString: "")
    let instruction = SettingsStatusField(wrappingLabelWithString: "")
    let status = SettingsStatusField(wrappingLabelWithString: "")
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
    private var reset: SettingsActionButton!
    private var open: SettingsActionButton!
    private var drag: PermissionDragItem!
    private var retrySave: SettingsActionButton!
    private var launchRecovery: SettingsActionButton!

    init(enumerate: @escaping () -> [NavigationProbeKeyboard] = NavigationProbeKeyboard.connected,
         hasAccess: @escaping () -> Bool = { NavigationProbeHID.hasAccess },
         saveProfile: @escaping (NavigationKeyboardProfile) throws -> Void = { try KeyboardNavigationProfiles.save($0) },
         readProfiles: @escaping () throws -> [NavigationKeyboardProfile] = { try KeyboardNavigationProfiles.read() },
         resetProfiles: @escaping (NavigationKeyboardIdentity?) throws -> Void = { try KeyboardNavigationProfiles.reset($0) },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        session = NavigationProbeSession(now: now)
        self.enumerate = enumerate; self.hasAccess = hasAccess; self.saveProfile = saveProfile
        self.readProfiles = readProfiles; self.resetProfiles = resetProfiles
        super.init()
        picker.identifier = .init("navigation.keyboard"); picker.setAccessibilityLabel("Keyboard to learn or manage")
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
            SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
        }
        open.frame = NSRect(x: 344, y: 333, width: 220, height: 30); view.addSubview(open)
        launchRecovery = SettingsActionButton(title: "Already enabled? Review keyboard access…") {
            (NSApp.delegate as? AppDelegate)?.keyboardAccessRecovery()
        }
        launchRecovery.frame = NSRect(x: 195, y: 5, width: 369, height: 32); view.addSubview(launchRecovery)
        reset = SettingsActionButton(title: "Reset saved layout…") { [weak self] in self?.resetProfile() }
        reset.frame = NSRect(x: 8, y: 333, width: 230, height: 30); view.addSubview(reset)
        instruction.announcesChanges = true
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
        skip = SettingsActionButton(title: "I don’t have this key") { [weak self] in
            self?.session.skipCurrent()
        }
        skip.frame = NSRect(x: 8, y: 5, width: 240, height: 32); view.addSubview(skip)
        retrySave = SettingsActionButton(title: "Retry saving") { [weak self] in
            guard let self else { return }
            self.saveCompletedLayout(); self.update()
        }
        retrySave.frame = start.frame; retrySave.isHidden = true; view.addSubview(retrySave)
        session.changed = { [weak self] in self?.update() }
        reload()
    }
    private var pageDetail: String {
        if session.state.phase == .complete {
            let name = setupIdentity?.name ?? "this keyboard"
            return saved ? "The layout for \(name) is saved. Choose another settings category, or return to setup."
                : "Setup for \(name) finished, but the layout was not saved. Your previous layout is still in use."
        }
        if !hasAccess() { return LaunchAccessRecovery.summary + " Use the access recovery below before learning a layout. Your saved layout is kept." }
        return "Press and release each requested key, or mark it absent. The layout saves automatically after the last key. Leaving this page stops unfinished setup and keeps your previous layout."
    }
    func show() {
        let host = SettingsWindow.shared
        host.show(.init(title: "Set up navigation keys", detail: pageDetail, view: view, leave: { [self] in close() }))
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
        let identity = selectedIdentity
        SettingsWindow.shared.present(alert) { [self] result in
            guard result == .alertFirstButtonReturn || result == .alertSecondButtonReturn else { return }
            do {
                guard result == .alertSecondButtonReturn || identity != nil else { return }
                try resetProfiles(result == .alertSecondButtonReturn ? nil : identity)
                session.reset(); setupIdentity = nil; reload()
            } catch { status.stringValue = "⚠ " + error.localizedDescription; status.textColor = StatusColors.warning }
        }
    }
    private func tick() {
        if !hasAccess() { session.stop("Input Monitoring became unavailable. Setup stopped; your saved layout was kept.") }
        else { session.tick() }
    }
    private func saveCompletedLayout() {
        if session.state.phase == .complete && !saved {
            // Mark the attempt before saving: preference notifications or later
            // UI refreshes must not write the same completed session again.
            saveAttempted = true
            if let identity = setupIdentity, let keys = session.state.learnedKeys {
                do {
                    let profile = NavigationKeyboardProfile(identity: identity, keys: keys)
                    try saveProfile(profile)
                    profiles.removeAll { $0.identity == identity }; profiles.append(profile)
                    saved = true; saveResult = "✓ Layout saved automatically. Choose another settings category, or return to setup."
                } catch { saveResult = "⚠ " + error.localizedDescription + " Your previous layout is still in use. Retry saving, or use Back to leave." }
            } else { saveResult = "⚠ Keyboard identity unavailable. Nothing was saved. Use Back, then recheck keyboards." }
        }
    }
    private func update() {
        let active = session.state.listening, access = hasAccess()
        if session.state.phase != .complete { saveAttempted = false; saveResult = nil; saved = false }
        else if !saveAttempted { saveCompletedLayout() }
        let complete = session.state.phase == .complete
        let recognized = selectedIdentity.map { KeyboardRegistrationStatus.assess($0, saved: profiles) }
        let offline = selected == nil && selectedIdentity != nil
        registration.stringValue = profileReadError.map { "⚠ " + $0 } ?? recognized?.detail ?? "Connect an external keyboard, then recheck."
        registration.textColor = profileReadError == nil && recognized?.needsSetup == false ? StatusColors.success : StatusColors.warning
        let ready = recognized?.needsSetup == false
        permission.stringValue = offline ? "Saved keyboard · disconnected" : access ? "✓ Input Monitoring granted to Perch" : ready ? "Input Monitoring is only needed to learn a different layout." : "⚠ Input Monitoring required to learn a layout"
        permission.textColor = offline || (ready && !access) ? .secondaryLabelColor : access ? StatusColors.success : StatusColors.warning
        permission.isHidden = complete
        drag.isHidden = complete || access || profileReadError != nil || offline; open.isHidden = complete || access || offline
        launchRecovery.isHidden = complete || access || offline
        launchRecovery.toolTip = LaunchAccessRecovery.summary
        reset.isHidden = complete || (!access && profileReadError == nil && !offline)
        reset.isEnabled = !active && (!profiles.isEmpty || profileReadError != nil)
        picker.isHidden = complete; recheck.isHidden = complete
        picker.isEnabled = !active && (!keyboards.isEmpty || !disconnected.isEmpty); recheck.isEnabled = !active
        start.isHidden = active || complete
        start.isEnabled = !active && access && selected?.identity.canRemember == true && profileReadError == nil
        start.title = active ? "Setup in progress…" : session.state.phase == .idle ? (ready ? "Learn a different layout" : "Start setup") : "Set up again"
        skip.title = "I don’t have \(session.state.currentKey?.name ?? "this key")"
        skip.isHidden = !active
        skip.isEnabled = active && session.state.guided && !session.state.keys.contains { $0.held }
        retrySave.isHidden = !complete || saved || setupIdentity == nil
        for (index, key) in NavigationKey.allCases.enumerated() {
            let state = session.state.keys[index]
            if session.state.phase == .idle, let profile = recognized?.profile {
                rows[index].stringValue = profile.keys[index] == nil ? "\(key.name) — marked absent in this layout" : "✓ \(key.name) — recognized"
                rows[index].textColor = profile.keys[index] == nil ? .secondaryLabelColor : StatusColors.success
            } else {
                rows[index].stringValue = state.absent ? "✓ \(key.name) — marked absent" : state.complete ? "✓ \(key.name) — identified" : state.held ? "\(key.name) — pressed; release it" : "\(key.name) — not identified yet"
                rows[index].textColor = state.complete ? StatusColors.success : state.held ? StatusColors.information : .secondaryLabelColor
            }
        }
        switch session.state.phase {
        case .idle:
            instruction.stringValue = ready && !offline ? "Layout ready — no setup needed." : "Start setup to identify one key at a time."
            status.stringValue = selected == nil && selectedIdentity != nil ? "This keyboard is disconnected. You can forget its saved layout here; connect it to learn a replacement." : ready ? "Home/End and Page Up/Down behavior can be changed in Navigation keys. Learn a different layout only if these keys behave differently." : "Start setup to identify Home, End, Page Up and Page Down. If a key is missing, choose “I don’t have this key.”"
            status.textColor = .secondaryLabelColor
        case .listening:
            let key = session.state.currentKey?.name ?? "next key"
            instruction.stringValue = "Press and release \(key) on this keyboard."
            let remaining = max(0, Int(ceil(session.state.deadline - session.now())))
            status.stringValue = session.state.notice ?? "Saves automatically after the last key · \(remaining) seconds left. Back stops setup and keeps your previous layout."
            status.textColor = session.state.notice == nil ? StatusColors.information : StatusColors.warning
        case .complete:
            instruction.stringValue = saved ? "Setup complete" : "The layout could not be saved"
            status.stringValue = saveResult ?? "Saving layout…"
            status.textColor = saved ? StatusColors.success : StatusColors.warning
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
        let height: CGFloat = complete ? 350 : 490
        let resized = view.frame.height != height
        if resized {
            view.setFrameSize(NSSize(width: 572, height: height))
            registration.frame.origin.y = complete ? 307 : 407
            instruction.frame = NSRect(x: 8, y: complete ? 259 : 265, width: 556, height: complete ? 40 : 54)
            for (index, row) in rows.enumerated() { row.frame.origin.y = (complete ? 221 : 229) - CGFloat(index * 34) }
            status.frame.origin.y = complete ? 40 : 48
        }
        let host = SettingsWindow.shared
        if !host.interactionBusy, let page = host.pages.last, page.view === view, resized || page.detail != pageDetail {
            let updated = SettingsWindow.Page(title: page.title, detail: pageDetail, view: view, leave: page.leave,
                refresh: page.refresh, backTitle: page.backTitle, preferredBodyHeight: page.preferredBodyHeight)
            host.pages[host.pages.count - 1] = updated
            host.display(updated)
        }
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
