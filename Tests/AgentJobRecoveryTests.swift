import Foundation

func runAgentJobRecoveryTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    let original = SafetyState(locked: true, disabledJobs: [])
    var state = original, saved = original, commands: [String] = []
    var rejected = false
    do { _ = try AgentJobRecovery.disable("fixture", state: &state, persist: { _ in throw AppError(message: "disk full") }, command: { commands.append("disable"); return "ok" }) } catch { rejected = true }
    try check(rejected && commands.isEmpty && state == original, "Failed recovery reservation still disabled a job")
    _ = try AgentJobRecovery.disable("fixture", state: &state, persist: { saved = $0 }, command: {
        commands.append("disable")
        return saved.disabledJobs == ["fixture"] ? "ok" : "missing recovery"
    })
    try check(saved.disabledJobs == ["fixture"] && commands == ["disable"], "Disable was not preceded by a recoverable record")
    state = saved // Reconstruct after an interrupted operation.
    rejected = false; commands = []
    do { _ = try AgentJobRecovery.resume(state: &state, persist: { _ in throw AppError(message: "disk full") }, enable: { _ in commands.append("enable"); return "ok" }) } catch { rejected = true }
    try check(rejected && state.locked && commands.isEmpty, "Resume released blocking before its decision was saved")
    var writes = 0
    rejected = false
    do {
        _ = try AgentJobRecovery.resume(state: &state, persist: {
            writes += 1
            if writes == 2 { throw AppError(message: "final write failed") }
            saved = $0
        }, enable: { _ in commands.append("enable"); return "ok" })
    } catch { rejected = true }
    try check(rejected && !state.locked && !saved.locked && state.disabledJobs == ["fixture"] && saved.disabledJobs == ["fixture"], "Failed final save erased retry evidence or would restart lockdown")
    state = saved
    let failed = try AgentJobRecovery.resume(state: &state, persist: { saved = $0 }, enable: { _ in "ok" })
    try check(failed.isEmpty && !saved.locked && saved.disabledJobs.isEmpty, "Restarted Resume did not finish recovery")
    state = original
    _ = try AgentJobRecovery.disable("uncertain", state: &state, persist: { saved = $0 }, command: { "timeout" })
    try check(saved.disabledJobs == ["uncertain"], "Ambiguous command lost its recovery intent")
    let incomplete = try AgentJobRecovery.resume(state: &state, persist: { saved = $0 }, enable: { _ in "failed" })
    try check(incomplete == ["uncertain"] && saved.disabledJobs == incomplete && !saved.locked, "Failed enable was not retained for retry")
    print("PASS: launch-job save-before-disable, failed reservation/Resume, interrupted recovery, ambiguous command and partial enable; no launchd commands")
}
