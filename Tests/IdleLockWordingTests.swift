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
    print("PASS: the idle lock row and help say how long the Mac stays unlocked, never the signalling interval")
}
