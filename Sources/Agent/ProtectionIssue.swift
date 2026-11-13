import Foundation

/// The one problem with Perch's background helpers worth showing on the
/// Settings menu item, if any.
///
/// None of these is critical any more. A dead or outdated helper used to mean
/// the Agent Kill Switch could not act, so Perch treated it as critical and
/// opened Settings by itself. With that feature removed the helper only keeps
/// the Mac awake and puts back desk screens, and Perch already repairs and
/// updates it automatically, so the problem is shown as a fact on Settings…
/// rather than by opening a window.
struct ProtectionIssue: Equatable {
    enum Severity { case warning, critical }
    let severity: Severity
    let title: String
    let detail: String
    let route: String
    static func assess(_ state: SafetyStatus?, config: SafetyConfiguration,
                       watcherInstalled: Bool = RetiredProcessWatcher.installed()) -> ProtectionIssue? {
        // First, because only the person can remove it and it costs the Mac
        // every second it runs; the helper problems below repair themselves.
        if watcherInstalled {
            return .init(severity: .warning, title: "Old process watcher still installed", detail: "Perch no longer watches processes, but the watcher it installed is still running on this Mac. Open Setup to remove it; macOS asks for your administrator password.", route: "watcher")
        }
        if let state, !state.compatible {
            return .init(severity: .warning, title: "Background helper needs updating", detail: "The running helper does not match this version of Perch. Perch updates installed helpers automatically. Open Background helpers in Setup to see progress.", route: "repair")
        }
        guard let state, state.fresh else {
            return .init(severity: .warning, title: "Background helper not responding", detail: "Keep awake and putting back desk screens wait for it. Perch attempts recovery automatically. Open Background helpers in Setup to see progress.", route: "repair")
        }
        if config.reverseTrackpad || config.reverseWheel || config.navigation?.enabled == true || config.keypadNavigation == true {
            let input = InputReadiness.assess(state, config: config)
            if !input.ready { return .init(severity: .warning, title: input.title, detail: input.message, route: input.route) }
        }
        if let error = state.error { return .init(severity: .warning, title: "Background helper needs attention", detail: error, route: "repair") }
        return nil
    }
}

func runProtectionIssueTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var config = SafetyConfiguration()
    var state = SafetyStatus(inputTrusted: true, inputActive: true, keepAwakeActive: false, message: "", error: nil)
    try check(ProtectionIssue.assess(state, config: config, watcherInstalled: false) == nil, "A healthy helper reported a problem")
    // Perch repairs the helper on its own, so nothing here opens a window.
    try check(ProtectionIssue.assess(nil, config: config, watcherInstalled: false)?.severity == .warning, "A helper not responding was treated as critical")
    config.reverseWheel = true
    state.inputTrusted = nil
    try check(ProtectionIssue.assess(state, config: config, watcherInstalled: false)?.route == "repair", "Unconfirmed input access did not route to repair")
    state.inputTrusted = false
    try check(ProtectionIssue.assess(state, config: config, watcherInstalled: false)?.route == "input", "Missing input access did not route to keyboard access")
    state.helperBuild = "previous-build"
    let stale = ProtectionIssue.assess(state, config: config, watcherInstalled: false)
    try check(!state.fresh && stale?.route == "repair" && stale?.severity == .warning, "An outdated helper was not routed to repair as a warning")
    // The old process watcher comes first: only the person can remove it.
    let watcher = ProtectionIssue.assess(state, config: config, watcherInstalled: true)
    try check(watcher?.route == "watcher" && watcher?.severity == .warning, "An installed process watcher was not shown first")
    try check(RetiredProcessWatcher.installed(exists: { _ in false }) == false && RetiredProcessWatcher.installed(exists: { $0 == RetiredProcessWatcher.job }),
              "The process watcher's presence was misjudged")
    try check(RetiredProcessWatcher.removalCommand.contains("bootout system/local.scott.perch.events") &&
              RetiredProcessWatcher.removalCommand.contains("'/Library/Application Support/Perch Events'"),
              "Removing the process watcher would not stop it and delete its folder: \(RetiredProcessWatcher.removalCommand)")
    var invalid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    invalid.removeValue(forKey: "helperBuild")
    try check((try? JSONDecoder().decode(SafetyStatus.self, from: JSONSerialization.data(withJSONObject: invalid))) == nil, "A status with no helper build decoded")
    print("PASS: helper health is shown as a warning, never by opening a window; the old process watcher is named first with its removal; outdated and silent helpers route to repair; input access problems route to keyboard access")
}
