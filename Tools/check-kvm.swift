import Foundation
import CryptoKit

@main struct KVMChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw KVMError("FAIL: " + message) }; count += 1
        }
        func rejects(_ message: String, _ block: () throws -> Void) throws {
            var rejected = false
            do { try block() } catch { rejected = true }
            try check(rejected, message)
        }
        let alice = KVMComputer(name: "MacBook"), bob = KVMComputer(name: "Studio")
        let left = KVMMonitor(name: "Left", geometry: KVMGeometry(x: 0, y: 0, width: 600, height: 340))
        let right = KVMMonitor(name: "Right", geometry: KVMGeometry(x: 600, y: 0, width: 600, height: 340))
        let a = KVMConnection(monitor: left.id, computer: alice.id, localDisplay: "same-local-id", inputName: "USB-C")
        let b = KVMConnection(monitor: right.id, computer: bob.id, localDisplay: "same-local-id", inputName: "HDMI 1", inputCode: 17)
        var group = KVMGroup(name: "Desk", computers: [alice, bob], monitors: [left, right], connections: [a, b])
        group.presets[0].assignments = [.init(monitor: left.id, connection: a.id), .init(monitor: right.id, connection: b.id)]
        _ = try group.validated(); count += 1
        let encoded = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(KVMGroup.self, from: encoded).validated()
        try check(decoded == group, "portable configuration round trip")
        var large = group
        for i in 3...16 { large.computers.append(KVMComputer(name: "Mac \(i)")); large.monitors.append(KVMMonitor(name: "Screen \(i)", geometry: .init(x: Double(i) * 650, y: 0, width: 600, height: 340))) }
        _ = try large.validated(); count += 1
        var tooMany = large; tooMany.computers.append(KVMComputer(name: "17"))
        try rejects("reject 17th computer") { _ = try tooMany.validated() }
        tooMany = large; tooMany.monitors.append(KVMMonitor(name: "17", geometry: .init(x: 12_000, y: 0, width: 600, height: 340)))
        try rejects("reject 17th physical monitor") { _ = try tooMany.validated() }
        var invalid = group; invalid.monitors[0].geometry.width = .nan
        try rejects("reject nonfinite geometry") { _ = try invalid.validated() }
        invalid = group; invalid.monitors[1].geometry.x = 599
        try rejects("reject overlapping monitors") { _ = try invalid.validated() }
        invalid = group; invalid.presets[0].assignments.append(invalid.presets[0].assignments[0])
        try rejects("reject double ownership") { _ = try invalid.validated() }
        invalid = group; invalid.presets[0].assignments[0].connection = UUID()
        try rejects("reject stale connection") { _ = try invalid.validated() }
        invalid = group; invalid.connections.append(KVMConnection(monitor: right.id, computer: alice.id, localDisplay: a.localDisplay, inputName: "USB-C"))
        try rejects("reject host display mapped twice") { _ = try invalid.validated() }
        invalid = group; invalid.presets[1].shortcut = invalid.presets[0].shortcut
        try rejects("reject duplicate preset shortcut") { _ = try invalid.validated() }
        var removed = group; removed.removeMonitor(left.id)
        _ = try removed.validated()
        try check(removed.connections == [b] && removed.presets[0].assignments.count == 1, "screen removal keeps unrelated mappings")
        removed = group; try removed.removeComputer(bob.id); _ = try removed.validated()
        try check(removed.monitors.count == 2 && removed.connections.count == 2 && removed.connections[1].computer == nil && removed.presets[0].assignments.count == 2, "computer removal keeps physical inputs and presets, unmaps computer")

        let observation = KVMDisplayObservation(computer: alice.id, localDisplay: "1", vendor: 1, model: 2, numericSerial: 42, textSerial: nil)
        var other = observation; other.computer = bob.id
        try check(observation.suggestedMatches(in: [other]) == [other], "unique serial suggests shared monitor")
        var duplicate = observation; duplicate.localDisplay = "2"
        try check(observation.suggestedMatches(in: [duplicate, other]).isEmpty, "duplicated serial is ambiguous")
        var missing = observation; missing.numericSerial = 0
        var missingOther = missing; missingOther.computer = bob.id
        try check(missing.suggestedMatches(in: [missingOther]).isEmpty, "same specs without serial never merge")

        let crossing = KVMEdge.crossing(group: group, preset: group.presets[0], source: left.id, from: .init(x: 590, y: 170), to: .init(x: 620, y: 170))
        try check(crossing == .remote(monitor: right.id, computer: bob.id, entry: .init(x: 600, y: 170)), "boundary routes logical destination")
        var gap = group; gap.monitors[1].geometry.x = 601
        try check(KVMEdge.crossing(group: gap, preset: gap.presets[0], source: left.id, from: .init(x: 590, y: 170), to: .init(x: 650, y: 170)) == .blocked, "no teleport across physical gap")
        try check(KVMEdge.crossing(group: group, preset: group.presets[0], source: left.id, from: .init(x: 590, y: 330), to: .init(x: 610, y: 350)) == .blocked, "corner has no arbitrary target")
        var native = group; native.connections[1].computer = alice.id; native.connections[1].localDisplay = "2"
        try check(KVMEdge.crossing(group: native, preset: native.presets[0], source: left.id, from: .init(x: 590, y: 100), to: .init(x: 610, y: 100)) == .native, "same computer uses native traversal")
        let portrait = KVMGeometry(x: 0, y: 0, width: 600, height: 340, rotation: .clockwise)
        let pixel = try portrait.nativePoint(.init(x: 0, y: 300), pixelWidth: 3840, pixelHeight: 2160)
        try check(pixel == .init(x: 1919.5, y: 2159), "portrait edge into native pixels")
        for rotation in KVMRotation.allCases {
            var g = portrait; g.rotation = rotation
            let centre = try g.nativePoint(.init(x: g.displayedWidth / 2, y: g.displayedHeight / 2), pixelWidth: 1000, pixelHeight: 600)
            try check(centre == .init(x: 499.5, y: 299.5), "rotation preserves centre")
        }

        let keyA = Curve25519.Signing.PrivateKey(), keyB = Curve25519.Signing.PrivateKey()
        let roster = KVMTrustRoster(group: group.id, epoch: UUID(), keys: [alice.id: keyA.publicKey.rawRepresentation, bob.id: keyB.publicKey.rawRepresentation])
        var first = try KVMSyncGraph(roster: roster)
        let root = try first.edit(group, author: alice.id, key: keyA)
        var second = try KVMSyncGraph(roster: roster); try second.receive(root)
        try check(first.awaitingAcknowledgement(of: root.id) == [bob.id], "receipt doesn't pretend all peers synced")
        try first.acknowledge(root.id, from: bob.id, epoch: roster.epoch)
        try check(first.awaitingAcknowledgement(of: root.id).isEmpty, "explicit receipt acknowledges")
        var editA = group; editA.monitors[0].name = "Alice's left"
        var editB = group; editB.monitors[0].name = "Bob's left"
        let revA = try first.edit(editA, author: alice.id, key: keyA)
        let revB = try second.edit(editB, author: bob.id, key: keyB)
        try first.receive(revB); try second.receive(revA)
        try check(first.hasConflict && second.hasConflict && first.heads == second.heads && first.current == nil, "concurrent edits converge as conflict")
        try rejects("no silent conflict overwrite") { _ = try first.edit(editA, author: alice.id, key: keyA) }
        try rejects("stale conflict review rejected") { _ = try first.edit(editA, author: alice.id, key: keyA, resolving: [root.id]) }
        let resolved = try first.edit(editA, author: alice.id, key: keyA, resolving: first.heads)
        try second.receive(resolved)
        try check(first.current == second.current && !second.hasConflict, "explicit resolution converges")
        try second.receive(root)
        try check(second.current == editA, "replay old revision doesn't roll back")
        var catchup = try KVMSyncGraph(roster: roster)
        try rejects("missing parents request catchup") { try catchup.receive(resolved) }
        for message in try first.history() {
            let wire = try JSONEncoder().encode(message)
            try catchup.receive(JSONDecoder().decode(KVMSignedRevision.self, from: wire))
        }
        try check(catchup.current == editA, "offline catchup across portable messages")
        var tampered = root; tampered.payload.append(32)
        try rejects("payload tampering rejected") { try catchup.receive(tampered) }
        tampered = root; tampered.signature = Data(repeating: 0, count: 64)
        try rejects("invalid signature rejected even on replay") { try catchup.receive(tampered) }
        var fakeMember = group; fakeMember.computers.append(KVMComputer(name: "Intruder"))
        let fake = try KVMSignedRevision.sign(.init(group: fakeMember, epoch: roster.epoch, author: alice.id, parents: [root.id]), key: keyA)
        try rejects("configuration can't self-grant membership") { try catchup.receive(fake) }
        var postRevocation = try KVMSyncGraph(roster: KVMTrustRoster(group: group.id, epoch: UUID(), keys: [alice.id: keyA.publicKey.rawRepresentation]))
        try rejects("old epoch cannot restore removed peer") { try postRevocation.receive(root) }
        try rejects("stale acknowledgement rejected") { try first.acknowledge(root.id, from: bob.id, epoch: UUID()) }
        // All 16 authenticated replicas converge, including out-of-order siblings.
        let manyKeys = Dictionary(uniqueKeysWithValues: large.computers.map { ($0.id, Curve25519.Signing.PrivateKey()) })
        let manyRoster = KVMTrustRoster(group: large.id, epoch: UUID(), keys: manyKeys.mapValues { $0.publicKey.rawRepresentation })
        var primary = try KVMSyncGraph(roster: manyRoster)
        let base = try primary.edit(large, author: alice.id, key: manyKeys[alice.id]!)
        var replicas = try large.computers.map { _ in try KVMSyncGraph(roster: manyRoster) }
        for i in replicas.indices { try replicas[i].receive(base) }
        var revisions: [KVMSignedRevision] = []
        for i in replicas.indices {
            var changed = large; changed.name = "Desk \(i)"
            let author = large.computers[i].id
            revisions.append(try replicas[i].edit(changed, author: author, key: manyKeys[author]!))
        }
        for i in replicas.indices { for r in revisions.reversed() { try replicas[i].receive(r) } }
        try check(replicas.allSatisfy { $0.heads == replicas[0].heads && $0.heads.count == 16 }, "16-peer conflict convergence")
        let merge = try replicas[0].edit(large, author: alice.id, key: manyKeys[alice.id]!, resolving: replicas[0].heads)
        for i in replicas.indices { try replicas[i].receive(merge) }
        try check(replicas.allSatisfy { $0.current == large }, "16-peer explicit resolution")

        let framed = try KVMMessageFramer.encode(encoded)
        var framer = KVMMessageFramer(), messages: [Data] = []
        for byte in framed { messages += try framer.append(Data([byte])) }
        try check(messages == [encoded], "arbitrary byte fragmentation")
        let two = try framer.append(framed + framed)
        try check(two == [encoded, encoded], "coalesced frames")
        try rejects("hostile frame length rejected") { _ = try framer.append(Data([255,255,255,255])) }
        let tinyFrame = try KVMMessageFramer.encode(Data([1]))
        try rejects("tiny-frame flood is bounded") { _ = try framer.append((0..<257).reduce(into: Data()) { data, _ in data.append(tinyFrame) }) }

        var handoff = KVMHandoff()
        let session = UUID()
        try rejects("empty preset doesn't act") { _ = try handoff.begin(group: group, presetID: group.presets[1].id, focusMonitor: left.id, inputSources: [alice.id], online: [alice.id,bob.id], session: session, now: 0) }
        try rejects("offline destination doesn't act") { _ = try handoff.begin(group: group, presetID: group.presets[0].id, focusMonitor: right.id, inputSources: [alice.id], online: [alice.id], session: session, now: 0) }
        let request = try handoff.begin(group: group, presetID: group.presets[0].id, focusMonitor: right.id, inputSources: [alice.id, bob.id], online: [alice.id,bob.id], session: session, now: 100)
        try check(!handoff.canForward(to: bob.id, now: 100), "preparation never forwards input")
        try rejects("concurrent trigger serialized") { _ = try handoff.begin(group: group, presetID: group.presets[0].id, focusMonitor: left.id, inputSources: [alice.id], online: [alice.id,bob.id], session: session, now: 100) }
        handoff.participantPrepared(alice.id, request: request.id, session: UUID(), releasedInput: true, now: 100)
        try check(handoff.prepared.isEmpty, "wrong session ignored")
        handoff.participantPrepared(alice.id, request: request.id, session: session, releasedInput: true, now: 101)
        handoff.participantPrepared(bob.id, request: request.id, session: session, releasedInput: true, now: 101)
        try check(handoff.phase == .switching, "all input participants release before switching")
        handoff.observedVisible(connection: a.id, by: alice.id, request: request.id, session: session, now: 102)
        try rejects("partial monitor success never commits") { try handoff.commit(request: request.id, session: session, now: 102) }
        handoff.observedVisible(connection: b.id, by: alice.id, request: request.id, session: session, now: 102)
        try rejects("wrong host can't attest destination") { try handoff.commit(request: request.id, session: session, now: 102) }
        handoff.observedVisible(connection: b.id, by: bob.id, request: request.id, session: session, now: 102)
        try handoff.commit(request: request.id, session: session, now: 102)
        try check(handoff.canForward(to: bob.id, now: 103) && !handoff.canForward(to: alice.id, now: 103), "only agreed logical destination gets input")
        try check(!handoff.canForward(to: bob.id, now: 104), "expired picture evidence stops input")
        handoff.renewVisible(connection: b.id, by: bob.id, request: request.id, session: session, now: 105)
        try check(!handoff.canForward(to: bob.id, now: 105), "late read cannot resurrect expired transaction")
        handoff.recoverLocally()
        let timeout = try handoff.begin(group: group, presetID: group.presets[0].id, focusMonitor: right.id, inputSources: [alice.id], online: [alice.id,bob.id], session: session, now: 200)
        handoff.expire(now: 210)
        handoff.participantPrepared(alice.id, request: timeout.id, session: session, releasedInput: true, now: 209)
        try check(handoff.phase != .switching && !handoff.canForward(to: bob.id, now: 210), "deadline fences late callbacks")
        handoff.recoverLocally()
        _ = try handoff.begin(group: group, presetID: group.presets[0].id, focusMonitor: right.id, inputSources: [alice.id], online: [alice.id,bob.id], session: session, now: 300)
        handoff.peerDisconnected(bob.id)
        try check(!handoff.canForward(to: bob.id, now: 301), "disconnect stops routing")
        // A real input without a grouped computer is a valid picture-only route.
        var pictureOnly = group
        pictureOnly.connections[1].computer = nil; pictureOnly.connections[1].localDisplay = nil
        _ = try pictureOnly.validated()
        handoff.recoverLocally()
        try rejects("unmapped route still needs a trusted monitor observer") {
            _ = try handoff.begin(group: pictureOnly, presetID: pictureOnly.presets[0].id, focusMonitor: right.id, inputSources: [alice.id], online: [alice.id], session: session, now: 400)
        }
        let displayOnly = try handoff.begin(group: pictureOnly, presetID: pictureOnly.presets[0].id, focusMonitor: right.id, inputSources: [alice.id], online: [alice.id], session: session, now: 400, monitorObservers: [right.id: alice.id])
        handoff.participantPrepared(alice.id, request: displayOnly.id, session: session, releasedInput: true, now: 401)
        for route in displayOnly.routes { handoff.observedVisible(connection: route.connection, by: alice.id, request: displayOnly.id, session: session, now: 402) }
        try handoff.commit(request: displayOnly.id, session: session, now: 402)
        try check(handoff.phase == .active && handoff.controlOwner == nil, "unassigned input switches picture without granting input ownership")
        try check(!handoff.canForward(to: alice.id, now: 402) && !handoff.canForward(to: bob.id, now: 402), "display-only activation never forwards input")
        try check(KVMEdge.crossing(group: pictureOnly, preset: pictureOnly.presets[0], source: left.id, from: .init(x: 590, y: 100), to: .init(x: 610, y: 100)) == .blocked, "pointer cannot cross to an unassigned computer")
        var incomplete = group; incomplete.presets[0].assignments.removeLast()
        handoff.recoverLocally()
        try rejects("no implicit None or leave-unchanged operation") {
            _ = try handoff.begin(group: incomplete, presetID: incomplete.presets[0].id, focusMonitor: left.id, inputSources: [alice.id], online: [alice.id,bob.id], session: session, now: 500)
        }
        var badMapping = pictureOnly; badMapping.connections[1].localDisplay = "ghost"
        try rejects("unassigned port cannot smuggle a host-local identity") { _ = try badMapping.validated() }
        var duplicatePort = group; var extraPort = a; extraPort.id = UUID(); extraPort.computer = nil; extraPort.localDisplay = nil; duplicatePort.connections.append(extraPort)
        try rejects("duplicate port names don't create ambiguous choices") { _ = try duplicatePort.validated() }
        try rejects("zero-size coordinate conversion rejected") {
            _ = try KVMGeometry(x: 0, y: 0, width: 0, height: 1).nativePoint(.init(x: 0, y: 0), pixelWidth: 1, pixelHeight: 1)
        }
        print("PASS: \(count) KVM checks — limits, identity, geometry, signed sync, 16 peers, framing and fenced handoffs. No UI, network or hardware used.")
    }
}
