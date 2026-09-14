import AppKit

// A modeless setup panel stays available while the user works in System Settings.
final class PermissionSetup: NSObject {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 310))
    let status = SettingsStatusField(wrappingLabelWithString: "Checking access…")
    let instructions = NSTextField(wrappingLabelWithString: "")
    var permissionDrag: PermissionDragItem!
    var openButton: NSButton!
    private var presentedHeight: CGFloat?
    var reviewButton: SettingsActionButton!
    var repairButton: SettingsActionButton!
    private var disclosure = SetupDisclosure()
    var timer: Timer?
    var returnsToSettings = false
    private let helperApp: () -> URL?
    init(helperApp: @escaping () -> URL? = { GuardianInstall.inputPermissionApp }) {
        self.helperApp = helperApp
        super.init()
        instructions.stringValue = "Open Accessibility, add Perch Helper, and enable its switch. Drag the icon below, or focus it and press Space to copy its path.\n\nKeyboard: choose + in System Settings, press ⌘⇧G, paste, then Open. If an old enabled entry still fails, replace it with this helper. Perch checks access automatically."
        instructions.frame = NSRect(x: 20, y: 115, width: 480, height: 135)
        content.addSubview(instructions)
        status.frame = NSRect(x: 20, y: 66, width: 480, height: 42)
        content.addSubview(status)
        let open = NSButton(title: "Open Accessibility", target: self, action: #selector(openSettings))
        openButton = open
        open.bezelStyle = .rounded
        open.frame = NSRect(x: 20, y: 20, width: 180, height: 30)
        content.addSubview(open)
        let drag = PermissionDragItem(title: "Perch Helper") {
            helperApp() ?? SafetyFiles.helperApp
        }
        permissionDrag = drag
        drag.frame = NSRect(x: 210, y: 16, width: 290, height: 38)
        content.addSubview(drag)
        reviewButton = SettingsActionButton(title: "Show permission instructions") { [weak self] in self?.disclosure.toggle(); self?.refresh() }
        reviewButton.frame = NSRect(x: 20, y: 195, width: 480, height: 30)
        reviewButton.isBordered = false; reviewButton.alignment = .left
        reviewButton.font = .systemFont(ofSize: 12, weight: .semibold)
        content.addSubview(reviewButton)
        repairButton = SettingsActionButton(title: "Background helpers in Setup…") {
            SettingsWindow.shared.navigateToSetupStage("maintenance")
        }
        repairButton.frame = NSRect(x: 20, y: 145, width: 480, height: 30)
        content.addSubview(repairButton)
    }

    func show(fromSettings: Bool = false) {
        returnsToSettings = fromSettings
        presentedHeight = nil
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel) }
        SettingsWindow.shared.show(.init(title: "Scrolling & navigation access", detail: "Current input access and controls are checked automatically. If setup needs attention, the next step appears here.", view: content, leave: { [weak self] in self?.timer?.invalidate(); self?.timer = nil }))
        refresh()
    }
    func refresh() {
        let input = HelperStatusIPC.inputClient.value
        if input?.fresh == true && helperApp() == nil {
            present(.init(ready: false, title: "Review helper setup", message: "Perch could not identify the active input helper’s app. Open Setup → Background helpers to repair its launch configuration before adding a permission entry.", route: "repair"))
        } else {
            present(InputReadiness.assess(input: input, config: SafetyConfiguration.load(), checking: HelperStatusIPC.inputClient.initiallyChecking))
        }
    }
    func refresh(state: SafetyStatus?, config: SafetyConfiguration) {
        present(InputReadiness.assess(state, config: config))
    }
    private func present(_ readiness: InputReadiness) {
        disclosure.update(ready: readiness.ready)
        let expanded = disclosure.expanded && readiness.route == "input"
        instructions.isHidden = !expanded
        permissionDrag.isHidden = !expanded || helperApp() == nil
        reviewButton.isHidden = readiness.route != "input"
        reviewButton.isEnabled = readiness.ready
        reviewButton.title = readiness.ready ? disclosure.title : "Permission instructions"
        repairButton.isHidden = readiness.route != "repair"
        status.stringValue = readiness.message
        status.textColor = readiness.ready ? StatusColors.success : readiness.route == "checking" ? .secondaryLabelColor : StatusColors.warning
        let height: CGFloat = expanded ? 410 : 160
        status.frame = NSRect(x: 20, y: height-108, width: 480, height: 100)
        reviewButton.frame.origin.y = height-150
        instructions.frame = NSRect(x: 20, y: 100, width: 480, height: 150)
        repairButton.frame.origin.y = height-150
        openButton.isHidden = !expanded
        do {
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

}
