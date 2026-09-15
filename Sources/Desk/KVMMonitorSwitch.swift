import Foundation
import Combine

struct KVMMonitorRoute: Codable, Equatable {
    let monitor: UUID
    let control: KVMMonitorControl
    let input: UInt16
    let force: Bool
    init(monitor: UUID, control: KVMMonitorControl, input: UInt16, force: Bool) {
        self.monitor = monitor; self.control = control; self.input = input; self.force = force
    }
    // Fields added after a message shipped decode with their default, so a
    // peer that has not sent them is not silently dropped.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitor = try values.decode(UUID.self, forKey: .monitor)
        control = try values.decode(KVMMonitorControl.self, forKey: .control)
        input = try values.decode(UInt16.self, forKey: .input)
        force = try values.decodeIfPresent(Bool.self, forKey: .force) ?? false
    }
}
struct KVMMonitorRequest: Codable, Equatable {
    let id: UUID
    let epoch: UUID
    let revision: String
    let preset: UUID?
    let routes: [KVMMonitorRoute]
    var connection: UUID? = nil
    /// Reissue every monitor write even when a read says the requested input
    /// is already selected. This is used by explicit force actions and when
    /// replaying the active preset.
    var force: Bool = false
    init(id: UUID, epoch: UUID, revision: String, preset: UUID?, routes: [KVMMonitorRoute], connection: UUID? = nil, force: Bool = false) {
        self.id = id; self.epoch = epoch; self.revision = revision; self.preset = preset; self.routes = routes; self.connection = connection; self.force = force
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        epoch = try values.decode(UUID.self, forKey: .epoch)
        revision = try values.decode(String.self, forKey: .revision)
        preset = try values.decodeIfPresent(UUID.self, forKey: .preset)
        routes = try values.decode([KVMMonitorRoute].self, forKey: .routes)
        connection = try values.decodeIfPresent(UUID.self, forKey: .connection)
        force = try values.decodeIfPresent(Bool.self, forKey: .force) ?? false
    }
    static func make(group: KVMGroup, preset: UUID, epoch: UUID, revision: String, id: UUID = UUID(), force: Bool = false) throws -> Self {
        _ = try group.validated()
        guard let preset = group.presets.first(where: { $0.id == preset }), !group.monitors.isEmpty,
              !preset.assignments.isEmpty else { throw KVMError("Click a monitor input to include a screen in this preset.") }
        let selected = Set(preset.assignments.map(\.monitor))
        let routes = try group.monitors.filter { selected.contains($0.id) }.map { monitor -> KVMMonitorRoute in
            guard let control = monitor.control else { throw KVMError("Choose a control connection for \(monitor.name).") }
            guard let assignment = preset.assignments.first(where: { $0.monitor == monitor.id }),
                  let input = group.connections.first(where: { $0.id == assignment.connection })?.inputCode else { throw KVMError("Choose the actual input code for \(monitor.name)’s connection.") }
            return .init(monitor: monitor.id, control: control, input: input, force: force)
        }
        return Self(id: id, epoch: epoch, revision: revision, preset: preset.id, routes: routes, force: force)
    }
    static func makeConnection(group: KVMGroup, connection: UUID, epoch: UUID, revision: String, id: UUID = UUID(), force: Bool = false) throws -> Self {
        _ = try group.validated()
        guard let port = group.connections.first(where: { $0.id == connection }),
              let monitor = group.monitors.first(where: { $0.id == port.monitor }),
              let control = monitor.control else { throw KVMError("Choose this monitor’s control connection in Monitor setup first.") }
        guard let input = port.inputCode else { throw KVMError("Set this port’s input code in Monitor setup first.") }
        return Self(id: id, epoch: epoch, revision: revision, preset: nil,
                    routes: [.init(monitor: monitor.id, control: control, input: input, force: force)], connection: connection, force: force)
    }
    func validated(in group: KVMGroup) throws -> Self {
        if let connection, preset == nil {
            return try Self.makeConnection(group: group, connection: connection, epoch: epoch, revision: revision, id: id, force: force)
        }
        guard let preset, connection == nil else { throw KVMError("The monitor request has no single valid target.") }
        return try Self.make(group: group, preset: preset, epoch: epoch, revision: revision, id: id, force: force)
    }
}
struct KVMMonitorOutcome: Codable, Equatable {
    enum State: String, Codable { case confirmed, unverified, failed }
    let request: UUID
    let monitor: UUID
    let input: UInt16
    let state: State
    let detail: String
}
enum KVMMonitorMessage: Codable {
    case refresh
    /// Sent to each destination before the monitor command: wake and reconnect
    /// the display that is about to receive the picture, then answer.
    case wakeDisplay(KVMMonitorRequest)
    case displayAwake(UUID)
    case desktopInvalidation(KVMMonitorRequest, Bool)
    case desktopObserved(UUID, UInt16?, String, String?)
    case prepare(KVMMonitorRequest)
    case prepared(UUID)
    case refused(UUID, String)
    case execute(UUID)
    case release(UUID)
    case result(KVMMonitorOutcome)
    case verify(KVMMonitorRequest, UUID)
    case verified(UUID, UUID, UInt16?)
    /// monitor, input, revision, and the read generation it was issued under so a
    /// read that started before a switch cannot override the switch's outcome.
    case observed(UUID, UInt16?, String, String?)
    /// The initiator's final per-route outcome: the monitors whose route was
    /// confirmed or accepted. Every peer applies exactly the same optimistic
    /// state and active preset as the initiator, including after a failure
    /// or timeout (an empty set). Peers never execute the request.
    case settled(KVMMonitorRequest, Set<UUID>)
    case delegate(KVMMonitorRequest, UUID)
    case delegated(KVMMonitorOutcome)
}

