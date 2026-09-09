import AppKit
import ServiceManagement

/// Simple task pages keep the same controls while observed status refreshes.
/// Only explicit control actions change preferences or request system changes.
final class SettingsTaskPage {
    let title: String
    let detail: String
    let view: NSView
    let status = SettingsStatusField(wrappingLabelWithString: "")
    var update: (() -> Void)?
    private var timer: Timer?
    private var y: CGFloat
    init(title: String, detail: String, height: CGFloat, statusHeight: CGFloat = 60) {
        self.title = title; self.detail = detail
        view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height))
        status.font = .systemFont(ofSize: 13)
        status.frame = NSRect(x: 8, y: height-statusHeight-5, width: 556, height: statusHeight)
        view.addSubview(status); y = height-statusHeight-83
    }
    @discardableResult
    func add(_ title: String, detail: String, checkbox: Bool = false, action: @escaping () -> Void) -> NSButton {
        let button = SettingsActionButton(title: title, action: action)
        button.identifier = .init("settings.task." + title)
        button.toolTip = detail
        button.setAccessibilityHelp(detail)
        if checkbox { button.setButtonType(.switch); button.allowsMixedState = true }
        button.frame = NSRect(x: 0, y: y+34, width: 572, height: 30)
        let label = NSTextField(wrappingLabelWithString: detail)
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 8, y: y, width: 556, height: 32)
        view.addSubview(button); view.addSubview(label); y -= 74
        return button
    }
    func refresh() {
        guard !SettingsWindow.shared.interactionBusy, SettingsWindow.shared.pages.last?.view === view else { return }
        update?()
    }
    func show(delegate: AppDelegate? = nil) {
        let host = SettingsWindow.shared
        host.show(.init(title: title, detail: detail, view: view, leave: { [self] in self.timer?.invalidate(); self.timer = nil }, refresh: { [weak self] in self?.refresh() }))
        delegate?.settingsRefresh = { [weak self] in self?.refresh() }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard !host.interactionBusy else { return }
            self?.refresh()
        }
        timer.tolerance = 0.2; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
}

