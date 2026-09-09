import AppKit

/// Public capability checks establish current access, not TCC's responsible
/// identity. In particular, parent PID is not proof of inherited permission.
enum LaunchAccessRecovery {
    static let summary = "macOS is not allowing keyboard access in this launch. If Perch is already enabled in Input Monitoring, quit and reopen it from Finder."
    static let detail = "Some external Fn controls and navigation-key learning need Input Monitoring for Perch. Opening Perch from a terminal or another app can affect access in that launch.\n\nIf Perch is already enabled, try reopening it from Finder before changing permissions. Scrolling and remapping use Perch Helper’s separate access."

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
                let alert = NSAlert(); alert.messageText = "Keyboard access is unavailable in this launch"
                alert.informativeText = LaunchAccessRecovery.summary + " Your saved keyboard choices are unchanged."
                alert.addButton(withTitle: "Review keyboard access"); alert.addButton(withTitle: "Close")
                SettingsWindow.shared.present(alert) { response in
                    if response == .alertFirstButtonReturn { self.configureSettings(); self.keyboardAccessRecovery() }
                }
            }
        }
    }
    @objc func keyboardAccessRecovery() {
        let page = SettingsTaskPage(title: "Keyboard access", detail: LaunchAccessRecovery.detail, height: 350, statusHeight: 100)
        page.add("Show Perch in Finder", detail: "Choose Quit Perch, then double-click the selected app. Quitting ends an active lid session.") {
            SettingsWindow.shared.handoffToExternalApp {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]); return true
            }
        }
        page.add("Open macOS Input Monitoring", detail: "If Perch is already enabled, leave it enabled and use the Finder relaunch above.") { [weak self] in self?.openKeyboardPreferences(permission: true) }
        page.add("Recheck keyboard access", detail: "Read access and device status again without changing your saved choices.") { [weak self] in self?.keyboardModes.recheck() }
        page.update = { [weak page] in
            let granted = NavigationProbeHID.hasAccess
            page?.status.stringValue = granted ? "✓ Input Monitoring is available to this Perch process. Return to Keyboard settings to check the connected devices." : LaunchAccessRecovery.summary
            page?.status.textColor = granted ? StatusColors.success : StatusColors.warning
        }
        page.show(delegate: self)
    }
}
