import Foundation

/// The Prevent idle lock row tells people how long their Mac stays unlocked.
/// It must never advertise Perch's internal signalling interval again.
func runIdleLockWordingTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    try check(IdleLockPreventer.rowHint(enabled: true) == "Until you turn it off", "The idle lock row does not say how long the Mac stays unlocked")
    try check(IdleLockPreventer.rowHint(enabled: false).isEmpty, "The idle lock row claims something while it is off")
    for text in [IdleLockPreventer.rowHint(enabled: true), ControlHelp.idleLock] {
        try check(!text.contains("30"), "Idle lock wording exposes the signalling interval: \(text)")
    }
    try check(ControlHelp.idleLock.contains("until you turn this off"), "Idle lock help does not say how long it lasts")

    // A lock report is facts: how long the Mac was idle, what Perch was doing,
    // and whether the Mac was even idle long enough for this to be an idle lock.
    let sudden = ScreenLockLog.lockSummary(idle: 4, preventing: true, sinceSignal: 12, signalRefused: false, sharing: false)
    try check(sudden.contains("idle 4 s") && sudden.contains("too short to be an idle lock") && sudden.contains("last reported activity 12 s ago"),
              "A lock while the Mac was busy did not report the idle time and Perch's signalling: \(sudden)")
    let idleLock = ScreenLockLog.lockSummary(idle: 615, preventing: false, sinceSignal: nil, signalRefused: false, sharing: false)
    try check(idleLock.contains("idle 10 min 15 s") && !idleLock.contains("too short") && idleLock.contains("Prevent idle lock is off."),
              "A lock after real idle time misreported it: \(idleLock)")
    let refused = ScreenLockLog.lockSummary(idle: 300, preventing: true, sinceSignal: 20, signalRefused: true, sharing: true)
    try check(refused.contains("macOS refused its last signal") && refused.contains("desk session was running"),
              "A refused signal or an interrupted desk session went unreported: \(refused)")
    let unknown = ScreenLockLog.lockSummary(idle: nil, preventing: true, sinceSignal: nil, signalRefused: false, sharing: false)
    try check(unknown.contains("could not be read") && unknown.contains("has not reported activity yet"),
              "An unreadable idle clock was reported as a fact: \(unknown)")
    try check(ScreenLockLog.unlockSummary(lockedFor: 3723).contains("1 h 2 min") && ScreenLockLog.unlockSummary(lockedFor: nil) == "Screen unlocked.",
              "Unlock reporting lost how long the Mac was locked")
    // The signal goes only where it can work and is judged by the clock the
    // screen saver uses (November 16, 2026: the old one never reset it).
    try check(IdleNudge.decide(sessionIdle: 3, buttonHeld: false, locked: false, canPost: true) == .notNeeded, "The idle signal was posted while the Mac was in use")
    try check(IdleNudge.decide(sessionIdle: 40, buttonHeld: false, locked: false, canPost: true) == .nudge, "An idle Mac was not signalled")
    try check(IdleNudge.decide(sessionIdle: 40, buttonHeld: true, locked: false, canPost: true) == .busy, "The idle signal was posted in the middle of a drag")
    try check(IdleNudge.decide(sessionIdle: 40, buttonHeld: false, locked: true, canPost: true) == .locked, "The idle signal was posted on the lock screen")
    try check(IdleNudge.decide(sessionIdle: 40, buttonHeld: false, locked: false, canPost: false) == .cannotPost, "A signal that could not be posted was not said")
    try check(IdleNudge.decide(sessionIdle: nil, buttonHeld: false, locked: false, canPost: true) == .notNeeded, "An unreadable clock was signalled blindly")
    try check(IdleNudge.judge(before: 31, after: 0.1) == .worked && IdleNudge.judge(before: 31, after: 31.3) == .failed && IdleNudge.judge(before: 31, after: nil) == .failed,
              "A signal was judged by anything but the session clock falling")
    try check(IdleNudge.after + 30 < 60, "With a signal every 30 s the session clock could reach the shortest screen saver time")
    print("PASS: the idle lock row and help say how long the Mac stays unlocked, never the signalling interval; every screen lock is logged with the idle time, Perch's signalling and whether a desk session was interrupted")
}
