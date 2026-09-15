import Foundation

enum LidCountdownLimits {
    static let step: Double = 5 * 60
    static let maximum: Double = 20 * 60
}

/// A single absolute deadline. Only a deliberate adjustment changes it.
struct LidCountdown: Codable, Equatable {
    enum End: String, Codable { case opened, expired, cancelled, interrupted }
    var id = UUID()
    private(set) var deadline: Double
    private(set) var sawClosed: Bool
    private(set) var end: End?
    private(set) var frozen: Int?
    let restoreSession: Bool
    var active: Bool { end == nil }
    mutating func retainClosedObservation(_ other: LidCountdown) { sawClosed = sawClosed || other.sawClosed }
    init(now: Double, closed: Bool, restoreSession: Bool) {
        deadline = now + LidCountdownLimits.step; sawClosed = closed
        self.restoreSession = restoreSession
    }
    func remaining(at now: Double) -> Int {
        frozen ?? Int(ceil(max(0, min(LidCountdownLimits.maximum, deadline - now))))
    }
    mutating func finish(_ reason: End, now: Double) {
        guard active else { return }
        frozen = (reason == .expired || reason == .cancelled) ? 0 : remaining(at: now); end = reason
    }
    mutating func observe(closed: Bool?, now: Double) {
        guard active else { return }
        // Expiry wins when opening and expiry are observed together.
        if now >= deadline { finish(.expired, now: now) }
        else if closed == true { sawClosed = true }
        else if closed == false && sawClosed { finish(.opened, now: now) }
    }
    mutating func adjust(_ direction: Int, now: Double) {
        guard active else { return }
        deadline = now + min(LidCountdownLimits.maximum, max(0, deadline - now + Double(direction) * LidCountdownLimits.step))
        if deadline <= now { finish(.expired, now: now) }
    }
    static func clockText(_ remaining: Int) -> String { String(format: "%d:%02d", max(0, remaining) / 60, max(0, remaining) % 60) }
}
