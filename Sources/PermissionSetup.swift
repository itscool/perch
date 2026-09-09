import AppKit

// A modeless setup panel stays available while the user works in System Settings.
final class PermissionSetup: NSObject, NSWindowDelegate {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let status = NSTextField(wrappingLabelWithString: "Checking access…")
    let instructions = NSTextField(wrappingLabelWithString: "")
    var permissionDrag: PermissionDragItem!
    var openButton: NSButton!
    private var presentedHeight: CGFloat?
    var reviewButton: SettingsActionButton!
    var repairButton: SettingsActionButton!
    private var reviewing = false
    private var lastReady = false
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
        instructions.stringValue = "Open Accessibility, add Perch Helper, and enable its switch. Drag the icon below, or focus it and press Space to copy its path.\n\nKeyboard: choose + in System Settings, press ⌘⇧G, paste, then Open. If an old enabled entry still fails, replace it with this helper. Perch checks access automatically."
        instructions.frame = NSRect(x: 20, y: 115, width: 480, height: 135)
        panel.contentView?.addSubview(instructions)
        status.frame = NSRect(x: 20, y: 66, width: 480, height: 42)
        panel.contentView?.addSubview(status)
        let open = NSButton(title: "Open Accessibility", target: self, action: #selector(openSettings))
        openButton = open
        open.bezelStyle = .rounded
        open.frame = NSRect(x: 20, y: 20, width: 180, height: 30)
        panel.contentView?.addSubview(open)
        let drag = PermissionDragItem(title: "Perch Helper · drag / copy path") {
            FileManager.default.fileExists(atPath: GuardianInstall.protectedBinary.path) ? GuardianInstall.protectedBinary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : SafetyFiles.helperApp
        }
        permissionDrag = drag
        drag.frame = NSRect(x: 210, y: 16, width: 290, height: 38)
        panel.contentView?.addSubview(drag)
        reviewButton = SettingsActionButton(title: "Review permission setup…") { [weak self] in self?.reviewing.toggle(); self?.refresh() }
        reviewButton.frame = NSRect(x: 20, y: 195, width: 480, height: 30)
        panel.contentView?.addSubview(reviewButton)
        repairButton = SettingsActionButton(title: "Open Maintenance…") {
            (NSApp.delegate as? AppDelegate)?.advancedSafetySettings()
        }
        repairButton.frame = NSRect(x: 20, y: 145, width: 480, height: 30)
        panel.contentView?.addSubview(repairButton)
    }

    func show(fromSettings: Bool = false) {
        returnsToSettings = fromSettings
        presentedHeight = nil
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel) }
        if let content = panel.contentView {
            SettingsWindow.shared.show(.init(title: "Input controls", detail: "Current input access and controls are checked automatically. If setup needs attention, the next step appears here.", view: content, leave: { [weak self] in self?.timer?.invalidate(); self?.timer = nil }))
        }
        refresh()
    }
    func refresh() {
        let input = HelperStatusIPC.inputClient.value
        present(InputReadiness.assess(input: input, config: SafetyConfiguration.load(), checking: HelperStatusIPC.inputClient.initiallyChecking))
    }
    func refresh(state: SafetyStatus?, config: SafetyConfiguration) {
        present(InputReadiness.assess(state, config: config))
    }
    private func present(_ readiness: InputReadiness) {
        if lastReady != readiness.ready { reviewing = false }; lastReady = readiness.ready
        instructions.isHidden = readiness.route != "input" || (readiness.ready && !reviewing)
        permissionDrag.isHidden = instructions.isHidden
        reviewButton.isHidden = !readiness.ready
        reviewButton.title = reviewing ? "Hide permission instructions" : "Review permission setup…"
        repairButton.isHidden = readiness.route != "repair"
        status.stringValue = readiness.message
        status.textColor = readiness.ready ? StatusColors.success : StatusColors.warning
        let expanded = !instructions.isHidden
        let height: CGFloat = expanded ? 310 : readiness.ready ? 160 : 190
        status.frame = expanded ? NSRect(x: 20, y: 66, width: 480, height: 42) : NSRect(x: 20, y: height-102, width: 480, height: 90)
        reviewButton.frame.origin.y = expanded ? 255 : 20
        repairButton.frame.origin.y = 20
        openButton.isHidden = !expanded
        if let content = panel.contentView {
            content.frame.size.height = height
            let host = SettingsWindow.shared
            if let current = host.pages.last, current.view === content, !host.interactionBusy, presentedHeight != height {
                host.display(current); presentedHeight = height
            }
        }
    }
    @objc func openSettings() {
        SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    }
    @objc func revealHelper() {
        let helper = FileManager.default.fileExists(atPath: GuardianInstall.protectedBinary.path) ? GuardianInstall.protectedBinary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : SafetyFiles.helperApp
        SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.activateFileViewerSelecting([helper]); return true }
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        returnsToSettings = false // This retired backing panel does not own a modal session.
    }
}