/// One lease at each monitor's explicit control computer. Preparation acquires
/// every needed control lease before commands start. No input permissions or
/// synthesized keyboard/mouse events participate in monitor-only switching.
final class KVMMonitorSwitch: ObservableObject {
    static let wirePrefix = Data("Perch monitor v1\0".utf8)
    private static let leaseRecoveryTimeout: TimeInterval = 65
    struct Lease { let peer: UUID; let request: KVMMonitorRequest; var created: TimeInterval; var executing = false; var completed = false; var outcome: KVMMonitorOutcome?; var releaseRequested = false }
    @Published private(set) var request: KVMMonitorRequest?
    @Published private(set) var results: [UUID: KVMMonitorOutcome] = [:]
    @Published private(set) var busy = false
    @Published private(set) var activePreset: UUID?
    @Published private(set) var activeGroup: KVMGroup?
    /// Accepted monitor routes remain usable for KVM and desktop reconciliation
    /// when readback is unavailable. A contradictory fresh read clears them.
    @Published private(set) var optimisticInputs: [UUID: UInt16] = [:]
    /// An actionable failure: a write was refused, timed out or contradicted.
    @Published private(set) var problem: String?
    /// A neutral fact: the switch was accepted but the monitor cannot confirm
    /// its input. Not a warning; the picture usually did change.
    @Published private(set) var caution: String?
    let node: KVMDeskNode
    var execute: ((KVMMonitorRoute, @escaping () -> Bool, @escaping (KVMMonitorOutcome.State, String) -> Void) -> Void)?
    var readForVerification: ((UUID, @escaping (UInt16?) -> Void) -> Void)?
    /// Reconnect this Mac's software-disconnected display(s) that a request is
    /// about to switch a monitor onto, so the picture has somewhere to land.
    var prepareDestination: ((KVMMonitorRequest) -> Void)?
    var otherMessage: ((UUID, Data) -> Void)?
    private var leases: [UUID: Lease] = [:]
    private var delegates: [UUID: UUID] = [:]
    private var prepared: Set<UUID> = []
    private var required: Set<UUID> = []
    private var verification: [UUID: Set<UUID>] = [:]
    private var verifyingMonitors: Set<UUID> = []
    private var verifyDeadline: [UUID: TimeInterval] = [:]
    private var awaitingWake: Set<UUID> = []
    private struct Observation { let input: UInt16; let peer: UUID; let time: TimeInterval; let revision: String }
    private var observations: [UUID: Observation] = [:]
    private var desktopObservations: [UUID: Observation] = [:]
    private var desktopGenerations: [UUID: String] = [:]
    var desktopInputs: [UUID: UInt16] {
        guard node.canEdit else { return [:] }
        return desktopObservations.filter { desktopGenerations[$0.key]?.hasSuffix("-pending") != true && $0.value.revision == node.revision && now - $0.value.time <= 45 && node.online.contains($0.value.peer) }.mapValues(\.input)
    }
    private func invalidateDesktop(_ request: KVMMonitorRequest, finished: Bool = false) {
        for route in request.routes {
            let pending = request.id.uuidString + "-pending"
            if finished && desktopGenerations[route.monitor] != pending { continue }
            desktopGenerations[route.monitor] = request.id.uuidString + (finished ? "-done" : "-pending")
            desktopObservations[route.monitor] = nil
        }
        nextRead = 0
    }

