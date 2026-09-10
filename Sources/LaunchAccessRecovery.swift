import AppKit

/// Public capability checks establish current access, not TCC's responsible
/// identity. In particular, parent PID is not proof of inherited permission.
enum LaunchAccessRecovery {
    static let summary = "Input Monitoring is not available to this copy of Perch. Open Keyboard access to add the current app or repair an outdated permission entry."
    static let detail = "External Fn controls and navigation-key learning need Input Monitoring for Perch. Add the app below in System Settings and enable it.\n\nIf Perch is already enabled but access still fails, the entry may refer to an older signed copy. Remove only that Perch entry and add this copy again. Follow any macOS quit/reopen prompt.\n\nOpening from Finder can help with launch attribution, but does not repair an outdated grant. Scrolling uses Perch Helper’s Accessibility access; Desk sharing needs access for Perch itself."

    static func automationFailure(_ message: String, code: Int?) -> String {
        guard code == -1743 else { return message }
        return message + "\n\nmacOS denied Automation access for this action. Check Perch in System Settings → Privacy & Security → Automation. If it is already allowed, quit and reopen Perch from Finder; a terminal-launched copy can inherit its launcher’s privacy identity. This is separate from keyboard Input Monitoring."
    }
}

struct StartupKeyboardAccessNotice {
    private(set) var shown = false
    mutating func shouldShow(blocked: Bool, connected: Bool, busy: Bool) -> Bool {
        guard !shown, blocked, connected, !busy else { return false }
        shown = true
        return true
    }
}

extension AppDelegate {
    func considerKeyboardAccessNotice() {
        guard accessNoticeStarted, Date() < accessNoticeDeadline,
              startupKeyboardAccessNotice.shouldShow(blocked: keyboardModes.needsAccess,
                connected: !keyboardModes.results.isEmpty, busy: keyboardModes.blocksFunctionKeyChanges) else { return }
        withMenuClosed { [weak self] in
            SettingsWindow.shared.afterInteraction {
                guard let self, self.keyboardModes.needsAccess else { return }
                // Present the actionable overview, not an informational modal blocking its sidebar.
                if !SettingsWindow.shared.window.isVisible { self.configureSettings() }
            }
        }
    }
    @objc func keyboardAccessRecovery() {
        presentKeyboardAccess(readAccess: { NavigationProbeHID.hasAccess })
    }
    func presentKeyboardAccess(readAccess: @escaping () -> Bool) {
        let page = KeyboardAccessPage(readAccess: readAccess, recheck: { [weak self] in self?.keyboardModes.recheck() }, openSettings: { [weak self] in self?.openKeyboardPreferences(permission: true) })
        page.show()
    }
}

final class KeyboardAccessPage {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 520))
    let status = SettingsStatusField(wrappingLabelWithString: "")
    let instructions = NSTextField(wrappingLabelWithString: LaunchAccessRecovery.detail)
    private let readAccess: () -> Bool
    private var reviewing = false
    private var previousAccess: Bool?
    private var presentedHeight: CGFloat?
    private var timer: Timer?
    private var repairControls: [NSView] = []
    private var review: SettingsActionButton!
    init(readAccess: @escaping () -> Bool, recheck: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.readAccess = readAccess
        status.font = .systemFont(ofSize: 13); view.addSubview(status)
        instructions.font = .systemFont(ofSize: 13)
        instructions.frame = NSRect(x: 8, y: 175, width: 556, height: 245); view.addSubview(instructions)
        review = SettingsActionButton(title: "Review permission setup…") { [weak self] in self?.reviewing.toggle(); self?.refresh() }
        view.addSubview(review)
        let open = SettingsActionButton(title: "Open macOS Input Monitoring", action: openSettings)
        open.frame = NSRect(x: 0, y: 130, width: 330, height: 30); view.addSubview(open)
        let finder = SettingsActionButton(title: "Show Perch in Finder") {
            SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]); return true }
        }
        finder.frame = NSRect(x: 0, y: 90, width: 230, height: 30)
        finder.toolTip = "To reopen manually, quit Perch and double-click the selected app. Quitting ends an active lid session."
        view.addSubview(finder)
        let check = SettingsActionButton(title: "Recheck access") { [weak self] in recheck(); self?.refresh() }
        check.frame = NSRect(x: 310, y: 90, width: 254, height: 30); view.addSubview(check)
        let drag = PermissionDragItem(title: "Perch · drag / copy path") { Bundle.main.bundleURL }
        drag.frame = NSRect(x: 8, y: 20, width: 556, height: 42); view.addSubview(drag)
        repairControls = [instructions, open, finder, check, drag]
    }
    func show() {
        SettingsWindow.shared.show(.init(title: "Keyboard access", detail: "Perch checks this copy’s Input Monitoring access automatically. Repair instructions appear when access is missing; reviewing a working grant is optional.", view: view, leave: { [self] in self.timer?.invalidate(); self.timer = nil }, refresh: { [self] in refresh() }))
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func refresh() {
        let host = SettingsWindow.shared
        guard !host.interactionBusy, host.pages.last?.view === view else { return }
        let granted = readAccess()
        if previousAccess != granted { reviewing = false }; previousAccess = granted
        let expanded = !granted || reviewing
        let height: CGFloat = expanded ? 560 : 160
        repairControls.forEach { $0.isHidden = !expanded }
        review.isHidden = !granted
        review.title = reviewing ? "Hide permission instructions" : "Review permission setup…"
        review.frame = NSRect(x: 0, y: expanded ? 425 : 15, width: 572, height: 30)
        status.stringValue = granted ? "✓ Keyboard access is ready. Perch can read supported external keyboards. Choose Keyboards or Keyboard layouts in the sidebar to review your devices." : LaunchAccessRecovery.summary
        status.textColor = granted ? StatusColors.success : StatusColors.warning
        status.frame = NSRect(x: 8, y: height-98, width: 556, height: 90)
        view.frame.size.height = height
        if presentedHeight != height, let current = host.pages.last { host.display(current); presentedHeight = height }
    }
}
