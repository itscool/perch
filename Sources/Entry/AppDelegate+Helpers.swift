import AppKit
import ServiceManagement

/// Settings entry points and background-helper health. These lived beside the
/// Agent Kill Switch's menu until that feature was removed; none of them
/// belonged to it.
extension AppDelegate {
    @objc func toggleProcessCPU(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: CPUDisplaySettings.key)
        systemMonitor.processCPU.setActive(menuOpen && sender.state == .on)
    }
    @objc func configureSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.configureSettings() }; return }
        installSettingsNavigation()
        if let overview = SettingsWindow.shared.sidebar.destinations.first {
            SettingsWindow.shared.navigate(to: overview)
        }
    }
    @objc func advancedSafetySettings() { openSetupStage("maintenance") }
    @objc func presentBackgroundSetup() {
        let detail = BackgroundHelperRecovery.shared.detail
        if SettingsWindow.shared.pages.last?.title == "Background helpers" {
            SettingsWindow.shared.updateCurrentPageDetail(detail)
            return
        }
        setupOverview()
        let page = SettingsTaskPage(title: "Background helpers", detail: "Perch installs and maintains the helpers used by scrolling, Keep awake and putting back desk screens automatically.", height: 160, statusHeight: 100)
        // What used to be separate Setup rows lives in this step, shown only
        // while it applies.
        let watcher = page.add("Remove old process watcher…", detail: "Perch no longer watches processes, but the watcher it installed is still running and slowing this Mac down. macOS asks for your password.") { [weak self] in self?.retireProcessWatcher() }
        let login = page.add("Open macOS Login Items…", detail: "Starting Perch at login needs your approval in macOS.") { [weak self] in self?.reviewLoginApproval() }
        page.update = { [weak page] in
            page?.status.stringValue = BackgroundHelperRecovery.shared.detail
            page?.status.textColor = BackgroundHelperRecovery.shared.healthy ? StatusColors.success : BackgroundHelperRecovery.shared.failure != nil ? StatusColors.warning : .secondaryLabelColor
            page?.arrangeRows(hiding: (RetiredProcessWatcher.installed() ? [] : [watcher]) + (SMAppService.mainApp.status == .requiresApproval ? [] : [login]))
        }
        page.show(delegate: self)
    }
    /// Remove the Agent Kill Switch's root process watcher. macOS asks for an
    /// administrator; the person pressing Remove… is the consent.
    @objc func retireProcessWatcher() {
        if menuOpen { withMenuClosed { [weak self] in self?.retireProcessWatcher() }; return }
        guard !SettingsWindow.shared.testing else { return }
        do {
            try RetiredProcessWatcher.remove()
            PerchLog.record("helper.watcher", "Removed the old process watcher")
        } catch {
            PerchLog.record("helper.watcher", "The old process watcher is still installed: " + error.localizedDescription)
        }
        refreshHelperHealth()
        // Stay on Background helpers: its row goes once the watcher has.
        settingsRefresh?()
    }
    @objc func reviewLoginApproval() {
        SettingsWindow.shared.handoffToExternalApp { SMAppService.openSystemSettingsLoginItems(); return true }
    }

    /// Show a background-helper problem as a hint on Settings…, or clear it.
    func refreshHelperHealth(status: SafetyStatus? = GuardianInstall.status, config: SafetyConfiguration = SafetyConfiguration.load(), checking: Bool? = nil) {
        let checking = checking ?? (status == nil && HelperStatusIPC.guardianClient.initiallyChecking)
        let issue = checking ? nil : ProtectionIssue.assess(status, config: config)
        let issueChanged = currentProtectionIssue != issue
        currentProtectionIssue = issue
        if issueChanged && SettingsWindow.shared.window.isVisible && !SettingsWindow.shared.modal && SettingsWindow.shared.pages.last?.title == "Perch settings" { configureSettings() }
        label(safetySettingsItem, "Settings…", hint: issue.map { _ in "⚠ Review setup" } ?? keyboardModes.attentionHint, hintColor: keyboardModes.warning && issue == nil ? StatusColors.warning : .secondaryLabelColor)
        if issue != nil, let title = menuTitleSources[safetySettingsItem] {
            let colored = NSMutableAttributedString(attributedString: title)
            let range = (colored.string as NSString).range(of: "⚠")
            if range.location != NSNotFound {
                colored.addAttributes([.foregroundColor: StatusColors.warning, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)], range: NSRange(location: range.location, length: colored.length - range.location))
            }
            setMenuTitle(safetySettingsItem, colored)
        }
        safetySettingsItem.menuHelp = ControlHelp.adding(issue?.detail ?? (keyboardModes.warning ? keyboardModes.attentionDetail : nil), to: ControlHelp.settings)
    }
}
