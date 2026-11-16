import Foundation

/// The desk owner's side of keyboard and mouse sharing: which Macs are ready,
/// the grant that is live or on its way, where the one pointer is, and where
/// each event goes. Only the owner (the Mac that created the desk) runs it.
/// Every Mac, the owner included, also runs its own side in `KVMInputSession`;
/// the two meet only at `releaseOwnParticipation`, `acceptOwnGrant` and
/// `replayHeldInput`, and through the session's shared status.
final class KVMInputCoordinator {
    unowned let session: KVMInputSession
    init(session: KVMInputSession) { self.session = session }

    private var node: KVMDeskNode { session.node }
    private var enabled: Bool { session.enabled }
    private func clock() -> Double { session.clock() }
    private func ready() -> Bool { session.ready() }
    @discardableResult private func send(_ message: KVMInputMessage, to peer: UUID) -> Bool { session.send(message, to: peer) }
    private var configurationRevision: String? { session.configurationRevision }
    private func destination(preset: UUID, monitor: UUID) -> UUID? { session.destination(preset: preset, monitor: monitor) }
    /// Where typing goes is the owner's decision, kept on its own side.
    private var keyboardFocus: KVMInputFocus? {
        get { session.keyboardFocus }
        set { session.keyboardFocus = newValue }
    }
    private var localProblem: String? {
        get { session.localProblem }
        set { session.localProblem = newValue }
    }
    private var blockedTarget: (preset: UUID, monitor: UUID)? {
        get { session.blockedTarget }
        set { session.blockedTarget = newValue }
    }
    private var localStatusProblem: String? { session.localStatusProblem }
    private var optimisticMonitorInput: ((UUID) -> UInt16?)? { session.optimisticMonitorInput }
    private var motionScale: (KVMInputFocus) -> KVMPoint { session.motionScale }

    /// How many times someone chose a preset or Share, on any Mac.
    private var choices = 0
    /// The grant to go back to if a handoff made while sharing (a crossing or a
    /// Mac joining) does not complete.
    private var fallback: (participants: Set<UUID>, pointer: KVMInputFocus)?
    /// When each Mac last tried to join a desk already sharing.
    private var joinAttempts: [UUID: Double] = [:]
    private var lastCrossingAt: Double = -.infinity
    /// The screen the pointer last crossed away from, so only a bounce straight
    /// back into it is ignored, never a swipe carrying on forward.
    private var lastCrossingFrom: UUID?
    private(set) var grant: KVMInputGrant?
    private(set) var pending: KVMInputGrant?
    private var prepared: Set<UUID> = []
    private var installed: Set<UUID> = []
    private var grantedAt: Double = 0
    private var deliveryBuffer: [(UUID, KVMInputEvent)] = []
    private var pendingAt: Double = 0
    private var readiness: [UUID: Double] = [:]
    /// Why each Mac that cannot share cannot, as it said in its last poll.
    private var reasons: [UUID: KVMShareReason] = [:]
    private var incoming: [UUID: UInt64] = [:]
    private var outputSequence: UInt64 = 0
    /// The owner must know that every participant is still inside the same
    /// short-lived lease. Readiness polls only prove that a process is alive;
    /// they do not prove that its local lease has not expired. Without this
    /// fence, one participant could fall back to local input while the owner
    /// continued delivering the old grant to another participant.
    private var peerHeartbeats: [UUID: Double] = [:]
    private var held = KVMInputHeld()
    private(set) var pointer: KVMInputFocus?
    private struct Probe { let peer: UUID; let monitor: UUID; let sent: Double; let revision: String }
    private var probes: [UUID: Probe] = [:]
    private struct Visibility { let input: UInt16; let sent: Double; let revision: String }
    private var visibility: [UUID: Visibility] = [:]
    private var nextInspection: Double = 0
    private var rates: [UUID: (Double, Int)] = [:]
    /// The grant a crossing made, so its bounce guard starts once every Mac has
    /// installed it rather than at the decision.
    private var crossingGrant: UUID?

