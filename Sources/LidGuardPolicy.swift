import Foundation

enum LidPower: String, Codable { case external, battery, unknown }
struct LidObservation: Equatable {
    var closed: Bool?
    var power: LidPower
}

enum LidGuardStart {
    /// A new session may start remotely on a powered, closed Mac. Starting on
    /// battery still needs an open lid; an existing session keeps its 60s grace.
    static func validate(_ observation: LidObservation) throws {
        guard observation.closed != nil, observation.power != .unknown else {
            throw AppError(message: "Perch could not read the lid and power state. Review lid protection before enabling it.")
        }
        guard observation.closed == false || observation.power == .external else {
            throw AppError(message: "Connect external power or open the lid before starting lid protection.")
        }
    }
}
struct LidGuardDecision: Equatable {
    var preventLidSleep: Bool
    var requestSleep: Bool
    var remaining: Int?
    var detail: String
}
struct LidGuardPolicy {
    static let grace: Double = 60
    private(set) var deadline: Double?
    private(set) var stopped = false
    private(set) var sleepInterruption: String?
    private var lastNow: Double?
    private var externalSince: Double?
    private(set) var countdown: LidCountdown?
    private var countdownEndHandled = false
    var countdownControlsDecision: Bool { countdown != nil && (countdown!.active || !countdownEndHandled) }
    mutating func adjustCountdown(_ direction: Int, now: Double, observation: LidObservation, restoreSession: Bool) throws {
        guard [-1, 0, 1].contains(direction), now.isFinite, now >= 0, !stopped,
              observation.closed != nil, observation.power != .unknown else { throw AppError(message: "Lid protection is not ready for a countdown.") }
        countdown?.observe(closed: observation.closed, now: now)
        countdownEndHandled = false
        if direction == 0 { countdown?.finish(.cancelled, now: now) }
        else if countdown?.active == true { countdown?.adjust(direction, now: now) }
        else if direction > 0 { countdown = LidCountdown(now: now, closed: observation.closed == true, restoreSession: restoreSession) }
    }
    mutating func acceptCountdown(_ value: LidCountdown?) {
        guard let value else { return }
        if let current = countdown, current.id == value.id {
            guard current.active else { return }
            var merged = value; merged.retainClosedObservation(current)
            countdown = merged
        } else { countdown = value; countdownEndHandled = false }
    }
    /// An armed source already handled a finished countdown. Preserve its
    /// frozen display value without applying its completion a second time.
    mutating func restoreMaintenance(deadline: Double?, countdown: LidCountdown?) {
        constrainDeadline(deadline)
        acceptCountdown(countdown)
        if countdown?.active == false { countdownEndHandled = true }
    }
    mutating func constrainDeadline(_ value: Double?) { if let value, value.isFinite { deadline = min(deadline ?? value, value) } }
    mutating func interruptCountdown(now: Double) { countdown?.finish(.interrupted, now: now) }
    mutating func systemSleepBegan(now: Double? = nil) {
        countdown?.finish(.interrupted, now: now ?? lastNow ?? 0)
        stopped = true
        sleepInterruption = "macOS began sleep while lid mode was requested. The session stopped. Review Lid activity, then enable it again."
    }
    mutating func step(_ observation: LidObservation, now: Double, authorized: Bool) -> LidGuardDecision {
        let timeValid = now.isFinite && now >= 0 && (lastNow == nil || now >= lastNow!)
        lastNow = now
        if !authorized || !timeValid { stopped = true }
        if observation.closed == false { deadline = nil }
        if observation.power == .external {
            if externalSince == nil { externalSince = now }
            if now - externalSince! >= 5 { deadline = nil }
        } else { externalSince = nil }
        let known = observation.closed != nil && observation.power != .unknown
        if !known { stopped = true }
        if timeValid { countdown?.observe(closed: observation.closed, now: now) }
        if stopped { countdown?.finish(.interrupted, now: timeValid ? now : 0) }
        if !stopped, let countdown {
            if countdown.active {
                return .init(preventLidSleep: true, requestSleep: false, remaining: countdown.remaining(at: now), detail: "Perch countdown: \(LidCountdown.clockText(countdown.remaining(at: now))) remaining. Opening the lid finishes it.")
            }
            if !countdownEndHandled {
                countdownEndHandled = true
                deadline = nil
                if observation.closed != false && observation.power != .external || !countdown.restoreSession { stopped = true }
                if stopped {
                    return .init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external,
                                 remaining: countdown.frozen, detail: "Perch countdown finished: \(countdown.end!.rawValue). Normal sleep behavior restored.")
                }
            }
        }
        if stopped {
            if let sleepInterruption {
                // macOS has already announced sleep. Release our command, but
                // do not add a second sleep request or obscure the first cause.
                return .init(preventLidSleep: false, requestSleep: false, remaining: nil, detail: sleepInterruption)
            }
            return .init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external, remaining: nil,
                         detail: known ? "Lid protection stopped. Enable it again with the lid open or external power connected." : "Lid or power status is unknown. Sleep protection has been released; check the Mac.")
        }
        if observation.closed == true && observation.power == .battery {
            if deadline == nil { deadline = now + Self.grace }
            if now >= deadline! {
                stopped = true
                return .init(preventLidSleep: false, requestSleep: true, remaining: 0, detail: "The lid stayed closed on battery for 60 seconds. Requesting sleep.")
            }
            let remaining = Int(ceil(deadline! - now))
            return .init(preventLidSleep: true, requestSleep: false, remaining: remaining, detail: "\(remaining) seconds to open the lid or reconnect power before Perch requests sleep.")
        }
        // Power cancels enforcement. Require five stable seconds before clearing
        // the old deadline so repeated brief dock/power flapping cannot extend it.
        return .init(preventLidSleep: true, requestSleep: false, remaining: nil,
                     detail: observation.closed == true ? "Lid closed on external power. Unplugging starts 60 seconds to open it or reconnect power." : "Closed on external power: request keep awake. Closed on battery: 60 seconds to open the lid or reconnect power.")
    }
}
