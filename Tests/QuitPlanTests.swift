import Foundation

func runQuitPlanTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let idle = QuitPlan(.init())
    try check(!idle.needsConfirmation && idle.stops.isEmpty, "An idle Perch asked before quitting")
    let all = QuitPlan(.init(closedLid: true, keepAwake: true, preventIdleLock: true, scrolling: true, desk: true))
    try check(all.stops == ["Closing the lid will sleep your Mac", "Your Mac can go to sleep again", "Your Mac can lock when idle",
                            "Scrolling and navigation keys go back to normal", "Desk switching and keyboard sharing stop"], "Quit effects changed: \(all.stops)")
    try check(all.needsConfirmation && all.keeps == ["Your settings are saved for next time"] && all.detail.hasPrefix("Stops:\n• Closing the lid"),
              "Quit detail is malformed")

    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("perch-closed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    var commands: [String] = []
    let record: HelperLifecycle.Run = { commands.append($0.joined(separator: " ")); return .ok }
    HelperLifecycle.stopForQuit(uid: 501, marker: marker, run: record)
    try check(commands == ["disable gui/501/local.scott.perch.guardian", "bootout gui/501/local.scott.perch.guardian",
                           "disable gui/501/local.scott.perch.input", "bootout gui/501/local.scott.perch.input"] &&
              FileManager.default.fileExists(atPath: marker.path), "Quit did not stop both helpers: \(commands)")
    commands = []
    HelperLifecycle.allowAtLaunch(uid: 501, marker: marker, run: record)
    try check(commands == ["enable gui/501/local.scott.perch.guardian", "enable gui/501/local.scott.perch.input"] &&
              !FileManager.default.fileExists(atPath: marker.path), "Launch did not allow the helpers again: \(commands)")

    var completions = 0, stops = 0, finished = false
    QuitShutdown.perform(timeout: 0.1, endLidSession: { _ in }, stopHelpers: { stops += 1 }, completion: { completions += 1; finished = true })
    var deadline = Date().addingTimeInterval(2)
    while !finished, Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    try check(completions == 1 && stops == 1, "Quit waited on a lid helper that never answered")
    completions = 0; stops = 0
    QuitShutdown.perform(timeout: 0.3, endLidSession: { done in done() }, stopHelpers: { stops += 1 }, completion: { completions += 1 })
    deadline = Date().addingTimeInterval(0.8)
    while Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    try check(completions == 1 && stops == 1, "Quit turn-off ran more than once")
    print("PASS: Quit names only features that are on, asks nothing when idle, stops and re-allows helpers, never waits on an unanswered lid helper")
}
