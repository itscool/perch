import Foundation
import Combine

struct KVMMonitorRoute: Codable, Equatable {
    let monitor: UUID
    let control: KVMMonitorControl
    let input: UInt16
}
struct KVMMonitorRequest: Codable, Equatable {
    let id: UUID
    let epoch: UUID
    let revision: String
    let preset: UUID
    let routes: [KVMMonitorRoute]
    static func make(group: KVMGroup, preset: UUID, epoch: UUID, revision: String, id: UUID = UUID()) throws -> Self {
        _ = try group.validated()
        guard let preset = group.presets.first(where: { $0.id == preset }), !group.monitors.isEmpty,
              preset.assignments.count == group.monitors.count else { throw KVMError("Choose an input for every screen in this preset.") }
        let routes = try group.monitors.map { monitor -> KVMMonitorRoute in
            guard let control = monitor.control else { throw KVMError("Choose a control connection for \(monitor.name).") }
            guard let assignment = preset.assignments.first(where: { $0.monitor == monitor.id }),
                  let input = group.connections.first(where: { $0.id == assignment.connection })?.inputCode else { throw KVMError("Choose the actual input code for \(monitor.name)’s connection.") }
            return .init(monitor: monitor.id, control: control, input: input)
        }
        return Self(id: id, epoch: epoch, revision: revision, preset: preset.id, routes: routes)
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
    case prepare(KVMMonitorRequest)
    case prepared(UUID)
    case refused(UUID, String)
    case execute(UUID)
    case release(UUID)
    case result(KVMMonitorOutcome)
    case verify(KVMMonitorRequest, UUID)
    case verified(UUID, UUID, UInt16?)
    case observed(UUID, UInt16?, String)
    case delegate(KVMMonitorRequest, UUID)
    case delegated(KVMMonitorOutcome)
}

/// One lease at each monitor's explicit control computer. Preparation acquires
/// every needed control lease before commands start. No input permissions or
/// synthesized keyboard/mouse events participate in monitor-only switching.
final class KVMMonitorSwitch: ObservableObject {
    struct Lease { let peer: UUID; let request: KVMMonitorRequest; let created: TimeInterval; var executing = false; var completed = false }
    @Published private(set) var request: KVMMonitorRequest?
    @Published private(set) var results: [UUID: KVMMonitorOutcome] = [:]
    @Published private(set) var busy = false
    @Published private(set) var activePreset: UUID?
    @Published private(set) var activeGroup: KVMGroup?
    @Published private(set) var problem: String?
    let node: KVMDeskNode
    var execute: ((KVMMonitorRoute, @escaping () -> Bool, @escaping (KVMMonitorOutcome.State, String) -> Void) -> Void)?
    var readForVerification: ((UUID, @escaping (UInt16?) -> Void) -> Void)?
    var otherMessage: ((UUID, Data) -> Void)?
    private var leases: [UUID: Lease] = [:]
    private var delegates: [UUID: UUID] = [:]
    private var prepared: Set<UUID> = []
    private var required: Set<UUID> = []
    private var verification: [UUID: Set<UUID>] = [:]
    private var verifyingMonitors: Set<UUID> = []
    private struct Observation { let input: UInt16; let peer: UUID; let time: TimeInterval }
    private var observations: [UUID: Observation] = [:]
    private var reading: Set<UUID> = []
    private var nextRead: TimeInterval = 0
    private var lastConfirmed: TimeInterval?
    private var timer: Timer?
    private var started: TimeInterval = 0
    private var committed = false
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var now: TimeInterval { clock() }
    init(node: KVMDeskNode) {
        self.node = node
        node.application = { [weak self] peer, data in
            guard let self else { return }
            if let message = try? JSONDecoder().decode(KVMMonitorMessage.self, from: data) { self.receive(message, peer: peer) }
            else { self.otherMessage?(peer, data) }
        }
        node.canCheckpoint = { [weak self] in self?.busy != true && self?.leases.isEmpty == true }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
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
    func activate(_ preset: UUID) {
        if let problem = readiness(preset) { self.problem = problem; return }
        do {
            let request = try KVMMonitorRequest.make(group: node.group, preset: preset, epoch: node.graph.roster.epoch, revision: node.revision!)
            self.request = request; results = [:]; prepared = []; verification = [:]; verifyingMonitors = []
            required = Set(request.routes.map { $0.control.computer }); started = now; committed = false
            busy = true; problem = nil; activePreset = nil; activeGroup = nil; lastConfirmed = nil
            for peer in required { send(.prepare(request), peer: peer) }
        } catch { problem = error.localizedDescription }
    }
    private func send(_ message: KVMMonitorMessage, peer: UUID) {
        if peer == node.localID { DispatchQueue.main.async { [weak self] in self?.receive(message, peer: peer) }; return }
        if let bytes = try? JSONEncoder().encode(message) { node.sendApplication(bytes, peer: peer) }
    }
    private func receive(_ message: KVMMonitorMessage, peer: UUID) {
        guard node.online.contains(peer) else { return }
        switch message {
        case .delegate(let request, let monitor):
            guard node.canEdit, request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                  let route = request.routes.first(where: { $0.monitor == monitor && $0.control.computer == peer }),
                  ["standard", "lg"].contains(route.control.mode),
                  let connection = node.group.connections.first(where: { $0.monitor == monitor && $0.computer == node.localID }),
                  let display = connection.localDisplay,
                  (try? KVMMonitorRequest.make(group: node.group, preset: request.preset, epoch: request.epoch, revision: request.revision, id: request.id)) == request,
                  leases[monitor] == nil, let execute else { return }
            let lease = Lease(peer: peer, request: request, created: now, executing: true)
            leases[monitor] = lease
            let localRoute = KVMMonitorRoute(monitor: monitor, control: .init(computer: node.localID, localDisplay: display, mode: route.control.mode), input: route.input)
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
        case .observed(let monitor, let input, let revision):
            guard revision == node.revision, node.group.monitors.contains(where: { $0.id == monitor && ($0.control?.computer == peer || node.group.connections.contains(where: { $0.monitor == monitor && $0.computer == peer })) }) else { return }
            if let input, input > 0 { observations[monitor] = Observation(input: input, peer: peer, time: now) }
            else if observations[monitor]?.peer == peer { observations[monitor] = nil }
            if !busy { deriveActive() }
        case .prepare(let request):
            do {
                guard node.canEdit, request.epoch == node.graph.roster.epoch, request.revision == node.revision,
                      request.routes.contains(where: { $0.control.computer == node.localID }),
                      try KVMMonitorRequest.make(group: node.group, preset: request.preset, epoch: request.epoch, revision: request.revision, id: request.id) == request else { throw KVMError("Desk setup changed. Wait for synchronization, then try the preset again.") }
                let own = request.routes.filter { $0.control.computer == node.localID }
                guard own.allSatisfy({ route in leases[route.monitor] == nil || leases[route.monitor]?.request.id == request.id && leases[route.monitor]?.peer == peer }) else { throw KVMError("Another computer is switching one of these screens. Wait for it to finish.") }
                for route in own where leases[route.monitor] == nil { leases[route.monitor] = Lease(peer: peer, request: request, created: now) }
                send(.prepared(request.id), peer: peer)
            } catch { send(.refused(request.id, error.localizedDescription), peer: peer) }
        case .prepared(let id):
            guard busy, let request, request.id == id, required.contains(peer), !committed else { return }
            prepared.insert(peer)
            if prepared == required { committed = true; for peer in required { send(.execute(id), peer: peer) } }
        case .refused(let id, let reason):
            guard busy, request?.id == id, required.contains(peer) else { return }; finishFailure(reason)
        case .execute(let id):
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
                    return current.request.id == id && current.peer == peer && self.now - current.created < 55 && self.node.online.contains(peer) && self.node.graph.roster.epoch == lease.request.epoch && self.node.group.monitors.first { $0.id == monitor }?.control == route.control
                }, { [weak self] state, detail in self?.complete(route, lease: lease, state: state, detail: detail) })
            }
        case .release(let id):
            for (monitor, lease) in leases where lease.peer == peer && lease.request.id == id && (!lease.executing || lease.completed) { leases[monitor] = nil; delegates[monitor] = nil }
        case .result(let outcome):
            guard busy, let request, request.id == outcome.request,
                  request.routes.contains(where: { $0.monitor == outcome.monitor && $0.input == outcome.input && $0.control.computer == peer }) else { return }
            results[outcome.monitor] = outcome
            if outcome.state == .unverified {
                let observers = Set(node.group.connections.filter { $0.monitor == outcome.monitor }.compactMap(\.computer)).intersection(node.online)
                verification[outcome.monitor] = observers
                verifyingMonitors.insert(outcome.monitor)
                for observer in observers { send(.verify(request, outcome.monitor), peer: observer) }
                if observers.isEmpty { verifyingMonitors.remove(outcome.monitor) }
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
            if input == route.input {
                results[monitor] = .init(request: id, monitor: monitor, input: route.input, state: .confirmed, detail: "A fresh monitor read on \(node.group.computers.first { $0.id == peer }?.name ?? "a paired Mac") confirms this input.")
                verifyingMonitors.remove(monitor)
            } else if verification[monitor]?.isEmpty == true { verifyingMonitors.remove(monitor) }
            finishIfReady()
        }
    }
    private func complete(_ route: KVMMonitorRoute, lease: Lease, state: KVMMonitorOutcome.State, detail: String) {
        guard leases[route.monitor]?.request.id == lease.request.id else { return }
        if state == .failed, delegates[route.monitor] == nil, ["standard", "lg"].contains(route.control.mode), now-lease.created < 18 {
            let candidates = node.group.connections.filter { $0.monitor == route.monitor && $0.computer != node.localID && $0.computer.map(node.online.contains) == true }
            let candidate = candidates.first { $0.inputCode == observations[route.monitor]?.input } ?? candidates.sorted { ($0.computer?.uuidString ?? "") < ($1.computer?.uuidString ?? "") }.first
            if let peer = candidate?.computer { delegates[route.monitor] = peer; send(.delegate(lease.request, route.monitor), peer: peer); return }
        }
        leases[route.monitor]?.completed = true
        send(.result(.init(request: lease.request.id, monitor: route.monitor, input: route.input, state: state, detail: String(detail.prefix(500)))), peer: lease.peer)
    }
    private func finishIfReady() {
        guard let request, results.count == request.routes.count, verifyingMonitors.isEmpty else { return }
        busy = false
        for peer in required { send(.release(request.id), peer: peer) }
        if results.values.allSatisfy({ $0.state == .confirmed }) {
            activePreset = request.preset; activeGroup = node.group; lastConfirmed = now; problem = nil
            for route in request.routes { observations[route.monitor] = Observation(input: route.input, peer: route.control.computer, time: now) }
        } else { problem = "Some screens could not confirm the requested input. Review their results and try the preset again." }
    }
    private func finishFailure(_ reason: String) {
        guard let request else { return }
        busy = false; problem = reason; activePreset = nil; activeGroup = nil
        for route in request.routes where results[route.monitor] == nil { results[route.monitor] = .init(request: request.id, monitor: route.monitor, input: route.input, state: .unverified, detail: "Switch not confirmed. " + reason) }
        for peer in required { send(.release(request.id), peer: peer) }
    }
    private func deriveActive() {
        observations = observations.filter { now - $0.value.time <= 45 && node.online.contains($0.value.peer) }
        let matches = node.group.presets.filter { preset in
            !node.group.monitors.isEmpty && preset.assignments.count == node.group.monitors.count && preset.assignments.allSatisfy { assignment in
                guard let expected = node.group.connections.first(where: { $0.id == assignment.connection })?.inputCode else { return false }
                return observations[assignment.monitor]?.input == expected
            }
        }
        if let activePreset, matches.contains(where: { $0.id == activePreset }) { return }
        activePreset = matches.count == 1 ? matches.first?.id : nil
        activeGroup = activePreset == nil ? nil : node.group
    }
    func poll() { tick() }
    private func tick() {
        // Keep executing leases until their bounded backend finishes. Expiration
        // denies further writes, but never unlocks a still-running command.
        for (monitor, lease) in leases where now - lease.created > 65 && (!lease.executing || lease.completed) { leases[monitor] = nil; delegates[monitor] = nil }
        if busy && (now - started > 45 || !required.isSubset(of: node.online)) { finishFailure("A computer disconnected or the switch timed out. Actual monitor inputs need to be checked.") }
        if !busy { deriveActive() }
        if now >= nextRead, let revision = node.revision, let readForVerification {
            nextRead = now + 20
            for monitor in node.group.monitors where !reading.contains(monitor.id) && (monitor.control?.computer == node.localID || node.group.connections.contains { $0.monitor == monitor.id && $0.computer == node.localID }) {
                reading.insert(monitor.id)
                readForVerification(monitor.id) { [weak self] input in
                    guard let self else { return }; self.reading.remove(monitor.id)
                    guard self.node.revision == revision else { return }
                    for peer in self.node.online { self.send(.observed(monitor.id, input, revision), peer: peer) }
                }
            }
        }
    }
}
