import Foundation

/// Resume saved intent once per launch/repair or new safe physical transition.
/// Polls and a stopped session alone cannot extend a battery/countdown deadline.
/// One exception: a session that ends (or a start that fails) while the Mac is
/// on external power is retried after `retryDelay`, at most `maximumRetries`
/// times. External power has no battery or countdown deadline to extend, and
/// without this a helper fault leaves saved Keep awake stopped indefinitely.
struct LidAutomaticResume {
    static let retryDelay: Double = 30
    static let maximumRetries = 3
    /// A session that stays armed this long restores the retry budget.
    static let stableSession: Double = 600
    static func helperReady(_ status: LidGuardStatus?, pending: Bool) -> Bool {
        // XPC authenticates the publisher. App-only builds can keep the same
        // compatible helper; their executable hashes need not match.
        status?.fresh == true && (status?.helperVersion ?? 0) >= LidGuardCompatibility.helperVersion && !pending
    }
    private var last: LidObservation?
    private var permitted = true
    private var endedAt: Double?
    private var activeSince: Double?
    private(set) var retries = 0
    mutating func repaired() { permitted = true; retries = 0 }
    mutating func shouldStart(observation: LidObservation, wanted: Bool, ready: Bool,
                              active: Bool, countdown: Bool, busy: Bool, clean: Bool, now: Double = LidGuardClock.now) -> Bool {
        if observation.closed != nil && observation.power != .unknown {
            if let last, (last.closed == true && observation.closed == false) ||
                (last.power == .battery && observation.power == .external) { permitted = true; retries = 0 }
            last = observation
        }
        if !wanted { permitted = true; retries = 0; endedAt = nil; activeSince = nil; return false }
        // Never replace an active normal session or manual countdown.
        if active || countdown {
            permitted = false; endedAt = nil
            if active {
                if activeSince == nil { activeSince = now }
                if let since = activeSince, now - since >= Self.stableSession { retries = 0 }
            }
            return false
        }
        if activeSince != nil { activeSince = nil; endedAt = now }
        if !permitted, let ended = endedAt, retries < Self.maximumRetries, now.isFinite, now - ended >= Self.retryDelay,
           observation.power == .external, observation.closed != nil {
            permitted = true; retries += 1
        }
        guard permitted, ready, !busy, clean,
              (try? LidGuardStart.validate(observation)) != nil else { return false }
        permitted = false; endedAt = now
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
