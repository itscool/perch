import AppKit

extension AppDelegate {
    @objc func lidProtectionSetup() { openSetupStage("lid-setup") }
    @objc func presentLidSetupStage() {
        setupOverview()
        presentLidProtectionSetup(readHelper: { .current })
    }
    func presentLidProtectionSetup(readHelper: @escaping () -> LidHelperSettingsSnapshot) {
        let page = SettingsTaskPage(title: "Lid protection setup", detail: "Install or repair the supervised lid helper here. Your Keep awake choices are retained. Setup does not start a new protected session. An update can resume an existing session; return to Keep awake to choose behavior or resume stopped protection.", height: 444, statusHeight: 120)
        let repair = page.add("Set up lid protection…", detail: "macOS asks for administrator authorization. Finish queued updates with the lid open; the current helper stays in place until then.") { [weak self] in
            guard let self else { return }
            if readHelper().helper.pending { LidHelperUpdate.shared.finish(); self.settingsRefresh?(); return }
            do { try LidGuardInstall.install(); LidGuardClient.shared.start(); self.settingsRefresh?() }
            catch { self.showError(error) }
        }
        page.add("Keep awake settings…", detail: "Choose idle and lid behavior, or resume protection after setup is ready.") { [weak self] in
            guard let destination = SettingsWindow.shared.sidebar.destinations.first(where: { $0.id == "awake" }) else { return }
            SettingsWindow.shared.navigate(to: destination)
            self?.settingsRefresh?()
        }
        page.add("Background helpers in Setup…", detail: "Repair the shared helper if Perch cannot confirm its idle-sleep request.") { [weak self] in self?.advancedSafetySettings() }
        page.add("Sleep reset options…", detail: "If you need to end Perch’s sleep protection, open its reset options. Nothing changes until you choose and confirm an action; return here afterward.") { [weak self] in self?.openReset(.sleep) }
        page.update = { [weak page] in
            let helper = readHelper()
            repair.title = helper.busy ? "Updating lid helper…" : helper.helper.pending ? "Finish lid helper update…" : !helper.helper.installed ? "Set up lid protection…" : "Repair lid protection…"
            repair.isEnabled = !helper.busy && !AppUpdate.shared.busy && (!helper.helper.pending || helper.helper.lidOpen)
            repair.contentTintColor = helper.helper.pending && !helper.busy ? StatusColors.warning : nil
            page?.status.stringValue = helper.busy ? "The lid helper is being updated. Your saved sleep choices are retained." : helper.helper.pending ? helper.helper.notice : !helper.helper.installed ? "The lid helper is not ready. Complete setup before relying on closed-lid protection." : "The lid helper is installed. Review Keep awake for the current session and observed sleep state."
            if let result = helper.result { page?.status.stringValue += "\n" + result }
            page?.status.textColor = helper.helper.pending || !helper.helper.installed ? StatusColors.warning : .labelColor
        }
        page.show(delegate: self)
    }

    @objc func sharingAccessSetup() { openSetupStage("sharing-access") }
    @objc func presentSharingAccessStage() {
        setupOverview()
        presentSharingAccess(readAccessibility: { AXIsProcessTrusted() && CGPreflightPostEventAccess() }, readMonitoring: { CGPreflightListenEventAccess() })
    }
    func presentSharingAccess(readAccessibility: @escaping () -> Bool, readMonitoring: @escaping () -> Bool) {
        let page = SettingsTaskPage(title: "Shared input access", detail: "Keyboard and mouse sharing needs Accessibility and Input Monitoring for Perch itself. Scrolling and navigation use Perch Helper’s separate grant. Checking access does not start sharing.", height: 460, statusHeight: 100)
        var disclosure = SetupDisclosure()
        let review = page.add("Show permission instructions", detail: "Instructions stay open while access needs attention.") { [weak page] in
            disclosure.toggle(); page?.refresh()
        }
        review.isBordered = false; review.alignment = .left
        review.font = .systemFont(ofSize: 12, weight: .semibold)
        let accessibilityButton = page.add("Open macOS Accessibility…", detail: "Add Perch and enable it. If an old enabled copy still fails, replace only that entry with the app below.") {
            SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
        }
        let monitoringButton = page.add("Keyboard access · Input Monitoring…", detail: "Uses the same Perch grant as external keyboard controls. Review its current state and instructions in Keyboard access.") { [weak self] in self?.keyboardAccessRecovery() }
        let drag = PermissionDragItem(title: "Perch") { Bundle.main.bundleURL }
        drag.frame = NSRect(x: 8, y: 15, width: 556, height: 42); page.view.addSubview(drag)
        page.update = { [weak page] in
            let accessibility = readAccessibility(), monitoring = readMonitoring()
            let ready = accessibility && monitoring
            disclosure.update(ready: ready)
            review.title = ready ? disclosure.title : "Permission instructions"
            review.isEnabled = ready
            drag.isHidden = !disclosure.expanded
            page?.arrangeRows(hiding: disclosure.expanded ? [] : [accessibilityButton, monitoringButton], footerHeight: drag.isHidden ? 0 : 58)
            page?.status.stringValue = "Accessibility: " + (accessibility ? "ready" : "needs attention") + "\nInput Monitoring: " + (monitoring ? "ready" : "needs attention") + "\n" + (accessibility && monitoring ? "Access is ready. Return to Keyboard & mouse sharing when you want to enable it." : "Complete the missing access below. Perch checks automatically; sharing remains under your control.")
            page?.status.textColor = accessibility && monitoring ? StatusColors.success : StatusColors.warning
        }
        page.show(delegate: self)
    }
}
