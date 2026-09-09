import Foundation

/// Permission alone does not prove that the configured input controls are running.
struct InputReadiness {
    let ready: Bool
    let title: String
    let message: String
    let route: String

    static func assess(_ state: SafetyStatus?, config: SafetyConfiguration) -> Self {
        guard let state, state.fresh, let trusted = state.inputTrusted else {
            return assess(input: nil, config: config)
        }
        return assess(input: InputHelperStatus(trusted: trusted, active: state.inputActive), config: config)
    }
    static func assess(input: InputHelperStatus?, config: SafetyConfiguration, checking: Bool = false) -> Self {
        guard let input, input.fresh else {
            return .init(ready: false, title: checking ? "Checking input helper…" : "Input helper unavailable", message: checking ? "Checking the input helper. Accessibility access has not been determined." : "⚠ Waiting for the input helper. If this persists, repair background protection in Settings. Accessibility access has not been determined.", route: checking ? "checking" : "repair")
        }
        guard input.trusted else {
            return .init(ready: false, title: "Input access needed", message: "⚠ Waiting for Accessibility access for Perch Helper. Toggling an outdated entry may not grant access to this version.", route: "input")
        }
        let wanted = config.reverseTrackpad || config.reverseWheel || config.navigation?.enabled == true
        guard !wanted || input.active else {
            return .init(ready: false, title: "Input controls not running", message: "⚠ Accessibility granted, but the enabled input controls are not running. If this persists, repair background protection in Settings.", route: "repair")
        }
        return .init(ready: true, title: "Input controls ready", message: "✓ Accessibility granted. Input controls are ready.", route: "input")
    }
}
