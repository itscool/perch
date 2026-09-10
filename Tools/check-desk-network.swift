import Foundation
import Network

@main struct DeskNetworkChecks {
    static func wait(_ message: String, seconds: TimeInterval = 8, until predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }
        guard predicate() else { throw KVMError("Timed out: " + message) }
    }
    static func main() { do { try run() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) } }
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("perch-tls-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try KVMDeskNode(identity: .fresh(), name: "Fixture A", storage: directory.appendingPathComponent("a.json"))
        let b = try KVMDeskNode(identity: .fresh(), name: "Fixture B", storage: directory.appendingPathComponent("b.json"))
        defer { a.stop(); b.stop() }
        let port = UInt16.random(in: 54000...59000)
        try a.start(localOnly: true, port: .init(rawValue: port)!); try b.start(localOnly: true, port: .init(rawValue: port + 1)!)
        try wait("listeners") { a.transport.listener?.port != nil && b.transport.listener?.port != nil }
        a.openPairing(hosting: true); b.openPairing(hosting: false)
        b.connect(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
        do { try wait("mutually authenticated TLS pairing") { a.pairings.count == 1 && b.pairings.count == 1 } } catch { fputs("TLS states: \(a.transport.links.values.map { String(describing: $0.connection.state) }) / \(b.transport.links.values.map { String(describing: $0.connection.state) })\n", stderr); fputs("TLS problems: \(a.problem ?? "none") / \(b.problem ?? "none")\n", stderr); throw error }
        guard a.pairings[0].comparison == b.pairings[0].comparison else { throw KVMError("Comparison mismatch") }
        a.approve(a.pairings[0].id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard !a.hasOtherMembers && !b.hasOtherMembers else { throw KVMError("One-sided approval granted membership") }
        b.approve(b.pairings[0].id)
        try wait("two-sided membership") { a.hasOtherMembers && b.hasOtherMembers && a.online.count == 2 && b.online.count == 2 }
        var changed = b.group; changed.name = "Shared from B"; try b.edit(changed)
        try wait("durable edit and acknowledgement") { a.group.name == "Shared from B" && b.pendingPeers.isEmpty }
        guard try KVMDeskArchive.read(a.storage).verified().1.current?.name == "Shared from B" else { throw KVMError("Peer acknowledged before durable storage") }
        let oldB = b.group
        b.transport.stop()
        try wait("disconnect") { a.online.count == 1 }
        var fromA = a.group; fromA.name = "Offline A"; try a.edit(fromA)
        var fromB = oldB; fromB.name = "Offline B"; try b.edit(fromB)
        b.closePairing(); a.closePairing()
        try b.transport.start(name: "Fixture B", localOnly: true, port: .init(rawValue: port + 1)!)
        b.connect(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), expected: a.localID)
        try wait("pinned reconnect and preserved conflict") { a.conflicts.count == 2 && b.conflicts.count == 2 }
        try a.resolve(a.conflicts.first { $0.name == "Offline B" }!)
        try wait("conflict convergence") { a.conflicts.isEmpty && b.conflicts.isEmpty && b.group.name == "Offline B" }
        let switchesA = KVMMonitorSwitch(node: a), switchesB = KVMMonitorSwitch(node: b)
        var desk = a.group
        for index in 0..<2 {
            let screen = KVMMonitor(name: "Screen \(index)", geometry: .init(x: Double(index * 550), y: 0, width: 550, height: 310), control: .init(computer: index == 0 ? a.localID : b.localID, localDisplay: UUID().uuidString))
            desk.monitors.append(screen)
            let ca = KVMConnection(monitor: screen.id, computer: a.localID, localDisplay: UUID().uuidString, inputName: "HDMI", inputCode: 17)
            let cb = KVMConnection(monitor: screen.id, computer: b.localID, localDisplay: UUID().uuidString, inputName: "DisplayPort", inputCode: 15)
            desk.connections += [ca, cb]
            for i in 0..<3 { desk.presets[i].assignments.append(.init(monitor: screen.id, connection: i == 1 ? cb.id : ca.id)) }
        }
        try a.edit(desk)
        try wait("monitor configuration sync") { b.group == desk }
        var writes = 0, fallback = false, hold = false, delayed: [() -> Void] = []
        var fakeTime = ProcessInfo.processInfo.systemUptime
        switchesA.clock = { fakeTime }; switchesB.clock = { fakeTime }
        for (service, owner) in [(switchesA, a.localID), (switchesB, b.localID)] {
            service.execute = { route, valid, completion in
                let work = {
                    if !valid() { completion(.failed, "Expired before write"); return }
                    if fallback && owner == a.localID { completion(.failed, "Source video path disappeared"); return }
                    writes += 1; completion(.confirmed, "Injected monitor readback")
                }
                if hold { delayed.append(work) } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work) }
            }
        }
        switchesA.activate(desk.presets[0].id)
        try wait("two monitor command/readback") { !switchesA.busy && switchesA.results.count == 2 }
        guard switchesA.activePreset == desk.presets[0].id && writes == 2 else { throw KVMError("Preset did not confirm both monitors") }
        fallback = true; writes = 0
        switchesA.activate(desk.presets[1].id)
        try wait("DDC source-path fallback") { !switchesA.busy && switchesA.results.count == 2 }
        guard switchesA.activePreset == desk.presets[1].id && writes == 2 else { throw KVMError("Paired control delegation failed") }
        fallback = false; hold = true; writes = 0
        switchesA.activate(desk.presets[0].id)
        try wait("held monitor work") { delayed.count == 2 }
        fakeTime += 70; switchesA.poll(); switchesB.poll()
        delayed.forEach { $0() }; delayed = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard writes == 0 && !switchesA.busy && switchesA.activePreset == nil else { throw KVMError("An expired switch wrote or became active") }
        switchesA.poll(); switchesB.poll(); hold = false
        let invalid = try JSONEncoder().encode(KVMMonitorMessage.execute(UUID()))
        a.sendApplication(invalid, peer: b.localID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard writes == 0 else { throw KVMError("Unprepared execute issued a command") }
        switchesA.activate(desk.presets[0].id); switchesB.activate(desk.presets[1].id)
        try wait("competing requests settle") { !switchesA.busy && !switchesB.busy }
        guard writes <= 2 else { throw KVMError("Competing requests overlapped monitor writes") }
        print("PASS: paired monitor-only two-phase preparation, two-screen confirmed outcomes, source-path delegation, expired/stale work refusal and competing requests; all hardware calls injected")
        try a.removePeer(b.localID)
        try wait("revocation") { a.online.count == 1 }
        b.connect(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), expected: a.localID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard a.online.count == 1 else { throw KVMError("Revoked peer reconnected") }
        let removed = try KVMDeskNode(identity: b.identity, name: "Fixture B", storage: b.storage)
        guard !removed.isMember else { throw KVMError("Removed member was restored on reopening") }
        try removed.archiveRemovedDesk()
        let fresh = try KVMDeskNode(identity: b.identity, name: "Fixture B", storage: b.storage)
        guard fresh.isOwner && !fresh.hasOtherMembers else { throw KVMError("Removed member could not create a fresh desk") }
        print("PASS: real TLS 1.3 loopback, matching comparison, two-sided approval, signed membership, durable cross-peer edit/receipt, pinned reconnect, offline conflict resolution and revoked certificate refusal. No Keychain, discovery, UI or hardware changes.")
    }
}
