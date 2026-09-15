import AppKit
import ServiceManagement

/// Scrolling, keyboard and input-access rows, and Start at login.
extension AppDelegate {
    func updateInputs() {
        var config = SafetyConfiguration.load()
        config.reverseTrackpad = inputs.reverseTrackpad
        config.reverseWheel = inputs.reverseWheel
        config.swapModifiers = inputs.swapModifiers
        do {
            try config.save()
        } catch { showError(error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if self.inputs.wanted && HelperStatusIPC.inputClient.value?.active != true {
                self.showInputAccessPrompt()
            }
            self.refresh()
        }
    }
    func showInputAccessPrompt() {
        SettingsWindow.shared.afterInteraction { [weak self] in
            guard let self, self.inputs.wanted, HelperStatusIPC.inputClient.value?.active != true else { return }
            self.inputPermissions()
        }
    }
    @objc func toggleTrackpad() { setScrollChoice(trackpad: true); refresh() }
    @objc func toggleWheel() { setScrollChoice(trackpad: false); refresh() }
    @objc func toggleModifiers() { setModifierGroup(true) }
    func refreshScrolling(input: InputHelperStatus?, checking: Bool? = nil) {
        let pending = checking ?? HelperStatusIPC.inputClient.initiallyChecking
        let trusted = input?.fresh == true && input?.trusted == true
        for (item, title, action) in [(trackpadItem!, "Reverse trackpad scroll", #selector(toggleTrackpad)), (wheelItem!, "Reverse mouse wheel", #selector(toggleWheel))] {
            let saved = item.state == .on
            let canChange = saved || trusted
            item.action = canChange ? action : #selector(inputPermissionsFromSettings)
            item.isEnabled = saved || trusted || !pending
            (item.view as? MenuRowView)?.opensAnotherInterface = { !canChange }
            let hint = pending && input == nil ? "Checking input helper…" : !trusted ? "Set up in Settings" : saved && input?.active != true ? "Saved · controls not running" : "Vertical"
            label(item, title, hint: hint, hintColor: trusted && (!saved || input?.active == true) ? .secondaryLabelColor : StatusColors.warning)
            let purpose = item === trackpadItem ? ControlHelp.trackpad : ControlHelp.wheel
            let context = pending && input == nil ? "Checking input access. Your saved choice is kept." : !trusted ? (saved ? "This choice is saved. Turn it off here, or restore input access in Settings." : "Select to set up input access in Settings.") : saved && input?.active != true ? "This choice is saved, but input controls are not running. Review Scrolling settings." : nil
            item.menuHelp = ControlHelp.adding(context, to: purpose)
        }
    }
    func observeHelperPresentation() {
        let repaint = { [weak self] in
            guard let self, self.awakeItem != nil else { return }
            HelperStatusIPC.guardianClient.withCachedValue {
                HelperStatusIPC.inputClient.withCachedValue {
                    self.refreshSafety(); self.refreshScrolling(input: HelperStatusIPC.inputClient.value)
                    self.refreshNavigationItems(); self.settingsRefresh?()
                }
            }
        }
        HelperStatusIPC.guardianClient.onChange = repaint
        HelperStatusIPC.inputClient.onChange = repaint
        LidGuardClient.shared.onChange = { [weak self] in
            guard let self else { return }
            self.resumeSavedLidProtectionIfReady()
            self.applyLidSleepPresentation(); self.settingsRefresh?()
        }
    }
    @objc func inputPermissionsFromSettings() { openSetupStage("input-access") }
    @objc func inputPermissions() { inputPermissionsFromSettings() }
    @objc func presentInputAccessStage() {
        setupOverview()
        if permissionSetup == nil { permissionSetup = PermissionSetup() }
        permissionSetup?.show(fromSettings: true)
    }
    @objc func toggleFunctionKeys() { keyboardModes.setBuiltIn(fnItem.state != .on) }
    @objc func toggleLogin() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            let enabling = SMAppService.mainApp.status != .enabled
            do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: break // The shared post-check opens approval once.
            default: try SMAppService.mainApp.register()
            }
                if enabling && SMAppService.mainApp.status == .requiresApproval { self.reviewLoginApproval() }
            } catch {
                if enabling { self.reviewLoginApproval() }
                else { self.showError(error) }
            }
            self.refresh()
        }
    }
}