    /// The Macs a new grant takes in: ready now and sharing the same way. A Mac
    /// on another sharing version is left out rather than offered a handoff it
    /// would ignore, which stalled everyone for 3 s and repeated.
    private var sharers: Set<UUID> { Set(readiness.keys.filter { fresh($0) && session.versionIssue($0) == nil }).union([node.localID]) }
    /// The Macs whose sharing is on and ready now, this one included.
    var sharingComputers: Set<UUID> { Set(readiness.keys.filter(fresh)).union(fresh(node.localID) ? [node.localID] : []) }
    /// Forget what the monitors were seen showing; the desk changed.
    func forgetObservations() { visibility = [:]; probes = [:] }
    /// Look at the monitors again at the next tick.
    func inspectSoon() { nextInspection = 0 }
    /// A Mac in the grant, or in the handoff on its way, went offline.
    func checkOnline() {
        if let grant, !grant.participants.isSubset(of: node.online) { end("a computer in the handoff went offline") }
        if let pending, !pending.participants.isSubset(of: node.online) { end("a computer in the handoff went offline") }
    }
    /// The owner's messages. Called only on the owner.
    func receive(_ message: KVMInputMessage, peer: UUID, now: Double) {
        switch message {
        case .heartbeat(let nonce, let grantID):
            guard node.isOwner, enabled, ready(), let grant,
                  grant.id == grantID, grant.participants.contains(peer), fresh(peer) else { return }
            peerHeartbeats[peer] = now
            send(.heartbeatAck(nonce, grantID), to: peer)
        case .poll(let nonce, let available, let reason):
            guard node.isOwner else { return }
            reasons[peer] = available ? nil : reason.flatMap(KVMShareReason.init(rawValue:))
            let wasSharing = fresh(peer)
            if available && enabled { readiness[peer] = now } else { readiness[peer] = nil }
            // The menu bar icon follows who shares; tell it when that changes.
            if fresh(peer) != wasSharing { session.objectWillChange.send() }
            if grant?.participants.contains(peer) == true && !available { end((node.group.computers.first { $0.id == peer }?.name ?? "a computer") + " reported it cannot share right now") }
            validateAuthority()
            let connections = Set(node.group.connections.filter { connection in
                if let observed = visibility[connection.monitor], observed.revision == configurationRevision,
                   now >= observed.sent, now - observed.sent < 2 {
                    return observed.input == connection.inputCode
                }
                return optimisticMonitorInput?(connection.monitor) == connection.inputCode
            }.map(\.id))
            send(.state(nonce, available ? grant : nil, localStatusProblem, connections, sharingComputers, pointer, keyboardFocus, choices, reasons.isEmpty ? nil : reasons.mapValues(\.rawValue)), to: peer)
        case .focus(let preset, let monitor, let position, let automatic):
            guard node.isOwner, enabled, ready(), pending == nil, fresh(peer), let revision = configurationRevision, node.canEdit,
                  let screen = node.group.monitors.first(where: { $0.id == monitor }),
                  let owner = destination(preset: preset, monitor: monitor), fresh(owner) else {
                if node.isOwner { localProblem = nil; blockedTarget = (preset, monitor) }
                return
            }
            // Ctrl-Opt-Esc on the coordinator stops the whole desk until the person
            // picks a preset or Share again; an automatic request must not undo it.
            if automatic && session.automaticStartSuppressed {
                PerchLog.note("input.start", "an automatic start was refused: this Mac chose local control")
                // Said where every Mac shows the status, not only in the log.
                localProblem = "Ctrl-Opt-Esc on " + node.localName + " stopped sharing. Choose a preset or Share on this Mac to start again."
                return
            }
            // The person chose a preset or Share: every Mac that chose local
            // control takes part again, this one included.
            if !automatic {
                choices += 1; session.knownChoices = choices
                session.allowAutomaticStart()
                if localProblem?.hasPrefix("Ctrl-Opt-Esc") == true { localProblem = nil }
            }
            // A Mac that was away (asleep, at work, restarting) asks for the
            // pointer while the desk is already sharing without it. It joins,
            // and the pointer stays exactly where it is. Refusing it, as before,
            // left the pointer stuck at the edge of that Mac's screens.
            if let grant, grant.preset == preset, !grant.participants.contains(peer), let pointer {
                // At most one try every 30 s: a Mac that cannot finish a handoff
                // must not interrupt everyone else's sharing over and over.
                guard session.versionIssue(peer) == nil, now - (joinAttempts[peer] ?? -.infinity) >= 30 else { return }
                joinAttempts[peer] = now
                let name = node.group.computers.first { $0.id == peer }?.name ?? "A computer"
                PerchLog.record("input.join", name + " joined the shared desk; the pointer stays where it is")
                let old = grant.participants
                prepare(.init(id: UUID(), epoch: node.graph.roster.epoch, revision: revision, preset: preset,
                              participants: sharers.union([peer]), focus: pointer))
                fallback = (old, pointer)
                return
            }
            guard KVMPointerRules.placementAllowed(sharing: grant?.preset == preset, automatic: automatic,
                                        pointerAlreadyThere: pointer?.monitor == monitor && pointer?.computer == owner) else { return }
            guard let entry = KVMPointerRules.entryPoint(requested: position, carried: pointer?.position, screen: screen.geometry) else {
                blockedTarget = (preset, monitor)
                localProblem = "Move the pointer onto one of the desk's screens to start sharing. Perch will not jump it somewhere you did not put it."
                return
            }
            let participants = sharers
            prepare(.init(id: UUID(), epoch: node.graph.roster.epoch, revision: revision, preset: preset,
                          participants: participants, focus: .init(monitor: monitor, computer: owner, position: entry)))
        case .prepared(let id):
            guard node.isOwner, let pending, pending.id == id, pending.participants.contains(peer), now - pendingAt < 2 else { return }
            prepared.insert(peer)
            if prepared == pending.participants {
                grant = pending; self.pending = nil; pointer = pending.focus; session.focus = pending.focus; incoming = [:]; outputSequence = 0
                installed = []
                if pending.participants.contains(node.localID) {
                    session.acceptOwnGrant(pending, now: now)
                    installed.insert(node.localID)
                }
                // A join that went through may be tried again later.
                for participant in pending.participants { joinAttempts[participant] = nil }
                grantedAt = now
                peerHeartbeats = Dictionary(uniqueKeysWithValues: pending.participants.filter { $0 != node.localID }.map { ($0, now) })
                localProblem = nil
                // What this Mac typed or clicked while its own handoff was on the
                // way goes where it was meant to, as it does on the other Macs.
                if pending.participants.contains(node.localID) { session.replayHeldInput() }
            }
        case .installed(let id):
            guard node.isOwner, let grant, grant.id == id, grant.participants.contains(peer) else { return }
            installed.insert(peer)
            if installed == grant.participants {
                // The pointer is only now on its new screen; a correction that
                // follows straight away is still a bounce, not a crossing back.
                if crossingGrant == grant.id { lastCrossingAt = now; crossingGrant = nil }
                let waiting = deliveryBuffer; deliveryBuffer = []
                for (source, event) in waiting where self.grant?.id == grant.id { route(event, source: source, grant: grant) }
            }
        case .stop(let id, let localChoice):
            // A Mac that chose local control is not counted as ready again
            // until its polls say so.
            if node.isOwner, peer != node.localID, localChoice == true { readiness[peer] = nil }
            // A Mac giving up on the handoff it was offered: same as not answering.
            if node.isOwner, peer != node.localID, let id, id == pending?.id, pending?.participants.contains(peer) == true, fallback != nil {
                abandonPending(missing: [peer]); return
            }
            if node.isOwner && (id == nil || id == grant?.id || id == pending?.id) && (grant?.participants.contains(peer) == true || pending?.participants.contains(peer) == true || peer == node.localID) { end(peer == node.localID ? "this Mac stopped sharing" : (node.group.computers.first { $0.id == peer }?.name ?? "a computer") + " asked to stop") }
        case .event(let id, let sequence, let event):
            guard node.isOwner else { return }
            validateAuthority()
            guard let grant, grant.id == id, grant.participants.contains(peer), fresh(peer), event.valid,
                  sequence > incoming[peer, default: 0], allowEvent(peer, now: now) else { return }
            incoming[peer] = sequence
            guard installed == grant.participants else {
                guard deliveryBuffer.count < 256 else { end(); localProblem = "Input returned locally because a computer did not finish the handoff."; return }
                deliveryBuffer.append((peer, event)); return
            }
            route(event, source: peer, grant: grant)
        case .visible(let id, let monitor, let input):
            guard node.isOwner, let probe = probes.removeValue(forKey: id), probe.peer == peer, probe.monitor == monitor,
                  probe.revision == configurationRevision, now >= probe.sent, now - probe.sent < 1.5 else { return }
            visibility[monitor] = input.map { .init(input: $0, sent: probe.sent, revision: probe.revision) }
        default: break
        }
    }
    func tick() {
        guard node.isOwner else { return }
        validateAuthority()
        readiness = readiness.filter { node.online.contains($0.key) }
        reasons = reasons.filter { node.online.contains($0.key) }
        rates = rates.filter { node.online.contains($0.key) }
        let ownerNow = clock()
        probes = probes.filter { ownerNow - $0.value.sent < 1.5 }
        if ownerNow >= nextInspection, let revision = configurationRevision, node.canEdit {
            // Each probe spawns a DDC read on the control Mac. Poll quickly only
            // while a handoff is being prepared or has just been granted; an
            // idle desk does not need a subprocess per monitor every second.
            let handoffActive = pending != nil || (grant != nil && ownerNow - grantedAt < 5)
            nextInspection = ownerNow + (handoffActive ? 0.75 : 5)
            for monitor in node.group.monitors {
                guard let peer = monitor.control?.computer, fresh(peer), !probes.values.contains(where: { $0.monitor == monitor.id }) else { continue }
                let id = UUID(); probes[id] = .init(peer: peer, monitor: monitor.id, sent: ownerNow, revision: revision)
                send(.inspect(id, revision, monitor.id), to: peer)
            }
        }
    }
    private func allowEvent(_ peer: UUID, now: Double) -> Bool {
        let old = rates[peer] ?? (now, 0)
        let count = now - old.0 >= 1 ? 1 : old.1 + 1
        rates[peer] = (now - old.0 >= 1 ? now : old.0, count)
        if count > 4000 { end(); localProblem = "Input returned locally because a computer sent events too quickly."; return false }
        return true
    }
    private func fresh(_ peer: UUID) -> Bool {
        if peer == node.localID { return enabled && ready() }
        guard node.online.contains(peer), let time = readiness[peer] else { return false }
        return clock() >= time && clock() - time < 2.5
    }
    private func prepare(_ value: KVMInputGrant) {
        session.upcoming = value
        end(); pending = value; pendingAt = clock(); session.lastPrepareAt = pendingAt
        session.upcoming = nil
        fallback = nil
        // A Mac on an older Perch cannot report its own clicks, so typing
        // follows the pointer again at each handoff, as it did there.
        if !session.all(value.participants, can: KVMInputProtocol.typingAcrossHandoffs) { keyboardFocus = nil }
        session.focusChanged()
        for peer in value.participants { send(.prepare(value), to: peer) }
    }
    private func validateAuthority() {
        if let grant {
            let stale = grant.participants.filter { !fresh($0) }
            if !stale.isEmpty {
                let names = stale.map { peer in node.group.computers.first { $0.id == peer }?.name ?? String(peer.uuidString.prefix(8)) }.sorted()
                end(names.joined(separator: ", ") + " has not confirmed it is ready to share in the last 2.5 s")
            } else if grant.revision != configurationRevision {
                end("the desk configuration changed since control was granted")
            } else if !node.canEdit {
                end("this Mac cannot edit the desk right now")
            }
        }
        if let grant {
            let now = clock()
            let missingHeartbeat = grant.participants.contains { peer in
                peer != node.localID && now - peerHeartbeats[peer, default: 0] >= KVMInputLease.duration
            }
            if missingHeartbeat {
                end("a computer stopped confirming the shared lease")
                localProblem = "Input returned locally because a computer stopped confirming the shared lease. Perch will retry automatically."
            }
        }
        if let grant, installed != grant.participants, clock() - grantedAt >= 2 { end("a computer did not accept control within 2 s"); localProblem = "A computer did not accept control in time. Input is local." }
        if let failed = pending, clock() - pendingAt >= 3 {
            abandonPending(missing: failed.participants.subtracting(prepared).subtracting([node.localID]))
        }
    }
    /// A handoff that did not complete: these Macs never answered or gave up.
    /// A crossing or a Mac joining goes back to how the desk was, without them,
    /// rather than ending sharing for everyone; a 30 s pause stops a Mac that
    /// cannot finish from interrupting the desk over and over.
    private func abandonPending(missing: Set<UUID>) {
        guard let failed = pending else { return }
        let names = missing.map { peer in node.group.computers.first { $0.id == peer }?.name ?? String(peer.uuidString.prefix(8)) }.sorted().joined(separator: ", ")
        for peer in missing { joinAttempts[peer] = clock() }
        if let previous = fallback, previous.participants.contains(previous.pointer.computer), !missing.contains(previous.pointer.computer),
           let revision = configurationRevision {
            PerchLog.record("input.end", (names.isEmpty ? "A computer" : names) + " did not finish the handoff; the desk carries on as it was")
            prepare(.init(id: UUID(), epoch: node.graph.roster.epoch, revision: revision, preset: failed.preset,
                          participants: previous.participants.subtracting(missing).union([node.localID]), focus: previous.pointer))
            return
        }
        end((names.isEmpty ? "a computer" : names) + " did not finish the handoff within 3 s")
        localProblem = (names.isEmpty ? "A computer" : names) + " did not finish the handoff. Control remains local."
    }
    private func route(_ value: KVMInputEvent, source: UUID, grant: KVMInputGrant) {
        // Movement that says no button is down, from a Mac still recorded as
        // holding one, means that button's release was lost (its tap was off,
        // or the link dropped). Release it now rather than drag on with it.
        if value.kind == .motion, value.dragging == false {
            for code in held.buttons(of: source) { route(KVMInputEvent(kind: .buttonUp, code: code), source: source, grant: grant) }
        }
        guard var location = pointer, var screen = node.group.monitors.first(where: { $0.id == location.monitor }),
              let preset = node.group.presets.first(where: { $0.id == grant.preset }) else { return }
        if value.kind == .motion {
            // The Mac that has focus reports where its hardware cursor actually
            // is; that also covers macOS moving it natively between two of its
            // own screens. Raw deltas only serve to detect an edge push.
            if source == location.computer {
                // The Mac showing the pointer reports where its cursor really is.
                // With no position, its cursor is on a screen that is not part of
                // the desk (a lid-open MacBook panel, Sidecar): that movement
                // says nothing about the desk, so the pointer stays put. Adding
                // it to the last known spot could carry it across an edge.
                // A point on a shared edge lies on both screens: it is on the
                // reporting Mac's own one.
                guard let absolute = value.absolute,
                      let here = node.group.monitors.first(where: { $0.geometry.contains(absolute) && destination(preset: grant.preset, monitor: $0.id) == source }) else { return }
                screen = here; location.monitor = here.id; location.position = absolute
                // The position already includes this movement. Only a push
                // outwards from the very edge, which macOS stopped, can cross;
                // anywhere else the cursor simply is where it says.
                let g = here.geometry, edge = KVMPointerRules.edgeTolerance
                let pushing = (value.x > 0 && g.right - absolute.x <= edge) || (value.x < 0 && absolute.x - g.x <= edge) ||
                              (value.y > 0 && g.bottom - absolute.y <= edge) || (value.y < 0 && absolute.y - g.y <= edge)
                if !pushing { pointer = location; return }
            }
            let from = location.position
            // Holding a button is a drag on the screen it started on. Crossing
            // mid-drag lost the button's release on one Mac and dropped the drag
            // at the edge of the other, so the pointer waits at the edge instead.
            let dragging = value.dragging == true || held.buttonHeld
            // The sender's own millimetres when it knows them, so the same hand
            // movement covers the same distance on every screen; else points
            // read at the pointer's screen scale, as an older Perch sends.
            let delta: KVMPoint
            if let mm = value.mm { delta = mm } else {
                let scale = motionScale(location)
                guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else { return }
                delta = KVMPoint(x: value.x * scale.x, y: value.y * scale.y)
            }
            let proposed = KVMPoint(x: location.position.x + delta.x, y: location.position.y + delta.y)
            if !screen.geometry.contains(proposed) {
                location.position = .init(x: min(screen.geometry.right, max(screen.geometry.x, proposed.x)),
                                          y: min(screen.geometry.bottom, max(screen.geometry.y, proposed.y)))
                let now = clock()
                // An overshoot corrected within a fraction of a second is not a
                // deliberate crossing back into the screen just left. Carrying on in
                // the same direction is: handoffs now finish within a round trip, so a
                // fast swipe can reach the next edge well inside that window.
                func bouncesBack(_ target: UUID) -> Bool { now - lastCrossingAt < 0.15 && target == lastCrossingFrom }
                switch KVMEdge.crossing(group: node.group, preset: preset, source: screen.id, from: from, to: proposed) {
                case .remote(let monitor, let computer, let entry):
                    // A Mac that is ready but not yet in the grant joins it here.
                    guard !dragging, !bouncesBack(monitor), fresh(computer), session.versionIssue(computer) == nil,
                          let target = node.group.monitors.first(where: { $0.id == monitor })?.geometry else { break }
                    lastCrossingAt = now; lastCrossingFrom = screen.id
                    // Carry on by as much as the hand went past the edge, so a
                    // straight movement stays straight across the two screens.
                    let landing = KVMPointerRules.carry(proposed, entry: entry, into: target)
                    let next = KVMInputGrant(id: UUID(), epoch: grant.epoch, revision: grant.revision, preset: grant.preset,
                                             participants: grant.participants.union([computer]), focus: .init(monitor: monitor, computer: computer, position: landing))
                    let previous = (grant.participants, location)
                    crossingGrant = next.id
                    prepare(next)
                    fallback = previous
                    return
                case .native:
                    if let next = node.group.monitors.first(where: { $0.id != screen.id && $0.geometry.contains(proposed) }), !bouncesBack(next.id) {
                        location.monitor = next.id; location.position = proposed
                    }
                case .blocked: break
                }
            } else { location.position = proposed }
            pointer = location
        }
        // A click is what moves typing to a Mac, the way one Mac decides which
        // window is typed into. Hovering another screen no longer takes the
        // keyboard with it.
        if KVMInputRouting.claimsKeyboard(value.kind) { keyboardFocus = location }
        let keyboard = keyboardFocus.flatMap { candidate -> KVMInputFocus? in
            guard grant.participants.contains(candidate.computer), fresh(candidate.computer),
                  destination(preset: grant.preset, monitor: candidate.monitor) == candidate.computer else { return nil }
            return candidate
        }
        if keyboardFocus != nil && keyboard == nil { keyboardFocus = nil }
        let target = KVMInputRouting.target(value.kind, pointer: location, keyboard: keyboard)
        // Nothing is delivered back to the Mac whose own hardware produced it:
        // its events stayed native, so an echo would double every action.
        guard source != target.computer else { return }
        guard outputSequence < UInt64.max else { end(); return }
        outputSequence += 1
        if let event = held.apply(value, source: source) {
            if !send(.delivery(grant.id, source, outputSequence, event, target), to: target.computer) {
                end(); localProblem = "Input returned locally because the destination Mac disconnected. Perch will reconnect automatically."
            }
        }
    }
    func end(_ reason: String? = nil) {
        if let reason, grant != nil || pending != nil { PerchLog.record("input.end", "The desk took control back: " + reason) }
        // Participants release their own injected state when the next poll
        // returns nil (or independently within one second if unreachable).
        grant = nil; pending = nil; prepared = []; pointer = nil; incoming = [:]
        installed = []; deliveryBuffer = []; peerHeartbeats = [:]
        // The owner is a participant too: its own side lets go as well.
        session.releaseOwnParticipation()
        _ = held.releaseAll()
    }
}

