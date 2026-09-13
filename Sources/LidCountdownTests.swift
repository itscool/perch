import Foundation

func runLidCountdownTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw AppError(message: message) } }
    let open = LidObservation(closed: false, power: .battery)
    let closed = LidObservation(closed: true, power: .battery)
    let plugged = LidObservation(closed: true, power: .external)
    var timer = LidCountdown(now: 0, closed: false, restoreSession: false)
    timer.observe(closed: false, now: 1)
    try check(timer.active && timer.remaining(at: 1) == 299, "Starting with an open lid immediately finished")
    timer.adjust(1, now: 10)
    try check(timer.remaining(at: 10) == 590, "Plus restarted instead of adding to current remainder")
    timer.adjust(-1, now: 20)
    try check(timer.remaining(at: 20) == 280, "Minus did not subtract from current remainder")
    for _ in 0..<20 { timer.adjust(1, now: 20) }
    try check(timer.remaining(at: 20) == Int(LidCountdownLimits.maximum), "Repeated plus escaped shared cap")
    timer.observe(closed: true, now: 21); timer.observe(closed: false, now: 30)
    try check(timer.end == .opened && timer.remaining(at: 3600) == 1190, "Opening failed to freeze the remainder")
    timer.adjust(1, now: 3601)
    try check(timer.end == .opened, "A finished value was silently reactivated without a fresh identity")
    var latch = CountdownKeyLatch()
    try check(latch.press(1) && !latch.press(1) && latch.press(2), "Held key repeat was accepted")
    latch.release(1); try check(latch.press(1), "Deliberate second press was blocked")
    latch.clear(); try check(latch.press(1), "Changed registration retained a stuck key")

    var count = 0
    func explore(_ original: LidCountdown, now: Double, depth: Int) throws {
        guard depth > 0 else { return }
        for advance in [0.0, 1, 300, 3600] {
            for lid in [false, true, nil] {
                for action in [-1, 0, 1] {
                    let time = now + advance
                    var value = original
                    value.observe(closed: lid, now: time)
                    if action != 0 { value.adjust(action, now: time) }
                    count += 1
                    try check((0...Int(LidCountdownLimits.maximum)).contains(value.remaining(at: time)), "Generated timer escaped cap")
                    if !original.active { try check(value == original, "Generated finished timer changed") }
                    if value.active {
                        try check(value.deadline > time, "Generated active timer had expired")
                        try check(value.remaining(at: time + 1) <= value.remaining(at: time), "Time passing added remaining time")
                    }
                    try explore(value, now: time, depth: depth - 1)
                }
            }
        }
    }
    try explore(LidCountdown(now: 0, closed: false, restoreSession: false), now: 0, depth: 3)

    for restore in [false, true] {
        for expiry in [false, true] {
            for observation in [open, closed, plugged, LidObservation(closed: false, power: .external)] {
                var policy = LidGuardPolicy()
                _ = policy.step(open, now: 0, authorized: true)
                try policy.adjustCountdown(1, now: 0, observation: open, restoreSession: restore)
                _ = policy.step(closed, now: 1, authorized: true)
                let time = expiry ? 300.0 : 30
                let result = policy.step(observation, now: time, authorized: true)
                let ends = expiry || observation.closed == false
                if ends {
                    try check(policy.countdown?.end == (expiry ? .expired : .opened), "Wrong completion reason")
                    try check(policy.countdown?.remaining(at: 3600) == (expiry ? 0 : 270), "Finished countdown did not freeze")
                    try check(result.preventLidSleep == (restore && observation != closed), "Normal session restoration incorrect")
                    try check(result.requestSleep == (observation == closed), "Completion sleep decision incorrect")
                } else {
                    try check(result.preventLidSleep && policy.countdown?.deadline == 300, "Power changed the timer")
                }
            }
        }
    }
    for action in [0, -1] {
        for observation in [open, closed, plugged] {
            var policy = LidGuardPolicy()
            try policy.adjustCountdown(1, now: 0, observation: open, restoreSession: false)
            _ = policy.step(observation, now: 10, authorized: true)
            try policy.adjustCountdown(action, now: 20, observation: observation, restoreSession: false)
            let result = policy.step(observation, now: 20, authorized: true)
            try check(!result.preventLidSleep && result.requestSleep == (observation == closed), "Cancel/minus-zero failed to end protection")
            try check(policy.countdown?.remaining(at: 3600) == 0, "Cancel/minus-zero frozen display wrong")
        }
    }
    // A completed countdown may start afresh in an existing normal session.
    var normal = LidGuardPolicy()
    try normal.adjustCountdown(1, now: 0, observation: open, restoreSession: true)
    _ = normal.step(closed, now: 1, authorized: true)
    _ = normal.step(open, now: 2, authorized: true)
    let previous = normal.countdown!.id
    try normal.adjustCountdown(1, now: 3, observation: open, restoreSession: true)
    try check(normal.countdown?.id != previous && normal.countdown?.remaining(at: 3) == 300, "Finished hotkey restart reused old time or identity")
    try normal.adjustCountdown(0, now: 4, observation: open, restoreSession: true)
    _ = normal.step(open, now: 4, authorized: true)
    try check(!normal.countdownControlsDecision, "Completed countdown still owns normal-session reporting")
    let cancelledID = normal.countdown!.id
    try check(normal.countdown?.end == .cancelled && normal.countdown?.remaining(at: 4) == 0, "Cancel should display zero immediately")
    try normal.adjustCountdown(1, now: 5, observation: open, restoreSession: true)
    try check(normal.countdown?.id != cancelledID && normal.countdown?.remaining(at: 5) == 300, "Plus after cancellation failed to create a fresh five minutes")
    var cancelled = LidGuardPolicy()
    try cancelled.adjustCountdown(1, now: 0, observation: open, restoreSession: false)
    cancelled.systemSleepBegan(now: 40)
    let woke = cancelled.step(open, now: 400, authorized: true)
    try check(cancelled.countdown?.end == .interrupted && cancelled.countdown?.remaining(at: 400) == 260 && !woke.preventLidSleep, "Unexpected sleep lost frozen time or rearmed")

    // Helper and watchdog independently follow the same absolute deadline,
    // including explicit extension, subtraction and repeated stale status.
    for restore in [false, true] {
        var helper = LidGuardPolicy(), watchdog = LidGuardWatchdogState()
        let token = UUID().uuidString
        try helper.adjustCountdown(1, now: 0, observation: open, restoreSession: restore)
        for second in 0...600 {
            let now = Double(second)
            if second == 200 { try helper.adjustCountdown(1, now: now, observation: closed, restoreSession: restore) }
            let observation = second == 0 ? open : closed
            let expected = helper.step(observation, now: now, authorized: true)
            try check(watchdog.receive(.init(token: token, expires: now + 3, deadline: helper.deadline, countdown: helper.countdown), now: now), "Watchdog rejected bounded countdown")
            let actual = watchdog.evaluate(observation, now: now, channelAlive: true)
            try check(expected.preventLidSleep == actual.preventLidSleep && expected.requestSleep == actual.requestSleep, "Helper/watchdog disagree at \(second)")
        }
    }
    print("PASS: \(count) generated countdown transitions; +/−, shared cap, frozen completion, power changes, cancel, restart, repeat filtering, sleep and helper/watchdog deadlines")
}
