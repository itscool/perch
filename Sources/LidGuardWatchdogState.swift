import Foundation

struct LidGuardLease: Codable {
    var token: String?; var expires: Double; var deadline: Double?
    func acceptsRenewal(_ supplied: String, now: Double) -> Bool { token == supplied && expires.isFinite && now.isFinite && now >= 0 && now < expires }
}
struct LidGuardAck: Codable { var token: String?; var time: Double; var allowed: Bool }
struct LidGuardWatchdogState {
    private(set) var lease = LidGuardLease(token: nil, expires: 0, deadline: nil)
    private var policy = LidGuardPolicy()
    mutating func receive(_ next: LidGuardLease, now: Double) -> Bool {
        guard next.expires.isFinite, next.expires >= 0, next.expires <= now + 6,
              next.token == nil || UUID(uuidString: next.token!) != nil,
              next.deadline == nil || (next.deadline!.isFinite && next.deadline! >= 0) else { return false }
        if next.token != lease.token { policy = LidGuardPolicy() }
        lease = next; return true
    }
    mutating func evaluate(_ observation: LidObservation, now: Double, channelAlive: Bool) -> LidGuardDecision {
        policy.constrainDeadline(lease.deadline)
        return policy.step(observation, now: now, authorized: channelAlive && lease.expires > now && lease.token != nil)
    }
}

