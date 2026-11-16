import Foundation
import Combine

/// Each Mac's own side of keyboard and mouse sharing: its lease on the grant
/// the desk owner made, capturing this Mac's keyboard and mouse and sending
/// what belongs on another Mac, posting what arrives here, and its status. The
/// owner's coordination is `KVMInputCoordinator`, which runs only on the owner.
/// The owner arbitrates transient input focus, never configuration edits;
/// losing it returns every Mac to local control, with no split-brain failover
/// and no permission to capture input that outlives the launch.
final class KVMInputSession: ObservableObject {
    static let wirePrefix = Data("Perch input v1\0".utf8)
    let node: KVMDeskNode
    @Published private(set) var enabled = false
    /// Where typing goes: the Mac last clicked on. The owner decides it; every
    /// Mac learns it with the status it already polls for.
    var keyboardFocus: KVMInputFocus?
    /// The Mac typing goes to while sharing is active, nil while it is not:
    /// the last Mac clicked on, or the pointer's Mac before any click. The
    /// shared clipboard's bring over acts for this Mac.
    var keyboardComputer: UUID? {
        guard active, let grant = lease.grant else { return nil }
        return KVMInputRouting.target(.keyDown, pointer: focus ?? grant.focus, keyboard: keyboardFocus).computer
    }
    /// Where the pointer is while this Mac holds a lease. Set here as grants and
    /// deliveries arrive; on the owner also by its coordinator.
    @Published var focus: KVMInputFocus? {
        // Where control actually is, each time it moves. A lease that is
        // taken and dropped again leaves both lines here, which is what
        // tells a collapsed handoff apart from one that never started.
        didSet {
            PerchLog.note("input.focus", focus.map { "control on computer \($0.computer) screen \($0.monitor)" } ?? "control on this Mac")
            // Straight away, not on the next run loop pass: the Mac taking the
            // pointer must place it before its own hardware or a delivered
            // event moves the cursor on from where it was parked.
            focusChanged()
        }
    }
    /// Control moved. Called the instant focus changes, in both directions.
    var focusChanged: () -> Void = {}
    @Published var localProblem: String?
    @Published private var coordinatorProblem: String?
    @Published var blockedTarget: (preset: UUID, monitor: UUID)?
    var localStatusProblem: String? {
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
    /// The Macs whose keyboard and mouse sharing is on and ready now, as this
    /// Mac knows them: the coordinator's own record on the coordinator, and the
    /// last state it sent everywhere else. Empty while sharing is off here,
    /// since only a Mac that shares hears about the others. Read by the menu
    /// bar icon.
    var sharingComputers: Set<UUID> {
        guard enabled else { return [] }
        return node.isOwner ? coordinator.sharingComputers : readyComputers
    }
    /// The sharing version each Mac last announced, and when this Mac last
    /// heard anything at all from it, so an older Perch that cannot announce
    /// one is told apart from a Mac that has not answered yet.
    private var peerVersions: [UUID: Int] = [:]
    private var peerHeard: [UUID: TimeInterval] = [:]
    private var nextVersionAnnounce: TimeInterval = 0
    /// How long to wait for a version before concluding the other Mac is too old.
    static let versionGrace: TimeInterval = 6
    /// Emergency/local-control exits are intentional and must not be
    /// immediately undone by the runtime's automatic preset start.
    private(set) var automaticStartSuppressed = false
    var ready: () -> Bool = { false }
    /// Why this Mac cannot share, while `ready` says it cannot. Injected by the
    /// native adapter.
    var readyReason: () -> KVMShareReason? = { nil }
    /// What this Mac tells the coordinator about itself.
    private var ownReason: KVMShareReason? { automaticStartSuppressed ? .choseLocal : (ready() ? nil : readyReason()) }
    /// Why each other Mac cannot share, as the coordinator last relayed it.
    private(set) var peerReasons: [UUID: KVMShareReason] = [:]
    var emit: (KVMInputEvent, KVMInputFocus) -> Void = { _, _ in }
    var release: () -> Void = {}
    var readMonitor: ((UUID, @escaping (UInt16?) -> Void) -> Void)?
    /// Best-effort request sent before a remote focus lease. It wakes the
    /// destination Mac’s display while leaving lock-screen/access checks intact.
    /// Accepted write-only monitor routes can permit a KVM lease while their
    /// current input remains unconfirmed. A contradictory read removes it.
    var optimisticMonitorInput: ((UUID) -> UInt16?)?
    var motionScale: (KVMInputFocus) -> KVMPoint = { _ in .init(x: 1, y: 1) }
    /// Where this Mac's own pointer currently is on the given screen, in desk
    /// millimetres, so a new focus starts under the hand instead of at the centre.
    var localPointerPosition: ((UUID) -> KVMPoint?)?
    /// Declares local user activity to macOS without posting any input, so a
    /// Mac that takes part in a lease does not idle into the lock screen while
    /// its keyboard is driving another Mac. Injected by the native adapter.
    var keepAwake: (() -> Void)?
    private var nextKeepAwake: Double = 0
    /// What each other Mac's sharing can do beyond its version.
    private var peerFeatures: [UUID: Set<String>] = [:]
    /// The latest count this Mac has heard, and the count when it chose local
    /// control; a later choice anywhere lets it take part again.
    var knownChoices = 0
    private var escapedAtChoice: Int?
    /// When this Mac's own mouse last clicked, so a status answer sent before
    /// that click cannot move typing back to where it was.
    private var lastLocalClickAt: Double = -.infinity
    /// Whether every other Mac in this set can do `feature`. An older Perch
    /// announces none, so the desk falls back to what it can do.
    func all(_ participants: Set<UUID>, can feature: String) -> Bool {
        participants.allSatisfy { $0 == node.localID || peerFeatures[$0]?.contains(feature) == true }
    }
    var lastPrepareAt: Double = -.infinity
    /// A handoff was requested or received very recently. Automatic focus
    /// starts wait for it to settle instead of competing with it.
    var settling: Bool { clock() - lastPrepareAt < 2 }
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    private var lease = KVMInputLease()
    private var preparedGrant: KVMInputGrant?
    private var preparedAt: Double = 0
    private var buffered: [KVMInputEvent] = []
    private var sequence: UInt64 = 0
    private var polls: [UUID: Double] = [:]
    private var stateExpires: Double = 0
    private var nextHeartbeat: Double = 0
    private var heartbeats: [UUID: Double] = [:]
    private var pendingMotion: KVMInputEvent?
    private var motionFlushScheduled = false
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
    var configurationRevision: String? {
        guard node.canEdit else { return nil }
        if fingerprintGroup != node.group {
            fingerprintGroup = node.group; fingerprintValue = KVMInputConfiguration.revision(node.group)
        }
        return fingerprintValue
    }
    private var lastRevision: String?
    private var lastContextIssue: String?
    private var inspecting: Set<UUID> = []
    private var fastPollsLeft = 0
    private var fastPollScheduled = false
    private static let fastPollLimit = 20
    private static let fastPollInterval = 0.02
    private var subscriptions: Set<AnyCancellable> = []
    /// The desk owner's side of sharing, used only on the owner.
    private(set) lazy var coordinator = KVMInputCoordinator(session: self)
    init(node: KVMDeskNode) {
        self.node = node
        let priorCheckpoint = node.canCheckpoint
        node.canCheckpoint = { [weak self] in
            priorCheckpoint() && self?.coordinator.grant == nil && self?.coordinator.pending == nil && self?.lease.grant == nil
        }
        node.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.checkContext() } }.store(in: &subscriptions)
    }
    deinit { timer?.invalidate() }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        // Turning sharing back on after macOS stopped it is not the person
        // choosing to share: Ctrl-Opt-Esc still holds (`allowAutomaticStart`).
        if !value { stop(); timer?.invalidate(); timer = nil; localProblem = nil; coordinatorProblem = nil; blockedTarget = nil; readyComputers = []; availableConnections = []; return }
        lastRevision = configurationRevision; lastContextIssue = contextIssue
        let timer = MainTimer.every(0.25) { [weak self] in self?.tick() }
        self.timer = timer
        tick()
    }
    func stop(_ reason: String = "stopped on this Mac") {
        PerchLog.record("input.end", "Control ended: " + reason)
        localInputSuppressedUntil = 0
        send(.stop(nil, automaticStartSuppressed ? true : nil), to: node.ownerID)
        endLocal()
        if node.isOwner { coordinator.end() }
        // Typing outlives a handoff, but not sharing itself.
        keyboardFocus = nil
    }
    func stopForLocalControl() {
        automaticStartSuppressed = true
        // The stop says it was the person's choice, so the coordinator makes
        // the next grant without this Mac rather than waiting for it in vain.
        escapedAtChoice = knownChoices
        stop("Ctrl-Opt-Esc on this Mac")
    }
    /// The person chose a preset or Share again: this Mac takes part once more.
    /// Its next poll says so at once, before any request to start can arrive.
    func allowAutomaticStart() {
        guard automaticStartSuppressed else { return }
        automaticStartSuppressed = false; escapedAtChoice = nil
        if enabled { pollNow() }
    }
    private func endLocal(_ reason: String? = nil) {
        if let reason, lease.grant != nil || preparedGrant != nil { PerchLog.record("input.end", "This Mac let go of control: " + reason) }
        // Typing stays where it was last clicked across a handoff: a crossing is
        // the pointer moving, never the keyboard (Scott, September 21).
        release(); lease.release(); preparedGrant = nil; buffered = []; focus = nil; sequence = 0
        localGrantAcceptedAt = -.infinity
        pendingMotion = nil; motionFlushScheduled = false; heartbeats = [:]; nextHeartbeat = 0
    }
    /// The coordinator ended or replaced the grant: the owner's own side lets go
    /// too. Clearing authority alone would leave the owner's lease looking active,
    /// its tap consuming local input that the coordinator then rejects.
    func releaseOwnParticipation() {
        // Release any native keys or buttons first, or a heartbeat loss or a new
        // handoff could leave one held on the owner while the others went local.
        release()
        lease.release(); preparedGrant = nil; focus = nil; sequence = 0
        pendingMotion = nil; motionFlushScheduled = false; localGrantAcceptedAt = -.infinity
        localInputSuppressedUntil = 0
    }
    /// The coordinator's own side takes the grant it just made, in the same step.
    func acceptOwnGrant(_ grant: KVMInputGrant, now: Double) {
        lease.acceptLocally(grant, now: now)
        localGrantAcceptedAt = now
    }
    /// What this Mac typed or clicked while its own handoff was on the way goes
    /// where it was meant to, as it does on the other Macs.
    func replayHeldInput() {
        let waiting = buffered; buffered = []
        replay(waiting)
    }
    private func checkContext() {
        guard enabled else { return }
        let revision = configurationRevision, context = contextIssue
        if revision != lastRevision || context != lastContextIssue {
            let wasControlling = lease.grant != nil || preparedGrant != nil || coordinator.pending != nil
            stop(revision != lastRevision ? "the desk configuration changed on this Mac" : "sharing conditions changed: " + (context ?? "now ready")); lastRevision = revision; lastContextIssue = context
            coordinator.forgetObservations(); availableConnections = []; readyComputers = []; stateExpires = 0
            peerVersions = [:]; peerHeard = [:]; nextVersionAnnounce = 0
            coordinatorProblem = nil; blockedTarget = nil
            localProblem = wasControlling && context == nil ? KVMInputStatus.layoutChanged : nil
        }
        if node.isOwner { coordinator.checkOnline() }
    }
    var active: Bool { enabled && ready() && lease.alive(now: clock()) && node.canEdit && lease.grant?.revision == configurationRevision }
    var preparing: Bool { enabled && ready() && preparedGrant != nil && lease.grant == nil && clock() >= preparedAt && clock() - preparedAt < 3 }
    /// Control is on its way from this Mac to another: as the desk owner with a
    /// handoff pending, or as a participant preparing one.
    var handingOff: Bool { coordinator.pending.map { $0.focus.computer != node.localID } == true || preparing }
    /// Where a handoff on its way will put the pointer, while one is. The cursor
    /// follows this, so it never shows in between (`DeskCursorStep`).
    var handoffTarget: KVMInputFocus? {
        if let upcoming { return upcoming.focus }
        if node.isOwner, let pending = coordinator.pending { return pending.focus }
        return preparing ? preparedGrant?.focus : nil
    }
    /// A handoff being set up right now: tearing down the old one clears focus,
    /// and the cursor must already know where the new one is going.
    var upcoming: KVMInputGrant?
    /// Where typing goes by the last click, or nil when it follows the pointer.
    var typingComputer: UUID? { keyboardFocus?.computer }
    /// Where the pointer is, as well as this Mac knows: the coordinator follows
    /// it closely, every other Mac from its grant and deliveries.
    var pointerLocation: KVMInputFocus? { node.isOwner ? (coordinator.pointer ?? focus) : focus }
    /// The computer whose screen currently has the pointer, if this Mac holds a lease.
    var focusComputer: UUID? { lease.grant.map { (focus ?? $0.focus).computer } }
    var capturing: Bool { active || preparing || clock() < localInputSuppressedUntil }
    /// `position`: where the pointer should be, in desk millimetres; this Mac's
    /// own cursor when nil.
    func start(preset: UUID, monitor: UUID, position: KVMPoint? = nil, automatic: Bool = false) {
        localProblem = nil; coordinatorProblem = nil
        guard readinessIssue(preset: preset, monitor: monitor) == nil else {
            blockedTarget = (preset, monitor); return
        }
        blockedTarget = nil
        requestDisplayWake(preset: preset, monitor: monitor)
        send(.focus(preset, monitor, position ?? localPointerPosition?(monitor), automatic), to: node.ownerID)
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
        coordinator.inspectSoon()
        if enabled { tick() }
    }
    func readinessIssue(preset: UUID, monitor: UUID) -> String? {
        blocker(preset: preset, monitor: monitor).map(KVMInputStatus.sentence)
    }
    /// Why control cannot start on this screen, as facts; worded by `KVMInputStatus`.
    func blocker(preset: UUID, monitor: UUID) -> KVMInputBlocker? {
        guard enabled && ready() else { return .notHere(enabled ? readyReason() : nil) }
        if let contextIssue { return .desk(contextIssue) }
        if let assignment = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
           let connection = node.group.connections.first(where: { $0.id == assignment.connection }), connection.computer != nil, connection.localDisplay == nil {
            return .screenNotSeen
        }
        guard node.online.contains(node.ownerID), clock() < stateExpires else { return .waitingForOwner(node.ownerName) }
        guard readyComputers.contains(node.ownerID) else { return .notSharing(node.ownerName, peerReasons[node.ownerID]) }
        if let issue = versionIssue(node.ownerID) { return .version(issue) }
        // No shared desk space means no edge to cross, so the pointer must
        // stay under this Mac's own control rather than being taken over
        // with nowhere to go. Decided from the monitor arrangement.
        if let saved = node.group.presets.first(where: { $0.id == preset }),
           let issue = KVMEdge.sharedSpaceIssue(group: node.group, preset: saved, local: node.localID) {
            return .noSharedEdge(issue)
        }
        guard let owner = destination(preset: preset, monitor: monitor) else { return .noComputer }
        let name = node.group.computers.first { $0.id == owner }?.name ?? "the screen’s computer"
        guard node.online.contains(owner) else { return .offline(name) }
        if let issue = versionIssue(owner) { return .version(issue) }
        guard readyComputers.contains(owner) else { return .notSharing(name, peerReasons[owner]) }
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
        if preparing, event.valid, let prepared = preparedGrant {
            // A handoff moves the pointer, never the keyboard. Typing stays native
            // when it goes to this Mac and waits when it goes to another; pointer
            // events stay native only when the pointer is coming here.
            let destination = KVMInputRouting.typing(event.kind) ? (keyboardFocus?.computer ?? prepared.focus.computer) : prepared.focus.computer
            if destination == node.localID { return false }
            buffer(&buffered, event); return true
        }
        guard active, event.valid, let grant = lease.grant else { return false }
        // Apple's newer function-row keys and extra mouse buttons go across only
        // when every Mac in the grant takes them; otherwise they stay here, as
        // they did before.
        if event.wide, !all(grant.participants, can: KVMInputProtocol.wideInput) { return false }
        let pointerFocus = focus ?? grant.focus
        if let typing = keyboardFocus, !grant.participants.contains(typing.computer) { keyboardFocus = nil }
        // Apply the click's effect here at once. Waiting to be told where typing
        // went, on the next quarter-second status, would send the first letters
        // after a click to the Mac the keyboard was on before it.
        if KVMInputRouting.claimsKeyboard(event.kind) { keyboardFocus = pointerFocus; lastLocalClickAt = clock() }
        let localFocus = KVMInputRouting.target(event.kind, pointer: pointerFocus, keyboard: keyboardFocus).computer == node.localID
        if event.kind == .motion {
            // Send the first movement straight away and combine only what
            // arrives while that one is on its way. Holding every movement for
            // the coalescing window added its delay to all of them.
            if pendingMotion == nil && !motionFlushScheduled {
                pendingMotion = event
                flushMotion()
                scheduleMotionFlush()
                return pointerFocus.computer != node.localID
            }
            pendingMotion = pendingMotion.map { previous in
                var combined = event
                combined.x += previous.x; combined.y += previous.y
                return combined
            } ?? event
            scheduleMotionFlush()
            // With focus on this Mac the hardware cursor has already moved; the
            // coordinator only needs the position to notice an edge crossing.
            return pointerFocus.computer != node.localID
        }
        // Keys, clicks and scrolling stay native while this Mac has focus.
        // Re-injecting them only added latency and broke secure text fields.
        // A click still tells the coordinator, which decides where typing goes;
        // it never delivers an event back to the Mac that made it.
        if localFocus {
            if KVMInputRouting.claimsKeyboard(event.kind), !node.isOwner {
                flushMotion()
                if sequence < UInt64.max { sequence += 1; send(.event(grant.id, sequence, event), to: node.ownerID) }
            }
            return false
        }
        flushMotion()
        guard sequence < UInt64.max else { stop(); return false }
        sequence += 1
        guard send(.event(grant.id, sequence, event), to: node.ownerID) else {
            stop(); localProblem = "Input returned locally because the Desk connection was lost. Perch will reconnect automatically."
            return false
        }
        return true
    }
    /// The Mac showing the pointer reports where its live cursor is after applying
    /// movement from another Mac, so the coordinator follows the real cursor rather
    /// than its own running estimate. Only a position rides on the report, never
    /// movement, so nothing is counted twice.
    func reportPointer(_ position: KVMPoint) {
        guard active, focusComputer == node.localID else { return }
        var report = KVMInputEvent(kind: .motion)
        report.absolute = position
        pendingMotion = pendingMotion.map { previous in
            var combined = report
            combined.x = previous.x; combined.y = previous.y; combined.flags = previous.flags
            return combined
        } ?? report
        scheduleMotionFlush()
    }
    /// Events swallowed while a handoff was pending are routed once focus is
    /// known. Whatever belongs on another Mac is sent there. Whatever belongs on
    /// this Mac can no longer pass through, so keys and clicks are posted here;
    /// motion that arrived with the pointer is simply dropped.
    private func replay(_ events: [KVMInputEvent]) {
        let local = focusComputer == node.localID
        for event in events {
            if local && event.kind == .motion { continue }
            if capture(event) { continue }
            if event.kind != .motion, let target = focus ?? lease.grant?.focus { emit(event, target) }
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
        guard var event = pendingMotion else { return }
        pendingMotion = nil
        event.sentAt = ProcessInfo.processInfo.systemUptime
        guard active, event.valid, let grant = lease.grant, sequence < UInt64.max else { return }
        sequence += 1
        guard send(.event(grant.id, sequence, event), to: node.ownerID) else {
            stop(); localProblem = "Input returned locally because the Desk connection was lost. Perch will reconnect automatically."
            return
        }
    }
    /// Send a readiness poll now. Each poll carries a fresh lease challenge that
    /// the coordinator's answer must match.
    /// Why this Mac cannot share with that one, when their sharing versions do
    /// not agree. Everything else about the desk keeps working: only the
    /// pointer needs both sides to behave the same way.
    func versionIssue(_ computer: UUID) -> String? {
        guard computer != node.localID else { return nil }
        let name = node.group.computers.first { $0.id == computer }?.name ?? "The other Mac"
        if let version = peerVersions[computer] {
            guard version != KVMInputProtocol.version else { return nil }
            return name + " shares the keyboard and mouse a different way (version \(version); this Mac uses \(KVMInputProtocol.version)). Update both Macs to the same version of Perch. The desk and its presets still work."
        }
        // Heard from, but it has never said which version it speaks.
        guard let heard = peerHeard[computer], clock() - heard >= Self.versionGrace else { return nil }
        return name + " runs a version of Perch that shares the keyboard and mouse a different way. Update it to this Mac's version. The desk and its presets still work."
    }
    /// Answer a version only when it is news: the first heard from that Mac, or
    /// a change. Answering every one made the two Macs bounce a version back
    /// and forth forever, and each 5-second announcement added another, until
    /// the link was full and display reports, switches, the clipboard and the
    /// pointer queued behind them. A Mac on 2.0.301 still answers every one;
    /// this side not answering back is what ends it.
    static func answersVersion(known: Int?, heard: Int) -> Bool { known != heard }
    private func pollNow() {
        let nonce = lease.challenge(now: clock())
        polls = polls.filter { clock() - $0.value < 2.5 }; polls[nonce] = clock()
        if clock() >= nextVersionAnnounce {
            nextVersionAnnounce = clock() + 5
            for peer in node.online where peer != node.localID {
                send(.version(KVMInputProtocol.version), to: peer)
                send(.features(KVMInputProtocol.features.sorted()), to: peer)
            }
        }
        send(.poll(nonce, ready() && !automaticStartSuppressed, ownReason?.rawValue), to: node.ownerID)
    }
    /// While a handoff prepares, ask again quickly in a bounded burst, so the grant
    /// installs within a round trip or two instead of on the next scheduled poll.
    private func scheduleFastPoll() {
        guard !fastPollScheduled, fastPollsLeft > 0 else { return }
        fastPollScheduled = true; fastPollsLeft -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fastPollInterval) { [weak self] in
            guard let self else { return }
            self.fastPollScheduled = false
            guard self.enabled, self.preparedGrant != nil, self.lease.grant == nil else { return }
            self.pollNow()
        }
    }
    @discardableResult func receive(_ data: Data, peer: UUID) -> Bool {
        guard data.starts(with: Self.wirePrefix) else { return false }
        guard data.count <= 8192, let message = try? JSONDecoder().decode(KVMInputMessage.self, from: data.dropFirst(Self.wirePrefix.count)) else { return true }
        receive(message, peer: peer); return true
    }
    @discardableResult func send(_ message: KVMInputMessage, to peer: UUID) -> Bool {
        if peer == node.localID { DispatchQueue.main.async { [weak self] in self?.receive(message, peer: peer) }; return true }
        if let data = try? JSONEncoder().encode(message) { return node.sendApplication(Self.wirePrefix + data, peer: peer) }
        return false
    }
    private func receive(_ message: KVMInputMessage, peer: UUID) {
        guard node.isMember, node.online.contains(peer) else { return }
        if peer != node.localID { peerHeard[peer] = clock() }
        let now = clock()
        switch message {
        case .wakeDisplay:
            guard peer == node.ownerID || node.isOwner else { return }
            DeskDisplayWake.request()
        case .heartbeatAck(let nonce, let grantID):
            guard peer == node.ownerID, enabled, let sent = heartbeats.removeValue(forKey: nonce),
                  now >= sent, now - sent < KVMInputLease.duration,
                  let grant = lease.grant, grant.id == grantID, lease.alive(now: now) else { return }
            lease.renew(grant: grantID, now: now)
        case .version(let value):
            let news = Self.answersVersion(known: peerVersions[peer], heard: value)
            if news {
                peerVersions[peer] = value
                PerchLog.note("input.version", "Computer \(peer.uuidString.prefix(8)) shares input at version \(value); this Mac speaks \(KVMInputProtocol.version)")
                // Answer at once, so the other Mac need not wait for the next
                // announcement to learn this one's.
                send(.version(KVMInputProtocol.version), to: peer)
                send(.features(KVMInputProtocol.features.sorted()), to: peer)
            }
        case .features(let names):
            let known = Set(names.prefix(32).map { String($0.prefix(64)) })
            if peerFeatures[peer] != known {
                peerFeatures[peer] = known
                PerchLog.note("input.features." + peer.uuidString.prefix(8), "Computer \(peer.uuidString.prefix(8)) shares input with: " + (known.isEmpty ? "nothing beyond its version" : known.sorted().joined(separator: ", ")))
            }
        case .state(let nonce, let value, let issue, let connections, let computers, let currentFocus, let typingFocus, let chosen, let reasons):
            guard peer == node.ownerID, enabled, let sent = polls.removeValue(forKey: nonce), now >= sent, now - sent < 2.5,
                  connections.count <= 256, computers.isSubset(of: Set(node.group.computers.map(\.id))) else { return }
            // Where typing goes, unless this Mac was clicked after asking: that
            // click is newer than the answer. The coordinator's own answer to
            // itself is never newer than what it decided meanwhile.
            if !node.isOwner, sent > lastLocalClickAt, keyboardFocus != typingFocus { keyboardFocus = typingFocus }
            // Someone chose a preset or Share since this Mac chose local control.
            if let chosen {
                knownChoices = chosen
                if let escaped = escapedAtChoice, chosen != escaped {
                    PerchLog.record("input.start", "A preset or Share was chosen on another Mac; this Mac shares again")
                    allowAutomaticStart()
                }
            }
            let relayed = (reasons ?? [:]).compactMapValues(KVMShareReason.init(rawValue:))
            if peerReasons != relayed { peerReasons = relayed }
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
                      lease.accept(value, challenge: nonce, now: now) else { lease.discard(challenge: nonce); return }
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
            } else {
                // No grant rides on this answer, so its challenge can never be used.
                lease.discard(challenge: nonce)
                // While a handoff prepares, ask again at once rather than waiting for
                // the next quarter-second poll; that wait was a visible hitch at
                // every crossing.
                if preparedGrant != nil, lease.grant == nil { scheduleFastPoll() }
                // A poll response may predate a prepare already received on this
                // ordered connection. Do not discard that pending preparation.
                if lease.grant != nil, localGrantAcceptedAt <= sent { endLocal("the desk reported no active control" + (issue.map { ": " + $0 } ?? "")) }
                // The coordinator has explicitly reported that no grant is
                // active. It is safe to release the local input fence; a
                // subsequent prepare installs a new transaction first.
                localInputSuppressedUntil = 0
                let remote = issue.map { String($0.prefix(300)) }
                if coordinatorProblem != remote { coordinatorProblem = remote }
            }
        case .prepare(let value):
            // A Mac that chose local control (Ctrl-Opt-Esc) stays out until the
            // person chooses a preset or Share again. Its polls already say so;
            // this covers the moment before the coordinator has heard one.
            guard peer == node.ownerID, enabled, ready(), node.isOwner || !automaticStartSuppressed,
                  value.participants.contains(node.localID), let revision = configurationRevision,
                  value.valid(group: node.group, epoch: node.graph.roster.epoch, revision: revision) else { return }
            upcoming = value
            endLocal(); localInputSuppressedUntil = 0; preparedGrant = value; preparedAt = now; lastPrepareAt = now
            upcoming = nil
            // Typing stays put across a handoff only while its Mac takes part, and
            // only when every Mac in it, the coordinator included, keeps it so.
            // Otherwise keys would go towards a Mac that left, or disagree.
            if let typing = keyboardFocus, !value.participants.contains(typing.computer) || !all(value.participants.union([node.ownerID]), can: KVMInputProtocol.typingAcrossHandoffs) { keyboardFocus = nil }
            send(.prepared(value.id), to: peer)
            // Poll straight after preparing so the grant arrives in a round trip.
            fastPollsLeft = Self.fastPollLimit
            if node.ownerID != node.localID { pollNow() }
        case .delivery(let id, let source, let sequence, let event, let location):
            guard peer == node.ownerID, active, event.valid, let grant = lease.grant, location.computer == node.localID,
                  destination(preset: grant.preset, monitor: location.monitor) == node.localID,
                  node.group.monitors.first(where: { $0.id == location.monitor })?.geometry.contains(location.position) == true,
                  lease.accepts(source: source, grant: id, sequence: sequence, now: now) else { return }
            // The owner addressed this to this Mac, so control is here now. Waiting
            // for the next status poll to say so left a moment in which this Mac
            // still thought the pointer was elsewhere and parked the cursor again.
            // Typing delivered to a Mac the pointer is not on says nothing about
            // where the pointer is.
            if !KVMInputRouting.typing(event.kind),
               focus?.monitor != location.monitor || focus?.computer != location.computer { focus = location }
            emit(event, location)
        case .heartbeat, .poll, .focus, .prepared, .installed, .stop, .event, .visible:
            // The owner's side: only the desk owner coordinates.
            if node.isOwner { coordinator.receive(message, peer: peer, now: now) }
        case .inspect(let id, let revision, let monitor):
            guard peer == node.ownerID, enabled, revision == configurationRevision, !inspecting.contains(monitor),
                  node.group.monitors.first(where: { $0.id == monitor })?.control?.computer == node.localID, let readMonitor else { return }
            inspecting.insert(monitor)
            readMonitor(monitor) { [weak self] input in
                guard let self else { return }; self.inspecting.remove(monitor)
                guard self.enabled, self.configurationRevision == revision else { return }
                self.send(.visible(id, monitor, input), to: peer)
            }
        }
    }
    func destination(preset: UUID, monitor: UUID) -> UUID? {
        guard let route = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }) else { return nil }
        guard let connection = node.group.connections.first(where: { $0.id == route.connection }), connection.localDisplay != nil else { return nil }
        return connection.computer
    }
    func tick() {
        guard enabled else { return }
        checkContext()
        if clock() >= stateExpires {
            if !readyComputers.isEmpty { readyComputers = [] }
            if !availableConnections.isEmpty { availableConnections = [] }
        }
        if let preparedGrant, lease.grant == nil, clock() - preparedAt >= 3 {
            endLocal(); send(.stop(preparedGrant.id, nil), to: node.ownerID); localProblem = "The handoff timed out. Input is local."
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
            send(.stop(grant.id, nil), to: node.ownerID)
        }
        let now = clock()
        heartbeats = heartbeats.filter { now - $0.value < KVMInputLease.duration }
        if let grant = lease.grant, lease.alive(now: now), node.ownerID != node.localID, now >= nextHeartbeat {
            let nonce = UUID(); heartbeats[nonce] = now
            send(.heartbeat(nonce, grant.id), to: node.ownerID)
            nextHeartbeat = now + 0.5
        }
        // While sharing, both Macs stay in use: a lid-closed Mac that locked could
        // not be unlocked with the shared keyboard (Scott, November 16: neither
        // may lock or sleep).
        if lease.grant != nil || coordinator.grant != nil, now >= nextKeepAwake {
            nextKeepAwake = now + 30
            keepAwake?()
        } else if lease.grant == nil, coordinator.grant == nil { nextKeepAwake = 0 }
        pollNow()
        if node.isOwner { coordinator.tick() }
    }
}
