import Foundation

func runLidMaintenanceTests() throws {
    func check(_ value: Bool, _ detail: String) throws { if !value { throw AppError(message: detail) } }
    let token = UUID().uuidString
    var compatible = LidGuardStatus(updatedAt: LidGuardClock.now, armed: false, detail: "Ready")
    compatible.codeIdentity = "previous-compatible-app-build"
    try check(LidAutomaticResume.helperReady(compatible, pending: false), "App-only updates disabled automatic resume with a compatible helper")
    try check(!LidAutomaticResume.helperReady(compatible, pending: true), "Pending helper replacement allowed a new session")
    compatible.helperVersion = LidGuardCompatibility.helperVersion - 1
    try check(!LidAutomaticResume.helperReady(compatible, pending: false), "Outdated helper allowed automatic resume")
    for closed in [false, true, nil] as [Bool?] {
        for power in [LidPower.external, .battery, .unknown] {
            for bits in 0..<64 {
                let wanted = bits & 1 != 0, ready = bits & 2 != 0, active = bits & 4 != 0
                let countdown = bits & 8 != 0, busy = bits & 16 != 0, clean = bits & 32 != 0
                var automatic = LidAutomaticResume()
                let observation = LidObservation(closed: closed, power: power)
                let expected = wanted && ready && !active && !countdown && !busy && clean && closed != nil && power != .unknown && (closed == false || power == .external)
                let start = automatic.shouldStart(observation: observation, wanted: wanted, ready: ready, active: active, countdown: countdown, busy: busy, clean: clean)
                try check(start == expected, "Automatic resume changed an active timer, bypassed readiness or started closed on battery")
                if start {
                    try check(!automatic.shouldStart(observation: observation, wanted: wanted, ready: ready, active: false, countdown: false, busy: false, clean: true), "Failed resume or repeated polling retried without a new safe transition")
                }
            }
        }
    }
    for recoverByOpening in [false, true] {
        var automatic = LidAutomaticResume()
        _ = automatic.shouldStart(observation: .init(closed: true, power: .battery), wanted: true, ready: true, active: true, countdown: false, busy: false, clean: true)
        for _ in 0..<100 {
            try check(!automatic.shouldStart(observation: .init(closed: true, power: .battery), wanted: true, ready: true, active: false, countdown: false, busy: false, clean: true), "An expired closed-lid battery session restarted automatically")
        }
        let safe = LidObservation(closed: !recoverByOpening, power: recoverByOpening ? .battery : .external)
        try check(!automatic.shouldStart(observation: safe, wanted: true, ready: true, active: false, countdown: false, busy: false, clean: false), "Automatic resume interrupted pending cleanup")
        try check(automatic.shouldStart(observation: safe, wanted: true, ready: true, active: false, countdown: false, busy: false, clean: true), "Opening the lid or connecting power still required a Resume button")
        automatic.repaired()
        try check(automatic.shouldStart(observation: safe, wanted: true, ready: true, active: false, countdown: false, busy: false, clean: true), "Successful helper repair failed to restore saved intent")
    }
    for delay in [0, 1, 9, 10, 20] {
        var now = 100.0, reaped = false, released = false
        let accepted: Bool
        do {
            try LidMaintenance.waitForUnload(now: { now }, pause: { now += 1 }, reap: { reaped = true }, unloaded: {
                try check(reaped, "Waited for launchd before releasing its blocked helper process")
                released = now >= 100 + Double(delay)
                return released
            })
            accepted = true
        } catch { accepted = false }
        try check(accepted == (delay < 10), "Delayed launchd unload was rejected early or allowed beyond its bound")
        try check(accepted == released, "Helper replacement continued without confirmed unloading")
    }
    for invalidTime in [Double.nan, .infinity, 99] {
        var now = 100.0, refused = false
        do { try LidMaintenance.waitForUnload(now: { now }, pause: { now = invalidTime }, reap: {}, unloaded: { false }) }
        catch { refused = true }
        try check(refused, "Invalid clock extended helper unloading")
    }
    let base = LidMaintenanceRecord(token: token, previousToken: nil, boot: "boot", started: 100, expires: 160, resume: false, countdown: nil, batteryDeadline: nil)
    for now in [Double.nan, -.infinity, 99, 100, 159.999, 160, 161, .infinity] {
        for boot in ["boot", "reboot", ""] {
            try check(base.fresh(boot: boot, now: now) == (boot == "boot" && now >= 100 && now < 160), "Maintenance deadline/reboot boundary allowed indefinite protection")
        }
    }
    var extended = base; extended.expires = 161
    try check(!extended.fresh(boot: "boot", now: 110), "Maintenance allowance was renewed beyond its original limit")
    let observation = LidObservation(closed: true, power: .battery)
    let status = LidGuardStatus(updatedAt: 100, armed: true, remaining: 30, detail: "Fixture")
    let reply = LidGuardReply(status: status, token: token)
    let captured = try LidMaintenance.checkStart(observation: observation, disabled: true, previousToken: token, status: reply, now: 101)
    try check(captured.0 && captured.2 == 129, "Transfer extended the rounded battery deadline")
    var policy = LidGuardPolicy(); policy.constrainDeadline(captured.2)
    try check(policy.step(observation, now: 128.99, authorized: true).preventLidSleep, "Transferred battery session ended early")
    try check(!policy.step(observation, now: 129, authorized: true).preventLidSleep, "Transferred battery session restarted its timer")
    var manual = reply
    manual.status.countdown = LidCountdown(now: 100, closed: true, restoreSession: true)
    let countdown = try LidMaintenance.checkStart(observation: observation, disabled: true, previousToken: token, status: manual, now: 101)
    try check(countdown.1?.deadline == manual.status.countdown?.deadline && countdown.2 == nil, "Update restarted the manual countdown")
    for end in [LidCountdown.End.opened, .expired, .cancelled] {
        var finished = LidCountdown(now: 100, closed: true, restoreSession: true)
        finished.finish(end, now: 110)
        var resumed = LidGuardPolicy()
        resumed.restoreMaintenance(deadline: 150, countdown: finished)
        let result = resumed.step(observation, now: 120, authorized: true)
        try check(result.preventLidSleep && result.remaining == 30 && resumed.countdown == finished,
                  "A previously finished countdown ended the resumed normal lid session or lost its frozen result")
        try check(resumed.step(observation, now: 150, authorized: true).requestSleep,
                  "Finished-countdown history extended the normal battery deadline")
    }
    for closed in [false, true, nil] as [Bool?] {
        for power in [LidPower.external, .battery, .unknown] {
            for disabled in [false, true] {
                let obs = LidObservation(closed: closed, power: power)
                let accepted = (try? LidMaintenance.checkStart(observation: obs, disabled: disabled, previousToken: disabled ? token : nil, status: reply, now: 101)) != nil
                let expected = closed != nil && power != .unknown && (disabled || closed == false || power == .external)
                try check(accepted == expected, "Update start mishandled lid/power/owned-override combination")
            }
        }
    }
    for (previous, snapshot, now) in [(nil, Optional(reply), 101.0), (Optional(token), nil, 101.0), (Optional("different"), Optional(reply), 101.0), (Optional(token), Optional(reply), 99.0), (Optional(token), Optional(reply), 160.0), (Optional(token), Optional(reply), 129.0)] {
        try check((try? LidMaintenance.checkStart(observation: observation, disabled: true, previousToken: previous, status: snapshot, now: now)) == nil, "Unknown/stale/expired session gained an update allowance")
    }
    let script = try LidGuardInstall.installationCommand(source: URL(fileURLWithPath: "/fixture/Perch ' $(literal).app"), requirement: "identifier \"fixture\"", owner: 501, protectedUpdate: true)
    try check(!script.contains(" --lid-cleanup") && !script.contains(" --check-lid-update"), "Protected replacement still releases sleep or requires an open lid")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("perch-maintenance-shell-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try script.write(to: file, atomically: true, encoding: .utf8)
    let parser = Process(); parser.executableURL = URL(fileURLWithPath: "/bin/sh"); parser.arguments = ["-n", file.path]
    try parser.run(); parser.waitUntilExit()
    try check(parser.terminationStatus == 0, "Protected installer has invalid shell syntax")
    print("PASS: bounded helper-update allowance; original battery/countdown deadlines; lid/power/start matrix; stale/unowned/reboot/expiry refusal; protected installer syntax; no live power writes")
}
