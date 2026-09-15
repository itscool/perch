import Foundation
import Darwin

func runHousekeepingTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    let guardian = AgentGuardian()
    guardian.configurationDirty = false; guardian.requestsDirty = false
    let identity = ProcessIdentity(pid: 123, uid: getuid(), seconds: 10, microseconds: 1)
    let process = AgentProcess(identity: identity, parent: 1, executable: "/fixture/agent")
    let entry = TrackedAgent(process: process, targetID: "fixture")
    guardian.tracker.insert(entry)
    guardian.updateCheckpointTracking()
    let revision = guardian.tracker.revision
    for _ in 0..<1000 {
        guardian.refreshConfigurationIfNeeded(); _ = guardian.pendingRequests()
        guardian.tracker.insert(entry); guardian.updateCheckpointTracking()
    }
    try check(guardian.maintenance.configurationReads == 0 && guardian.maintenance.requestScans == 0,
              "Unchanged guardian performed configuration reads or request scans")
    try check(guardian.maintenance.checkpointSorts == 1 && guardian.tracker.revision == revision,
              "Unchanged tracking repeatedly sorted or became dirty")
    guardian.tracker.update(processes: [process], roots: [identity: "fixture"], enabledTargets: ["fixture"], excluded: [])
    guardian.updateCheckpointTracking()
    try check(guardian.maintenance.checkpointSorts == 1, "Unchanged snapshot triggered sorting")
    let changed = AgentProcess(identity: identity, parent: 2, executable: "/fixture/new-exec")
    guardian.tracker.insert(TrackedAgent(process: changed, targetID: "fixture"))
    guardian.updateCheckpointTracking()
    try check(guardian.maintenance.checkpointSorts == 2 && guardian.state.tracked.first?.process == changed,
              "Changed exec metadata did not reach the checkpoint")
    guardian.tracker.remove(identity); guardian.updateCheckpointTracking()
    try check(guardian.maintenance.checkpointSorts == 3 && guardian.state.tracked.isEmpty, "Exit did not dirty the checkpoint")
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
    print("PASS: unchanged guardian skips reads/scans/sorts; exec/exit changes checkpoint; immediate request notification; same-inode edit, deletion and recreation recovery")
}
