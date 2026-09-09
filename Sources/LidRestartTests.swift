import Foundation
import Security

func runLidRestartTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func rejects(_ action: () throws -> Void) throws { var failed = false; do { try action() } catch { failed = true }; try check(failed, "Invalid restart handoff accepted") }
    let hash = String(repeating: "a", count: 40)
    var handoff = LidRestartHandoff()
    try rejects { _ = try handoff.prepare(identity: hash, now: 10, active: false) }
    try rejects { _ = try handoff.prepare(identity: "not a code hash", now: 10, active: true) }
    let ticket = try handoff.prepare(identity: hash, now: 10, active: true)
    try check(ticket.deadline == 70, "Restart allowance is not bounded to 60 seconds")
    let retry = try handoff.prepare(identity: hash, now: 69, active: true)
    try check(retry == ticket, "A retry extended the restart deadline")
    try rejects { _ = try handoff.prepare(identity: String(repeating: "b", count: 40), now: 69, active: true) }
    try rejects { try handoff.claim(ticket.id, pinnedConnection: nil, now: 69, active: true) }
    try rejects { try handoff.claim(UUID().uuidString, pinnedConnection: ticket.id, now: 69, active: true) }
    try rejects { try handoff.claim(ticket.id, pinnedConnection: ticket.id, now: 9, active: true) }
    try rejects { try handoff.claim(ticket.id, pinnedConnection: ticket.id, now: 69, active: false) }
    var expired = handoff
    try rejects { try expired.claim(ticket.id, pinnedConnection: ticket.id, now: 70, active: true) }
    try rejects { _ = try expired.prepare(identity: hash, now: 70, active: true) }
    try handoff.claim(ticket.id, pinnedConnection: ticket.id, now: 69.99, active: true)
    try rejects { try handoff.claim(ticket.id, pinnedConnection: ticket.id, now: 69.999, active: true) }
    expired.clear()
    try rejects { try expired.claim(ticket.id, pinnedConnection: ticket.id, now: 69, active: true) }
    var requirement: SecRequirement?
    try check(SecRequirementCreateWithString(("identifier \"local.scott.perch\" and cdhash H\"" + hash + "\"") as CFString, [], &requirement) == errSecSuccess, "Exact update code-signing requirement is invalid")
    // The independent battery policy must win even while the app allowance has
    // 50 seconds left. Supervisor/watchdog failures retain their short deadline.
    let battery = LidObservation(closed: true, power: .battery)
    var policy = LidGuardPolicy(), update = LidRestartHandoff()
    _ = policy.step(battery, now: 0, authorized: true)
    let late = try update.prepare(identity: hash, now: 50, active: true)
    try check(late.deadline == 110 && policy.step(battery, now: 60, authorized: true).requestSleep, "Update reset the existing battery grace")
    var watcher = LidGuardWatchdogState()
    _ = watcher.receive(.init(token: UUID().uuidString, expires: 53, deadline: 60), now: 50)
    try check(watcher.evaluate(battery, now: 53, channelAlive: true).requestSleep, "Update extended the independent watchdog deadline")
    var requested: [LidGuardSession.Request] = []
    var delayed: ((Data?) -> Void)?
    let session = LidGuardSession(send: { request, reply in requested.append(request); delayed = reply }, schedule: { _,_ in }, invalidate: {}, publish: { _,_ in }, activity: { _ in }, now: { 100 })
    session.refresh(); let old = delayed
    let token = UUID().uuidString
    let reply = try JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: true, detail: "fixture"), token: token))
    try session.adoptRestart(reply); old?(nil); session.refresh()
    try check(requested.last == .renew(token), "A late pre-restart reply discarded the adopted session")
    let error = try JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: true, detail: "fixture"), token: token, restartError: "expired"))
    try rejects { try session.adoptRestart(error) }
    // Exercise the queue/RPC adapter too, including a lost prepare reply. The
    // injected transport records cancellation without contacting any helper.
    let lock = NSLock()
    var restartRequests: [LidGuardClient.RestartRequest] = []
    var failPreparation = false
    let rpcTicket = LidRestartTicket(id: UUID().uuidString, targetIdentity: hash, deadline: LidGuardClock.now + 60)
    let client = LidGuardClient(transport: { request, completion in
        let armed: Bool
        if case .change(false) = request { armed = false } else { armed = true }
        completion(try? JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: armed, detail: "fixture"), token: armed ? token : nil)))
    }, restart: { request, completion in
        lock.withLock { restartRequests.append(request) }
        if case .prepare = request, lock.withLock({ failPreparation }) { completion(nil); return }
        let ticket: LidRestartTicket?
        if case .prepare = request { ticket = rpcTicket } else { ticket = nil }
        completion(try? JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: true, detail: "fixture"), token: token, restart: ticket)))
    })
    func until(_ done: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(2)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try check(done(), "Injected restart adapter did not complete")
    }
    var enabled = false
    client.change(true) { if case .success = $0 { enabled = true } }; try until { enabled }
    var prepared = false
    client.prepareForRestart(identity: hash) { if case .success(let received) = $0 { prepared = received == rpcTicket } }
    try until { prepared }
    var resumed = false
    client.resumeAfterRestart(rpcTicket.id) { if case .success = $0 { resumed = true } }
    try until { resumed }
    try check(client.active, "Restart adapter did not publish its adopted session")
    lock.withLock { failPreparation = true }
    var failed = false
    client.prepareForRestart(identity: hash) { if case .failure = $0 { failed = true } }
    try until { failed }
    try check(lock.withLock { restartRequests.contains(.cancel(token, "")) }, "A lost prepare reply left a restart allowance without attempting cancellation")
    print("PASS: one bounded restart ticket, exact-code connection requirement, retries/replays, expiry/fault/disable, original battery and watchdog deadlines, resumed heartbeat and late reply isolation")
}
