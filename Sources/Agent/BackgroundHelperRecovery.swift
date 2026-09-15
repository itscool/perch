import AppKit

struct BackgroundHelperRecoveryPolicy {
    private var missingSince: Double?
    private var attempted = false
    private var retryAt: Double?
    private var retries = 0
    var retryScheduled: Bool { retryAt != nil }
    /// A failed repair. One that needed the person's authorization is never
    /// repeated automatically; an authorization-free one retries with backoff
    /// (30 seconds, doubling to 10 minutes) until the helpers are healthy.
    mutating func failed(now: Double, retryable: Bool = false) {
        missingSince = now; attempted = true
        if retryable { retryAt = now + min(600, 30 * pow(2, Double(retries))); retries += 1 } else { retryAt = nil }
    }
    mutating func shouldRecover(healthy: Bool, busy: Bool, now: Double) -> Bool {
        guard now.isFinite else { return false }
        if healthy { missingSince = nil; attempted = false; retryAt = nil; retries = 0; return false }
        if missingSince == nil || now < missingSince! { missingSince = now }
        if attempted, let retryAt, now >= retryAt, !busy { self.retryAt = nil; return true }
        guard !attempted, !busy, now - missingSince! >= 10 else { return false }
        attempted = true
        return true
    }
}

final class BackgroundHelperRecovery {
    static let shared = BackgroundHelperRecovery()
    private var policy = BackgroundHelperRecoveryPolicy()
    private(set) var busy = false
    private(set) var failure: String?
    private var verificationDeadline: Double?
    var healthy: Bool {
        let guardian = HelperStatusIPC.guardianClient.value, input = HelperStatusIPC.inputClient.value
        return guardian?.fresh == true && guardian?.compatible == true && input?.fresh == true
    }
    var detail: String {
        if healthy { return "Perch’s background helpers are responding and up to date. No action is needed." }
        if busy { return "Perch is restarting its background helpers. Your saved choices are kept." }
        if let failure { return "Automatic helper recovery did not complete. " + failure + (policy.retryScheduled ? " Perch tries again automatically." : " Quit and reopen Perch to try again.") + " Permission setup is listed separately below Setup." }
        return "Perch is checking its background helpers and will restart them automatically if needed. Your saved choices are kept."
    }
    func recordFailure(_ error: Error) {
        failure = error.localizedDescription
        policy.failed(now: LidGuardClock.now, retryable: !GuardianInstall.requiresAuthorization)
    }
    func check() {
        guard !SettingsWindow.shared.testing else { return }
        let healthy = healthy
        if healthy { failure = nil; verificationDeadline = nil }
        else if let deadline = verificationDeadline, LidGuardClock.now >= deadline {
            verificationDeadline = nil
            failure = "The helpers did not respond after restarting."
            policy.failed(now: LidGuardClock.now, retryable: !GuardianInstall.requiresAuthorization)
        }
        guard policy.shouldRecover(healthy: healthy,
            busy: busy || SettingsWindow.shared.interactionBusy || LidHelperUpdate.shared.busy || AppUpdate.shared.busy || PerchUpdater.shared.busy,
            now: LidGuardClock.now) else { return }
        busy = true
        defer { busy = false }
        do { try GuardianInstall.install(); failure = nil; verificationDeadline = LidGuardClock.now + 5 }
        catch { failure = error.localizedDescription; policy.failed(now: LidGuardClock.now, retryable: !GuardianInstall.requiresAuthorization) }
        HelperStatusIPC.guardianClient.refresh(); HelperStatusIPC.inputClient.refresh()
    }
}
