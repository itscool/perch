import AppKit

// A modeless setup panel stays available while the user works in System Settings.
final class PermissionSetup: NSObject, NSWindowDelegate {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 275), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let status = NSTextField(wrappingLabelWithString: "Checking access…")
    var timer: Timer?
    var returnsToSettings = false
    override init() {
        super.init()
        panel.title = "Set up input controls"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let instructions = NSTextField(wrappingLabelWithString: "1. Open Accessibility settings.\n2. Drag the Perch Helper icon below into the list and enable it.\n3. If an old entry is enabled but access still fails, remove it and drag the current helper in again.\n\nKeep this window open—it checks the actual helper and will confirm when your controls work.")
        instructions.frame = NSRect(x: 20, y: 115, width: 480, height: 135)
        panel.contentView?.addSubview(instructions)
        status.frame = NSRect(x: 20, y: 66, width: 480, height: 42)
        panel.contentView?.addSubview(status)
        let open = NSButton(title: "Open Accessibility", target: self, action: #selector(openSettings))
        open.bezelStyle = .rounded
        open.frame = NSRect(x: 20, y: 20, width: 180, height: 30)
        panel.contentView?.addSubview(open)
        let drag = PermissionDragItem(title: "Drag helper → Settings") {
            FileManager.default.fileExists(atPath: GuardianInstall.protectedBinary.path) ? GuardianInstall.protectedBinary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : SafetyFiles.helperApp
        }
        drag.frame = NSRect(x: 210, y: 16, width: 290, height: 38)
        panel.contentView?.addSubview(drag)
    }

    func show(fromSettings: Bool = false) {
        returnsToSettings = fromSettings
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel) }
        if let content = panel.contentView {
            SettingsWindow.shared.show(.init(title: "Input controls", detail: "Keep this page open while granting Accessibility. It checks the actual input helper.", view: content, leave: { [weak self] in self?.timer?.invalidate(); self?.timer = nil }))
        }
        refresh()
    }
    func refresh() { refresh(state: GuardianInstall.status, config: SafetyConfiguration.load()) }
    func refresh(state: SafetyStatus?, config: SafetyConfiguration) {
        let readiness = InputReadiness.assess(state, config: config)
        status.stringValue = readiness.message
        status.textColor = readiness.ready ? StatusColors.success : StatusColors.warning
    }
    @objc func openSettings() {
        try? SafetyFiles.send("input-access")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func revealHelper() {
        let helper = FileManager.default.fileExists(atPath: GuardianInstall.protectedBinary.path) ? GuardianInstall.protectedBinary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : SafetyFiles.helperApp
        NSWorkspace.shared.activateFileViewerSelecting([helper])
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        if returnsToSettings { returnsToSettings = false; NSApp.stopModal() }
    }
}
