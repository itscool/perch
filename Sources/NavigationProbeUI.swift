import AppKit
import IOKit.hidsystem

final class NavigationProbePage: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
    let session = NavigationProbeSession()
    let picker = NSPopUpButton(frame: NSRect(x: 8, y: 450, width: 352, height: 30), pullsDown: false)
    let permission = NSTextField(labelWithString: "")
    let status = NSTextField(wrappingLabelWithString: "")
    let rows = NavigationKey.allCases.map { _ in NSTextField(labelWithString: "") }
    private(set) var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var keyboards: [NavigationProbeKeyboard] = []
    private let enumerate: () -> [NavigationProbeKeyboard]
    private let hasAccess: () -> Bool
    private var recheck: SettingsActionButton!
    private var start: SettingsActionButton!
    private var cancel: SettingsActionButton!
    private var open: SettingsActionButton!
    private var drag: PermissionDragItem!

    init(enumerate: @escaping () -> [NavigationProbeKeyboard] = NavigationProbeKeyboard.connected,
         hasAccess: @escaping () -> Bool = { NavigationProbeHID.hasAccess }) {
        self.enumerate = enumerate; self.hasAccess = hasAccess
        super.init()
        view.addSubview(picker)
        picker.setAccessibilityLabel("External keyboard to test")
        recheck = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.reload() }
        recheck.frame = NSRect(x: 368, y: 450, width: 196, height: 30); view.addSubview(recheck)
        permission.frame = NSRect(x: 8, y: 410, width: 556, height: 30)
        permission.font = .systemFont(ofSize: 13, weight: .semibold); view.addSubview(permission)
        drag = PermissionDragItem(title: "Drag Perch → Input Monitoring") { Bundle.main.bundleURL }
        drag.frame = NSRect(x: 8, y: 361, width: 332, height: 42); view.addSubview(drag)
        open = SettingsActionButton(title: "Open Input Monitoring") {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
        open.frame = NSRect(x: 344, y: 367, width: 220, height: 30); view.addSubview(open)
        let instructions = NSTextField(wrappingLabelWithString: "Press Start, then press and release Home, End, Page Up, and Page Down on the selected keyboard. Keep this window focused. The test stops after all four keys or 30 seconds.")
        instructions.font = .systemFont(ofSize: 13); instructions.textColor = .labelColor
        instructions.frame = NSRect(x: 8, y: 291, width: 556, height: 62); view.addSubview(instructions)
        for (index, row) in rows.enumerated() {
            row.font = .systemFont(ofSize: 14)
            row.frame = NSRect(x: 16, y: 248 - CGFloat(index*38), width: 540, height: 30)
            view.addSubview(row)
        }
        status.font = .systemFont(ofSize: 13)
        status.frame = NSRect(x: 8, y: 57, width: 556, height: 67); view.addSubview(status)
        start = SettingsActionButton(title: "Start 30-second test") { [weak self] in self?.begin() }
        start.frame = NSRect(x: 8, y: 7, width: 274, height: 32); view.addSubview(start)
        cancel = SettingsActionButton(title: "Done") { [weak self] in
            guard let self else { return }
            if self.session.state.listening { self.session.stop("Test cancelled. No keyboard settings changed.") }
            else { SettingsWindow.shared.goBack() }
        }
        cancel.frame = NSRect(x: 290, y: 7, width: 274, height: 32); view.addSubview(cancel)
        session.changed = { [weak self] in self?.update() }
        reload()
    }
    func show() {
        let host = SettingsWindow.shared
        host.show(.init(title: "External navigation test", detail: "Check that Perch receives only the selected external keyboard’s navigation keys. This test does not remap keys or change built-in Fn+arrows. Success confirms key delivery; the remapping feature is still in development.", view: view, leave: { [self] in close() }))
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: host.window, queue: .main) { [weak self] _ in
            self?.session.stop("Test stopped because you left this window. Press Start to try again.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.update() })
    }
    private func reload() {
        guard !session.state.listening else { return }
        keyboards = enumerate(); picker.removeAllItems()
        for keyboard in keyboards {
            picker.menu?.addItem(NSMenuItem(title: "\(keyboard.name) · \(keyboard.transport)", action: nil, keyEquivalent: ""))
            picker.lastItem?.toolTip = "Device identity: \(keyboard.id)"
        }
        if keyboards.isEmpty { picker.addItem(withTitle: "No supported external keyboard detected") }
        picker.selectItem(at: 0)
        update()
    }
    private func begin() {
        guard SettingsWindow.shared.window.isKeyWindow, hasAccess(),
              keyboards.indices.contains(picker.indexOfSelectedItem), !session.state.listening else { return }
        let keyboard = keyboards[picker.indexOfSelectedItem]
        session.start(deviceID: keyboard.id, source: NavigationProbeHID(keyboard: keyboard))
    }
    private func tick() {
        if !hasAccess() { session.stop("Input Monitoring became unavailable. Test stopped.") }
        else { session.tick() }
    }
    private func update() {
        let active = session.state.listening, access = hasAccess()
        permission.stringValue = access ? "✓ Input Monitoring granted to Perch" : "⚠ Enable Input Monitoring for Perch to run this test"
        permission.textColor = access ? StatusColors.success : StatusColors.warning
        drag.isHidden = access; open.isHidden = access
        picker.isEnabled = !active && !keyboards.isEmpty
        recheck.isEnabled = !active
        start.isEnabled = !active && access && !keyboards.isEmpty
        start.title = session.state.phase == .idle ? "Start 30-second test" : "Test again"
        cancel.title = active ? "Cancel test" : "Done"
        for (index, key) in NavigationKey.allCases.enumerated() {
            let state = session.state.keys[index]
            rows[index].stringValue = state.complete ? "✓ \(key.name) — press and release received" : state.held ? "\(key.name) — pressed; release the key" : "\(key.name) — waiting"
            rows[index].textColor = state.complete ? StatusColors.success : state.held ? StatusColors.information : .secondaryLabelColor
        }
        switch session.state.phase {
        case .idle:
            status.stringValue = !access ? "Enable Perch above, then return here. Start becomes available when permission is granted and an external keyboard is detected." : keyboards.isEmpty ? "Connect or wake an external keyboard, then click Recheck keyboards. Built-in and unrecognized devices are excluded from this test." : "Ready when you press Start. Only these four keys are observed. Nothing is recorded to a file."
            status.textColor = access && !keyboards.isEmpty ? .secondaryLabelColor : StatusColors.warning
        case .listening:
            let remaining = max(0, Int(ceil(session.state.deadline - session.now())))
            status.stringValue = "Listening to the selected keyboard · \(remaining) seconds left"
            status.textColor = StatusColors.information
        case .complete:
            status.stringValue = "✓ All four keys received from this keyboard. Test stopped. Key delivery works; remapping, repeat, and recovery still need validation."
            status.textColor = StatusColors.success
        case .incomplete:
            status.stringValue = "⚠ Test ended before all four presses and releases arrived. Wake the keyboard, recheck it, and try again. No mappings changed."
            status.textColor = StatusColors.warning
        case .stopped(let reason):
            status.stringValue = reason; status.textColor = StatusColors.warning
        }
        if active && timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.05; self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !active { timer?.invalidate(); timer = nil }
    }
    func close() {
        session.stop("Test stopped. No keyboard settings changed.")
        timer?.invalidate(); timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
    }
    deinit { close() }
}

extension AppDelegate {
    @objc func testNavigationKeys() { NavigationProbePage().show() }
}
