import Foundation

/// Fast regression tests from the September 15 focused review: Lid protection and Settings.
func runLidSettingsReviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }

    // Saved Keep awake on external power recovers from an ended session after a
    // bounded delay instead of staying "needs attention" until a physical change.
    let powered = LidObservation(closed: true, power: .external)
    func poll(_ resume: inout LidAutomaticResume, _ observation: LidObservation = powered, active: Bool = false, ready: Bool = true, at now: Double) -> Bool {
        resume.shouldStart(observation: observation, wanted: true, ready: ready, active: active, countdown: false, busy: false, clean: true, now: now)
    }
    var resume = LidAutomaticResume()
    try check(poll(&resume, at: 0), "Launch did not resume saved lid protection on external power")
    _ = poll(&resume, active: true, at: 1)
    try check(!poll(&resume, at: 100), "An ended session restarted without waiting")
    try check(!poll(&resume, at: 100 + LidAutomaticResume.retryDelay - 0.5), "An ended session restarted before the retry delay")
    try check(poll(&resume, at: 100 + LidAutomaticResume.retryDelay), "Saved lid protection on external power never resumed after its session ended")
    // A start that never becomes active also retries, but only a bounded number of times.
    var attempt = 100 + LidAutomaticResume.retryDelay
    var retried = 1
    while poll(&resume, at: attempt + LidAutomaticResume.retryDelay) { attempt += LidAutomaticResume.retryDelay; retried += 1 }
    try check(retried == LidAutomaticResume.maximumRetries, "Automatic lid retries were not bounded: \(retried)")
    try check(!poll(&resume, at: attempt + 10_000), "Retries resumed after the budget was spent")
    // A physical transition restores the budget.
    _ = poll(&resume, LidObservation(closed: true, power: .battery), at: attempt + 10_001)
    try check(poll(&resume, at: attempt + 10_002), "Connecting power did not restore automatic resume")
    // A long stable session restores the budget too.
    var stable = LidAutomaticResume()
    _ = poll(&stable, at: 0)
    for cycle in 0..<LidAutomaticResume.maximumRetries {
        let base = Double(cycle) * 100 + 10
        _ = poll(&stable, active: true, at: base)
        _ = poll(&stable, at: base + 1)
        _ = poll(&stable, at: base + 1 + LidAutomaticResume.retryDelay)
    }
    try check(stable.retries == LidAutomaticResume.maximumRetries, "Retry fixture did not spend the budget")
    _ = poll(&stable, active: true, at: 1_000)
    _ = poll(&stable, active: true, at: 1_000 + LidAutomaticResume.stableSession)
    try check(stable.retries == 0, "A long stable session did not restore the retry budget")
    // Battery never retries: a closed Mac on battery must keep its deadline.
    var battery = LidAutomaticResume()
    let open = LidObservation(closed: false, power: .battery)
    _ = poll(&battery, open, at: 0)
    _ = poll(&battery, open, active: true, at: 1)
    for step in 1...10 { try check(!poll(&battery, open, at: 1 + Double(step) * LidAutomaticResume.retryDelay), "A session on battery was retried automatically") }
    // Not ready yet: the granted retry waits for readiness instead of being lost.
    var waiting = LidAutomaticResume()
    _ = poll(&waiting, at: 0); _ = poll(&waiting, active: true, at: 1); _ = poll(&waiting, at: 2)
    try check(!poll(&waiting, ready: false, at: 2 + LidAutomaticResume.retryDelay), "Retry started with an unready helper")
    try check(poll(&waiting, at: 3 + LidAutomaticResume.retryDelay), "A retry granted while the helper was unready was lost")

    // Watchdog lease tolerance: the supervisor renews every 0.25 s with a
    // three-second lease. A stall just under it keeps protection; at expiry it
    // stops; leases more than six seconds ahead are refused.
    var watchdog = LidGuardWatchdogState()
    let token = UUID().uuidString
    try check(watchdog.receive(.init(token: token, expires: 10 + 3, deadline: nil), now: 10), "A normal three-second lease was refused")
    try check(watchdog.evaluate(powered, now: 12.99, channelAlive: true).preventLidSleep, "A supervisor stall shorter than the lease ended protection")
    try check(!watchdog.evaluate(powered, now: 13, channelAlive: true).preventLidSleep, "An expired lease kept protection")
    var bounded = LidGuardWatchdogState()
    try check(bounded.receive(.init(token: token, expires: 16, deadline: nil), now: 10) && !bounded.receive(.init(token: token, expires: 16.01, deadline: nil), now: 10),
              "The watchdog lease bound changed")
    // Restart handoff results must arrive while AppKit's terminate loop runs
    // inside a main-queue block; a main-queue delivery would wait forever.
    let handoffToken = UUID().uuidString, identity = String(repeating: "a", count: 40)
    let ticket = LidRestartTicket(id: UUID().uuidString, targetIdentity: identity, deadline: LidGuardClock.now + 60)
    func reply(armed: Bool, restart: LidRestartTicket? = nil) -> Data? {
        try? JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: armed, detail: "fixture"), token: armed ? handoffToken : nil, restart: restart))
    }
    let client = LidGuardClient(transport: { request, completion in
        if case .change(false) = request { completion(reply(armed: false)) } else { completion(reply(armed: true)) }
    }, restart: { request, completion in
        if case .prepare = request { completion(reply(armed: true, restart: ticket)) } else { completion(reply(armed: true)) }
    })
    func spin(_ mode: RunLoop.Mode, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !done() && Date() < deadline { _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.01)) }
    }
    var enabled = false
    client.change(true) { if case .success = $0 { enabled = true } }
    spin(.default) { enabled }
    try check(enabled, "Restart handoff fixture could not start a session")
    var prepared = false, resumed = false, queuedInside = false, finished = false
    DispatchQueue.main.async {
        client.prepareForRestart(identity: identity) { if case .success = $0 { prepared = true } }
        DispatchQueue.main.async { queuedInside = true }
        spin(.modalPanel) { prepared }
        client.resumeAfterRestart(ticket.id) { if case .success = $0 { resumed = true } }
        spin(.modalPanel) { resumed }
        finished = !queuedInside
    }
    spin(.default) { finished || (prepared && resumed && queuedInside) }
    try check(finished, "The fixture no longer models a main-queue block that cannot re-enter")
    try check(prepared, "Restart preparation result did not arrive inside the terminate loop")
    try check(resumed, "Restart claim result did not arrive inside the terminate loop")
    try runLidSaveFailureChecks()
    print("PASS: saved lid protection on external power retries an ended session after 30 s, at most 3 times, restored by power/lid changes or a stable session; never on battery; watchdog keeps protection through stalls shorter than its 3 s lease; restart handoff results arrive inside a main-queue terminate loop")
}

