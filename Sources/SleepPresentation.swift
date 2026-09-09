import AppKit

/// A single final snapshot: a saved lid choice is not evidence of a live session.
struct SleepPresentation: Equatable {
    let awake: NSControl.StateValue
    let awakeEnabled: Bool
    let awakeHint: String
    let lid: NSControl.StateValue
    let lidEnabled: Bool
    let lidHint: String

    init(ordinary: SleepStatus?, actualLid: NSControl.StateValue, savedLid: Bool,
         masterWanted: Bool, legacy: Bool, changing: Bool, remaining: Int?) {
        awake = actualLid == .on ? .on : ordinary.map { $0.perchActive || $0.caffeinateActive ? .on : .off } ?? .mixed
        awakeEnabled = actualLid != .mixed && awake != .mixed && !changing
        awakeHint = actualLid == .on ? "Lid mode requested" : awake == .mixed ? "Unavailable" : ordinary?.caffeinateActive == true ? "caffeinate active" : "Mac only"
        lid = savedLid || legacy ? .on : .off
        // A stopped saved choice can always be explicitly cleared once the
        // actual state is known, even when the master is off.
        lidEnabled = awakeEnabled && (savedLid || legacy || awake == .on)
        lidHint = legacy ? "Old override · review sleep settings" : changing ? "Changing…" : actualLid == .mixed ? "Status unknown · review settings" : actualLid == .on ? remaining.map { "Requested · \($0)s remaining" } ?? "Requested · unverified" : savedLid ? (masterWanted ? "Saved · protection stopped" : "Applies when Keep awake is on") : "Normal lid sleep"
    }
}
