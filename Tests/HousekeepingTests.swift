import Foundation
import Darwin

func runHousekeepingTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    let guardian = AgentGuardian()
    guardian.configurationDirty = false; guardian.requestsDirty = false
    for _ in 0..<1000 { guardian.refreshConfigurationIfNeeded(); _ = guardian.pendingRequests() }
    try check(guardian.maintenance.configurationReads == 0 && guardian.maintenance.requestScans == 0,
              "Unchanged guardian performed configuration reads or request scans")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let signal = FileChangeSignal(directory) { guardian.requestsDirty = true }
    let request = SafetyRequest(id: UUID(), action: "fixture-no-action")
    let file = directory.appendingPathComponent("request.json")
    try JSONEncoder().encode(request).write(to: file, options: .atomic)
    let until = Date().addingTimeInterval(2)
    while !guardian.requestsDirty && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(guardian.requestsDirty, "Request arrival did not trigger immediate work")
    let received = guardian.pendingRequests(directory: directory)
    try check(received.count == 1 && received[0].1.id == request.id, "Queued request was missed")
    _ = guardian.pendingRequests(directory: directory)
    try check(guardian.maintenance.requestScans == 1, "Clean request directory was scanned again")
    let config = directory.appendingPathComponent("config.json")
    try Data("first".utf8).write(to: config)
    let watch = FileChangeSignal(config) {}
    // Check before the run loop can deliver the notification: this is the
    // periodic-recovery path for in-place edits and recreated files.
    try Data("second".utf8).write(to: config)
    try check(watch.refresh(), "Recovery missed an in-place edit with the same inode")
    try check(!watch.refresh(), "Unchanged revision appeared dirty")
    try FileManager.default.removeItem(at: config)
    try check(watch.refresh(), "Recovery missed deletion")
    try Data("recreated".utf8).write(to: config, options: .atomic)
    try check(watch.refresh(), "Recovery missed file recreation")
    withExtendedLifetime((watch, signal)) {}

    // Removing the Agent Kill Switch must never leave someone's apps unable
    // to start: launch jobs its emergency stop switched off are switched back
    // on before its state is discarded, and a job that will not re-enable keeps
    // the state so the next start tries again.
    let stateURL = directory.appendingPathComponent("state.json")
    let leftovers = ["events.jsonl", "agents.json"].map { directory.appendingPathComponent($0) }
    func seed(_ state: SafetyState) throws {
        try JSONEncoder().encode(state).write(to: stateURL)
        for url in leftovers { try Data("x".utf8).write(to: url) }
    }
    var enabled: [String] = []
    try seed(SafetyState(locked: true, disabledJobs: ["com.example.agent", "com.example.other"]))
    var outcome = AgentGuardian.retireKillSwitch(stateURL: stateURL, retired: leftovers) { enabled.append($0); return "ok" }
    try check(outcome == nil && enabled == ["com.example.agent", "com.example.other"], "Switched-off launch jobs were not switched back on: \(enabled)")
    try check(!FileManager.default.fileExists(atPath: stateURL.path) && leftovers.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
              "The retired kill switch's files were left behind")
    enabled = []
    try seed(SafetyState(locked: false, disabledJobs: ["com.example.agent", "com.example.stuck"]))
    outcome = AgentGuardian.retireKillSwitch(stateURL: stateURL, retired: leftovers) { enabled.append($0); return $0 == "com.example.stuck" ? "failed" : "ok" }
    let kept = try? JSONDecoder().decode(SafetyState.self, from: Data(contentsOf: stateURL))
    try check(outcome?.contains("com.example.stuck") == true && kept?.disabledJobs == ["com.example.stuck"],
              "A job that would not re-enable was forgotten instead of retried: \(String(describing: kept))")
    enabled = []
    outcome = AgentGuardian.retireKillSwitch(stateURL: stateURL, retired: leftovers) { enabled.append($0); return "ok" }
    try check(outcome == nil && enabled == ["com.example.stuck"] && !FileManager.default.fileExists(atPath: stateURL.path),
              "The next start did not retry and finish: \(enabled)")
    try Data("not json".utf8).write(to: stateURL)
    try check(AgentGuardian.retireKillSwitch(stateURL: stateURL, retired: leftovers) { _ in "ok" } == nil && !FileManager.default.fileExists(atPath: stateURL.path),
              "An unreadable kill switch state was kept and would be retried forever")
    print("PASS: unchanged helper skips reads and scans; immediate request notification; same-inode edit, deletion and recreation recovery; removing the kill switch switches its stopped apps back on, retries what fails, and then deletes its files")
}
