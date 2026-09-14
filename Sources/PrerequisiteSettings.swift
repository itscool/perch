import AppKit

extension AppDelegate {
    @objc func lidProtectionSetup() { openSetupStage("lid-setup") }
    @objc func presentLidSetupStage() {
        setupOverview()
        presentLidProtectionSetup(readHelper: { .current })
    }
    func presentLidProtectionSetup(readHelper: @escaping () -> LidHelperSettingsSnapshot) {
        let page = SettingsTaskPage(title: "Lid protection setup", detail: "Install or repair the supervised lid helper here. Your Keep awake choices are retained. Behavior switches are in the Perch menu. Protection follows your saved choice automatically when the helper is ready. After a battery timeout, open the lid or connect power to start a new session.", height: 444, statusHeight: 120)
        let repair = page.add("Set up lid protection…", detail: "macOS asks for administrator authorization. Updates briefly hold sleep protection, then restore its previous state. You can keep the lid closed.") { [weak self] in
            guard let self else { return }
            if readHelper().helper.pending { LidHelperUpdate.shared.finish(); self.settingsRefresh?(); return }
            do { try LidGuardInstall.install(); LidGuardClient.shared.start(); self.settingsRefresh?() }
            catch { self.showError(error) }
        }
        page.add("Sleep reset options…", detail: "If you need to end Perch’s sleep protection, open its reset options. Nothing changes until you choose and confirm an action; return here afterward.") { [weak self] in self?.openReset(.sleep) }
        page.update = { [weak page] in
            let helper = readHelper()
            repair.title = helper.busy ? "Updating lid helper…" : helper.helper.pending ? "Retry incomplete helper update…" : !helper.helper.installed ? "Set up lid protection…" : "Lid helper is up to date"
            repair.isEnabled = !helper.busy && !AppUpdate.shared.busy && (!helper.helper.installed || helper.helper.pending)
            repair.contentTintColor = helper.helper.pending && !helper.busy ? StatusColors.warning : nil
            page?.status.stringValue = helper.busy ? "The lid helper is being updated. Your saved sleep choices are retained." : helper.helper.pending ? helper.helper.notice : !helper.helper.installed ? "The lid helper is not ready. Complete setup before relying on closed-lid protection." : "The lid helper is installed. Behavior switches are in the Perch menu; recorded events are in Lid activity."
            if helper.helper.installed && !helper.helper.pending { page?.status.stringValue += "\n" + LidGuardClient.shared.detail }
            if let result = helper.result { page?.status.stringValue += "\n" + result }
            page?.status.textColor = helper.busy ? .secondaryLabelColor : helper.helper.pending || !helper.helper.installed ? StatusColors.warning : .labelColor
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
            page?.status.stringValue = "Accessibility: " + (accessibility ? "ready" : "needs attention") + "\nInput Monitoring: " + (monitoring ? "ready" : "needs attention") + "\n" + (accessibility && monitoring ? "Access is ready. Return to the Perch menu and turn on Share on this Mac." : "Complete the missing access below. Perch checks automatically; sharing remains under your control.")
            page?.status.textColor = accessibility && monitoring ? StatusColors.success : StatusColors.warning
        }
        page.show(delegate: self)
    }
}