    private var reading: Set<UUID> = []
    private var nextRead: TimeInterval = 0
    private var lastRefresh: TimeInterval = -.infinity
    private var lastConfirmed: TimeInterval?
    private var timer: Timer?
    private var started: TimeInterval = 0
    private var committed = false
    private var lastControlResend: TimeInterval = -.infinity
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var now: TimeInterval { clock() }
    init(node: KVMDeskNode) {
        self.node = node
        node.application = { [weak self] peer, data in
            guard let self else { return }
            // Each application channel is tagged so identically named cases in
            // different enums (refresh, wakeDisplay) cannot be mistaken for
            // one another by trial decoding.
            if data.starts(with: Self.wirePrefix) {
                if let message = try? JSONDecoder().decode(KVMMonitorMessage.self, from: data.dropFirst(Self.wirePrefix.count)) { self.receive(message, peer: peer) }
            } else { self.otherMessage?(peer, data) }
        }
        node.canCheckpoint = { [weak self] in self?.busy != true && self?.leases.isEmpty == true }
        let timer = MainTimer.every(1) { [weak self] in self?.tick() }
        self.timer = timer
    }
    deinit { timer?.invalidate() }
    func readiness(_ preset: UUID) -> String? {
        guard !busy else { return "A monitor preset is still switching." }
        guard node.canEdit, let revision = node.revision else { return "Review the desk changes before switching." }
        do {
            let request = try KVMMonitorRequest.make(group: node.group, preset: preset, epoch: node.graph.roster.epoch, revision: revision)
            let missing = Set(request.routes.map { $0.control.computer }).subtracting(node.online)
            if !missing.isEmpty { return "Reconnect \(node.group.computers.filter { missing.contains($0.id) }.map(\.name).joined(separator: ", ")) to control these screens." }
            let chosen = node.group.presets.first { $0.id == preset }!
            let destinations = Set(chosen.assignments.compactMap { a in node.group.connections.first { $0.id == a.connection }?.computer })
            if !destinations.isSubset(of: node.online) { return "A computer selected in this preset is offline. Reconnect it or choose another input." }
            return nil
        } catch { return error.localizedDescription }
    }
    func activate(_ preset: UUID, force: Bool = false) {
        if let problem = readiness(preset) { self.problem = problem; return }
        do {
            let request = try KVMMonitorRequest.make(group: node.group, preset: preset, epoch: node.graph.roster.epoch, revision: node.revision!, force: force)
            begin(request)
        } catch { problem = error.localizedDescription }
    }
    func connectionReadiness(_ connection: UUID) -> String? {
        guard !busy else { return "A monitor is still switching." }
        guard node.canEdit, let revision = node.revision else { return "Review the desk changes before switching." }
        do {
            let request = try KVMMonitorRequest.makeConnection(group: node.group, connection: connection, epoch: node.graph.roster.epoch, revision: revision)
            guard request.routes.allSatisfy({ node.online.contains($0.control.computer) }) else {
                return "Reconnect this monitor’s control computer before switching."
            }
            return nil
        } catch { return error.localizedDescription }
    }
    func activateConnection(_ connection: UUID) {
        if let problem = connectionReadiness(connection) { self.problem = problem; return }
        do {
            let request = try KVMMonitorRequest.makeConnection(group: node.group, connection: connection, epoch: node.graph.roster.epoch, revision: node.revision!, force: true)
            // A monitor that cannot report its input is still safe to use after
            // Perch has accepted a prior write: the accepted target is our
            // explicit software-known state. Do not send the same hardware
            // command again just because LG readback is unavailable.
            if !request.force && request.routes.allSatisfy({ knownInput(for: $0.monitor) == $0.input }) {
                results = [:]
                problem = nil; caution = nil
                deriveActive()
                return
            }
            begin(request)
        } catch { problem = error.localizedDescription }
    }

    /// Returns only recent, revision-matched evidence. A nil result is an
    /// honest unknown state; callers must not treat it as a different input.
    private func knownInput(for monitor: UUID) -> UInt16? {
        if let observation = observations[monitor], observation.revision == node.revision,
           now - observation.time <= 45, node.online.contains(observation.peer) {
            return observation.input
        }
        return optimisticInputs[monitor]
    }

    /// Take over a direct input request when a previous, non-executing lease
    /// is still holding the monitor. A command that is already being written
    /// is never interrupted; the user gets a bounded retry message instead.
    func forceActivateConnection(_ connection: UUID) {
        guard node.canEdit, let revision = node.revision else { problem = "Review the desk changes before switching."; return }
        do {
            let next = try KVMMonitorRequest.makeConnection(group: node.group, connection: connection,
                                                            epoch: node.graph.roster.epoch, revision: revision, force: true)
            let monitors = Set(next.routes.map(\.monitor))
            let relevant = leases.filter { monitors.contains($0.key) }
            let stale = relevant.filter { now - $0.value.created >= Self.leaseRecoveryTimeout }
            for (monitor, lease) in stale {
                send(.release(lease.request.id), peer: lease.peer)
                leases[monitor] = nil
                delegates[monitor] = nil
            }
            let stillExecuting = relevant.filter { leases[$0.key]?.executing == true && leases[$0.key]?.completed != true }
            if !stillExecuting.isEmpty {
                problem = "Another computer is actively switching this screen. Wait for that command to finish, then try again."
                return
            }
            if busy, let current = request {
                let currentExecuting = leases.filter { $0.value.request.id == current.id && $0.value.executing && !$0.value.completed }
                let staleCurrent = currentExecuting.filter { now - $0.value.created >= Self.leaseRecoveryTimeout }
                for (monitor, lease) in staleCurrent {
                    send(.release(lease.request.id), peer: lease.peer)
                    leases[monitor] = nil
                    delegates[monitor] = nil
                }
                guard !leases.contains(where: { $0.value.request.id == current.id && $0.value.executing && !$0.value.completed }) else {
                    problem = "This Mac is still writing the previous monitor switch. Wait for it to finish, then try again."
                    return
                }
                release(current)
            }
            for (monitor, lease) in relevant {
                send(.release(lease.request.id), peer: lease.peer)
                leases[monitor] = nil
                delegates[monitor] = nil
            }
            begin(next)
        } catch { problem = error.localizedDescription }
    }