/// Failed saves never lose or resurrect lid state: an unsavable sleep notice
/// keeps the saved one, and an unsavable countdown clears the stale saved one.
func runLidSaveFailureChecks() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let suite = "perch.lid-save-failure." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { throw AppError(message: "Isolated defaults are unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    let notice = LidSleepNotice(defaults: defaults)
    let saved = LidSleepIncident(began: Date(timeIntervalSinceReferenceDate: 1000), power: .external, protectionRequested: true)
    notice.pending = saved
    notice.pending = LidSleepIncident(began: Date(timeIntervalSinceReferenceDate: .nan), power: .battery, protectionRequested: nil)
    try check(notice.pending == saved, "A sleep notice that could not be saved erased the pending notice")
    notice.pending = nil
    try check(notice.pending == nil, "Acknowledging a sleep notice did not clear it")
    let countdown = LidCountdown(now: 100, closed: true, restoreSession: false)
    LidCountdownController.save(countdown, to: defaults)
    try check(defaults.codable(LidCountdown.self, forKey: "sleep.countdown.last") == countdown, "A countdown was not saved for relaunch")
    LidCountdownController.save(LidCountdown(now: .nan, closed: false, restoreSession: false), to: defaults)
    try check(defaults.data(forKey: "sleep.countdown.last") == nil, "A countdown that could not be saved left an older one to restore")
}