/// The rules for where the pointer goes, as pure functions pinned by fast tests.
enum KVMPointerRules {
    /// Whether a request to place the pointer on a screen may move it.
    ///
    /// The desk has exactly two things that move the pointer, and only one of
    /// them may be running at a time:
    ///
    /// - Starting: a Mac asks for the pointer on one of its screens. This is
    ///   how sharing begins, and it is allowed only while sharing is not yet
    ///   running.
    /// - Crossing: once sharing runs, the pointer moves because it reached a
    ///   screen edge. `route` decides that centrally, from the motion reported
    ///   by whichever Mac is holding the pointer, so it stays one decision no
    ///   matter how many Macs are on the desk.
    ///
    /// Letting a start request through mid-session let a Mac take a pointer it
    /// did not have. Worse, it fed itself: preparing a handoff clears every
    /// Mac's record of where the pointer is, and a Mac that does not know where
    /// the pointer is asks for it on its own screen. So each handoff caused the
    /// next one, and two Macs traded the pointer about once a second with the
    /// person's hands nowhere near it. The old one-second guard did not cause
    /// that loop; it only set its tempo.
    ///
    /// The person is the exception, because a deliberate act is the one request
    /// that cannot be generated by the desk arguing with itself: choosing a
    /// preset, or Share on this Mac, places the pointer at any time.
    static func placementAllowed(sharing: Bool, automatic: Bool, pointerAlreadyThere: Bool) -> Bool {
        guard sharing else { return true }
        // Asking for where the pointer already is stays a no-op, so a repeated
        // deliberate request never re-prepares a handoff on top of itself.
        return !automatic && !pointerAlreadyThere
    }

