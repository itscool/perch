import Foundation
import Combine

enum KVMInputMessage: Codable {
    case poll(UUID, Bool)
    case state(UUID, KVMInputGrant?, String?, Set<UUID>, Set<UUID>, KVMInputFocus?)
    case focus(UUID, UUID)
    case prepare(KVMInputGrant)
    case prepared(UUID)
    case installed(UUID)
    case stop(UUID?)
    case event(UUID, UInt64, KVMInputEvent)
    case delivery(UUID, UUID, UInt64, KVMInputEvent, KVMInputFocus)
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
    @Published private(set) var focus: KVMInputFocus?
    @Published private(set) var problem: String?
    @Published private(set) var availableConnections: Set<UUID> = []
    @Published private(set) var readyComputers: Set<UUID> = []
    var ready: () -> Bool = { false }
    var emit: (KVMInputEvent, KVMInputFocus) -> Void = { _, _ in }
    var release: () -> Void = {}
    var readMonitor: ((UUID, @escaping (UInt16?) -> Void) -> Void)?
    var attachedKeyboards: () -> Set<UUID> = { [] }
    var motionScale: (KVMInputFocus) -> KVMPoint = { _ in .init(x: 1, y: 1) }
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
    private var held = KVMInputHeld()
    private var pointer: KVMInputFocus?
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
        keyboardPublished = nil
        if !value { stop(); timer?.invalidate(); timer = nil; problem = nil; return }
        lastRevision = configurationRevision
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        tick()
    }
    func stop() {
        pendingStart = nil
        send(.stop(nil), to: node.ownerID)
        endLocal()
        if node.isOwner { endAuthority() }
    }
    private func endLocal() {
        release(); lease.release(); preparedGrant = nil; buffered = []; focus = nil; sequence = 0
        attachmentWaitingSince = nil; attachmentBuffered = []
    }
    private func endAuthority() {
        // Participants release their own injected state when the next poll
        // returns nil (or independently within one second if unreachable).
        grant = nil; pending = nil; prepared = []; pointer = nil; incoming = [:]
        installed = []; deliveryBuffer = []
        _ = held.releaseAll()
    }
    private func checkContext() {
        guard enabled else { return }
        if configurationRevision != lastRevision || !node.canEdit || !node.online.contains(node.ownerID) {
            stop(); lastRevision = configurationRevision
            visibility = [:]; probes = [:]
            keyboardFollow = KVMKeyboardFollow(); keyboardAttachments = [:]; keyboardPublished = nil
            problem = "Input is local. Reconnect the desk or review its changes, then choose a screen to control."
        }
        if let grant, !grant.participants.isSubset(of: node.online) { endAuthority() }
        if let pending, !pending.participants.isSubset(of: node.online) { endAuthority() }
    }
    var active: Bool { enabled && ready() && lease.alive(now: clock()) && node.canEdit && lease.grant?.revision == configurationRevision }
    var preparing: Bool { enabled && ready() && preparedGrant != nil && lease.grant == nil && clock() >= preparedAt && clock() - preparedAt < 2 }
    var capturing: Bool { active || preparing }
    func start(preset: UUID, monitor: UUID) {
        guard enabled && ready() else { problem = "Enable sharing and resolve this Mac’s access before choosing a screen."; return }
        send(.focus(preset, monitor), to: node.ownerID)
    }
    func resumeAfterPreset(_ preset: UUID, monitor: UUID) {
        guard enabled else { return }
        pendingStart = (preset, monitor, clock() + 5)
    }
    func readinessIssue(preset: UUID, monitor: UUID) -> String? {
        guard enabled && ready() else { return "Enable sharing and resolve this Mac’s access first." }
        guard node.online.contains(node.ownerID), clock() < stateExpires else { return "Waiting for the desk coordinator to confirm readiness." }
        guard let owner = destination(preset: preset, monitor: monitor), readyComputers.contains(owner) else { return "Enable sharing on the screen’s mapped computer and keep it connected." }
        guard let connection = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor })?.connection,
              availableConnections.contains(connection) else { return "This screen has not confirmed the selected preset’s input. Use Play in Desk to switch it, or check its connection." }
        return nil
    }
    /// Returning false means the native adapter must leave the event local.
    func capture(_ event: KVMInputEvent) -> Bool {
        if attachmentWaitingSince != nil, enabled && ready(), event.valid {
            guard attachmentBuffered.count < 64 else { stop(); return true }
            attachmentBuffered.append(event); return true
        }
        if preparing, event.valid {
            guard buffered.count < 64 else { stop(); problem = "Input returned locally because the handoff took too long. Choose a screen to retry."; return true }
            buffered.append(event); return true
        }
        guard active, event.valid, let grant = lease.grant else { return false }
        guard sequence < UInt64.max else { stop(); return false }
        sequence += 1
        send(.event(grant.id, sequence, event), to: node.ownerID)
        return true
    }
    @discardableResult func receive(_ data: Data, peer: UUID) -> Bool {
        guard data.starts(with: Self.wirePrefix) else { return false }
        guard data.count <= 8192, let message = try? JSONDecoder().decode(KVMInputMessage.self, from: data.dropFirst(Self.wirePrefix.count)) else { return true }
        receive(message, peer: peer); return true
    }
    private func send(_ message: KVMInputMessage, to peer: UUID) {
        if peer == node.localID { DispatchQueue.main.async { [weak self] in self?.receive(message, peer: peer) } }
        else if let data = try? JSONEncoder().encode(message) { node.sendApplication(Self.wirePrefix + data, peer: peer) }
    }
    private func receive(_ message: KVMInputMessage, peer: UUID) {
        guard node.isMember, node.online.contains(peer) else { return }
        let now = clock()
        switch message {
        case .keyboards(let attached):
            guard node.isOwner, enabled, fresh(peer), attached.count <= 16,
                  attached.isSubset(of: Set((node.group.sharedKeyboards ?? []).filter { $0.bindings[peer] != nil }.map(\.id))) else { return }
            let previous = keyboardAttachments[peer] ?? []
            keyboardAttachments[peer] = attached
            for keyboard in previous.symmetricDifference(attached) {
                if let destination = keyboardFollow.observe(keyboard: keyboard, computer: peer, attached: attached.contains(keyboard), online: node.online),
                   node.group.sharedKeyboards?.first(where: { $0.id == keyboard })?.follow == true,
                   let grant, let monitor = node.group.monitors.first(where: { self.destination(preset: grant.preset, monitor: $0.id) == destination }) {
                    receive(.focus(grant.preset, monitor.id), peer: destination)
                }
            }
        case .poll(let nonce, let available):
            guard node.isOwner else { return }
            if available && enabled { readiness[peer] = now } else { readiness[peer] = nil }
            if grant?.participants.contains(peer) == true && !available { endAuthority() }
            validateAuthority()
            let connections = Set(node.group.connections.filter { connection in
                guard let observed = visibility[connection.monitor], observed.revision == configurationRevision,
                      now >= observed.sent, now - observed.sent < 2 else { return false }
                return observed.input == connection.inputCode
            }.map(\.id))
            send(.state(nonce, available ? grant : nil, problem, connections, Set(readiness.keys.filter(fresh)).union(fresh(node.localID) ? [node.localID] : []), pointer), to: peer)
        case .state(let nonce, let value, let issue, let connections, let computers, let currentFocus):
            guard peer == node.ownerID, enabled, let sent = polls.removeValue(forKey: nonce), now >= sent, now - sent < 1,
                  connections.count <= 256, computers.isSubset(of: Set(node.group.computers.map(\.id))) else { return }
            if availableConnections != connections { availableConnections = connections }
            if readyComputers != computers { readyComputers = computers }
            stateExpires = sent + 1
            if let value {
                let first = lease.grant == nil
                guard ready(), preparedGrant == value, value.participants.contains(node.localID),
                      let revision = configurationRevision, value.valid(group: node.group, epoch: node.graph.roster.epoch, revision: revision),
                      lease.accept(value, challenge: nonce, now: now) else { return }
                let current = currentFocus.flatMap { location in
                    destination(preset: value.preset, monitor: location.monitor) == value.focus.computer &&
                        node.group.monitors.first(where: { $0.id == location.monitor })?.geometry.contains(location.position) == true ? location : nil
                } ?? value.focus
                if focus?.monitor != current.monitor || focus?.computer != current.computer { focus = current }
                if problem != nil { problem = nil }
                if first {
                    send(.installed(value.id), to: peer)
                    let waiting = buffered; buffered = []
                    for event in waiting { _ = capture(event) }
                }
                if attachmentWaitingSince != nil, current.computer == node.localID {
                    let waiting = attachmentBuffered; attachmentBuffered = []; attachmentWaitingSince = nil
                    for event in waiting { _ = capture(event) }
                }
            } else {
                // A poll response may predate a prepare already received on this
                // ordered connection. Do not discard that pending preparation.
                if lease.grant != nil { endLocal() }
                if let issue { problem = String(issue.prefix(300)) }
            }
        case .focus(let preset, let monitor):
            guard node.isOwner, enabled, ready(), pending == nil, fresh(peer), let revision = configurationRevision, node.canEdit,
                  let screen = node.group.monitors.first(where: { $0.id == monitor }),
                  let owner = destination(preset: preset, monitor: monitor), fresh(owner), visible(preset: preset, monitor: monitor) else {
                if node.isOwner { problem = "Input stays local until the chosen screen confirms its input and both Macs enable sharing." }
                return
            }
            let participants = Set(readiness.keys.filter(fresh)).union([node.localID])
            prepare(.init(id: UUID(), epoch: node.graph.roster.epoch, revision: revision, preset: preset,
                          participants: participants, focus: .init(monitor: monitor, computer: owner,
                          position: .init(x: screen.geometry.x + screen.geometry.displayedWidth/2, y: screen.geometry.y + screen.geometry.displayedHeight/2))))
        case .prepare(let value):
            guard peer == node.ownerID, enabled, ready(), value.participants.contains(node.localID), let revision = configurationRevision,
                  value.valid(group: node.group, epoch: node.graph.roster.epoch, revision: revision) else { return }
            let attachmentTime = attachmentWaitingSince, attachmentEvents = attachmentBuffered
            endLocal(); preparedGrant = value; preparedAt = now
            if value.focus.computer == node.localID { attachmentWaitingSince = attachmentTime; attachmentBuffered = attachmentEvents }
            send(.prepared(value.id), to: peer)
        case .prepared(let id):
            guard node.isOwner, let pending, pending.id == id, pending.participants.contains(peer), now - pendingAt < 2 else { return }
            prepared.insert(peer)
            if prepared == pending.participants {
                grant = pending; self.pending = nil; pointer = pending.focus; incoming = [:]; outputSequence = 0
                installed = []; grantedAt = now
                problem = nil
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
                guard deliveryBuffer.count < 256 else { endAuthority(); problem = "Input returned locally because a computer did not finish the handoff."; return }
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
        if count > 4000 { endAuthority(); problem = "Input returned locally because a computer sent events too quickly."; return false }
        return true
    }
    private func fresh(_ peer: UUID) -> Bool {
        if peer == node.localID { return enabled && ready() }
        guard node.online.contains(peer), let time = readiness[peer] else { return false }
        return clock() >= time && clock() - time < 1
    }
    private func destination(preset: UUID, monitor: UUID) -> UUID? {
        guard let route = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }) else { return nil }
        return node.group.connections.first(where: { $0.id == route.connection })?.computer
    }
    private func visible(preset: UUID, monitor: UUID) -> Bool {
        guard let observation = visibility[monitor], observation.revision == configurationRevision,
              clock() >= observation.sent, clock() - observation.sent < 2,
              let route = node.group.presets.first(where: { $0.id == preset })?.assignments.first(where: { $0.monitor == monitor }),
              let input = node.group.connections.first(where: { $0.id == route.connection })?.inputCode else { return false }
        return observation.input == input
    }
    private func prepare(_ value: KVMInputGrant) {
        endAuthority(); pending = value; pendingAt = clock()
        for peer in value.participants { send(.prepare(value), to: peer) }
    }
    private func validateAuthority() {
        if let grant, (!grant.participants.allSatisfy(fresh) || !visible(preset: grant.preset, monitor: pointer?.monitor ?? grant.focus.monitor) ||
                       grant.revision != configurationRevision || !node.canEdit) { endAuthority() }
        if let grant, installed != grant.participants, clock() - grantedAt >= 1 { endAuthority(); problem = "A computer did not accept control in time. Input is local." }
        if pending != nil && clock() - pendingAt >= 2 { endAuthority(); problem = "A computer did not finish releasing input. Control remains local." }
    }
    private func route(_ value: KVMInputEvent, source: UUID, grant: KVMInputGrant) {
        guard var location = pointer, let screen = node.group.monitors.first(where: { $0.id == location.monitor }),
              let preset = node.group.presets.first(where: { $0.id == grant.preset }) else { return }
        if value.kind == .motion {
            let from = location.position
            let scale = motionScale(location)
            guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else { return }
            let proposed = KVMPoint(x: location.position.x + value.x * scale.x, y: location.position.y + value.y * scale.y)
            if !screen.geometry.contains(proposed) {
                location.position = .init(x: min(screen.geometry.right, max(screen.geometry.x, proposed.x)),
                                          y: min(screen.geometry.bottom, max(screen.geometry.y, proposed.y)))
                switch KVMEdge.crossing(group: node.group, preset: preset, source: screen.id, from: from, to: proposed) {
                case .remote(let monitor, let computer, let entry):
                    guard grant.participants.contains(computer), fresh(computer), visible(preset: grant.preset, monitor: monitor) else { break }
                    prepare(.init(id: UUID(), epoch: grant.epoch, revision: grant.revision, preset: grant.preset,
                                  participants: grant.participants, focus: .init(monitor: monitor, computer: computer, position: entry)))
                    return
                case .native:
                    if let next = node.group.monitors.first(where: { $0.id != screen.id && $0.geometry.contains(proposed) }), visible(preset: grant.preset, monitor: next.id) {
                        location.monitor = next.id; location.position = proposed
                    }
                case .blocked: break
                }
            } else { location.position = proposed }
            pointer = location
        }
        guard outputSequence < UInt64.max else { endAuthority(); return }
        outputSequence += 1
        if let event = held.apply(value, source: source) {
            send(.delivery(grant.id, source, outputSequence, event, location), to: location.computer)
        }
    }
    func tick() {
        guard enabled else { return }
        checkContext()
        if let since = attachmentWaitingSince, clock() - since >= 2 {
            stop(); problem = "The keyboard changed hosts, but the desk could not confirm its destination. Input is local; choose a screen to retry."
        }
        if let preparedGrant, lease.grant == nil, clock() - preparedAt >= 2 {
            endLocal(); send(.stop(preparedGrant.id), to: node.ownerID); problem = "The handoff timed out. Input is local."
        }
        if let grant = lease.grant, !lease.alive(now: clock()) || !ready() {
            endLocal(); problem = "Input returned locally. Choose a screen to resume sharing."; send(.stop(grant.id), to: node.ownerID)
        }
        let nonce = lease.challenge(now: clock())
        polls = polls.filter { clock() - $0.value < 1 }; polls[nonce] = clock()
        send(.poll(nonce, ready()), to: node.ownerID)
        if let (preset, monitor, until) = pendingStart {
            if clock() >= until { pendingStart = nil; problem = "The preset switched, but input sharing is still waiting for a ready computer and confirmed screen. Choose Control here when ready." }
            else if readinessIssue(preset: preset, monitor: monitor) == nil { pendingStart = nil; start(preset: preset, monitor: monitor) }
        }
        publishKeyboardAttachments()
        guard node.isOwner else { return }
        validateAuthority()
        readiness = readiness.filter { node.online.contains($0.key) }
        rates = rates.filter { node.online.contains($0.key) }
        let now = clock()
        probes = probes.filter { now - $0.value.sent < 1.5 }
        if now >= nextInspection, let revision = configurationRevision, node.canEdit {
            nextInspection = now + 0.75
            for monitor in node.group.monitors {
                guard let peer = monitor.control?.computer, fresh(peer), !probes.values.contains(where: { $0.monitor == monitor.id }) else { continue }
                let id = UUID(); probes[id] = .init(peer: peer, monitor: monitor.id, sent: now, revision: revision)
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
