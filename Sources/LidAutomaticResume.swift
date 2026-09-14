import Foundation

/// Resume saved intent once per launch/repair or new safe physical transition.
/// Polls and a stopped session alone cannot extend a battery/countdown deadline.
struct LidAutomaticResume {
    static func helperReady(_ status: LidGuardStatus?, pending: Bool) -> Bool {
        // XPC authenticates the publisher. App-only builds can keep the same
        // compatible helper; their executable hashes need not match.
        status?.fresh == true && (status?.helperVersion ?? 0) >= LidGuardCompatibility.helperVersion && !pending
    }
    private var last: LidObservation?
    private var permitted = true
    mutating func repaired() { permitted = true }
    mutating func shouldStart(observation: LidObservation, wanted: Bool, ready: Bool,
                              active: Bool, countdown: Bool, busy: Bool, clean: Bool) -> Bool {
        if observation.closed != nil && observation.power != .unknown {
            if let last, (last.closed == true && observation.closed == false) ||
                (last.power == .battery && observation.power == .external) { permitted = true }
            last = observation
        }
        if !wanted { permitted = true; return false }
        // Never replace an active normal session or manual countdown.
        if active || countdown { permitted = false; return false }
        guard permitted, ready, !busy, clean,
              (try? LidGuardStart.validate(observation)) != nil else { return false }
        permitted = false
        return true
    }
}

extension AppDelegate {
    func resumeSavedLidProtectionIfReady() {
        guard automaticLidResumeReady, !SettingsWindow.shared.testing else { return }
        let client = LidGuardClient.shared, status = client.status
        guard automaticLidResume.shouldStart(observation: MacLidGuardHardware().observe(),
            wanted: UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey) && SafetyConfiguration.load().keepAwake,
            ready: LidAutomaticResume.helperReady(status, pending: LidHelperUpdate.shared.state.pending),
            active: status?.armed == true, countdown: status?.countdown?.active == true,
            busy: client.changing || LidHelperUpdate.shared.busy || AppUpdate.shared.busy || PerchUpdater.shared.busy,
            clean: !LidGuardOwnership.recorded && !LidSleepOverride.owned && (try? LidSleepOverride.systemDisabled()) == false) else { return }
        client.change(true) { [weak self] outcome in
            if case .failure(let error) = outcome {
                LidHelperUpdate.shared.recordResumeFailure(error)
            }
            self?.settingsRefresh?()
        }
    }
}