    /// Where control resumes on the screen it is moving to.
    ///
    /// Picking up the mouse attached to the other Mac carries no position, and
    /// teleporting to the middle of that screen is what made the pointer jump
    /// on every switch. Continue from where the pointer already is, moved the
    /// shortest distance needed to land on the new screen. The centre is a
    /// last resort, used only when there is no pointer yet to carry over.
    /// Nil means there is no real pointer to continue from, and Perch does not
    /// invent one: control waits rather than teleporting the cursor somewhere
    /// the person never put it.
    static func entryPoint(requested: KVMPoint?, carried: KVMPoint?, screen: KVMGeometry) -> KVMPoint? {
        if let requested, screen.contains(requested) { return requested }
        // The shared pointer wins, then the asking Mac's own cursor, each moved
        // the shortest distance needed to land on this screen.
        guard let nearest = carried ?? requested else { return nil }
        return KVMPoint(x: min(screen.right, max(screen.x, nearest.x)),
                        y: min(screen.bottom, max(screen.y, nearest.y)))
    }

    /// How close to an edge, in desk millimetres, the hardware cursor counts as
    /// on it: about two pixels on a desk monitor.
    static let edgeTolerance = 0.5
    /// Where the pointer lands on the next screen: where the movement would have
    /// taken it, as if the two screens were one, kept just inside the screen.
    static func carry(_ proposed: KVMPoint, entry: KVMPoint, into g: KVMGeometry) -> KVMPoint {
        let inset = 1.5
        guard proposed.x.isFinite, proposed.y.isFinite else { return nudge(entry, into: g) }
        let x = min(g.right - inset, max(g.x + inset, proposed.x))
        let y = min(g.bottom - inset, max(g.y + inset, proposed.y))
        return nudge(KVMPoint(x: x, y: y), into: g)
    }
    /// Start a hair inside the destination so the entry itself cannot read as
    /// an immediate crossing back.
    static func nudge(_ entry: KVMPoint, into g: KVMGeometry) -> KVMPoint {
        let inset = 1.5
        var p = entry
        if abs(p.x - g.x) < 0.001 { p.x = min(g.right, g.x + inset) } else if abs(p.x - g.right) < 0.001 { p.x = max(g.x, g.right - inset) }
        if abs(p.y - g.y) < 0.001 { p.y = min(g.bottom, g.y + inset) } else if abs(p.y - g.bottom) < 0.001 { p.y = max(g.y, g.bottom - inset) }
        return p
    }
}
