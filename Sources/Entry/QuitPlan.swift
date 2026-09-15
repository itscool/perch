import Foundation

/// What a manual Quit turns off, worded for someone who knows Perch's
/// features rather than the helpers behind them. Only features that are on
/// right now appear, and Quit asks nothing when nothing would change.
struct QuitPlan: Equatable {
    struct Features: Equatable {
        var closedLid = false
        var keepAwake = false
        var preventIdleLock = false
        var scrolling = false
        var desk = false
        var panicShortcut = false
        var agentsBlocked = false
    }
    let stops: [String]
    let keeps: [String]
    /// An Agent Kill Switch block stays enforced until the person resumes it.
    let keepsGuardian: Bool

    init(_ features: Features) {
        var stops: [String] = []
        if features.closedLid { stops.append("Closing the lid will sleep your Mac") }
        if features.keepAwake { stops.append("Your Mac can go to sleep again") }
        if features.preventIdleLock { stops.append("Your Mac can lock when idle") }
        if features.scrolling { stops.append("Scrolling and navigation keys go back to normal") }
        if features.desk { stops.append("Desk switching and keyboard sharing stop") }
        if features.panicShortcut && !features.agentsBlocked { stops.append("The panic shortcut stops working") }
        self.stops = stops
        keepsGuardian = features.agentsBlocked
        keeps = (features.agentsBlocked ? ["Blocked agents stay blocked until you Resume"] : []) + ["Your settings are saved for next time"]
    }
    var needsConfirmation: Bool { !stops.isEmpty }
    var title: String { "Quit Perch?" }
    var detail: String {
        "Stops:\n" + stops.map { "• " + $0 }.joined(separator: "\n") + "\n\nKept:\n" + keeps.map { "• " + $0 }.joined(separator: "\n")
    }
}
