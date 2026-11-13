import AppKit

/// A single final snapshot: a saved lid choice is not evidence of a live session.
struct SleepPresentation: Equatable {
    let awake: NSControl.StateValue
    let awakeEnabled: Bool
    let awakeHint: String
    let lid: NSControl.StateValue
    let lidEnabled: Bool
    let lidHint: String

    /// `outsidePerch`: macOS has sleep disabled and Perch did not do it, as a
    /// command or another app can. Perch neither takes it over nor turns it
    /// off, and says so as a fact rather than "unknown".
    init(ordinary: SleepStatus?, actualLid: NSControl.StateValue, savedLid: Bool,
         masterWanted: Bool, changing: Bool, remaining: Int?, outsidePerch: Bool = false) {
        awake = actualLid == .on ? .on : ordinary.map { $0.perchActive || $0.caffeinateActive ? .on : .off } ?? .mixed
        awakeEnabled = actualLid != .mixed && awake != .mixed && !changing
        // Each note says whose the state is: Perch's, caffeinate's, or set
        // outside Perch, as with pmset when Perch could not be used.
        awakeHint = actualLid == .on ? "On by Perch · lid closed too" : outsidePerch ? "Sleep disabled outside Perch" : awake == .mixed ? "Unavailable" : ordinary?.caffeinateActive == true ? "caffeinate active" : "Mac only"
        lid = savedLid ? .on : .off
        // A stopped saved choice can always be explicitly cleared once the
        // actual state is known, even when the master is off.
        lidEnabled = awakeEnabled && (savedLid || awake == .on)
        lidHint = changing ? "Changing…" : actualLid == .mixed ? (outsidePerch ? "On outside Perch" : "Status unknown · review settings") : actualLid == .on ? remaining.map { "On by Perch · \($0)s remaining" } ?? "On by Perch" : savedLid ? (masterWanted ? "Saved · protection stopped" : "Applies when Keep awake is on") : "Normal lid sleep"
    }
}
