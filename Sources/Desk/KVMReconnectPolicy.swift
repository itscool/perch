import Foundation

/// Backoff for a peer that has no authenticated route. A pending attempt is
/// tracked separately, so this delay is only used after that attempt closes.
enum KVMReconnectPolicy {
    /// Members that lost a route only need a short, growing pause; with one
    /// dialer and stale routes replaced on sight there is no storm to damp.
    static let maximumDelay: TimeInterval = 15

    static func delay(failures: Int) -> TimeInterval {
        let count = max(1, min(failures, 7))
        return min(maximumDelay, pow(2, Double(count - 1)))
    }
}
