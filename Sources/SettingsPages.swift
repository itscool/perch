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
    private let statusHeight: CGFloat
    private var rows: [(button: NSButton, label: NSTextField)] = []
    init(title: String, detail: String, height: CGFloat, statusHeight: CGFloat = 60) {
        self.title = title; self.detail = detail; self.statusHeight = statusHeight
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
        rows.append((button, label))
        return button
    }
    /// Reflow optional instructions as one row, including their explanation.
    /// Hidden setup controls must not leave stale instructions or empty blocks.
    func arrangeRows(hiding hidden: [NSButton], footerHeight: CGFloat = 0) {
        let visible = rows.filter { row in !hidden.contains { $0 === row.button } }
        let height = statusHeight + 54 + CGFloat(visible.count) * 74 + footerHeight
        let resized = view.frame.height != height
        view.frame.size.height = height
        status.frame.origin.y = height - statusHeight - 5
        var y = height - statusHeight - 83
        for row in rows {
            let hide = hidden.contains { $0 === row.button }
            row.button.isHidden = hide; row.label.isHidden = hide
            if !hide {
                row.button.frame.origin.y = y + 34; row.label.frame.origin.y = y
                y -= 74
            }
        }
        let host = SettingsWindow.shared
        if host.pages.last?.view === view, let focused = host.window.firstResponder as? NSView,
           focused.isHiddenOrHasHiddenAncestor {
            host.window.makeFirstResponder(visible.first?.button ?? host.sidebar.table)
        }
        if resized, let current = host.pages.last, current.view === view { host.display(current) }
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
        let page = SettingsTaskPage(title: "Displays", detail: "Use Desk to group computers and switch monitor presets. Turning displays off is a separate action.", height: 240)
        page.add("Open Desk…", detail: "Arrange shared screens, map connections and use three monitor presets.") { [weak self] in self?.deskSettings() }
        page.add("Turn display off now", detail: "Turns off connected displays. Move the mouse or press a key to wake them.") { [weak self] in self?.turnDisplayOff() }
        page.update = { [weak page] in page?.status.stringValue = DeskCoordinator.shared.runtime.map { "\($0.node.group.monitors.count) screens in \($0.node.group.name). " + ($0.input.enabled ? ($0.input.active ? "Keyboard and mouse sharing is active." : "Input sharing is enabled. Open Keyboard & mouse sharing to review readiness.") : "Keyboard and mouse sharing has its own settings page.") } ?? "Desk is optional. Set it up when you want to use computers and screens together." }
        page.show(delegate: self)
    }
    @objc func scrollingSettings() {
        let page = SettingsTaskPage(title: "Scrolling", detail: "Choose each device’s vertical scroll direction. Changes save immediately. Horizontal scrolling is unchanged.", height: 310)
        let trackpad = page.add("Reverse trackpad scrolling", detail: ControlHelp.trackpad, checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: true) }
        let wheel = page.add("Reverse mouse-wheel scrolling", detail: ControlHelp.wheel, checkbox: true) { [weak self] in self?.setScrollChoice(trackpad: false) }
        let access = page.add("Scrolling & navigation access…", detail: "Open Setup to check Perch Helper’s access or restore it after a system permission reset.") { [weak self] in
            if HelperStatusIPC.inputClient.value?.fresh == true { self?.inputPermissionsFromSettings() }
            else { self?.advancedSafetySettings() }
        }
        page.update = { [weak page] in
            let config = SafetyConfiguration.load(), input = HelperStatusIPC.inputClient.value
            trackpad.state = config.reverseTrackpad ? .on : .off; wheel.state = config.reverseWheel ? .on : .off
            let granted = input?.fresh == true && input?.trusted == true
            trackpad.isEnabled = granted || config.reverseTrackpad; wheel.isEnabled = granted || config.reverseWheel
            access.title = input?.fresh != true ? "Background helpers in Setup…" : "Scrolling & navigation access…"
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
        let page = SettingsTaskPage(title: "Keep awake", detail: "Keep working with the lid closed on external power. When you undock or close the lid on battery, you have 60 seconds to open it. If it stays closed, Perch requests sleep. Opening the lid starts a fresh interval next time; briefly reconnecting power does not restart the clock.", height: 498, statusHeight: 100)
        let awake = page.add("Keep awake", detail: "Prevent idle sleep. Turning this off also removes an active lid override.", checkbox: true) { [weak self] in self?.toggleAwake() }
        let lid = page.add("Including with the lid closed", detail: "Temporarily blocks all system sleep, including Apple menu → Sleep. The 60-second deadline, watchdog and independent recovery remove the override. Turn this off to sleep manually.", checkbox: true) { [weak self] in self?.toggleLid() }
        awake.toolTip = ControlHelp.awake; awake.setAccessibilityHelp(ControlHelp.awake)
        lid.toolTip = ControlHelp.adding(ControlHelp.lidSaved, to: ControlHelp.lid); lid.setAccessibilityHelp(lid.toolTip)
        let resume = page.add("Resume lid protection", detail: "Start a new supervised session using your saved choice. Protection never restarts just because this box stayed checked.") { [weak self] in self?.resumeLidProtection() }
        page.add("Lid activity…", detail: "See lid and power changes, countdowns, command results and macOS sleep/wake events from the last 24 hours.") { [weak self] in self?.lidActivity() }
        let repair = page.add("Lid protection setup…", detail: "Open Setup to finish helper installation, updates or recovery. Your sleep choices stay here.") { [weak self] in
            self?.lidProtectionSetup()
        }
        page.update = { [weak self, weak page] in
            guard let self else { return }
            let presentation = self.sleepPresentation()
            awake.state = presentation.awake
            awake.isEnabled = presentation.awakeEnabled
            // The menu remembers the lid choice while Keep awake is off. This page
            // distinguishes that preference from the observed macOS override.
            let helper = readHelper()
            repair.title = helper.helper.pending ? "Lid helper update needed — open Setup…" : "Lid protection setup…"
            repair.contentTintColor = helper.helper.pending ? StatusColors.warning : nil
            let guarded = LidGuardClient.shared.active
            lid.state = presentation.lid
            lid.isEnabled = presentation.lidEnabled
            resume.isEnabled = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey) && SafetyConfiguration.load().keepAwake && !guarded && !LidGuardClient.shared.changing && self.observedLidDisabled == false && !LidGuardOwnership.recorded && LidGuardClient.shared.status?.fresh == true && !helper.helper.pending
            let remembered = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
            page?.status.stringValue = self.observedLidDisabled == true ? "System sleep is disabled outside Perch’s current protection session. Perch cannot safely take ownership of that setting. Restore normal system sleep before enabling lid protection." : guarded || remembered || LidGuardClient.shared.changing || LidGuardClient.shared.status?.error != nil ? LidGuardClient.shared.detail : self.observedLidDisabled == nil || awake.state == .mixed ? "Sleep state is not confirmed. Review the helper status before relying on Keep awake." : awake.state == .on ? "Keep awake is active. Enable lid protection below to add the 60-second undocking interval." : "Keep awake is off. Normal macOS sleep behavior applies."
            if remembered && !guarded && self.actualLidState == .off && !LidGuardClient.shared.changing {
                page?.status.stringValue = SafetyConfiguration.load().keepAwake
                    ? "Your lid choice is saved, but protection is stopped. Normal lid sleep applies. Use Resume lid protection to start a new session.\n" + LidGuardClient.shared.detail
                    : "Your lid choice is saved. Keep awake is off, so normal macOS sleep applies. Turning Keep awake on starts a new lid session."
            }
            if remembered && self.actualLidState == .mixed {
                page?.status.stringValue = "Your lid choice is saved, but the current protection state is unknown. Review the helper status before relying on it.\n" + LidGuardClient.shared.detail
            }
            if remembered && self.observedLidDisabled != true {
                if !helper.helper.installed {
                    page?.status.stringValue = "Your lid choice is saved. Open Setup → Lid protection, then return here to Resume lid protection after the helper is ready. Protection has not been confirmed."
                } else if helper.helper.pending {
                    page?.status.stringValue = "Your lid choice is saved. Finish the helper update before starting a new session."
                } else if LidGuardClient.shared.status?.fresh != true {
                    page?.status.stringValue = "Your lid choice is saved. Waiting for the lid helper before Resume becomes available. If it does not connect, review Setup → Lid protection."
                }
            }
            if helper.helper.pending { page?.status.stringValue += "\nReview Setup → Lid protection to finish the update." }
            let needsAttention = self.observedLidDisabled == true || helper.helper.pending ||
                LidGuardClient.shared.status?.error != nil ||
                (remembered && SafetyConfiguration.load().keepAwake && !guarded && !LidGuardClient.shared.changing)
            page?.status.textColor = needsAttention ? StatusColors.warning : .labelColor
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
        page.add("Setup & status…", detail: "Review prerequisite readiness and repair missing access or helpers in Setup.") { [weak self] in self?.setupOverview() }
        page.add("Resets…", detail: "Reset saved choices, keyboard layouts, menu appearance, privacy permissions or sleep and audio. Choose a scope before making changes.") { [weak self] in self?.openResets() }
        page.add("About Perch…", detail: "Version and build information.") { [weak self] in self?.about() }
        page.update = { [weak page] in
            let status = SMAppService.mainApp.status
            login.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
            cpu.state = CPUDisplaySettings.enabled() ? .on : .off
            let restartState = readRestart()
            restartButton.isEnabled = !restartState.busy
            restartButton.title = restartState.busy ? "Please wait…" : "Restart Perch"
            page?.status.stringValue = !restartState.message.isEmpty ? restartState.message : status == .requiresApproval ? "Start at login needs approval. Select it to review background setup." : "Ordinary preferences save immediately. Setup and resets explain their effects before making changes."
        }
        page.show(delegate: self)
    }
    @objc func perchPrivacyResetFromSettings() { openReset(.perchPrivacy) }
}
