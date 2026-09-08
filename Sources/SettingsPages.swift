import AppKit
import ServiceManagement

/// Simple task pages keep the same controls while observed status refreshes.
/// Only explicit control actions change preferences or request system changes.
final class SettingsTaskPage {
    let title: String
    let detail: String
    let view: NSView
    let status = NSTextField(wrappingLabelWithString: "")
    var update: (() -> Void)?
    private var timer: Timer?
    private var y: CGFloat
    init(title: String, detail: String, height: CGFloat) {
        self.title = title; self.detail = detail
        view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height))
        status.font = .systemFont(ofSize: 13)
        status.frame = NSRect(x: 8, y: height-65, width: 556, height: 60)
        view.addSubview(status); y = height-143
    }
    @discardableResult
    func add(_ title: String, detail: String, checkbox: Bool = false, action: @escaping () -> Void) -> NSButton {
        let button = SettingsActionButton(title: title, action: action)
        if checkbox { button.setButtonType(.switch); button.allowsMixedState = true }
        button.frame = NSRect(x: 0, y: y+34, width: 572, height: 30)
        let label = NSTextField(wrappingLabelWithString: detail)
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 8, y: y, width: 556, height: 32)
        view.addSubview(button); view.addSubview(label); y -= 74
        return button
    }
    func refresh() {
        guard SettingsWindow.shared.pages.last?.view === view else { return }
        update?()
    }
    func show(delegate: AppDelegate? = nil) {
        let host = SettingsWindow.shared
        host.show(.init(title: title, detail: detail, view: view, leave: { [self] in self.timer?.invalidate(); self.timer = nil }, refresh: { [weak self] in self?.refresh() }))
        delegate?.settingsRefresh = { [weak self] in self?.refresh() }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard !host.modal, !host.authorizing else { return }
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
        let trackpad = page.add("Reverse trackpad scrolling", detail: "Reverse the trackpad’s current macOS vertical scroll direction.", checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: true) }
        let wheel = page.add("Reverse mouse-wheel scrolling", detail: "Reverse the wheel’s current macOS vertical scroll direction.", checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: false) }
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

    @objc func keepAwakeSettings() {
        let page = SettingsTaskPage(title: "Keep awake", detail: "Keep working with the lid closed on external power. When you undock or close the lid on battery, you have 60 seconds to open it. If it stays closed, Perch requests sleep. Opening the lid starts a fresh interval next time; briefly reconnecting power does not restart the clock.", height: 458)
        let awake = page.add("Keep awake", detail: "Prevent idle sleep. Turning this off also removes an active lid override.", checkbox: true) { [weak self] in self?.toggleAwake() }
        let lid = page.add("Including with the lid closed", detail: "Set up with the lid open. Authorizes a supervised helper; wait for Enabled before closing the lid.", checkbox: true) { [weak self] in self?.toggleLid() }
        page.add("Repair lid protection…", detail: "Reinstall the lid helper. Protection stays off until you enable it again with the lid open.") { [weak self] in
            guard let self else { return }; do { try LidGuardInstall.install(); LidGuardClient.shared.start(); self.settingsRefresh?() } catch { self.showError(error) }
        }
        page.add("Review background helpers…", detail: "Use if Perch cannot confirm or apply a keep-awake request.") { [weak self] in self?.advancedSafetySettings() }
        page.add("Review sleep reset…", detail: "Remove the lid override and Perch’s keep-awake request, with an explicit reset action.") { [weak self] in self?.systemResetPage(includeAudio: false) }
        page.update = { [weak self, weak page] in
            guard let self else { return }
            awake.state = self.observedLidDisabled == nil ? .mixed : self.awakeItem?.state ?? .mixed
            awake.isEnabled = self.observedLidDisabled != nil && self.awakeItem?.isEnabled == true
            // The menu remembers the lid choice while Keep awake is off. This page
            // distinguishes that preference from the observed macOS override.
            let guarded = LidGuardClient.shared.active
            lid.state = LidGuardClient.controlState(legacyDisabled: self.observedLidDisabled, status: LidGuardClient.shared.status, recordedSession: LidGuardOwnership.exists)
            lid.isEnabled = self.awakeItem?.state == .on && self.observedLidDisabled != nil && !LidGuardClient.shared.changing
            let remembered = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey)
            page?.status.stringValue = self.observedLidDisabled == true ? "An older system-wide sleep override is active without a timeout. Remove it with Review sleep reset before using lid protection." : guarded || remembered || LidGuardClient.shared.changing || LidGuardClient.shared.status?.error != nil ? LidGuardClient.shared.detail : self.observedLidDisabled == nil || awake.state == .mixed ? "Sleep state is not confirmed. Review the helper status before relying on Keep awake." : awake.state == .on ? "Keep awake is active. Enable lid protection below to add the 60-second undocking interval." : "Keep awake is off. Normal macOS sleep behavior applies."
            page?.status.textColor = self.observedLidDisabled == true ? StatusColors.warning : .labelColor
        }
        page.show(delegate: self)
    }
    @objc func appSettings() {
        let page = SettingsTaskPage(title: "App settings", detail: "Preferences for Perch itself. Feature controls are in their own Settings categories.", height: 458)
        let login = page.add("Start Perch at login", detail: "Open the menu app when you sign in. macOS may require approval in Login Items.", checkbox: true) { [weak self] in self?.toggleLogin() }
        let cpu = page.add("Show top process and Perch CPU usage", detail: "Updates every 10 seconds while the menu is open. Percentages use total CPU capacity.", checkbox: true) {
            let sender = NSButton(); sender.state = CPUDisplaySettings.enabled() ? .off : .on
            self.toggleProcessCPU(sender)
        }
        cpu.identifier = NSUserInterfaceItemIdentifier(CPUDisplaySettings.key)
        page.add("Maintenance…", detail: "Review or repair background helpers and Perch’s own permission setup.") { [weak self] in self?.advancedSafetySettings() }
        page.add("Reset Perch settings…", detail: "Choose saved device setup or Perch preferences to forget, with a separate confirmation.") { [weak self] in self?.resetSettingsPage() }
        page.add("About Perch…", detail: "Version and build information.") { [weak self] in self?.about() }
        page.update = { [weak page] in
            let status = SMAppService.mainApp.status
            login.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
            cpu.state = CPUDisplaySettings.enabled() ? .on : .off
            page?.status.stringValue = status == .requiresApproval ? "Start at login needs approval. Select it to open macOS Login Items." : "Ordinary preferences save immediately. Maintenance and resets explain their effects before making changes."
        }
        page.show(delegate: self)
    }
    @objc func perchPrivacyResetFromSettings() { privacyOnlyReset(global: false) }
}
