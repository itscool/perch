import Foundation
import Network
import Darwin

@main struct DeskNetworkChecks {
    static func wait(_ message: String, seconds: TimeInterval = 8, until predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }
        guard predicate() else { throw KVMError("Timed out: " + message) }
    }
    static func main() { do { try run() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) } }
    static func run() throws {
        let now = Date()
        let events = (0..<1030).map { _ in KVMConnectionEvent(id: UUID(), time: now, peer: nil, peerName: "Fixture", detail: "ready", unexpected: false, duration: nil) }
        guard KVMConnectionEvent.retained(events, now: now).count == 1024,
              KVMConnectionEvent.retained(events, now: now.addingTimeInterval(86401)).isEmpty,
              !KVMCloseReason.duplicate.unexpected, !KVMCloseReason.shutdown.unexpected,
              KVMCloseReason.network.unexpected, KVMCloseReason.heartbeat.unexpected else { throw KVMError("Connection diagnostic retention/classification failed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("perch-tls-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try KVMDeskNode(identity: .fresh(), name: "Fixture A", storage: directory.appendingPathComponent("a.json"))
        let b = try KVMDeskNode(identity: .fresh(), name: "Fixture B", storage: directory.appendingPathComponent("b.json"))
        defer { a.stop(); b.stop() }
        let port = UInt16.random(in: 54000...59000)
        try a.start(localOnly: true, port: .init(rawValue: port)!); try b.start(localOnly: true, port: .init(rawValue: port + 1)!)
        try wait("listeners") { a.transport.listener?.port != nil && b.transport.listener?.port != nil }
        a.openPairing(hosting: true); b.openPairing(hosting: false)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!)
        let advertised = KVMPeerTransport.Nearby.make(id: a.localID.uuidString, endpoint: endpoint,
            txt: NWTXTRecord(["name": "Alice’s Mac", "pairing": "invite", "desk": "Studio"]))
        guard advertised.name == "Alice’s Mac", advertised.deskName == "Studio", b.canSelect(advertised), !a.canSelect(advertised),
              KVMPeerTransport.Nearby.make(id: a.localID.uuidString, endpoint: endpoint, txt: nil).name == "Unnamed Mac" else {
            throw KVMError("Discovery names or pairing roles are misleading")
        }
        a.problem = "Fixture persistence failure"
        a.transport.discoveryProblem?("Fixture discovery interruption")
        guard a.discoveryProblem != nil, a.displayProblem == "Fixture persistence failure" else { throw KVMError("Discovery replaced a saved-state failure") }
        a.transport.discoveryProblem?(nil)
        guard a.discoveryProblem == nil, a.problem == "Fixture persistence failure" else { throw KVMError("Discovery recovery cleared an unrelated error") }
        a.problem = nil
        b.connect(endpoint)
        let pendingID = b.pairingConnection!
        b.connect(endpoint)
        guard b.pairingConnection == pendingID, b.transport.links.count == 1, !b.canSelect(advertised) else { throw KVMError("Repeated selection created duplicate pairing work") }
        b.transport.connectionProblem?(b.transport.links[pendingID]!, "Fixture waiting")
        guard b.pairingProblem != nil, b.displayProblem == nil else { throw KVMError("Pairing status leaked into the shared desk failure") }

        do { try wait("mutually authenticated TLS pairing") { a.pairings.count == 1 && b.pairings.count == 1 } } catch { fputs("TLS states: \(a.transport.links.values.map { String(describing: $0.connection.state) }) / \(b.transport.links.values.map { String(describing: $0.connection.state) })\n", stderr); fputs("TLS problems: \(a.problem ?? "none") / \(b.problem ?? "none")\n", stderr); throw error }
        guard b.pairingProblem == nil else { throw KVMError("Recovered TLS connection retained its waiting error") }
        guard a.pairings[0].comparison == b.pairings[0].comparison else { throw KVMError("Comparison mismatch") }
        a.approve(a.pairings[0].id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard !a.hasOtherMembers && !b.hasOtherMembers else { throw KVMError("One-sided approval granted membership") }
        b.approve(b.pairings[0].id)
        try wait("two-sided membership") { a.hasOtherMembers && b.hasOtherMembers && a.online.count == 2 && b.online.count == 2 }
        guard a.pairingConnection == nil, b.pairingConnection == nil, a.pairings.isEmpty, b.pairings.isEmpty else { throw KVMError("Completed pairing retained pending state") }
        a.closePairing(); b.closePairing()
        guard a.online.count == 2, b.online.count == 2 else { throw KVMError("Closing completed setup disconnected the joined desk") }
        // A failed extra route must not paint a working peer as broken.
        b.connect(endpoint, expected: a.localID)
        let redundant = b.transport.links.values.first { $0.id != pendingID }!
        b.transport.connectionProblem?(redundant, "Fixture redundant route failed")
        guard b.networkProblem == nil else { throw KVMError("A redundant route failure masked a working peer") }
        b.transport.close(redundant)
        let working = b.transport.links[pendingID]!
        b.transport.connectionProblem?(working, "Fixture waiting")
        guard b.peerProblems[a.localID] != nil, b.networkProblem == nil else { throw KVMError("Online peer was reported offline") }
        b.transport.connectionProblem?(working, nil)
        guard b.peerProblems.isEmpty else { throw KVMError("Connection recovery retained stale errors") }
        guard a.connectionEvents.contains(where: { $0.peer == b.localID && $0.detail == "Authenticated connection ready" }),
              b.connectionEvents.contains(where: { $0.peer == a.localID && $0.detail == "Authenticated connection ready" }) else { throw KVMError("Authenticated connection was not recorded") }
        print("PASS: bounded connection activity and expected/unexpected classifications")
        print("PASS: readable discovery metadata, role selection, duplicate-click guard, scoped failures/recovery, completed pairing close, redundant-route failure isolation")
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
        var partial = desk
        partial.presets[2].assignments = [desk.presets[2].assignments[0]]
        partial.monitors[1].control = nil // Omitted hardware must need no control setup.
        try a.edit(partial); try wait("partial preset sync") { b.group == partial }
        let planned = try KVMMonitorRequest.make(group: partial, preset: partial.presets[2].id, epoch: UUID(), revision: "test")
        guard planned.routes.map(\.monitor) == [partial.monitors[0].id] else { throw KVMError("Partial preset scheduled an omitted monitor") }
        writes = 0; switchesA.activate(partial.presets[2].id)
        try wait("partial preset completes") { !switchesA.busy && switchesA.results.count == 1 }
        guard writes == 1 && switchesA.activePreset == partial.presets[2].id && switchesA.results[partial.monitors[1].id] == nil else { throw KVMError("Partial preset touched omitted monitor or failed activation") }
        var empty = partial; empty.presets[2].assignments = []
        var emptyRejected = false
        do { _ = try KVMMonitorRequest.make(group: empty, preset: empty.presets[2].id, epoch: UUID(), revision: "test") } catch { emptyRejected = true }
        guard emptyRejected else { throw KVMError("Empty preset became a switch request") }
        try a.edit(desk); try wait("restore complete preset configuration") { b.group == desk }
        print("PASS: partial preset switches exactly one monitor; omitted screen needs no control path; empty preset cannot execute")
        // One-off port selection uses the same leased protocol, without editing
        // any preset, and accepts a known port with no mapped computer.
        var directDesk = desk
        let unusedPort = KVMConnection(monitor: desk.monitors[1].id, computer: nil, localDisplay: nil, inputName: "HDMI 2", inputCode: 18)
        directDesk.connections.append(unusedPort)
        try a.edit(directDesk); try wait("direct port configuration sync") { b.group == directDesk }
        let holdPort = KVMConnection(monitor: desk.monitors[1].id, computer: nil, localDisplay: nil, inputName: "HDMI 3", inputCode: 19)
        directDesk.connections.append(holdPort)
        try a.edit(directDesk); try wait("second direct port configuration sync") { b.group == directDesk }
        let direct = try KVMMonitorRequest.makeConnection(group: directDesk, connection: unusedPort.id, epoch: a.graph.roster.epoch, revision: a.revision!)
        guard direct.preset == nil, direct.routes.count == 1, direct.routes[0].input == 18,
              try direct.validated(in: directDesk) == direct,
              try JSONDecoder().decode(KVMMonitorRequest.self, from: JSONEncoder().encode(direct)) == direct else { throw KVMError("Direct port request lost its scope") }
        let forged = KVMMonitorRequest(id: direct.id, epoch: direct.epoch, revision: direct.revision, preset: nil,
                                      routes: [.init(monitor: desk.monitors[0].id, control: desk.monitors[0].control!, input: 99)], connection: unusedPort.id)
        guard try forged.validated(in: directDesk) != forged else { throw KVMError("Direct port request accepted an arbitrary target") }
        writes = 0; switchesA.activateConnection(unusedPort.id)
        try wait("one-off remote port completes") { !switchesA.busy && switchesA.results.count == 1 }
        guard writes == 1, switchesA.results[desk.monitors[1].id]?.input == 18,
              switchesA.results[desk.monitors[0].id] == nil,
              a.group == directDesk, b.group == directDesk else { throw KVMError("Direct port action changed a preset or another screen") }
        writes = 0; switchesA.activateConnection(unusedPort.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard writes == 0 && !switchesA.busy else { throw KVMError("Repeated accepted direct port sent another hardware switch") }
        // Repeating the accepted target must be a no-op even when readback is
        // unavailable. Use a different direct port for the stale-lease path.
        hold = true; writes = 0; switchesA.activateConnection(holdPort.id)
        try wait("hold one-off command") { delayed.count == 1 }
        var editedPort = directDesk
        editedPort.connections[editedPort.connections.count - 1].inputCode = 20
        try a.edit(editedPort); try wait("port changes before command") { b.group == editedPort }
        delayed.forEach { $0() }; delayed = []; hold = false
        fakeTime += 70; switchesA.poll(); switchesB.poll()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard writes == 0, !switchesA.busy else { throw KVMError("A stale one-off port command reached hardware") }
        switchesA.poll(); switchesB.poll()
        try a.edit(desk); try wait("restore after direct port") { b.group == desk }
        print("PASS: one-off remote port switch, unassigned port, unchanged presets, stale-edit cancellation, canonical target validation and wire round trip")
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
        // A failed readback is not a failed write. Recover using fresh reads,
        // without reissuing the command or accepting pre-attempt observations.
        var confirmedReadback = false
        let expectedInputs = Dictionary(uniqueKeysWithValues: desk.presets[0].assignments.map { assignment in
            (assignment.monitor, desk.connections.first { $0.id == assignment.connection }!.inputCode!)
        })
        var readbackInputs = expectedInputs
        for service in [switchesA, switchesB] {
            service.execute = { _, valid, complete in
                guard valid() else { complete(.failed, "Expired"); return }
                writes += 1; complete(.unverified, "The monitor did not return its current input. Check current input again; if it remains unknown, review Monitor setup.")
            }
            service.readForVerification = { monitor, complete in complete(confirmedReadback ? readbackInputs[monitor] : nil) }
        }
        fakeTime += 1; writes = 0
        switchesA.activate(desk.presets[0].id)
        try wait("unconfirmed inputs have named recovery") { !switchesA.busy && switchesA.problem?.contains(desk.monitors[0].name) == true }
        guard switchesA.results.values.allSatisfy({ $0.state == .unverified }), writes == 2 else { throw KVMError("Old observation falsely cleared new readback failure") }
        guard switchesA.problem?.contains("accepted the switch") == true else { throw KVMError("Unconfirmed switch did not explain optimistic desktop reconciliation") }
        guard switchesA.optimisticInputs == expectedInputs else { throw KVMError("Accepted unverified inputs did not authorize optimistic reconciliation") }
        guard switchesA.retryConnection(for: desk.monitors[0].id) != nil else { throw KVMError("Unchanged failed input has no retry target") }
        confirmedReadback = true; fakeTime += 1
        switchesA.refreshObservations()
        try wait("fresh passive read clears old switch failure") { switchesA.problem == nil && switchesA.results.values.allSatisfy { $0.state == .confirmed } }
        guard writes == 2 else { throw KVMError("Checking inputs repeated hardware writes") }
        try wait("generation-matched desktop evidence") { switchesA.desktopInputs.count == expectedInputs.count && switchesB.desktopInputs.count == expectedInputs.count }
        guard switchesA.desktopInputs == expectedInputs else { throw KVMError("Desktop ownership did not use fresh hardware evidence") }
        // Use a different direct input so this section exercises desktop
        // invalidation after a real one-off switch; the repeated-target no-op
        // is covered immediately above.
        var directVerificationDesk = desk
        let directVerificationPort = KVMConnection(monitor: desk.monitors[0].id, computer: nil, localDisplay: nil, inputName: "HDMI 2", inputCode: 18)
        directVerificationDesk.connections.append(directVerificationPort)
        try a.edit(directVerificationDesk); try wait("direct verification port configuration sync") { b.group == directVerificationDesk }
        let directAssignment = directVerificationDesk.connections.last!
        var directExpected = expectedInputs
        directExpected[directAssignment.monitor] = directAssignment.inputCode!
        readbackInputs = directExpected
        confirmedReadback = false; fakeTime += 1
        switchesA.activateConnection(directAssignment.id)
        guard switchesA.desktopInputs[directAssignment.monitor] == nil else { throw KVMError("Direct port action retained pre-switch desktop authority") }
        try wait("direct port awaits fresh evidence") { !switchesA.busy }
        guard switchesA.optimisticInputs[directAssignment.monitor] == directAssignment.inputCode else { throw KVMError("Unconfirmed direct port switch did not retain accepted target") }
        confirmedReadback = true; fakeTime += 1
        switchesA.refreshObservations()
        try wait("direct port desktop handoff evidence on both peers") {
            switchesA.desktopInputs == directExpected && switchesB.desktopInputs == directExpected
        }
        guard writes == 3 && a.group == directVerificationDesk && b.group == directVerificationDesk else { throw KVMError("Direct port reconciliation wrote again or changed presets") }
        print("PASS: direct port switches share desktop invalidation; accepted unknown inputs reconcile optimistically and fresh reads override them")
        fakeTime += 46
        guard switchesA.desktopInputs.isEmpty else { throw KVMError("Expired observations still authorize desktop disconnection") }
        print("PASS: named per-screen failures, stale-read refusal and read-only reconciliation after recovery")

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
        let mouse = KVMSharedKeyboard(name: "Fixture switching mouse", bindings: [a.localID: "mouse-a", b.localID: "mouse-b"], follow: true, kind: .mouse)
        arranged.sharedKeyboards?.append(mouse)
        keyboardA.insert(mouse.id)
        var wrongKind = arranged
        wrongKind.sharedKeyboards![wrongKind.sharedKeyboards!.count - 1].kind = nil
        guard KVMInputConfiguration.revision(wrongKind) != KVMInputConfiguration.revision(arranged) else { throw KVMError("Changing device kind did not fence input state") }
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
        try wait("sharing readiness is current") { inputA.readinessIssue(preset: arranged.presets[0].id, monitor: arranged.monitors[0].id) == nil && inputB.readinessIssue(preset: arranged.presets[0].id, monitor: arranged.monitors[0].id) == nil }
        inputA.start(preset: UUID(), monitor: UUID())
        try wait("coordinator failure reaches peer") { inputB.problem != nil }
        inputA.refreshReadiness()
        try wait("fresh healthy coordinator response clears prior failure") { inputA.problem == nil && inputB.problem == nil }
        guard !inputA.active && !inputB.active else { throw KVMError("Refreshing status started input capture") }
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
        keyboardA = [mouse.id]; inputA.tick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        keyboardB = [keyboard.id]; inputB.publishKeyboardAttachments()
        guard inputB.capture(.init(kind: .keyDown, code: 15)) else { throw KVMError("Arriving keyboard event leaked locally") }
        inputB.tick()
        try wait("confirmed keyboard host following") { inputA.active && inputB.active && inputA.focus?.computer == b.localID }
        // Let the queued first key arrive before deliberately replacing that session.
        try wait("first arriving-keyboard key reaches B") { deliveries.contains { $0.0 == b.localID && $0.1.code == 15 } }
        guard !deliveries.contains(where: { $0.0 == a.localID && $0.1.code == 15 }) else { throw KVMError("Arriving keyboard typed on the previous computer") }
        inputA.start(preset: arranged.presets[0].id, monitor: arranged.monitors[0].id)
        try wait("return focus before mouse follow") { inputA.active && inputB.active && inputA.focus?.computer == a.localID }
        keyboardA = []; inputA.tick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        keyboardB.insert(mouse.id); inputB.publishKeyboardAttachments(); inputB.tick()
        try wait("confirmed mouse host following") { inputA.active && inputB.active && inputA.focus?.computer == b.localID }
        guard b.group.sharedKeyboards?.first(where: { $0.id == mouse.id })?.deviceKind == .mouse else { throw KVMError("Mouse identity lost in signed synchronization") }

        visible = false
        try wait("unknown monitor input keeps control", seconds: 4) { inputA.active && inputB.active }
        guard inputA.capture(.init(kind: .keyDown, code: 14)) else { throw KVMError("Unknown monitor input interrupted active control") }
        inputA.stop(); inputB.stop()
        visible = true
        try wait("fresh readiness clears the status without starting") { inputA.problem == nil && inputB.problem == nil }
        guard !inputA.active && !inputB.active else { throw KVMError("Readiness recovery silently started capture") }

        for link in Array(b.transport.links.values) { b.transport.close(link, reason: .heartbeat) }
        guard let incident = b.connectionEvents.last(where: { $0.peer == a.localID && $0.unexpected && $0.detail == KVMCloseReason.heartbeat.rawValue }),
              incident.duration != nil else { throw KVMError("Lost active link omitted its cause, peer or duration") }
        let logURL = b.storage.deletingPathExtension().appendingPathExtension("connections.json")
        try wait("durable connection incident") {
            guard let data = try? Data(contentsOf: logURL), let saved = try? JSONDecoder().decode([KVMConnectionEvent].self, from: data) else { return false }
            return saved.contains { $0.id == incident.id }
        }
        let reopened = try KVMDeskNode(identity: b.identity, name: "Fixture B", storage: b.storage)
        guard reopened.connectionEvents.contains(where: { $0.id == incident.id }),
              (try FileManager.default.attributesOfItem(atPath: logURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { throw KVMError("Incident missing after reopen or log not private") }
        try wait("named coordinator offline recovery") { inputB.contextIssue?.contains(a.localName) == true }
        b.retryConnections()
        try wait("trusted reconnect clears context") { inputB.contextIssue == nil && b.online.contains(a.localID) }
        inputA.refreshReadiness(); inputB.refreshReadiness()
        try wait("recovered status clears failures without control") { inputA.problem == nil && inputB.problem == nil }
        guard !inputA.active && !inputB.active else { throw KVMError("Reconnect started input capture") }
        inputA.setEnabled(false); inputB.setEnabled(false)
        guard inputA.problem == nil && inputB.problem == nil && inputA.readyComputers.isEmpty && inputB.readyComputers.isEmpty else { throw KVMError("Disabled sharing retained stale readiness") }
        print("PASS: named disconnection and automatic error clearance, read-only refresh, mouse/keyboard host following, kind-aware signed configuration")
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
        let duration = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 0
        if duration > 0 {
            let started = ProcessInfo.processInfo.systemUptime
            // Each source owns a distinct key. The real held-key model correctly
            // coalesces shared keys, so counting 16 identical keys would be wrong.
            var sustainedDelivered = 0
            for service in inputs {
                service.emit = { event, _ in
                    if event.code >= 40 && event.code < 56 && [.keyDown, .keyUp].contains(event.kind) { sustainedDelivered += 1 }
                }
            }
            var sent = 0, peakQueue = 0, latencies: [Double] = [], samples: [[String: Double]] = []
            var nextSample = 0.0, nextEdit = 10.0
            while ProcessInfo.processInfo.systemUptime - started < duration {
                let batch = ProcessInfo.processInfo.systemUptime
                for (index, service) in inputs.enumerated() {
                    for kind in [KVMInputEvent.Kind.keyDown, .keyUp] {
                        guard service.capture(.init(kind: kind, code: UInt16(40 + index))) else {
                            let states = inputs.enumerated().map { "\($0.offset): active=\($0.element.active), issue=\($0.element.problem ?? "none")" }.joined(separator: "; ")
                            throw KVMError("Endurance lost input authority after \(ProcessInfo.processInfo.systemUptime - started)s / \(sent) events: " + states)
                        }
                        sent += 1
                    }
                }
                peakQueue = max(peakQueue, nodes.flatMap { $0.transport.links.values }.map(\.queuedBytes).max() ?? 0)
                try wait("endurance delivery", seconds: 3) { sustainedDelivered == sent }
                latencies.append(ProcessInfo.processInfo.systemUptime - batch)
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                if elapsed >= nextSample {
                    var info = mach_task_basic_info()
                    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
                    let result = withUnsafeMutablePointer(to: &info) { pointer in
                        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                        }
                    }
                    guard result == KERN_SUCCESS else { throw KVMError("Could not sample fixture memory") }
                    samples.append(["seconds": elapsed, "residentMiB": Double(info.resident_size) / 1048576])
                    nextSample += 5
                }
                if elapsed >= nextEdit {
                    var changed = nodes[15].group; changed.name = "Endurance \(Int(elapsed))"
                    try nodes[15].edit(changed)
                    try wait("edit during sustained input") { nodes.allSatisfy { $0.group == changed } }
                    guard inputs.allSatisfy({ $0.active }) else { throw KVMError("Cosmetic edit interrupted sustained input") }
                    nextEdit += 10
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            try wait("endurance transport drain") { nodes.flatMap { $0.transport.links.values }.allSatisfy { $0.queuedBytes == 0 } }
            guard inputs.allSatisfy({ $0.active }) else { throw KVMError("Endurance silently lost session") }
            let ordered = latencies.sorted()
            let metrics: [String: Any] = ["seconds": ProcessInfo.processInfo.systemUptime - started,
                "sent": sent, "delivered": sustainedDelivered,
                "batchP95Milliseconds": ordered[Int(Double(ordered.count - 1) * 0.95)] * 1000,
                "peakQueuedBytesPerLink": peakQueue, "memory": samples]
            print("ENDURANCE " + String(decoding: try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]), as: UTF8.self))
            print("PASS: sustained 16-peer authenticated input, exact delivery count, concurrent cosmetic edits and drained queues; no native input")
        }
        inputs.forEach { $0.setEnabled(false) }
        try owner.removePeer(nodes[7].localID)
        try wait("16-member revocation convergence", seconds: 15) { nodes.enumerated().allSatisfy { $0.offset == 7 || $0.element.group.computers.count == 15 } }
        print("PASS: 16 real TLS fixture members, roster and signed edit convergence from member 16, 16-screen input readiness, all 16 sources, three-computer traversal, full-group invitation rejection and revocation; temporary identities only")
    }
}
