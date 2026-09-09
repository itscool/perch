import AppKit

struct LidHelperUpdateState: Equatable {
    let installed: Bool
    let pending: Bool
    let lidOpen: Bool
    var notice: String {
        guard pending else { return installed ? "Lid helper is up to date." : "Lid protection is optional. Set it up in Keep awake when needed." }
        return lidOpen ? "Lid helper update ready. Finish it below when convenient." : "Lid helper update queued. Open the lid to finish it; the existing helper stays installed."
    }
    init(info: [String: Any], lidOpen: Bool) {
        installed = !info.isEmpty; self.lidOpen = lidOpen
        pending = installed && (info["PerchLidProtocolVersion"] as? Int != LidGuardCompatibility.protocolVersion ||
            (info["PerchLidHelperVersion"] as? Int ?? 0) < LidGuardCompatibility.helperVersion)
    }
}
final class LidHelperUpdate {
    static let shared = LidHelperUpdate()
    private(set) var busy = false
    private(set) var result: String?
    var state: LidHelperUpdateState {
        LidHelperUpdateState(info: AppUpdate.appInfo(URL(fileURLWithPath: LidGuardInstall.bundle)), lidOpen: MacLidGuardHardware().observe().closed == false)
    }
    func finish() {
        guard !busy, !SettingsWindow.shared.testing else { return }
        guard state.pending, state.lidOpen else { result = "Open the lid before finishing the queued helper update."; return }
        busy = true; result = "Installing the lid helper. macOS will ask for administrator authorization."
        let resume = LidGuardClient.shared.active
        do {
            // The root installer repeats this check after authorization and
            // signature verification, immediately before stopping any helper.
            try LidGuardInstall.install(requireOpenLid: true)
            LidGuardClient.shared.start()
            waitForHelper(until: LidGuardClock.now + 5, resume: resume)
        } catch { busy = false; result = "Helper update is still queued. " + error.localizedDescription }
    }
    private func waitForHelper(until: Double, resume: Bool) {
        LidGuardClient.shared.refresh()
        let status = LidGuardClient.shared.status
        if status?.fresh == true, status?.codeIdentity == LidGuardIdentity.current {
            guard resume else {
                busy = false; result = "Lid helper updated and responding. Enable lid protection in Keep awake when you want it."; return
            }
            guard MacLidGuardHardware().observe().closed == false else {
                busy = false; result = "Lid helper updated. The lid closed during installation, so protection was left off. Review Keep awake."; return
            }
            LidGuardClient.shared.change(true) { outcome in
                self.busy = false
                switch outcome {
                case .success: self.result = "Lid helper updated. Your active lid choice was restored with the lid open; continued sleep prevention remains unverified."
                case .failure(let error): self.result = "Lid helper updated, but protection could not resume. " + error.localizedDescription
                }
            }
        } else if LidGuardClock.now >= until {
            busy = false; result = "The new lid helper has not confirmed startup. Review Keep awake or try Repair lid protection."
        } else { DispatchQueue.main.asyncAfter(deadline: .now()+0.25) { self.waitForHelper(until: until, resume: resume) } }
    }
}

struct UpdateSettingsSnapshot {
    var message: String
    var prepared = false
    var busy = false
    var helperBusy = false
    var helperResult: String?
    var helper: LidHelperUpdateState
    static var current: Self {
        .init(message: AppUpdate.shared.message, prepared: AppUpdate.shared.candidate != nil,
              busy: AppUpdate.shared.busy, helperBusy: LidHelperUpdate.shared.busy,
              helperResult: LidHelperUpdate.shared.result, helper: LidHelperUpdate.shared.state)
    }
}

extension AppDelegate {
    @objc func updateSettings() { presentUpdateSettings(read: { .current }) }
    func presentUpdateSettings(read: @escaping () -> UpdateSettingsSnapshot) {
        let page = SettingsTaskPage(title: "Updates", detail: "App updates and lid-helper updates are separate. A compatible app can restart while the helper keeps the current lid session for up to 60 seconds. Battery and watchdog deadlines still apply. A helper update waits for an open lid and your administrator authorization.", height: 508, statusHeight: 110)
        let choose = page.add("Choose update…", detail: "Select a newer signed Perch.app. Verification and staging happen before restarting.") { AppUpdate.shared.choose() }
        let restart = page.add("Update & restart", detail: "Apply the prepared app and restart Perch. Saved settings are kept; success requires the new app to reclaim any active lid session.") { AppUpdate.shared.restart() }
        let finish = page.add("Finish helper update…", detail: "Requires the lid open. An active, confirmed lid choice is restored after the new helper responds, while the lid is still open.") { LidHelperUpdate.shared.finish() }
        page.add("Keep awake…", detail: "Review the actual lid session, adjust your choices or repair a failed helper.") { [weak self] in self?.keepAwakeSettings() }
        page.add("Lid activity…", detail: "See restart handoffs, battery timing and observed sleep/wake transitions.") { [weak self] in self?.lidActivity() }
        page.update = { [weak page] in
            let snapshot = read(), state = snapshot.helper
            let blocked = snapshot.busy || snapshot.helperBusy
            choose.isEnabled = !blocked
            restart.isEnabled = snapshot.prepared && !blocked
            finish.isEnabled = state.pending && state.lidOpen && !blocked
            finish.title = snapshot.helperBusy ? "Updating lid helper…" : state.pending && !state.lidOpen ? "Open lid to finish helper update" : "Finish helper update…"
            // Reserve room for both status blocks and recovery text. The last
            // helper result replaces its notice and remains when returning.
            page?.status.stringValue = snapshot.message + "\n" + (snapshot.helperResult ?? state.notice)
        }
        page.show(delegate: self)
    }
}
