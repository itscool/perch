import AppKit

struct BackgroundHelperRecoveryPolicy {
    private var missingSince: Double?
    private var attempted = false
    mutating func failed(now: Double) { missingSince = now; attempted = true }
    mutating func shouldRecover(healthy: Bool, busy: Bool, now: Double) -> Bool {
        guard now.isFinite else { return false }
        if healthy { missingSince = nil; attempted = false; return false }
        if missingSince == nil || now < missingSince! { missingSince = now }
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
        if let failure { return "Automatic helper recovery did not complete. " + failure + " Quit and reopen Perch to try again. Permission setup is listed separately below Setup." }
        return "Perch is checking its background helpers and will restart them automatically if needed. Your saved choices are kept."
    }
    func recordFailure(_ error: Error) {
        failure = error.localizedDescription
        policy.failed(now: LidGuardClock.now)
    }
    func check() {
        guard !SettingsWindow.shared.testing else { return }
        let healthy = healthy
        if healthy { failure = nil; verificationDeadline = nil }
        else if let deadline = verificationDeadline, LidGuardClock.now >= deadline {
            verificationDeadline = nil
            failure = "The helpers did not respond after restarting. Quit and reopen Perch to try again."
        }
        guard policy.shouldRecover(healthy: healthy,
            busy: busy || SettingsWindow.shared.interactionBusy || LidHelperUpdate.shared.busy || AppUpdate.shared.busy || PerchUpdater.shared.busy,
            now: LidGuardClock.now) else { return }
        busy = true
        defer { busy = false }
        do { try GuardianInstall.install(); failure = nil; verificationDeadline = LidGuardClock.now + 5 }
        catch { failure = error.localizedDescription }
        HelperStatusIPC.guardianClient.refresh(); HelperStatusIPC.inputClient.refresh()
    }
}
