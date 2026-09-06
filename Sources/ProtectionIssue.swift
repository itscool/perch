import Foundation

struct ProtectionIssue: Equatable {
    enum Severity { case warning, critical }
    let severity: Severity
    let title: String
    let detail: String
    let route: String
    static func assess(_ state: SafetyStatus?, config: SafetyConfiguration) -> ProtectionIssue? {
        guard let state, state.fresh else { return .init(severity: .critical, title: "Panic protection unavailable", detail: "The background helper is not responding. Repair protection before relying on panic.", route: "repair") }
        if config.shortcut.enabled && !state.shortcutActive && state.testUntil == nil {
            return .init(severity: .critical, title: "Emergency shortcut unavailable", detail: "Your enabled panic shortcut is not registered. Menu panic is still available. Check the shortcut configuration and test it.", route: "shortcut")
        }
        if let error = state.error, error.contains("configuration is unreadable") || error.contains("Lockdown could not be saved") {
            return .init(severity: .critical, title: "Panic protection needs repair", detail: error, route: "repair")
        }
        if state.eventCoverage != nil && state.eventCoverage != "Process events active" {
            return .init(severity: .warning, title: (state.processEventCount ?? 0) == 0 ? "Finish process-event setup" : "Process-event coverage degraded", detail: (state.error ?? "Event collection has not passed its health check.") + " Panic remains available through snapshot tracking.", route: "events")
        }
        if config.reverseTrackpad || config.reverseWheel || config.swapModifiers {
            let input = InputReadiness.assess(state, config: config)
            if !input.ready { return .init(severity: .warning, title: input.title, detail: input.message, route: input.route) }
        }
        if let error = state.error { return .init(severity: .warning, title: "Protection needs attention", detail: error, route: "safety") }
        return nil
    }
}

func runProtectionIssueTests() throws {
    func check(_ b: Bool) throws { if !b { throw AppError(message: "Protection severity classification failed") } }
    var config = SafetyConfiguration(); config.shortcut.enabled = true
    var state = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: true, inputActive: true, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
    try check(ProtectionIssue.assess(nil, config: config)?.severity == .critical)
    try check(ProtectionIssue.assess(state, config: config) == nil)
    state.eventCoverage = "Degraded"; state.processEventCount = 0
    try check(ProtectionIssue.assess(state, config: config)?.severity == .warning)
    state.shortcutActive = false
    try check(ProtectionIssue.assess(state, config: config)?.title == "Emergency shortcut unavailable")
    config.shortcut.enabled = false
    try check(ProtectionIssue.assess(state, config: config)?.severity == .warning)
    state.eventCoverage = "Process events active"
    try check(ProtectionIssue.assess(state, config: config) == nil)
    config.reverseWheel = true
    state.inputTrusted = nil
    try check(ProtectionIssue.assess(state, config: config)?.route == "repair")
    state.inputTrusted = false
    try check(ProtectionIssue.assess(state, config: config)?.route == "input")
    print("PASS: critical helper/shortcut failure, warning-only event setup, intentional shortcut disablement, verified recovery")
}
