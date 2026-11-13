import Foundation

/// Switches back on the launch jobs the Agent Kill Switch switched off, so
/// removing that feature can never leave someone's apps unable to start.
/// Commands are injected so disk failure and retry can be tested without
/// launchd.
enum AgentJobRecovery {
    /// Persist the release before re-enabling anything, and keep any job that
    /// could not be re-enabled on the list so the next start tries again.
    static func resume(state: inout SafetyState, persist: (SafetyState) throws -> Void,
                       enable: (String) -> String) throws -> [String] {
        var released = state
        released.locked = false
        try persist(released)
        state = released
        let failed = released.disabledJobs.filter { enable($0) != "ok" }
        var completed = released
        completed.disabledJobs = failed
        // If this write fails, keep the saved recovery list available for retry.
        try persist(completed)
        state = completed
        return failed
    }
}
