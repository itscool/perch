import Foundation

/// Backoff for a peer that has no authenticated route. A pending attempt is
/// tracked separately, so this delay is only used after that attempt closes.
enum KVMReconnectPolicy {
    static let maximumDelay: TimeInterval = 60

    static func delay(failures: Int) -> TimeInterval {
        let count = max(1, min(failures, 7))
        return min(maximumDelay, pow(2, Double(count - 1)))
    }
}