    private func release(_ request: KVMMonitorRequest) {
        busy = false
        for route in request.routes { optimisticInputs[route.monitor] = nil }
        finishedDesktopReadBarrier(request)
        for peer in required { send(.release(request.id), peer: peer) }
        for (monitor, lease) in leases where lease.request.id == request.id {
            leases[monitor] = nil
            delegates[monitor] = nil
        }
        self.request = nil
        required = []
        prepared = []
        verification = [:]
        verifyingMonitors = []; verifyDeadline = [:]; awaitingWake = []
    }

    private func begin(_ request: KVMMonitorRequest) {
        self.request = request; results = [:]; prepared = []; verification = [:]; verifyingMonitors = []; verifyDeadline = [:]
        for route in request.routes { optimisticInputs[route.monitor] = nil }
        required = Set(request.routes.map { $0.control.computer }); started = now; committed = false; lastControlResend = -.infinity
        busy = true; problem = nil; caution = nil; activePreset = nil; activeGroup = nil; lastConfirmed = nil
        invalidateDesktop(request)
        for peer in node.online where peer != node.localID { send(.desktopInvalidation(request, false), peer: peer) }
        // Wake the computer that owns each selected input and reconnect its
        // display before the monitor command runs, and wait (briefly) for it
        // to say so. A monitor switched onto a sleeping or software-
        // disconnected output sees no signal and may bounce straight back.
        let destinations = Set(request.routes.compactMap { route in
            node.group.connections.first { $0.monitor == route.monitor && $0.inputCode == route.input }?.computer
        })
        awaitingWake = []
        for destination in destinations {
            if destination == node.localID { DeskDisplayWake.requestIfNeeded(); prepareDestination?(request) }
            else if node.online.contains(destination) { awaitingWake.insert(destination); send(.wakeDisplay(request), peer: destination) }
        }
        for peer in required { send(.prepare(request), peer: peer) }
    }
    /// Execute once every control computer is prepared and every destination
    /// has answered its wake request, or two seconds have passed without it.
    private func tryCommit() {
        guard busy, !committed, let request, prepared == required, awaitingWake.isEmpty || now - started >= 2 else { return }
        committed = true
        for peer in required { send(.execute(request.id), peer: peer) }
    }
    private func send(_ message: KVMMonitorMessage, peer: UUID) {
        if peer == node.localID { DispatchQueue.main.async { [weak self] in self?.receive(message, peer: peer) }; return }
        if let bytes = try? JSONEncoder().encode(message) { node.sendApplication(Self.wirePrefix + bytes, peer: peer) }
    }
    private func receive(_ message: KVMMonitorMessage, peer: UUID) {
        guard node.online.contains(peer) else { return }
        switch message {
        case .wakeDisplay(let request):
            guard request.epoch == node.graph.roster.epoch, (try? request.validated(in: node.group)) == request else { return }
            DeskDisplayWake.requestIfNeeded()
            prepareDestination?(request)
            // Give the display a moment to light up before the write goes out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.send(.displayAwake(request.id), peer: peer) }
        case .displayAwake(let id):
            guard busy, request?.id == id else { return }
            awaitingWake.remove(peer); tryCommit()
        case .desktopInvalidation(let request, let finished):
            guard request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                  (try? request.validated(in: node.group)) == request else { return }
            // A switch is starting elsewhere: what we believed about these
            // monitors is no longer evidence, exactly as on the initiator.
            if !finished { for route in request.routes { optimisticInputs[route.monitor] = nil } }
            invalidateDesktop(request, finished: finished)
        case .desktopObserved(let monitor, let input, let revision, let generation):
            guard revision == node.revision, generation == desktopGenerations[monitor],
                  node.group.monitors.contains(where: { $0.id == monitor && ($0.control?.computer == peer || node.group.connections.contains(where: { $0.monitor == monitor && $0.computer == peer })) }) else { return }
            if let input, input > 0 { desktopObservations[monitor] = Observation(input: input, peer: peer, time: now, revision: revision) }
            else if desktopObservations[monitor]?.peer == peer { desktopObservations[monitor] = nil }
        case .delegate(let request, let monitor):
            guard node.canEdit, request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                  let route = request.routes.first(where: { $0.monitor == monitor && $0.control.computer == peer }),
                  ["standard", "lg"].contains(route.control.mode),
                  let connection = node.group.connections.first(where: { $0.monitor == monitor && $0.computer == node.localID }),
                  let display = connection.localDisplay,
                  (try? request.validated(in: node.group)) == request,
                  leases[monitor] == nil, let execute else { return }
            let lease = Lease(peer: peer, request: request, created: now, executing: true)
            leases[monitor] = lease
            let localRoute = KVMMonitorRoute(monitor: monitor, control: .init(computer: node.localID, localDisplay: display, mode: route.control.mode), input: route.input, force: route.force)
            execute(localRoute, { [weak self] in
                guard let self, let current = self.leases[monitor] else { return false }
                return current.request.id == request.id && current.peer == peer && self.now-current.created < 30 && self.node.online.contains(peer) && self.node.revision == request.revision
            }, { [weak self] state, detail in
                guard let self, self.leases[monitor]?.request.id == request.id else { return }
                self.leases[monitor]?.completed = true
                self.send(.delegated(.init(request: request.id, monitor: monitor, input: route.input, state: state, detail: String(detail.prefix(500)))), peer: peer)
            })
        case .delegated(let outcome):
            guard delegates[outcome.monitor] == peer, let lease = leases[outcome.monitor], lease.request.id == outcome.request,
                  let route = lease.request.routes.first(where: { $0.monitor == outcome.monitor && $0.input == outcome.input }) else { return }
            send(.release(outcome.request), peer: peer)
            complete(route, lease: lease, state: outcome.state, detail: outcome.detail)
        case .refresh:
            if now - lastRefresh >= 1 { lastRefresh = now; nextRead = 0; tick() }
        case .observed(let monitor, let input, let revision, let generation):
            // A read issued before a switch began (or while it was pending)
            // describes the old world; it must not flip the active preset back
            // or clear the outcome the switch just established.
            guard revision == node.revision, generation == desktopGenerations[monitor],
                  node.group.monitors.contains(where: { $0.id == monitor && ($0.control?.computer == peer || node.group.connections.contains(where: { $0.monitor == monitor && $0.computer == peer })) }) else { return }
            if let input, input > 0 { observations[monitor] = Observation(input: input, peer: peer, time: now, revision: revision) }
            else if observations[monitor]?.peer == peer { observations[monitor] = nil }
            if let input, input > 0, optimisticInputs[monitor] != nil, input != optimisticInputs[monitor] {
                optimisticInputs[monitor] = nil
            }
            if !busy { deriveActive() }
        case .settled(let request, let accepted):
            guard request.epoch == node.graph.roster.epoch,
                  request.revision == node.revision,
                  (try? request.validated(in: node.group)) == request else { return }
            for route in request.routes { optimisticInputs[route.monitor] = accepted.contains(route.monitor) ? route.input : nil }
            if let preset = request.preset {
                if accepted == Set(request.routes.map(\.monitor)) { activePreset = preset; activeGroup = node.group }
                else if activePreset == preset { activePreset = nil; activeGroup = nil }
            } else { deriveActive() }
        case .prepare(let request):
            do {
                guard node.canEdit, request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                      request.routes.contains(where: { $0.control.computer == node.localID }),
                      try request.validated(in: node.group) == request else { throw KVMError("Desk setup changed. Wait for synchronization, then try switching again.") }
                let own = request.routes.filter { $0.control.computer == node.localID }
                // A lease whose command already completed is finished work,
                // not a conflict; a new request may take it over.
                guard own.allSatisfy({ route in
                    let lease = leases[route.monitor]
                    return lease == nil || lease?.request.id == request.id && lease?.peer == peer || lease?.completed == true
                }) else { throw KVMError("Another computer is switching one of these screens. Wait for it to finish.") }
                for route in own {
                    if leases[route.monitor]?.request.id == request.id, leases[route.monitor]?.peer == peer {
                        // A re-sent prepare renews the window in which execute may follow.
                        if leases[route.monitor]?.executing == false { leases[route.monitor]?.created = now }
                    } else { leases[route.monitor] = Lease(peer: peer, request: request, created: now); delegates[route.monitor] = nil }
                }
                send(.prepared(request.id), peer: peer)
            } catch { send(.refused(request.id, error.localizedDescription), peer: peer) }
        case .prepared(let id):
            guard busy, let request, request.id == id, required.contains(peer), !committed else { return }
            prepared.insert(peer)
            tryCommit()
        case .refused(let id, let reason):
            guard busy, request?.id == id, required.contains(peer) else { return }; finishFailure(reason)
        case .execute(let id):
            // A result can be retransmitted safely after a connection reset.
            // The lease remembers the completed outcome, so a retry never
            // repeats a hardware write.
            for (_, lease) in leases where lease.request.id == id && lease.peer == peer && lease.completed {
                if let outcome = lease.outcome { send(.result(outcome), peer: peer) }
            }
            let own = leases.filter { $0.value.request.id == id && $0.value.peer == peer && !$0.value.executing }
            for (monitor, lease) in own {
                guard now - lease.created < 10, lease.request.epoch == node.graph.roster.epoch,
                      lease.request.revision == node.revision, let route = lease.request.routes.first(where: { $0.monitor == monitor }) else {
                    leases[monitor] = nil; send(.refused(id, "The prepared monitor switch expired or its setup changed."), peer: peer); continue
                }
                leases[monitor]?.executing = true
                guard let execute else { complete(route, lease: lease, state: .failed, detail: "The monitor adapter is not available."); continue }
                execute(route, { [weak self] in
                    // Hardware adapters invoke this on main immediately before a
                    // write; a late work item cannot revive an expired lease.
                    guard let self, let current = self.leases[monitor] else { return false }
                    return current.request.id == id && current.peer == peer && self.now - current.created < 55 && self.node.online.contains(peer) && self.node.canEdit && self.node.revision == lease.request.revision && self.node.graph.roster.epoch == lease.request.epoch && self.node.group.monitors.first { $0.id == monitor }?.control == route.control
                }, { [weak self] state, detail in self?.complete(route, lease: lease, state: state, detail: detail) })
            }
        case .release(let id):
            for (monitor, lease) in leases where lease.peer == peer && lease.request.id == id {
                // A command that is mid-write is never interrupted, but its
                // lease must not outlive the initiator's interest by a minute:
                // drop it as soon as the write completes.
                if !lease.executing || lease.completed { leases[monitor] = nil; delegates[monitor] = nil }
                else { leases[monitor]?.releaseRequested = true }
            }
        case .result(let outcome):
            guard busy, let request, request.id == outcome.request,
                  request.routes.contains(where: { $0.monitor == outcome.monitor && $0.input == outcome.input && $0.control.computer == peer }) else { return }
            results[outcome.monitor] = outcome
            if outcome.state == .unverified {
                let observers = Set(node.group.connections.filter { $0.monitor == outcome.monitor }.compactMap(\.computer)).intersection(node.online)
                verification[outcome.monitor] = observers
                // Readback is a best-effort contradiction check, bounded to a
                // moment: it must not hold the switch open when the monitor
                // has accepted the command but cannot report its input.
                if !observers.isEmpty {
                    verifyingMonitors.insert(outcome.monitor); verifyDeadline[outcome.monitor] = now + 1.5
                    for observer in observers { send(.verify(request, outcome.monitor), peer: observer) }
                }
            }
            finishIfReady()
        case .verify(let request, let monitor):
            guard request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                  request.routes.contains(where: { $0.monitor == monitor }), let readForVerification else { return }
            readForVerification(monitor) { [weak self] input in self?.send(.verified(request.id, monitor, input), peer: peer) }
        case .verified(let id, let monitor, let input):
            guard busy, let request, request.id == id, verification[monitor]?.contains(peer) == true,
                  let route = request.routes.first(where: { $0.monitor == monitor }) else { return }
            verification[monitor]?.remove(peer)
            if results[monitor]?.state == .failed {
                // A contradictory positive read already won; another observer
                // must not turn this confirmed failure back into success.
                if verification[monitor]?.isEmpty == true { verifyingMonitors.remove(monitor) }
            } else if let input, input > 0, input == route.input {
                results[monitor] = .init(request: id, monitor: monitor, input: route.input, state: .confirmed, detail: "A fresh monitor read on \(node.group.computers.first { $0.id == peer }?.name ?? "a paired Mac") confirms this input.")
                optimisticInputs[monitor] = nil
                verifyingMonitors.remove(monitor)
            } else if let input, input > 0 {
                // Nil/zero means this observer cannot report its input. Keep
                // the accepted-command fallback in that case.
                optimisticInputs[monitor] = nil
                results[monitor] = .init(request: id, monitor: monitor, input: route.input, state: .failed, detail: "A fresh monitor read contradicted the requested input.")
                if verification[monitor]?.isEmpty == true { verifyingMonitors.remove(monitor) }
            } else if verification[monitor]?.isEmpty == true {
                verifyingMonitors.remove(monitor)
            }
            finishIfReady()
        }
    }
    private func complete(_ route: KVMMonitorRoute, lease: Lease, state: KVMMonitorOutcome.State, detail: String) {
        guard leases[route.monitor]?.request.id == lease.request.id else { return }
        if state == .failed, delegates[route.monitor] == nil, ["standard", "lg"].contains(route.control.mode), now-lease.created < 18,
           node.canEdit, node.revision == lease.request.revision, node.graph.roster.epoch == lease.request.epoch {
            let candidates = node.group.connections.filter { $0.monitor == route.monitor && $0.computer != node.localID && $0.computer.map(node.online.contains) == true }
            let candidate = candidates.first { $0.inputCode == observations[route.monitor]?.input } ?? candidates.sorted { ($0.computer?.uuidString ?? "") < ($1.computer?.uuidString ?? "") }.first
            if let peer = candidate?.computer { delegates[route.monitor] = peer; send(.delegate(lease.request, route.monitor), peer: peer); return }
        }
        let outcome = KVMMonitorOutcome(request: lease.request.id, monitor: route.monitor, input: route.input, state: state, detail: String(detail.prefix(500)))
        leases[route.monitor]?.completed = true
        leases[route.monitor]?.outcome = outcome
        send(.result(outcome), peer: lease.peer)
        if leases[route.monitor]?.releaseRequested == true { leases[route.monitor] = nil; delegates[route.monitor] = nil }
    }
    private func finishedDesktopReadBarrier(_ request: KVMMonitorRequest) {
        invalidateDesktop(request, finished: true)
        for peer in node.online where peer != node.localID { send(.desktopInvalidation(request, true), peer: peer) }
    }
    private func finishIfReady() {
        guard let request, results.count == request.routes.count, verifyingMonitors.isEmpty else { return }
        for route in request.routes where results[route.monitor]?.state == .confirmed || results[route.monitor]?.state == .unverified {
            // Permit KVM and desktop reconciliation for an accepted route even
            // when its current input cannot be read. A later contradictory
            // readback clears this fallback before desktop reconciliation.
            optimisticInputs[route.monitor] = route.input
        }
        busy = false; verifyingMonitors = []; verifyDeadline = [:]
        finishedDesktopReadBarrier(request)
        for peer in required { send(.release(request.id), peer: peer) }
        // Every peer applies the same per-route outcome as this Mac, so no
        // Mac keeps believing a monitor moved when its write actually failed.
        let accepted = Set(request.routes.filter { results[$0.monitor]?.state == .confirmed || results[$0.monitor]?.state == .unverified }.map(\.monitor))
        for peer in node.online where peer != node.localID { send(.settled(request, accepted), peer: peer) }
        let acceptedPreset = request.preset != nil && accepted.count == request.routes.count
        func describe(_ routes: [KVMMonitorRoute]) -> String {
            routes.map { route in
                let name = node.group.monitors.first { $0.id == route.monitor }?.name ?? "Screen"
                let input = node.group.connections.first { $0.monitor == route.monitor && $0.inputCode == route.input }?.inputName ?? "input \(route.input)"
                return name + " (" + input + ")"
            }.joined(separator: ", ")
        }
        if results.values.allSatisfy({ $0.state == .confirmed }) {
            activePreset = request.preset; activeGroup = request.preset == nil ? nil : node.group; lastConfirmed = now; problem = nil; caution = nil
            for route in request.routes { observations[route.monitor] = Observation(input: route.input, peer: route.control.computer, time: now, revision: request.revision) }
            if request.connection != nil { deriveActive() }
        } else {
            if acceptedPreset {
                // The preset is active even though one or more monitors could
                // not report their input. That is a fact to show, not a failure.
                activePreset = request.preset; activeGroup = node.group
            }
            let failed = request.routes.filter { results[$0.monitor]?.state == .failed }
            let unverified = request.routes.filter { results[$0.monitor]?.state == .unverified }
            if !failed.isEmpty {
                let reason = failed.compactMap { results[$0.monitor]?.detail }.first ?? ""
                problem = "Could not switch " + describe(failed) + ". " + reason + " Retry the preset; if it keeps failing, check the cable and the control computer."
            } else { problem = nil }
            caution = unverified.isEmpty ? nil : "Perch accepted the switch for " + describe(unverified) + " but the monitor cannot report its input. The picture usually changed; if it did not, choose the input again."
        }
    }
    private func finishFailure(_ reason: String) {
        guard let request else { return }
        busy = false; problem = reason; caution = nil; activePreset = nil; activeGroup = nil
        verifyingMonitors = []; verifyDeadline = [:]
        for route in request.routes { optimisticInputs[route.monitor] = nil }
        finishedDesktopReadBarrier(request)
        for route in request.routes where results[route.monitor] == nil { results[route.monitor] = .init(request: request.id, monitor: route.monitor, input: route.input, state: .unverified, detail: "Switch not confirmed. " + reason) }
        for peer in required { send(.release(request.id), peer: peer) }
        for peer in node.online where peer != node.localID { send(.settled(request, []), peer: peer) }
    }
    private func deriveActive() {
        observations = observations.filter { $0.value.revision == node.revision && now - $0.value.time <= 45 && node.online.contains($0.value.peer) }
        let matches = node.group.presets.filter { preset in
            !preset.assignments.isEmpty && preset.assignments.allSatisfy { assignment in
                guard let expected = node.group.connections.first(where: { $0.id == assignment.connection })?.inputCode else { return false }
                return (observations[assignment.monitor]?.input ?? optimisticInputs[assignment.monitor]) == expected
            }
        }
        if let request, request.revision == node.revision, request.epoch == node.graph.roster.epoch {
            for route in request.routes where results[route.monitor]?.state != .confirmed {
                if let observation = observations[route.monitor], observation.input == route.input, observation.time > started {
                    results[route.monitor] = .init(request: request.id, monitor: route.monitor, input: route.input, state: .confirmed,
                                                  detail: "A fresh monitor read now confirms this input.")
                }
            }
            if !results.isEmpty && results.values.allSatisfy({ $0.state == .confirmed }) { if problem != nil { problem = nil }; if caution != nil { caution = nil } }
        }
        if let activePreset, matches.contains(where: { $0.id == activePreset }) { return }
        activePreset = matches.count == 1 ? matches.first?.id : nil
        activeGroup = activePreset == nil ? nil : node.group
    }
    /// The user says the picture did not move: forget the accepted-but-
    /// unconfirmed state on every Mac so desktops reconnect, then look again.
    func revert() {
        guard !busy, let request else { return }
        for route in request.routes where results[route.monitor]?.state != .confirmed { optimisticInputs[route.monitor] = nil }
        results = results.filter { $0.value.state == .confirmed }
        caution = nil; problem = nil
        if request.preset != nil, activePreset == request.preset { activePreset = nil; activeGroup = nil }
        for peer in node.online where peer != node.localID { send(.settled(request, Set(results.keys)), peer: peer) }
        lastRefresh = -.infinity
        refreshObservations()
    }
    /// Read-only recovery; does not repeat a monitor write.
    func refreshObservations() {
        guard now - lastRefresh >= 1 else { return }
        lastRefresh = now; nextRead = 0; tick()
        for peer in node.online where peer != node.localID { send(.refresh, peer: peer) }
    }
    func retryConnection(for monitor: UUID) -> UUID? {
        guard !busy, let request, request.revision == node.revision,
              let route = request.routes.first(where: { $0.monitor == monitor }) else { return nil }
        let connection = request.connection ?? node.group.presets.first { $0.id == request.preset }?.assignments.first { $0.monitor == monitor }?.connection
        guard let connection, node.group.connections.contains(where: { $0.id == connection && $0.monitor == monitor && $0.inputCode == route.input }) else { return nil }
        return connection
    }
    func poll() { tick() }
    private func tick() {
        // Keep executing leases until their bounded backend finishes. Expiration
        // denies further writes, but never unlocks a still-running command.
        for (monitor, lease) in leases where now - lease.created > Self.leaseRecoveryTimeout {
            // The execute validity closure expires after 55 seconds. At this
            // point an execution callback that never returned cannot still
            // write hardware, so release the stale lease and unblock recovery.
            leases[monitor] = nil
            delegates[monitor] = nil
        }
        if busy && now - started > 45 { finishFailure("A computer disconnected or the switch timed out. Actual monitor inputs need to be checked.") }
        if busy { tryCommit() }
        let expiredVerification = verifyDeadline.filter { now >= $0.value }.map(\.key)
        if !expiredVerification.isEmpty {
            for monitor in expiredVerification { verifyingMonitors.remove(monitor); verifyDeadline[monitor] = nil }
            finishIfReady()
        }
        // The authenticated link can reset between prepare/execute/result.
        // Retransmit only control messages at a bounded rate. Peer leases and
        // cached outcomes make these retries idempotent and prevent duplicate
        // monitor writes while a connection is recovering.
        if busy && now - lastControlResend >= 0.75 {
            lastControlResend = now
            if committed, let request {
                for peer in required { send(.execute(request.id), peer: peer) }
            } else if let request {
                for peer in required where !prepared.contains(peer) { send(.prepare(request), peer: peer) }
            }
        }
        if !busy { deriveActive() }
        if now >= nextRead, let revision = node.revision, let readForVerification {
            nextRead = now + 20
            for monitor in node.group.monitors where !reading.contains(monitor.id) && (monitor.control?.computer == node.localID || node.group.connections.contains { $0.monitor == monitor.id && $0.computer == node.localID }) {
                reading.insert(monitor.id)
                let generation = desktopGenerations[monitor.id]
                readForVerification(monitor.id) { [weak self] input in
                    guard let self else { return }; self.reading.remove(monitor.id)
                    guard self.node.revision == revision else { return }
                    for peer in self.node.online { self.send(.observed(monitor.id, input, revision, generation), peer: peer) }
                    guard generation == self.desktopGenerations[monitor.id] else { return }
                    for peer in self.node.online { self.send(.desktopObserved(monitor.id, input, revision, generation), peer: peer) }
                }
            }
        }
    }
}
