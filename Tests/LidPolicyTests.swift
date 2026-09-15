import Foundation

/// Pure policy tests: no app, real clock, system queries, power adapter or sleeps.
func runLidPolicyTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) throws {
        if !condition() { throw AppError(message: message()) }
    }
    func rejects(_ action: () throws -> Void) -> Bool {
        do { try action(); return false } catch { return true }
    }
    let battery = LidObservation(closed: true, power: .battery)
    let plugged = LidObservation(closed: true, power: .external)
    let observations = [false, true, nil].flatMap { closed in
        [LidPower.external, .battery, .unknown].map { LidObservation(closed: closed, power: $0) }
    }
    // Every known/unknown lid × power startup combination.
    for observation in observations {
        let allowed = observation.closed != nil && observation.power != .unknown &&
            (observation.closed == false || observation.power == .external)
        try check(rejects { try LidGuardStart.validate(observation) } != allowed, "Startup: \(observation)")
    }

    // All observation/authorization/time sequences through depth three. This
    // explores prefixes too, including same-tick events and 60-minute stalls.
    // Properties are independent safety constraints, not a second policy copy.
    var transitions = 0
    func explore(_ policy: LidGuardPolicy, now: Double, depth: Int, trace: String) throws {
        guard depth > 0 else { return }
        for observation in observations {
            for authorized in [false, true] {
                for delta in [0.0, 1, 60, 3600] {
                    var next = policy
                    let time = now + delta
                    let result = next.step(observation, now: time, authorized: authorized)
                    transitions += 1
                    let description = "\(trace) → \(observation)/authorized=\(authorized)@\(time)"
                    try check(!(result.preventLidSleep && result.requestSleep), description)
                    try check(!policy.stopped || next.stopped, "Stopped session revived: \(description)")
                    try check(!next.stopped || !result.preventLidSleep, "Stopped session armed: \(description)")
                    try check(authorized || !result.preventLidSleep, "Lost authorization: \(description)")
                    try check((observation.closed != nil && observation.power != .unknown) || !result.preventLidSleep,
                              "Unknown sensors: \(description)")
                    try check(!result.requestSleep || (observation.closed != false && observation.power != .external),
                              "Sleep with open lid or external power: \(description)")
                    if let remaining = result.remaining {
                        try check((0...60).contains(remaining), "Unbounded countdown: \(description)")
                        try check(observation == battery, "Countdown outside closed battery: \(description)")
                    }
                    if observation == battery, let deadline = policy.deadline, !policy.stopped {
                        try check(next.deadline == deadline, "Battery event extended deadline: \(description)")
                        if time >= deadline { try check(!result.preventLidSleep && result.requestSleep, "Missed expiry: \(description)") }
                    }
                    try explore(next, now: time, depth: depth - 1, trace: description)
                }
            }
        }
    }
    try explore(LidGuardPolicy(), now: 0, depth: 3, trace: "new session")

    // Exact expiry and external-power stabilization boundaries, including power
    // arriving at expiry. Each row starts from a fresh, independent session.
    for time in [0.0, 0.001, 1, 59, 59.999, 60, 60.001, 1200, 3600] {
        for observation in observations {
            for authorized in [false, true] {
                var policy = LidGuardPolicy()
                _ = policy.step(battery, now: 0, authorized: true)
                let result = policy.step(observation, now: time, authorized: authorized)
                let known = observation.closed != nil && observation.power != .unknown
                let expired = observation == battery && time >= 60
                let expectedActive = authorized && known && !expired
                try check(result.preventLidSleep == expectedActive, "Boundary \(time): \(observation), auth=\(authorized)")
                try check(result.requestSleep == (!expectedActive && observation.closed != false && observation.power != .external),
                          "Boundary sleep decision \(time): \(observation)")
                if observation == battery && expectedActive {
                    try check(result.remaining == Int(ceil(60 - time)), "Countdown rounding at \(time)")
                }
            }
        }
    }
    for stable in [0.0, 4.999, 5, 5.001] {
        var policy = LidGuardPolicy()
        _ = policy.step(battery, now: 0, authorized: true)
        _ = policy.step(plugged, now: 10, authorized: true)
        _ = policy.step(plugged, now: 10 + stable, authorized: true)
        let result = policy.step(battery, now: 20, authorized: true)
        try check(result.remaining == (stable >= 5 ? 60 : 40), "Power stability boundary \(stable)")
    }
    var flapping = LidGuardPolicy()
    _ = flapping.step(battery, now: 0, authorized: true)
    for second in 1...60 {
        _ = flapping.step(second % 2 == 0 ? battery : plugged, now: Double(second), authorized: true)
    }
    try check(flapping.stopped, "Repeated power flaps prevented expiry")
    for invalid in [-1.0, 9, Double.nan, .infinity, -.infinity] {
        var policy = LidGuardPolicy()
        _ = policy.step(battery, now: 10, authorized: true)
        try check(policy.step(battery, now: invalid, authorized: true).requestSleep, "Invalid clock retained protection")
        try check(!policy.step(plugged, now: 11, authorized: true).preventLidSleep, "Clock recovery revived a stopped session")
    }
    for observation in observations {
        var policy = LidGuardPolicy()
        _ = policy.step(battery, now: 0, authorized: true)
        policy.systemSleepBegan()
        for time in [1.0, 60, 3600] {
            let result = policy.step(observation, now: time, authorized: true)
            try check(!result.preventLidSleep && !result.requestSleep, "Sleep/wake revived protection or requested duplicate sleep")
        }
    }

    // Watchdog must retain the earliest deadline and never revive a stopped
    // token, even with a healthy transport and repeated later deadline offers.
    let token = UUID().uuidString
    for alive in [false, true] {
        for time in [0.0, 2.999, 3, 3.001, 3600] {
            var watchdog = LidGuardWatchdogState()
            try check(watchdog.receive(.init(token: token, expires: 3, deadline: 60), now: 0), "Valid lease rejected")
            let result = watchdog.evaluate(battery, now: time, channelAlive: alive)
            try check(result.preventLidSleep == (alive && time < 3), "Lease expiry/channel boundary")
            if !result.preventLidSleep {
                _ = watchdog.receive(.init(token: token, expires: time + 3, deadline: time + 60), now: time)
                try check(!watchdog.evaluate(battery, now: time, channelAlive: true).preventLidSleep, "Late renewal revived stopped token")
            }
        }
    }
    var watchdog = LidGuardWatchdogState()
    for second in 0...60 {
        let now = Double(second)
        try check(watchdog.receive(.init(token: token, expires: now + 3, deadline: now + 60), now: now), "Healthy renewal rejected")
        let result = watchdog.evaluate(battery, now: now, channelAlive: true)
        try check(result.preventLidSleep == (second < 60), "Renewal extended battery deadline")
    }
    for badLease in [LidGuardLease(token: "invalid", expires: 3, deadline: 60),
                     .init(token: token, expires: 7, deadline: 60),
                     .init(token: token, expires: .nan, deadline: 60),
                     .init(token: token, expires: 3, deadline: .infinity),
                     .init(token: token, expires: 3, deadline: -1)] {
        var watcher = LidGuardWatchdogState()
        try check(!watcher.receive(badLease, now: 0), "Malformed watchdog lease accepted")
    }

    // Restart allowance is independent of the existing battery deadline.
    let identity = String(repeating: "a", count: 40)
    for time in [0.0, 59.999, 60, 3600] {
        var handoff = LidRestartHandoff()
        let ticket = try handoff.prepare(identity: identity, now: 0, active: true)
        for active in [false, true] {
            var trial = handoff
            let rejected = rejects { try trial.claim(ticket.id, pinnedConnection: ticket.id, now: time, active: active) }
            try check(rejected == (!active || time >= 60), "Restart claim boundary")
            if !rejected {
                try check(rejects { try trial.claim(ticket.id, pinnedConnection: ticket.id, now: time, active: true) }, "Ticket replay accepted")
            }
        }
        if time < 60 {
            let repeated = try handoff.prepare(identity: identity, now: time, active: true)
            try check(repeated == ticket, "Restart retry extended ticket")
        }
    }
    try runLidEnforcerMatrixTests()
    print("PASS: \(transitions) generated policy transitions (all paths through depth 3); startup, expiry/stability boundaries, invalid clocks, flapping, sleep/wake, watchdog and restart matrices; virtual time only")
}

