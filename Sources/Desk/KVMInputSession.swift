import Foundation
import Combine

enum KVMInputMessage: Codable {
    case poll(UUID, Bool)
    case wakeDisplay
    case state(UUID, KVMInputGrant?, String?, Set<UUID>, Set<UUID>, KVMInputFocus?)
    /// preset, screen, the requester's pointer position, and whether the request
    /// is automatic (a settling handoff may ignore those) or deliberate.
    case focus(UUID, UUID, KVMPoint?, Bool)
    case prepare(KVMInputGrant)
    case prepared(UUID)
    case installed(UUID)
    case stop(UUID?)
    case event(UUID, UInt64, KVMInputEvent)
    case delivery(UUID, UUID, UInt64, KVMInputEvent, KVMInputFocus)
    case heartbeat(UUID, UUID)
    case heartbeatAck(UUID, UUID)
    case inspect(UUID, String, UUID)
    case visible(UUID, UUID, UInt16?)
    case keyboards(Set<UUID>)
}

/// The desk owner arbitrates transient input focus, never configuration edits.
/// Losing it returns every participant to local control; there is no split-brain
/// failover and no persisted permission to capture input on the next launch.
final class KVMInputSession: ObservableObject {
    static let wirePrefix = Data("Perch input v1\0".utf8)
    let node: KVMDeskNode
    @Published private(set) var enabled = false
    @Published private(set) var focus: KVMInputFocus? {
        // Where control actually is, each time it moves. A lease that is
        // taken and dropped again leaves both lines here, which is what
        // tells a collapsed handoff apart from one that never started.
        didSet {
            PerchLog.note("input.focus", focus.map { "control on computer \($0.computer) screen \($0.monitor)" } ?? "control on this Mac")
        }
    }
    @Published private var localProblem: String?
    @Published private var coordinatorProblem: String?
    @Published private var blockedTarget: (preset: UUID, monitor: UUID)?
    private var localStatusProblem: String? {
        blockedTarget.flatMap { readinessIssue(preset: $0.preset, monitor: $0.monitor) } ?? localProblem
    }
    var problem: String? { enabled ? (contextIssue ?? localStatusProblem ?? coordinatorProblem) : nil }
    var contextIssue: String? {
        guard node.isMember else { return "This Mac is no longer in this desk. Use Add computer to join it again." }
        guard node.canEdit else { return "Desk changes need a decision. Use Review conflicting changes above before starting control." }
        guard node.online.contains(node.ownerID) else { return "Waiting to reconnect to " + node.ownerName + ". Open Perch on that Mac and keep it reachable. Perch retries automatically." }
        return nil
    }
    @Published private(set) var availableConnections: Set<UUID> = []
    @Published private(set) var readyComputers: Set<UUID> = []
    /// Emergency/local-control exits are intentional and must not be
    /// immediately undone by the runtime's automatic preset start.
    private(set) var automaticStartSuppressed = false
    var ready: () -> Bool = { false }
    var emit: (KVMInputEvent, KVMInputFocus) -> Void = { _, _ in }
    var release: () -> Void = {}
    var readMonitor: ((UUID, @escaping (UInt16?) -> Void) -> Void)?
    /// Best-effort request sent before a remote focus lease. It wakes the
    /// destination Mac’s display while leaving lock-screen/access checks intact.
    /// Accepted write-only monitor routes can permit a KVM lease while their
    /// current input remains unconfirmed. A contradictory read removes it.
    var optimisticMonitorInput: ((UUID) -> UInt16?)?
    var attachedKeyboards: () -> Set<UUID> = { [] }
    var motionScale: (KVMInputFocus) -> KVMPoint = { _ in .init(x: 1, y: 1) }
    /// Where this Mac's own pointer currently is on the given screen, in desk
    /// millimetres, so a new focus starts under the hand instead of at the centre.
    var localPointerPosition: ((UUID) -> KVMPoint?)?
    /// Declares local user activity to macOS without posting any input, so a
    /// Mac that takes part in a lease does not idle into the lock screen while
    /// its keyboard is driving another Mac. Injected by the native adapter.
    var keepAwake: (() -> Void)?
    private var nextKeepAwake: Double = 0
    private var lastPrepareAt: Double = -.infinity
    private var lastCrossingAt: Double = -.infinity
    /// A handoff was requested or received very recently. Automatic focus
    /// starts wait for it to settle instead of competing with it.
    var settling: Bool { clock() - lastPrepareAt < 2 }
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    private var lease = KVMInputLease()
    private var preparedGrant: KVMInputGrant?
    private var preparedAt: Double = 0
    private var buffered: [KVMInputEvent] = []
    private var attachmentWaitingSince: Double?
    private var attachmentBuffered: [KVMInputEvent] = []
    private var grant: KVMInputGrant?
    private var pending: KVMInputGrant?
    private var prepared: Set<UUID> = []
    private var installed: Set<UUID> = []
    private var grantedAt: Double = 0
    private var deliveryBuffer: [(UUID, KVMInputEvent)] = []
    private var pendingAt: Double = 0
    private var readiness: [UUID: Double] = [:]
    private var incoming: [UUID: UInt64] = [:]
    private var sequence: UInt64 = 0
    private var polls: [UUID: Double] = [:]
    private var stateExpires: Double = 0
    private var pendingStart: (UUID, UUID, Double)?
    private var outputSequence: UInt64 = 0
    private var nextHeartbeat: Double = 0
    private var heartbeats: [UUID: Double] = [:]
    /// The owner must know that every participant is still inside the same
    /// short-lived lease. Readiness polls only prove that a process is alive;
    /// they do not prove that its local lease has not expired. Without this
    /// fence, one participant could fall back to local input while the owner
    /// continued delivering the old grant to another participant.
    private var peerHeartbeats: [UUID: Double] = [:]
    private var pendingMotion: KVMInputEvent?
    private var motionFlushScheduled = false
    private var held = KVMInputHeld()
    private var pointer: KVMInputFocus?
    /// A participant may briefly outlive the coordinator's view of a lease.
    /// Fence local events for one bounded reconciliation interval, then return
    /// them locally even if the peer is unreachable. An unbounded fence would
    /// turn a transient network loss into a machine that appears frozen.
    private var localInputSuppressedUntil: Double = 0
    /// Monotonic timestamp of the locally accepted grant. A state(nil)
    /// response can have been generated by an earlier poll than a prepare;
    /// without this fence it could tear down a newer grant that arrived on
    /// the opposite direction of the TCP connection.
    private var localGrantAcceptedAt: Double = -.infinity
    private var timer: Timer?
    private var fingerprintGroup: KVMGroup?
    private var fingerprintValue: String?
    private var configurationRevision: String? {
        guard node.canEdit else { return nil }
        if fingerprintGroup != node.group {
            fingerprintGroup = node.group; fingerprintValue = KVMInputConfiguration.revision(node.group)
        }
        return fingerprintValue
    }
    private var lastRevision: String?
    private var lastContextIssue: String?
    private struct Probe { let peer: UUID; let monitor: UUID; let sent: Double; let revision: String }
    private var probes: [UUID: Probe] = [:]
    private struct Visibility { let input: UInt16; let sent: Double; let revision: String }
    private var visibility: [UUID: Visibility] = [:]
    private var nextInspection: Double = 0
    private var inspecting: Set<UUID> = []
    private var rates: [UUID: (Double, Int)] = [:]
    private var keyboardFollow = KVMKeyboardFollow()
    private var keyboardAttachments: [UUID: Set<UUID>] = [:]
    private var keyboardPublished: Set<UUID>?
    private var nextKeyboardPublish: Double = 0
    private var subscriptions: Set<AnyCancellable> = []
    init(node: KVMDeskNode) {
        self.node = node
        let priorCheckpoint = node.canCheckpoint
        node.canCheckpoint = { [weak self] in
            priorCheckpoint() && self?.grant == nil && self?.pending == nil && self?.lease.grant == nil
        }
        node.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.checkContext() } }.store(in: &subscriptions)
    }
    deinit { timer?.invalidate() }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value { automaticStartSuppressed = false }
        keyboardPublished = nil
        if !value { stop(); timer?.invalidate(); timer = nil; localProblem = nil; coordinatorProblem = nil; blockedTarget = nil; readyComputers = []; availableConnections = []; return }
        lastRevision = configurationRevision; lastContextIssue = contextIssue
        let timer = MainTimer.every(0.25) { [weak self] in self?.tick() }
        self.timer = timer
        tick()
    }
    func stop() {
        pendingStart = nil
        localInputSuppressedUntil = 0
        send(.stop(nil), to: node.ownerID)
        endLocal()
        if node.isOwner { endAuthority() }
    }
    func stopForLocalControl() {
        automaticStartSuppressed = true
        stop()
    }
    func allowAutomaticStart() { automaticStartSuppressed = false }
    private func endLocal() {
        release(); lease.release(); preparedGrant = nil; buffered = []; focus = nil; sequence = 0
        localGrantAcceptedAt = -.infinity
        pendingMotion = nil; motionFlushScheduled = false; heartbeats = [:]; nextHeartbeat = 0
        attachmentWaitingSince = nil; attachmentBuffered = []
    }
    private func endAuthority() {
        // Participants release their own injected state when the next poll
        // returns nil (or independently within one second if unreachable).
        grant = nil; pending = nil; prepared = []; pointer = nil; incoming = [:]
        installed = []; deliveryBuffer = []; peerHeartbeats = [:]
        // The owner is a participant too. If it was the active destination,
        // release any native keys/buttons before dropping authority; otherwise
        // a heartbeat loss or a new handoff could leave a modifier or button
        // physically held on the owner while the remote peer went local.
        release()
        // The owner is also an input participant and accepts the grant locally
        // in the same transaction. Clearing authority alone would leave that
        // local lease looking active: its event tap would consume local input
        // while the owner rejected the resulting events because `grant` is
        // already nil.
        lease.release(); preparedGrant = nil; focus = nil; sequence = 0
        pendingMotion = nil; motionFlushScheduled = false; localGrantAcceptedAt = -.infinity
        localInputSuppressedUntil = 0
        _ = held.releaseAll()
    }
    private func checkContext() {
        guard enabled else { return }
        let revision = configurationRevision, context = contextIssue
        if revision != lastRevision || context != lastContextIssue {
            let wasControlling = lease.grant != nil || preparedGrant != nil || pending != nil || pendingStart != nil
            stop(); lastRevision = revision; lastContextIssue = context
            visibility = [:]; probes = [:]; availableConnections = []; readyComputers = []; stateExpires = 0
            keyboardFollow = KVMKeyboardFollow(); keyboardAttachments = [:]; keyboardPublished = nil
            coordinatorProblem = nil; blockedTarget = nil
            localProblem = wasControlling && context == nil ? "The desk layout changed. Control returned to this Mac. Select a screen and choose Control to resume." : nil
        }
        if let grant, !grant.participants.isSubset(of: node.online) { endAuthority() }
        if let pending, !pending.participants.isSubset(of: node.online) { endAuthority() }
    }
    var active: Bool { enabled && ready() && lease.alive(now: clock()) && node.canEdit && lease.grant?.revision == configurationRevision }
    var preparing: Bool { enabled && ready() && preparedGrant != nil && lease.grant == nil && clock() >= preparedAt && clock() - preparedAt < 3 }
    /// The computer whose screen currently has the pointer, if this Mac holds a lease.
    var focusComputer: UUID? { lease.grant.map { (focus ?? $0.focus).computer } }
    var capturing: Bool { active || preparing || clock() < localInputSuppressedUntil }
    func start(preset: UUID, monitor: UUID, automatic: Bool = false) {
        localProblem = nil; coordinatorProblem = nil
        guard readinessIssue(preset: preset, monitor: monitor) == nil else {
            blockedTarget = (preset, monitor); return
        }
        blockedTarget = nil
        requestDisplayWake(preset: preset, monitor: monitor)
        send(.focus(preset, monitor, localPointerPosition?(monitor), automatic), to: node.ownerID)
    }
    private func requestDisplayWake(preset: UUID, monitor: UUID) {
        guard let assignment = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
              let computer = node.group.connections.first(where: { $0.id == assignment.connection })?.computer else { return }
        if computer == node.localID { DeskDisplayWake.request() }
        else if node.online.contains(computer) { send(.wakeDisplay, to: computer) }
    }
    /// Recheck existing sharing consent and monitor visibility; never start capture.
    func refreshReadiness() {
        localProblem = nil; coordinatorProblem = nil; blockedTarget = nil
        nextInspection = 0
        if enabled { tick() }
    }
    func resumeAfterPreset(_ preset: UUID, monitor: UUID) {
        guard enabled else { return }
        pendingStart = (preset, monitor, clock() + 5)
    }
    func readinessIssue(preset: UUID, monitor: UUID) -> String? {
        guard enabled && ready() else { return "Enable sharing and resolve this Mac’s access first." }
        if let contextIssue { return contextIssue }
        if let assignment = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
           let connection = node.group.connections.first(where: { $0.id == assignment.connection }), connection.computer != nil, connection.localDisplay == nil {
            return "Match this screen’s display in Desk before sharing input. Its monitor preset can still switch the picture."
        }
        guard node.online.contains(node.ownerID), clock() < stateExpires else { return "Waiting for " + node.ownerName + " to confirm sharing status. Turn on Share on this Mac from the Perch menu there; Perch will update this status automatically." }
        guard readyComputers.contains(node.ownerID) else { return "On " + node.ownerName + ", turn on Share on this Mac from the Perch menu. The desk coordinator must allow sharing too." }
        // No shared desk space means no edge to cross, so the pointer must
        // stay under this Mac's own control rather than being taken over
        // with nowhere to go. Decided from the monitor arrangement.
        if let saved = node.group.presets.first(where: { $0.id == preset }), !KVMEdge.sharesDeskSpace(group: node.group, preset: saved) {
            return "These screens do not sit next to each other in Desk, so there is no edge to move the pointer across. Place them side by side to share the keyboard and mouse."
        }
        guard let owner = destination(preset: preset, monitor: monitor) else { return "This input has no matched computer. Connect and match its computer before starting control." }
        let name = node.group.computers.first { $0.id == owner }?.name ?? "the screen’s computer"
        guard node.online.contains(owner) else { return name + " is offline. Open Perch there and retry the desk connection." }
        guard readyComputers.contains(owner) else { return "On " + name + ", turn on Share on this Mac from the Perch menu and resolve any access warning shown there. Perch will update this status automatically." }
        // A monitor that cannot report its current input must not block KVM.
        // The monitor command and the input handoff are separate operations:
        // an accepted write (including the optimistic readback fallback) is
        // enough to control the other computer. The UI exposes the uncertainty
        // as a check-picture note instead of an impossible recovery step.
        return nil
    }
    func inputStatusNote(preset: UUID, monitor: UUID) -> String? {
        guard let assignment = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
              let connection = node.group.connections.first(where: { $0.id == assignment.connection }),
              let expected = connection.inputCode else { return nil }
        if availableConnections.contains(connection.id) || optimisticMonitorInput?(monitor) == expected { return nil }
        return "Monitor input is not confirmed. Control can still start; check the picture after switching."
    }
    /// Returning false means the native adapter must leave the event local.
    func capture(_ event: KVMInputEvent) -> Bool {
        // Do not leak input locally while the coordinator is still fencing an
        // expired remote lease. Ctrl-Opt-Esc is handled before this method by
        // DeskInputAdapter and remains an immediate local-control escape.
        if clock() < localInputSuppressedUntil, event.valid { return true }
        if localInputSuppressedUntil != 0 {
            localInputSuppressedUntil = 0
            if localProblem?.hasPrefix("Input is paused") == true { localProblem = nil }
        }
        if attachmentWaitingSince != nil, enabled && ready(), event.valid {
            buffer(&attachmentBuffered, event); return true
        }
        if preparing, event.valid {
            // A handoff whose destination is this Mac keeps native input flowing.
            if preparedGrant?.focus.computer == node.localID { return false }
            buffer(&buffered, event); return true
        }
        guard active, event.valid, let grant = lease.grant else { return false }
        let localFocus = (focus ?? grant.focus).computer == node.localID
        if event.kind == .motion {
            pendingMotion = pendingMotion.map { previous in
                var combined = event
                combined.x += previous.x; combined.y += previous.y
                return combined
            } ?? event
            scheduleMotionFlush()
            // With focus on this Mac the hardware cursor has already moved; the
            // coordinator only needs the position to notice an edge crossing.
            return !localFocus
        }
        // Keys, clicks and scrolling stay native while this Mac has focus.
        // Re-injecting them only added latency and broke secure text fields.
        if localFocus { return false }
        flushMotion()
        guard sequence < UInt64.max else { stop(); return false }
        sequence += 1
        guard send(.event(grant.id, sequence, event), to: node.ownerID) else {
            stop(); localProblem = "Input returned locally because the Desk connection was lost. Perch will reconnect automatically."
            return false
        }
        return true
    }
    /// Events swallowed while a handoff was pending are forwarded once focus is
    /// known. If focus landed on this very Mac they cannot "pass through" any
    /// more, so keys and clicks are injected here; motion is simply dropped.
    private func replay(_ events: [KVMInputEvent]) {
        let local = focusComputer == node.localID
        for event in events {
            if !local { _ = capture(event); continue }
            if event.kind != .motion, let focus { emit(event, focus) }
        }
    }
    /// Motion coalesces into the last buffered motion; a fast swipe across an
    /// edge must not overflow the handoff buffer and tear the session down.
    private func buffer(_ store: inout [KVMInputEvent], _ event: KVMInputEvent) {
        if event.kind == .motion, let last = store.last, last.kind == .motion {
            var combined = event; combined.x += last.x; combined.y += last.y; store[store.count - 1] = combined
        } else if store.count < 64 { store.append(event) }
        else if let index = store.firstIndex(where: { $0.kind == .motion }) { store.remove(at: index); store.append(event) }
    }
    private func scheduleMotionFlush() {
        guard !motionFlushScheduled else { return }
        motionFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [weak self] in
            guard let self else { return }
            self.motionFlushScheduled = false
            self.flushMotion()
        }
    }
    private func flushMotion() {
        guard let event = pendingMotion else { return }
        pendingMotion = nil
        guard active, event.valid, let grant = lease.grant, sequence < UInt64.max else { return }
        sequence += 1
        guard send(.event(grant.id, sequence, event), to: node.ownerID) else {
            stop(); localProblem = "Input returned locally because the Desk connection was lost. Perch will reconnect automatically."
            return
        }
    }
    @discardableResult func receive(_ data: Data, peer: UUID) -> Bool {
        guard data.starts(with: Self.wirePrefix) else { return false }
        guard data.count <= 8192, let message = try? JSONDecoder().decode(KVMInputMessage.self, from: data.dropFirst(Self.wirePrefix.count)) else { return true }
        receive(message, peer: peer); return true
    }
    @discardableResult private func send(_ message: KVMInputMessage, to peer: UUID) -> Bool {
        if peer == node.localID { DispatchQueue.main.async { [weak self] in self?.receive(message, peer: peer) }; return true }
        if let data = try? JSONEncoder().encode(message) { return node.sendApplication(Self.wirePrefix + data, peer: peer) }
        return false
    }
    private func receive(_ message: KVMInputMessage, peer: UUID) {
        guard node.isMember, node.online.contains(peer) else { return }
        let now = clock()
        switch message {
        case .wakeDisplay:
            guard peer == node.ownerID || node.isOwner else { return }
            DeskDisplayWake.request()
        case .heartbeat(let nonce, let grantID):
            guard node.isOwner, enabled, ready(), let grant,
                  grant.id == grantID, grant.participants.contains(peer), fresh(peer) else { return }
            peerHeartbeats[peer] = now
            send(.heartbeatAck(nonce, grantID), to: peer)
        case .heartbeatAck(let nonce, let grantID):
            guard peer == node.ownerID, enabled, let sent = heartbeats.removeValue(forKey: nonce),
                  now >= sent, now - sent < KVMInputLease.duration,
                  let grant = lease.grant, grant.id == grantID, lease.alive(now: now) else { return }
            lease.renew(grant: grantID, now: now)
        case .keyboards(let attached):
            guard node.isOwner, enabled, fresh(peer), attached.count <= 16,
                  attached.isSubset(of: Set((node.group.sharedKeyboards ?? []).filter { $0.bindings[peer] != nil }.map(\.id))) else { return }
            let previous = keyboardAttachments[peer] ?? []
            keyboardAttachments[peer] = attached
            for keyboard in previous.symmetricDifference(attached) {
                if let destination = keyboardFollow.observe(keyboard: keyboard, computer: peer, attached: attached.contains(keyboard), online: node.online),
                   node.group.sharedKeyboards?.first(where: { $0.id == keyboard })?.follow == true,
                   let grant, let monitor = node.group.monitors.first(where: { self.destination(preset: grant.preset, monitor: $0.id) == destination }) {
                    receive(.focus(grant.preset, monitor.id, nil, false), peer: destination)
                }
            }
        case .poll(let nonce, let available):
            guard node.isOwner else { return }
            if available && enabled { readiness[peer] = now } else { readiness[peer] = nil }
            if grant?.participants.contains(peer) == true && !available { endAuthority() }
            validateAuthority()
            let connections = Set(node.group.connections.filter { connection in
                if let observed = visibility[connection.monitor], observed.revision == configurationRevision,
                   now >= observed.sent, now - observed.sent < 2 {
                    return observed.input == connection.inputCode
                }
                return optimisticMonitorInput?(connection.monitor) == connection.inputCode
            }.map(\.id))
            send(.state(nonce, available ? grant : nil, localStatusProblem, connections, Set(readiness.keys.filter(fresh)).union(fresh(node.localID) ? [node.localID] : []), pointer), to: peer)
        case .state(let nonce, let value, let issue, let connections, let computers, let currentFocus):
            guard peer == node.ownerID, enabled, let sent = polls.removeValue(forKey: nonce), now >= sent, now - sent < 2.5,
                  connections.count <= 256, computers.isSubset(of: Set(node.group.computers.map(\.id))) else { return }
            if availableConnections != connections { availableConnections = connections }
            if readyComputers != computers { readyComputers = computers }
            // The response proves the owner was reachable now. Start the
            // local freshness window at receipt, rather than at the sender's
            // earlier poll timestamp, so normal network latency does not
            // cause a visible focus hiccup.
            stateExpires = now + KVMInputLease.duration
            if let value {
                let first = lease.grant == nil
                guard ready(), preparedGrant == value, value.participants.contains(node.localID),
                      let revision = configurationRevision, value.valid(group: node.group, epoch: node.graph.roster.epoch, revision: revision),
                      lease.accept(value, challenge: nonce, now: now) else { return }
                localGrantAcceptedAt = now
                let current = currentFocus.flatMap { location in
                    destination(preset: value.preset, monitor: location.monitor) == value.focus.computer &&
                        node.group.monitors.first(where: { $0.id == location.monitor })?.geometry.contains(location.position) == true ? location : nil
                } ?? value.focus
                if focus?.monitor != current.monitor || focus?.computer != current.computer { focus = current }
                if localProblem != nil { localProblem = nil }
                if blockedTarget != nil { blockedTarget = nil }
                if coordinatorProblem != nil { coordinatorProblem = nil }
                if first {
                    send(.installed(value.id), to: peer)
                    let waiting = buffered; buffered = []
                    replay(waiting)
                }
                if attachmentWaitingSince != nil, current.computer == node.localID {
                    let waiting = attachmentBuffered; attachmentBuffered = []; attachmentWaitingSince = nil
                    replay(waiting)
                }
            } else {
                // A poll response may predate a prepare already received on this
                // ordered connection. Do not discard that pending preparation.
                if lease.grant != nil, localGrantAcceptedAt <= sent { endLocal() }
                // The coordinator has explicitly reported that no grant is
                // active. It is safe to release the local input fence; a
                // subsequent prepare installs a new transaction first.
                localInputSuppressedUntil = 0
                let remote = issue.map { String($0.prefix(300)) }
                if coordinatorProblem != remote { coordinatorProblem = remote }
            }
        case .focus(let preset, let monitor, let position, let automatic):
            guard node.isOwner, enabled, ready(), pending == nil, fresh(peer), let revision = configurationRevision, node.canEdit,
                  let screen = node.group.monitors.first(where: { $0.id == monitor }),
                  let owner = destination(preset: preset, monitor: monitor), fresh(owner) else {
                if node.isOwner { localProblem = nil; blockedTarget = (preset, monitor) }
                return
            }
            if let grant, grant.preset == preset {
                // An automatic request against a grant that is still settling,
                // or any request for where focus already is, is not
                // re-prepared. Re-preparing here is what teleported the pointer
                // to a screen centre after every handoff whenever another
                // Mac's automatic start raced it.
                if automatic, now - grantedAt < 1, peer != grant.focus.computer { return }
                if pointer?.monitor == monitor, pointer?.computer == owner { return }
            }
            let entry = Self.entryPoint(requested: position, carried: pointer?.position, screen: screen.geometry)
            let participants = Set(readiness.keys.filter(fresh)).union([node.localID])
            prepare(.init(id: UUID(), epoch: node.graph.roster.epoch, revision: revision, preset: preset,
                          participants: participants, focus: .init(monitor: monitor, computer: owner, position: entry)))
        case .prepare(let value):
            guard peer == node.ownerID, enabled, ready(), value.participants.contains(node.localID), let revision = configurationRevision,
                  value.valid(group: node.group, epoch: node.graph.roster.epoch, revision: revision) else { return }
            let attachmentTime = attachmentWaitingSince, attachmentEvents = attachmentBuffered
            endLocal(); localInputSuppressedUntil = 0; preparedGrant = value; preparedAt = now; lastPrepareAt = now
            if value.focus.computer == node.localID { attachmentWaitingSince = attachmentTime; attachmentBuffered = attachmentEvents }
            send(.prepared(value.id), to: peer)
        case .prepared(let id):
            guard node.isOwner, let pending, pending.id == id, pending.participants.contains(peer), now - pendingAt < 2 else { return }
            prepared.insert(peer)
            if prepared == pending.participants {
                grant = pending; self.pending = nil; pointer = pending.focus; focus = pending.focus; incoming = [:]; outputSequence = 0
                installed = []
                if pending.participants.contains(node.localID) {
                    lease.acceptLocally(pending, now: now)
                    localGrantAcceptedAt = now
                    installed.insert(node.localID)
                }
                grantedAt = now
                peerHeartbeats = Dictionary(uniqueKeysWithValues: pending.participants.filter { $0 != node.localID }.map { ($0, now) })
                localProblem = nil
            }
        case .installed(let id):
            guard node.isOwner, let grant, grant.id == id, grant.participants.contains(peer) else { return }
            installed.insert(peer)
            if installed == grant.participants {
                let waiting = deliveryBuffer; deliveryBuffer = []
                for (source, event) in waiting where self.grant?.id == grant.id { route(event, source: source, grant: grant) }
            }
        case .stop(let id):
            if node.isOwner && (id == nil || id == grant?.id || id == pending?.id) && (grant?.participants.contains(peer) == true || pending?.participants.contains(peer) == true || peer == node.localID) { endAuthority() }
        case .event(let id, let sequence, let event):
            guard node.isOwner else { return }
            validateAuthority()
            guard let grant, grant.id == id, grant.participants.contains(peer), fresh(peer), event.valid,
                  sequence > incoming[peer, default: 0], allowEvent(peer, now: now) else { return }
            incoming[peer] = sequence
            guard installed == grant.participants else {
                guard deliveryBuffer.count < 256 else { endAuthority(); localProblem = "Input returned locally because a computer did not finish the handoff."; return }
                deliveryBuffer.append((peer, event)); return
            }
            route(event, source: peer, grant: grant)
        case .delivery(let id, let source, let sequence, let event, let location):
            guard peer == node.ownerID, active, event.valid, let grant = lease.grant, location.computer == node.localID,
                  destination(preset: grant.preset, monitor: location.monitor) == node.localID,
                  node.group.monitors.first(where: { $0.id == location.monitor })?.geometry.contains(location.position) == true,
                  lease.accepts(source: source, grant: id, sequence: sequence, now: now) else { return }
            emit(event, location)
        case .inspect(let id, let revision, let monitor):
            guard peer == node.ownerID, enabled, revision == configurationRevision, !inspecting.contains(monitor),
                  node.group.monitors.first(where: { $0.id == monitor })?.control?.computer == node.localID, let readMonitor else { return }
            inspecting.insert(monitor)
            readMonitor(monitor) { [weak self] input in
                guard let self else { return }; self.inspecting.remove(monitor)
                guard self.enabled, self.configurationRevision == revision else { return }
                self.send(.visible(id, monitor, input), to: peer)
            }
        case .visible(let id, let monitor, let input):
            guard node.isOwner, let probe = probes.removeValue(forKey: id), probe.peer == peer, probe.monitor == monitor,
                  probe.revision == configurationRevision, now >= probe.sent, now - probe.sent < 1.5 else { return }
            visibility[monitor] = input.map { .init(input: $0, sent: probe.sent, revision: probe.revision) }
        }
    }
    private func allowEvent(_ peer: UUID, now: Double) -> Bool {
        let old = rates[peer] ?? (now, 0)
        let count = now - old.0 >= 1 ? 1 : old.1 + 1
        rates[peer] = (now - old.0 >= 1 ? now : old.0, count)
        if count > 4000 { endAuthority(); localProblem = "Input returned locally because a computer sent events too quickly."; return false }
        return true
    }
    private func fresh(_ peer: UUID) -> Bool {
        if peer == node.localID { return enabled && ready() }
        guard node.online.contains(peer), let time = readiness[peer] else { return false }
        return clock() >= time && clock() - time < 2.5
    }
    private func destination(preset: UUID, monitor: UUID) -> UUID? {
        guard let route = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }) else { return nil }
        guard let connection = node.group.connections.first(where: { $0.id == route.connection }), connection.localDisplay != nil else { return nil }
        return connection.computer
    }
    private func visible(preset: UUID, monitor: UUID) -> Bool {
        guard let route = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
              let input = node.group.connections.first(where: { $0.id == route.connection })?.inputCode else { return false }
        if let observation = visibility[monitor], observation.revision == configurationRevision,
           clock() >= observation.sent, clock() - observation.sent < 2 {
            return observation.input == input
        }
        return optimisticMonitorInput?(monitor) == input
    }
    private func prepare(_ value: KVMInputGrant) {
        endAuthority(); pending = value; pendingAt = clock(); lastPrepareAt = pendingAt
        for peer in value.participants { send(.prepare(value), to: peer) }
    }
    private func validateAuthority() {
        if let grant, (!grant.participants.allSatisfy(fresh) ||
                       grant.revision != configurationRevision || !node.canEdit) { endAuthority() }
        if let grant {
            let now = clock()
            let missingHeartbeat = grant.participants.contains { peer in
                peer != node.localID && now - peerHeartbeats[peer, default: 0] >= KVMInputLease.duration
            }
            if missingHeartbeat {
                endAuthority()
                localProblem = "Input returned locally because a computer stopped confirming the shared lease. Perch will retry automatically."
            }
        }
        if let grant, installed != grant.participants, clock() - grantedAt >= 2 { endAuthority(); localProblem = "A computer did not accept control in time. Input is local." }
        if pending != nil && clock() - pendingAt >= 3 { endAuthority(); localProblem = "A computer did not finish releasing input. Control remains local." }
    }
    private func route(_ value: KVMInputEvent, source: UUID, grant: KVMInputGrant) {
        guard var location = pointer, var screen = node.group.monitors.first(where: { $0.id == location.monitor }),
              let preset = node.group.presets.first(where: { $0.id == grant.preset }) else { return }
        if value.kind == .motion {
            // The Mac that has focus reports where its hardware cursor actually
            // is; that also covers macOS moving it natively between two of its
            // own screens. Raw deltas only serve to detect an edge push.
            if let absolute = value.absolute, source == location.computer,
               let here = node.group.monitors.first(where: { $0.geometry.contains(absolute) }),
               destination(preset: grant.preset, monitor: here.id) == source {
                screen = here; location.monitor = here.id; location.position = absolute
            }
            let from = location.position
            let scale = motionScale(location)
            guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else { return }
            let proposed = KVMPoint(x: location.position.x + value.x * scale.x, y: location.position.y + value.y * scale.y)
            if !screen.geometry.contains(proposed) {
                location.position = .init(x: min(screen.geometry.right, max(screen.geometry.x, proposed.x)),
                                          y: min(screen.geometry.bottom, max(screen.geometry.y, proposed.y)))
                let now = clock()
                // An overshoot corrected within a fraction of a second is not a
                // deliberate crossing back.
                if now - lastCrossingAt >= 0.15 {
                    switch KVMEdge.crossing(group: node.group, preset: preset, source: screen.id, from: from, to: proposed) {
                    case .remote(let monitor, let computer, let entry):
                        guard grant.participants.contains(computer), fresh(computer),
                              let target = node.group.monitors.first(where: { $0.id == monitor })?.geometry else { break }
                        lastCrossingAt = now
                        prepare(.init(id: UUID(), epoch: grant.epoch, revision: grant.revision, preset: grant.preset,
                                      participants: grant.participants, focus: .init(monitor: monitor, computer: computer, position: Self.nudge(entry, into: target))))
                        return
                    case .native:
                        if let next = node.group.monitors.first(where: { $0.id != screen.id && $0.geometry.contains(proposed) }) {
                            location.monitor = next.id; location.position = proposed
                        }
                    case .blocked: break
                    }
                }
            } else { location.position = proposed }
            pointer = location
        }
        // Nothing is delivered back to the Mac whose own hardware produced it:
        // its events stayed native, so an echo would double every action.
        guard source != location.computer else { return }
        guard outputSequence < UInt64.max else { endAuthority(); return }
        outputSequence += 1
        if let event = held.apply(value, source: source) {
            if !send(.delivery(grant.id, source, outputSequence, event, location), to: location.computer) {
                endAuthority(); localProblem = "Input returned locally because the destination Mac disconnected. Perch will reconnect automatically."
            }
        }
    }
    /// Where control resumes on the screen it is moving to.
    ///
    /// Picking up the mouse attached to the other Mac carries no position, and
    /// teleporting to the middle of that screen is what made the pointer jump
    /// on every switch. Continue from where the pointer already is, moved the
    /// shortest distance needed to land on the new screen. The centre is a
    /// last resort, used only when there is no pointer yet to carry over.
    static func entryPoint(requested: KVMPoint?, carried: KVMPoint?, screen: KVMGeometry) -> KVMPoint {
        if let requested, screen.contains(requested) { return requested }
        if let carried {
            return KVMPoint(x: min(screen.right, max(screen.x, carried.x)),
                            y: min(screen.bottom, max(screen.y, carried.y)))
        }
        return KVMPoint(x: screen.x + screen.displayedWidth / 2, y: screen.y + screen.displayedHeight / 2)
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
    func tick() {
        guard enabled else { return }
        checkContext()
        if clock() >= stateExpires {
            if !readyComputers.isEmpty { readyComputers = [] }
            if !availableConnections.isEmpty { availableConnections = [] }
        }
        if let since = attachmentWaitingSince, clock() - since >= 2 {
            // Many receivers never report a detach. Resume where control was
            // instead of stopping the whole session on every device switch.
            let waiting = attachmentBuffered; attachmentBuffered = []; attachmentWaitingSince = nil
            replay(waiting)
        }
        if let preparedGrant, lease.grant == nil, clock() - preparedAt >= 3 {
            endLocal(); send(.stop(preparedGrant.id), to: node.ownerID); localProblem = "The handoff timed out. Input is local."
        }
        if let grant = lease.grant, !lease.alive(now: clock()) || !ready() {
            let remote = (focus ?? grant.focus).computer != node.localID
            endLocal()
            if remote {
                // One bounded interval keeps a half-expired remote lease from
                // leaking keystrokes locally; with focus already here there is
                // nothing to fence.
                localInputSuppressedUntil = clock() + 1
                localProblem = "Input is paused while Perch confirms the shared lease. Press Ctrl-Opt-Esc for local control."
            }
            send(.stop(grant.id), to: node.ownerID)
        }
        let now = clock()
        heartbeats = heartbeats.filter { now - $0.value < KVMInputLease.duration }
        if let grant = lease.grant, lease.alive(now: now), node.ownerID != node.localID, now >= nextHeartbeat {
            let nonce = UUID(); heartbeats[nonce] = now
            send(.heartbeat(nonce, grant.id), to: node.ownerID)
            nextHeartbeat = now + 0.5
        }
        if lease.grant != nil || grant != nil, now >= nextKeepAwake {
            nextKeepAwake = now + 30
            keepAwake?()
        } else if lease.grant == nil, grant == nil { nextKeepAwake = 0 }
        let nonce = lease.challenge(now: clock())
        polls = polls.filter { clock() - $0.value < 2.5 }; polls[nonce] = clock()
        send(.poll(nonce, ready()), to: node.ownerID)
        if let (preset, monitor, until) = pendingStart {
            if clock() >= until { pendingStart = nil; localProblem = "The preset switched, but input sharing is still waiting for a ready computer and matched screen. Perch will retry automatically when they are ready." }
            else if readinessIssue(preset: preset, monitor: monitor) == nil { pendingStart = nil; start(preset: preset, monitor: monitor) }
        }
        publishKeyboardAttachments()
        guard node.isOwner else { return }
        validateAuthority()
        readiness = readiness.filter { node.online.contains($0.key) }
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
    func publishKeyboardAttachments() {
        guard enabled else { return }
        let attached = attachedKeyboards()
        if active, focus?.computer != node.localID, let previous = keyboardPublished,
           attached.subtracting(previous).contains(where: { id in node.group.sharedKeyboards?.first(where: { $0.id == id })?.follow == true }) {
            attachmentWaitingSince = clock(); attachmentBuffered = []
        }
        if attached != keyboardPublished || clock() >= nextKeyboardPublish {
            keyboardPublished = attached; nextKeyboardPublish = clock() + 1
            send(.keyboards(attached), to: node.ownerID)
        }
    }
}
