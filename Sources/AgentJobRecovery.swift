import Foundation

/// Persist recovery intent before changing launch eligibility. Commands are
/// injected so disk failure and restart recovery can be tested without launchd.
enum AgentJobRecovery {
    static func disable(_ label: String, state: inout SafetyState,
                        persist: (SafetyState) throws -> Void, command: () -> String) throws -> String {
        guard !state.disabledJobs.contains(label) else { return "already recorded" }
        var reserved = state
        reserved.disabledJobs.append(label)
        try persist(reserved)
        state = reserved
        // A timeout/failure can be ambiguous; retain intent for Resume even then.
        return command()
    }
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
