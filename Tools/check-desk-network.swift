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
        // Production input coordinator over the same authenticated links. Native
        // capture/posting are never constructed: every event sink is injected.
        let inputA = KVMInputSession(node: a), inputB = KVMInputSession(node: b)
        switchesA.otherMessage = { peer, bytes in _ = inputA.receive(bytes, peer: peer) }
        switchesB.otherMessage = { peer, bytes in _ = inputB.receive(bytes, peer: peer) }
        inputA.ready = { true }; inputB.ready = { true }
        var deliveries: [(UUID, KVMInputEvent)] = [], releaseCount = 0
        inputA.emit = { event, _ in deliveries.append((a.localID, event)) }
        inputB.emit = { event, _ in deliveries.append((b.localID, event)) }
        inputA.release = { releaseCount += 1 }; inputB.release = { releaseCount += 1 }
        var arranged = a.group
        arranged.presets[0].assignments = arranged.monitors.enumerated().map { index, screen in
            .init(monitor: screen.id, connection: arranged.connections.first { $0.monitor == screen.id && $0.computer == (index == 0 ? a.localID : b.localID) }!.id)
        }
        let keyboard = KVMSharedKeyboard(name: "Test keyboard", bindings: [a.localID: "fixture-a", b.localID: "fixture-b"], follow: true)
        arranged.sharedKeyboards = [keyboard]
        var keyboardA: Set<UUID> = [keyboard.id], keyboardB: Set<UUID> = []
        inputA.attachedKeyboards = { keyboardA }; inputB.attachedKeyboards = { keyboardB }
        try a.edit(arranged)
        try wait("input arrangement sync") { b.group == arranged }
        var reads = 0, visible = true
        for service in [inputA, inputB] {
            service.readMonitor = { monitor, complete in reads += 1; complete(visible ? (monitor == arranged.monitors[0].id ? 17 : 15) : nil) }
            service.setEnabled(true)
        }
        defer { inputA.setEnabled(false); inputB.setEnabled(false) }
        try wait("fresh input visibility") { reads >= 2 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        inputB.start(preset: arranged.presets[0].id, monitor: arranged.monitors[0].id)
        try wait("source enters handoff barrier") { inputB.preparing }
        guard inputB.capture(.init(kind: .keyDown, code: 11)), inputB.capture(.init(kind: .keyUp, code: 11)) else { throw KVMError("Preparing input leaked locally") }
        try wait("buffered handoff input reaches only A") { deliveries.contains { $0.0 == a.localID && $0.1.kind == .keyDown && $0.1.code == 11 } }
        try wait("release and grant on both peers") { inputA.active && inputB.active }
        guard inputB.capture(.init(kind: .keyDown, code: 12)) else { throw KVMError("Remote keyboard could not send") }
        try wait("remote keyboard reaches A") { deliveries.contains { $0.0 == a.localID && $0.1.kind == .keyDown } }
        var renamedDesk = a.group; renamedDesk.name = "Renamed while sharing"; renamedDesk.monitors[0].name = "A clearer screen name"
        try a.edit(renamedDesk); try wait("cosmetic edit sync") { b.group == renamedDesk }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        guard inputA.active && inputB.active else { throw KVMError("Renaming interrupted remote typing") }
        guard inputA.capture(.init(kind: .motion, x: 300, y: 0)) else { throw KVMError("Mouse could not send") }
        try wait("pointer boundary handoff to B") { inputA.active && inputB.active && inputA.focus?.computer == b.localID }
        guard releaseCount >= 4 else { throw KVMError("Handoff did not release held input") }
        guard inputA.capture(.init(kind: .keyDown, code: 13)) else { throw KVMError("Keyboard source did not follow pointer") }
        try wait("A keyboard reaches B") { deliveries.contains { $0.0 == b.localID && $0.1.code == 13 } }
        // Re-focus A, then simulate the same confirmed physical keyboard moving
        // to B. This is a device observation, never inferred from idle keys.
        inputA.start(preset: arranged.presets[0].id, monitor: arranged.monitors[0].id)
        try wait("return focus to A") { inputA.active && inputB.active && inputA.focus?.computer == a.localID }
        keyboardA = []; inputA.tick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        keyboardB = [keyboard.id]; inputB.publishKeyboardAttachments()
        guard inputB.capture(.init(kind: .keyDown, code: 15)) else { throw KVMError("Arriving keyboard event leaked locally") }
        inputB.tick()
        try wait("confirmed keyboard host following") { inputA.active && inputB.active && inputA.focus?.computer == b.localID }
        try wait("first arriving-keyboard key reaches B") { deliveries.contains { $0.0 == b.localID && $0.1.code == 15 } }
        guard !deliveries.contains(where: { $0.0 == a.localID && $0.1.code == 15 }) else { throw KVMError("Arriving keyboard typed on the previous computer") }
        visible = false
        try wait("unknown monitor input stops forwarding", seconds: 4) { !inputA.active && !inputB.active }
        guard !inputA.capture(.init(kind: .keyDown, code: 14)) else { throw KVMError("Unverified screen retained control") }
        inputA.setEnabled(false); inputB.setEnabled(false)
        print("PASS: real TLS input routing in both directions, pointer handoff, release-before-focus, and lost visibility recovery; no native input capture or posting")
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
        try scaleChecks(directory: directory.appendingPathComponent("large"))
    }
    static func scaleChecks(directory: URL) throws {
        let owner = try KVMDeskNode(identity: .fresh(), name: "Scale 1", storage: directory.appendingPathComponent("1.json"))
        var nodes = [owner]
        defer { nodes.forEach { $0.stop() } }
        let base = UInt16.random(in: 54000...58000)
        try owner.start(localOnly: true, port: .init(rawValue: base)!)
        try wait("scale owner listener") { owner.transport.listener?.port != nil }
        for index in 2...16 {
            let node = try KVMDeskNode(identity: .fresh(), name: "Scale \(index)", storage: directory.appendingPathComponent("\(index).json"))
            nodes.append(node)
            try node.start(localOnly: true, port: .init(rawValue: base + UInt16(index))!)
            try wait("scale member listener") { node.transport.listener?.port != nil }
            owner.openPairing(hosting: true); node.openPairing(hosting: false)
            node.connect(.hostPort(host: "127.0.0.1", port: .init(rawValue: base)!))
            try wait("scale pairing \(index)") { owner.pairings.count == 1 && node.pairings.count == 1 }
            owner.approve(owner.pairings[0].id); node.approve(node.pairings[0].id)
            try wait("scale membership \(index)") { owner.group.computers.count == index && node.group.computers.count == index }
            owner.closePairing(); node.closePairing()
        }
        try wait("16-member roster convergence", seconds: 15) { nodes.allSatisfy { $0.group.computers.count == 16 && $0.ownerID == owner.localID } }
        owner.openPairing(hosting: true)
        guard !owner.pairingOpen, owner.problem?.contains("16") == true else { throw KVMError("Full group offered a 17th invitation") }
        var edit = nodes[15].group; edit.name = "Edited on member 16"
        try nodes[15].edit(edit)
        try wait("16-member signed edit convergence", seconds: 15) { nodes.allSatisfy { $0.group.name == edit.name } }
        var arrangement = owner.group
        for (index, node) in nodes.enumerated() {
            let display = UUID().uuidString
            let monitor = KVMMonitor(name: "Screen \(index + 1)", geometry: .init(x: Double(index % 4) * 500, y: Double(index / 4) * 300, width: 500, height: 300), control: .init(computer: node.localID, localDisplay: display))
            let connection = KVMConnection(monitor: monitor.id, computer: node.localID, localDisplay: display, inputName: "DisplayPort", inputCode: 15)
            arrangement.monitors.append(monitor); arrangement.connections.append(connection)
            arrangement.presets[0].assignments.append(.init(monitor: monitor.id, connection: connection.id))
        }
        try owner.edit(arrangement)
        try wait("16-screen arrangement convergence", seconds: 15) { nodes.allSatisfy { $0.group == arrangement } }
        let inputs = nodes.map { KVMInputSession(node: $0) }
        defer { inputs.forEach { $0.setEnabled(false) } }
        var delivered: [UUID: Int] = [:]
        for (index, service) in inputs.enumerated() {
            let local = nodes[index].localID
            nodes[index].application = { [weak service] peer, bytes in _ = service?.receive(bytes, peer: peer) }
            service.ready = { true }
            service.readMonitor = { _, complete in complete(15) }
            service.emit = { _, _ in delivered[local, default: 0] += 1 }
            service.setEnabled(true)
        }
        let first = arrangement.monitors[0].id, preset = arrangement.presets[0].id
        try wait("16 input participants ready", seconds: 10) { inputs[15].readyComputers.count == 16 && inputs[15].availableConnections.count == 16 && inputs[15].readinessIssue(preset: preset, monitor: first) == nil }
        inputs[15].start(preset: preset, monitor: first)
        try wait("16-party release and input grant") { inputs.allSatisfy { $0.active } }
        for (index, service) in inputs.enumerated() { guard service.capture(.init(kind: .keyDown, code: UInt16(index))) else { throw KVMError("Input source unavailable in full group") } }
        try wait("all 16 physical sources route to focus") { delivered[owner.localID, default: 0] == 16 }
        for index in 1...2 {
            guard inputs[15].capture(.init(kind: .motion, x: index == 1 ? 300 : 510)) else { throw KVMError("Pointer source lost full-group session") }
            do { try wait("three-computer pointer traversal \(index)") { inputs.allSatisfy { $0.active && $0.focus?.computer == nodes[index].localID } } }
            catch { print(inputs.enumerated().map { "\($0.offset): active=\($0.element.active), focus=\($0.element.focus?.computer.uuidString ?? "nil"), problem=\($0.element.problem ?? "none"), revision=\($0.element.node.revision ?? "nil")" }.joined(separator: "\n")); throw error }
        }
        inputs.forEach { $0.setEnabled(false) }
        try owner.removePeer(nodes[7].localID)
        try wait("16-member revocation convergence", seconds: 15) { nodes.enumerated().allSatisfy { $0.offset == 7 || $0.element.group.computers.count == 15 } }
        print("PASS: 16 real TLS fixture members, roster and signed edit convergence from member 16, 16-screen input readiness, all 16 sources, three-computer traversal, full-group invitation rejection and revocation; temporary identities only")
    }
}