extension AppDelegate {
    @objc func displaySettings() {
        let page = SettingsTaskPage(title: "Displays", detail: "Display power and input switching are separate choices. Switching an input shows another connected computer; turning the display off leaves the Mac running.", height: 310)
        page.add("Monitor input switching…", detail: "Choose a display, inputs and shortcut. Connection setup has its own Save/Cancel editor.") { [weak self] in self?.monitorInputSettings() }
        page.add("Switching groups…", detail: "Switch one display or several to a named computer, with a separate input mapping for each.") { [weak self] in self?.monitorGroupSettings() }
        page.add("Turn display off now", detail: "Turns off connected displays. Move the mouse or press a key to wake them.") { [weak self] in self?.turnDisplayOff() }
        page.update = { [weak self, weak page] in guard let self else { return }
            page?.status.stringValue = self.monitorInputs.plan.display.isEmpty ? "Input switching has not been set up. Choose a display and its inputs below." : self.monitorInputs.currentSummary }
        page.show(delegate: self)
    }
    @objc func scrollingSettings() {
        let page = SettingsTaskPage(title: "Scrolling", detail: "Choose each device’s vertical scroll direction. Changes save immediately. Horizontal scrolling is unchanged.", height: 310)
        let trackpad = page.add("Reverse trackpad scrolling", detail: ControlHelp.trackpad, checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: true) }
        let wheel = page.add("Reverse mouse-wheel scrolling", detail: ControlHelp.wheel, checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: false) }
        let access = page.add("Set up Accessibility…", detail: "Check Perch Helper’s access or restore it after a system permission reset.") { [weak self] in
            if HelperStatusIPC.inputClient.value?.fresh == true { self?.inputPermissionsFromSettings() }
            else { self?.advancedSafetySettings() }
        }
        page.update = { [weak page] in
            let config = SafetyConfiguration.load(), input = HelperStatusIPC.inputClient.value
            trackpad.state = config.reverseTrackpad ? .on : .off; wheel.state = config.reverseWheel ? .on : .off
            let granted = input?.fresh == true && input?.trusted == true
            trackpad.isEnabled = granted || config.reverseTrackpad; wheel.isEnabled = granted || config.reverseWheel
            access.title = input?.fresh != true ? "Review background helpers…" : granted ? "Review Accessibility…" : "Set up Accessibility…"
            page?.status.stringValue = input?.fresh != true ? "Waiting for the input helper. Review helpers to restore controls; saved scroll choices are kept." : !granted ? "Accessibility is needed before scrolling controls can run. Your saved choices are kept." : (config.reverseTrackpad || config.reverseWheel) && input?.active != true ? "Your choices are saved. Waiting for the helper to apply them." : "Ready. Checked choices are saved and the helper has the required access."
            page?.status.textColor = granted ? .labelColor : StatusColors.warning
        }
        page.show(delegate: self)
    }
    func setScrollChoice(trackpad: Bool) {
        // Disabling a saved choice remains possible after a permission reset and
        // does not request a grant just to turn that feature off.
        var config = SafetyConfiguration.load()
        let wasEnabled = trackpad ? config.reverseTrackpad : config.reverseWheel
        guard wasEnabled || (HelperStatusIPC.inputClient.value?.fresh == true && HelperStatusIPC.inputClient.value?.trusted == true) else { return }
        if trackpad { config.reverseTrackpad.toggle() } else { config.reverseWheel.toggle() }
        do {
            try config.save()
            inputs.reverseTrackpad = config.reverseTrackpad; inputs.reverseWheel = config.reverseWheel
        } catch { showError(error) }
        settingsRefresh?()
    }

    @objc func keepAwakeSettings() { presentKeepAwakeSettings(readHelper: { .current }) }
    func presentKeepAwakeSettings(readHelper: @escaping () -> LidHelperSettingsSnapshot) {
        let page = SettingsTaskPage(title: "Keep awake", detail: "Keep working with the lid closed on external power. When you undock or close the lid on battery, you have 60 seconds to open it. If it stays closed, Perch requests sleep. Opening the lid starts a fresh interval next time; briefly reconnecting power does not restart the clock.", height: 646, statusHeight: 100)
        let awake = page.add("Keep awake", detail: "Prevent idle sleep. Turning this off also removes an active lid override.", checkbox: true) { [weak self] in self?.toggleAwake() }
        let lid = page.add("Including with the lid closed", detail: "Temporarily blocks all system sleep, including Apple menu → Sleep. The 60-second deadline, watchdog and independent recovery remove the override. Turn this off to sleep manually.", checkbox: true) { [weak self] in self?.toggleLid() }
        awake.toolTip = ControlHelp.awake; awake.setAccessibilityHelp(ControlHelp.awake)
        lid.toolTip = ControlHelp.adding(ControlHelp.lidSaved, to: ControlHelp.lid); lid.setAccessibilityHelp(lid.toolTip)
        let resume = page.add("Resume lid protection", detail: "Start a new supervised session using your saved choice. Protection never restarts just because this box stayed checked.") { [weak self] in self?.resumeLidProtection() }
        page.add("Lid activity…", detail: "See lid and power changes, countdowns, command results and macOS sleep/wake events from the last 24 hours.") { [weak self] in self?.lidActivity() }
        let repair = page.add("Repair lid protection…", detail: "Finish a queued helper update with the lid open, or reinstall to repair protection. macOS asks for administrator authorization.") { [weak self] in
            guard let self else { return }
            if readHelper().helper.pending { LidHelperUpdate.shared.finish(); self.settingsRefresh?(); return }
            do { try LidGuardInstall.install(); LidGuardClient.shared.start(); self.settingsRefresh?() } catch { self.showError(error) }
        }
        page.add("Review background helpers…", detail: "Use if Perch cannot confirm or apply a keep-awake request.") { [weak self] in self?.advancedSafetySettings() }
        page.add("Review sleep reset…", detail: "Remove the lid override and Perch’s keep-awake request, with an explicit reset action.") { [weak self] in self?.systemResetPage(includeAudio: false) }
        page.update = { [weak self, weak page] in
            guard let self else { return }
            let presentation = self.sleepPresentation()
            awake.state = presentation.awake
            awake.isEnabled = presentation.awakeEnabled
            // The menu remembers the lid choice while Keep awake is off. This page
            // distinguishes that preference from the observed macOS override.
            let helper = readHelper()
            repair.title = helper.busy ? "Updating lid helper…" : helper.helper.pending ? "Finish lid helper update…" : "Repair lid protection…"
            repair.isEnabled = !helper.busy && !AppUpdate.shared.busy && (!helper.helper.pending || helper.helper.lidOpen)
            let guarded = LidGuardClient.shared.active
            lid.state = presentation.lid
            lid.isEnabled = presentation.lidEnabled
            resume.isEnabled = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey) && SafetyConfiguration.load().keepAwake && !guarded && !LidGuardClient.shared.changing && self.observedLidDisabled == false && !LidGuardOwnership.recorded
            let remembered = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey)
            page?.status.stringValue = self.observedLidDisabled == true ? "An older system-wide sleep override is active without a timeout. Remove it with Review sleep reset before using lid protection." : guarded || remembered || LidGuardClient.shared.changing || LidGuardClient.shared.status?.error != nil ? LidGuardClient.shared.detail : self.observedLidDisabled == nil || awake.state == .mixed ? "Sleep state is not confirmed. Review the helper status before relying on Keep awake." : awake.state == .on ? "Keep awake is active. Enable lid protection below to add the 60-second undocking interval." : "Keep awake is off. Normal macOS sleep behavior applies."
            if remembered && !guarded && self.actualLidState == .off && !LidGuardClient.shared.changing {
                page?.status.stringValue = SafetyConfiguration.load().keepAwake
                    ? "Your lid choice is saved, but protection is stopped. Normal lid sleep applies. Use Resume lid protection to start a new session.\n" + LidGuardClient.shared.detail
                    : "Your lid choice is saved. Keep awake is off, so normal macOS sleep applies. Turning Keep awake on starts a new lid session."
            }
            if remembered && self.actualLidState == .mixed {
                page?.status.stringValue = "Your lid choice is saved, but the current protection state is unknown. Review the helper status before relying on it.\n" + LidGuardClient.shared.detail
            }
            if let result = helper.result { page?.status.stringValue += "\n" + result }
            else if helper.helper.pending { page?.status.stringValue += "\n" + helper.helper.notice }
            page?.status.textColor = self.observedLidDisabled == true ? StatusColors.warning : .labelColor
        }
        page.show(delegate: self)
    }
    @objc func appSettings() { presentAppSettings(readRestart: { .current }, restart: { AppUpdate.shared.restartCurrentApp() }) }
    func presentAppSettings(readRestart: @escaping () -> RestartSettingsSnapshot, restart: @escaping () -> Void) {
        let page = SettingsTaskPage(title: "App settings", detail: "Preferences for Perch itself. Feature controls are in their own Settings categories.", height: 532)
        let login = page.add("Start Perch at login", detail: ControlHelp.login, checkbox: true) { [weak self] in self?.toggleLogin() }
        let cpu = page.add("Show top process and Perch CPU usage", detail: "Updates every 10 seconds while the menu is open. Percentages use total CPU capacity.", checkbox: true) {
            let sender = NSButton(); sender.state = CPUDisplaySettings.enabled() ? .off : .on
            self.toggleProcessCPU(sender)
        }
        cpu.identifier = NSUserInterfaceItemIdentifier(CPUDisplaySettings.key)
        let restartButton = page.add("Restart Perch", detail: "Close and reopen Perch, keeping your saved choices. An active lid session keeps its existing timeout.") { [weak page] in restart(); page?.refresh() }
        page.add("Maintenance…", detail: "Review or repair background helpers and Perch’s own permission setup.") { [weak self] in self?.advancedSafetySettings() }
        page.add("Reset Perch settings…", detail: "Choose saved device setup or Perch preferences to forget, with a separate confirmation.") { [weak self] in self?.resetSettingsPage() }
        page.add("About Perch…", detail: "Version and build information.") { [weak self] in self?.about() }
        page.update = { [weak page] in
            let status = SMAppService.mainApp.status
            login.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
            cpu.state = CPUDisplaySettings.enabled() ? .on : .off
            let restartState = readRestart()
            restartButton.isEnabled = !restartState.busy
            restartButton.title = restartState.busy ? "Please wait…" : "Restart Perch"
            page?.status.stringValue = !restartState.message.isEmpty ? restartState.message : status == .requiresApproval ? "Start at login needs approval. Select it to open macOS Login Items." : "Ordinary preferences save immediately. Maintenance and resets explain their effects before making changes."
        }
        page.show(delegate: self)
    }
    @objc func perchPrivacyResetFromSettings() { privacyOnlyReset(global: false) }
}
