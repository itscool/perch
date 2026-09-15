import Foundation

/// The lid supervisor and its watchdog exchange leases every 0.25 seconds and
/// treat a two-to-three-second gap as a hang. Neither may run in macOS's
/// background band, where timers are coalesced and CPU is throttled.
enum LidGuardScheduling {
    /// Leave Darwin background throttling and disable timer coalescing for the
    /// life of the returned activity. Idle system sleep stays allowed.
    static func makeResponsive(reason: String) -> NSObjectProtocol {
        _ = setpriority(PRIO_DARWIN_PROCESS, 0, 0)
        return ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: reason)
    }
    /// Whether this process is currently in the Darwin background band.
    static var throttled: Bool { getpriority(PRIO_DARWIN_PROCESS, 0) != 0 }
}