private func runLidEnforcerMatrixTests() throws {
    final class Hardware: LidGuardHardware {
        var calls: [String] = []
        var fail: String?
        func observe() -> LidObservation { .init(closed: true, power: .battery) }
        func call(_ name: String) throws { calls.append(name); if fail == name { throw AppError(message: name) } }
        func preventLidSleep(_ enabled: Bool) throws { try call(enabled ? "on" : "off") }
        func requestSleep() throws { try call("sleep") }
        func verifyLidSleepPrevention() throws { try call("verify") }
    }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let on = LidGuardDecision(preventLidSleep: true, requestSleep: false, remaining: 60, detail: "")
    let off = LidGuardDecision(preventLidSleep: false, requestSleep: true, remaining: 0, detail: "")
    for failure in ["on", "verify", "off", "sleep"] {
        let hardware = Hardware(), enforcer = LidGuardEnforcer(hardware)
        if failure == "off" || failure == "sleep" { try enforcer.apply(on, now: 0) }
        hardware.calls = []; hardware.fail = failure
        var threw = false
        do { try enforcer.apply(failure == "on" || failure == "verify" ? on : off, now: 60) } catch { threw = true }
        try check(threw, "Hardware failure not propagated: \(failure)")
        let expected = ["on": ["on", "off"], "verify": ["on", "verify"], "off": ["off"], "sleep": ["off", "sleep"]]
        try check(hardware.calls == expected[failure], "Failure command ordering: \(failure), \(hardware.calls)")
        hardware.fail = nil; hardware.calls = []
        try enforcer.apply(off, now: 61, forceRelease: true)
        try check(hardware.calls == ["off", "sleep"] && !enforcer.preventing, "Recovery must release before sleep")
        hardware.calls = []
        try enforcer.apply(off, now: 65.999)
        try check(hardware.calls.isEmpty, "Successful sleep command retried too early")
        try enforcer.apply(off, now: 66)
        try check(hardware.calls == ["sleep"], "Sleep retry missing at five-second boundary")
    }
}
