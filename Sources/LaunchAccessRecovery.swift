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
        let page = SettingsTaskPage(title: "Keyboard access", detail: LaunchAccessRecovery.detail, height: 400, statusHeight: 70)
        page.add("Show Perch in Finder", detail: "Choose Quit Perch, then double-click the selected app. Quitting ends an active lid session.") {
            SettingsWindow.shared.handoffToExternalApp {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]); return true
            }
        }
        page.add("Open macOS Input Monitoring", detail: "Add this copy of Perch. If an old enabled entry still fails, replace only that entry with the app below.") { [weak self] in self?.openKeyboardPreferences(permission: true) }
        page.add("Recheck keyboard access", detail: "Read access and device status again without changing your saved choices.") { [weak self] in self?.keyboardModes.recheck() }
        page.update = { [weak page] in
            let granted = NavigationProbeHID.hasAccess
            page?.status.stringValue = granted ? "✓ Input Monitoring is available to this Perch process. Return to Keyboard settings to check the connected devices." : LaunchAccessRecovery.summary
            page?.status.textColor = granted ? StatusColors.success : StatusColors.warning
        }
        let drag = PermissionDragItem(title: "Perch · drag / copy path") { Bundle.main.bundleURL }
        drag.frame = NSRect(x: 8, y: 8, width: 556, height: 42); page.view.addSubview(drag)
        page.show(delegate: self)
    }
}
