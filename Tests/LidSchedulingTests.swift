import Foundation

/// Lid sessions ended whenever the Background-throttled supervisor or watchdog
/// missed a two-second lease. These checks run in milliseconds.
func runLidSchedulingTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let job = LidGuardInstall.serviceJob(owner: 501)
    try check(job["ProcessType"] as? String == "Interactive", "The lid supervisor job would run throttled in the background band")
    let encoded = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).base64EncodedString()
    let command = try LidGuardInstall.installationCommand(source: URL(fileURLWithPath: "/fixture/Perch.app"), requirement: "identifier \"fixture\"", owner: 501)
    try check(command.contains(encoded), "Lid installation does not write the tested supervisor job")

    _ = setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)
    let wasThrottled = LidGuardScheduling.throttled
    let activity = LidGuardScheduling.makeResponsive(reason: "Lid scheduling self-test")
    let stillThrottled = LidGuardScheduling.throttled
    ProcessInfo.processInfo.endActivity(activity)
    _ = setpriority(PRIO_DARWIN_PROCESS, 0, 0)
    try check(wasThrottled && !stillThrottled, "Lid helpers do not leave the background band at startup")

    try check(Bundle.main.infoDictionary?["PerchLidHelperVersion"] as? Int == LidGuardCompatibility.helperVersion,
              "Info.plist and the lid helper version disagree; installed helpers would not update")
    let older: [String: Any] = ["PerchLidProtocolVersion": LidGuardCompatibility.protocolVersion, "PerchLidHelperVersion": LidGuardCompatibility.helperVersion - 1]
    try check(LidHelperUpdateState(info: older, lidOpen: true).pending, "An older lid helper is not offered an update")
    print("PASS: lid supervisor job is Interactive and installed as tested; helpers leave background throttling; helper version matches the bundle and older helpers update")
}
