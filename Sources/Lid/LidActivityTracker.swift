import Foundation

/// Produces meaningful transitions, not a copy of every quarter-second poll.
/// Durations use the same continuous clock as enforcement, never wall-clock time.
struct LidActivityTracker {
    private var previous: LidObservation?
    private var closedAt: Double?
    private var batteryAt: Double?
    private var activeCountdown = false
    private var previousDeadline: Double?
    private var lastDecision: String?
    static func seconds(_ elapsed: Double) -> String { String(format: "%.1f seconds", max(0, elapsed)) }
    mutating func observe(_ observation: LidObservation, now: Double) -> [String] {
        defer { previous = observation }
        guard let previous else {
            return ["Observation started: lid \(observation.closed.map { $0 ? "closed" : "open" } ?? "unknown"); \(powerDescription(observation.power)). Earlier changes were not observed."]
        }
        var messages: [String] = []
        if observation.closed != previous.closed {
            switch observation.closed {
            case true:
                closedAt = now; messages.append("Lid closed.")
            case false:
                messages.append(closedAt.map { "Lid opened after \(Self.seconds(now - $0)) closed." } ?? "Lid opened; time closed was not observed.")
                closedAt = nil
            case nil: messages.append("Lid state is unavailable."); closedAt = nil
            }
        }
        if observation.power != previous.power {
            switch observation.power {
            case .battery:
                batteryAt = now
                messages.append(previous.power == .external ? "Unplugged; now on battery." : "Battery power observed.")
            case .external:
                messages.append(batteryAt.map { "Plugged in after \(Self.seconds(now - $0)) on battery." } ?? "External power connected; time unplugged was not observed.")
                batteryAt = nil
            case .unknown: messages.append("Power source is unavailable."); batteryAt = nil
            }
        }
        return messages
    }
    private func powerDescription(_ power: LidPower) -> String {
        switch power { case .external: return "plugged in"; case .battery: return "on battery"; case .unknown: return "power source unknown" }
    }
    mutating func decision(_ decision: LidGuardDecision, observation: LidObservation, deadline: Double?, now: Double) -> [String] {
        var messages: [String] = []
        let counting = decision.preventLidSleep && decision.remaining != nil
        if counting && !activeCountdown {
            if deadline == previousDeadline, let deadline {
                messages.append("Back on battery with the lid closed; continuing the original interval (\(Self.seconds(deadline-now)) remaining).")
            } else {
                messages.append("Lid closed on battery. Starting 60 seconds to open the lid or reconnect power.")
            }
        } else if activeCountdown && !counting && decision.preventLidSleep {
            if observation.closed == false {
                let elapsed = previousDeadline.map { now - ($0-LidGuardPolicy.grace) } ?? 0
                messages.append("Lid opened after \(Self.seconds(elapsed)) of the battery interval. Countdown cancelled.")
            } else if observation.power == .external {
                let elapsed = previousDeadline.map { now - ($0-LidGuardPolicy.grace) } ?? 0
                messages.append("Power connected after \(Self.seconds(elapsed)) of the battery interval. Countdown paused; five stable seconds on power clears it.")
            }
        }
        if previousDeadline != nil && deadline == nil && observation.closed == true && observation.power == .external && decision.preventLidSleep {
            messages.append("External power stayed connected for five seconds. Battery interval cleared.")
        }
        let key = decision.requestSleep ? "sleep" : decision.preventLidSleep ? "enabled" : "stopped"
        if key != lastDecision {
            if decision.requestSleep {
                messages.append(decision.remaining == 0 ? "Lid not opened and external power not restored within 60 seconds. Releasing lid protection and requesting sleep." : "Protection stopped while the lid was closed or unknown without confirmed external power. Releasing protection and requesting sleep.")
            } else if !decision.preventLidSleep { messages.append(decision.detail) }
            else if lastDecision == nil { messages.append("Lid protection session started.") }
        }
        activeCountdown = counting; previousDeadline = deadline; lastDecision = key
        return messages
    }
    mutating func endSession() { activeCountdown = false; previousDeadline = nil; lastDecision = nil }
}
