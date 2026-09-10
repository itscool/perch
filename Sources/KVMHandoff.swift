import Foundation

struct KVMHandoff {
    enum Phase: Equatable { case idle, preparing, switching, active, paused(String) }
    struct Request: Equatable {
        let id: UUID
        let session: UUID
        let preset: UUID
        let group: UUID
        let routes: [KVMAssignment]
        let participants: Set<UUID>
        let focusComputer: UUID?
        let focusMonitor: UUID
        let deadline: Double // monotonic coordinator clock; never wall clock
    }
    private(set) var phase: Phase = .idle
    private(set) var request: Request?
    private(set) var prepared: Set<UUID> = []
    private(set) var verifiedRoutes: Set<UUID> = []
    private(set) var controlOwner: UUID?
    private(set) var routeObservers: [UUID: UUID] = [:]
    private var visibleAt: [UUID: Double] = [:]
    // Upper bound on stale observed visibility; poll adapters must invalidate on
    // disconnect/input changes and renew only with fresh readback, not cached UI.
    static let visibilityLease: Double = 2

    mutating func begin(group: KVMGroup, presetID: UUID, focusMonitor: UUID, inputSources: Set<UUID>,
                        online: Set<UUID>, session: UUID, now: Double, monitorObservers: [UUID: UUID] = [:]) throws -> Request {
        _ = try group.validated()
        guard now.isFinite, now >= 0 else { throw KVMError("Invalid handoff clock.") }
        guard phase != .preparing && phase != .switching else { throw KVMError("Another desk handoff is in progress.") }
        guard let preset = group.presets.first(where: { $0.id == presetID }), !preset.assignments.isEmpty,
              preset.assignments.count == group.monitors.count,
              let focus = preset.assignments.first(where: { $0.monitor == focusMonitor }) else { throw KVMError("Choose a configured preset and a screen to work on.") }
        let connectionMap = Dictionary(uniqueKeysWithValues: group.connections.map { ($0.id, $0) })
        let destinations = Set(preset.assignments.compactMap { connectionMap[$0.connection]?.computer })
        let members = Set(group.computers.map(\.id))
        guard !inputSources.isEmpty, inputSources.isSubset(of: members) else { throw KVMError("Choose the computers receiving your mouse and keyboard.") }
        let focusOwner = connectionMap[focus.connection]?.computer
        var observers: [UUID: UUID] = [:]
        for assignment in preset.assignments {
            guard let observer = monitorObservers[assignment.monitor] ?? connectionMap[assignment.connection]?.computer,
                  members.contains(observer) else { throw KVMError("A grouped computer must be able to switch and verify each selected monitor input.") }
            observers[assignment.connection] = observer
        }
        var participants = destinations.union(inputSources)
        participants.formUnion(observers.values)
        // The previous source computers may still hold keys/buttons even when
        // neither is a destination in the next preset.
        if let previous = request { participants.formUnion(previous.participants) }
        if let controlOwner { participants.insert(controlOwner) }
        guard participants.isSubset(of: online) else { throw KVMError("A computer needed by this preset is offline. Your current control has not changed.") }
        let value = Request(id: UUID(), session: session, preset: presetID, group: group.id, routes: preset.assignments,
                            participants: participants, focusComputer: focusOwner, focusMonitor: focusMonitor, deadline: now + 10)
        // Input routing is suspended immediately. Participants must release held
        // events before reporting prepared. The adapter preserves local recovery.
        request = value; phase = .preparing; prepared = []; verifiedRoutes = []; visibleAt = [:]
        routeObservers = observers
        controlOwner = nil
        return value
    }

    private func accepts(_ id: UUID, _ session: UUID, now: Double) -> Bool {
        guard let request else { return false }
        return id == request.id && session == request.session && now.isFinite && now >= request.deadline - 10 && now < request.deadline
    }
    mutating func participantPrepared(_ peer: UUID, request id: UUID, session: UUID, releasedInput: Bool, now: Double) {
        expire(now: now)
        guard phase == .preparing, accepts(id, session, now: now), request!.participants.contains(peer) else { return }
        guard releasedInput else { fail("A computer could not release held keys or mouse buttons."); return }
        prepared.insert(peer)
        if prepared == request!.participants { phase = .switching }
    }
    mutating func observedVisible(connection: UUID, by peer: UUID, request id: UUID, session: UUID, now: Double) {
        expire(now: now)
        guard phase == .switching, accepts(id, session, now: now), routeObservers[connection] == peer else { return }
        // This method means a fresh, transaction-bound verified visible picture.
        // Merely enumerating a display or sending DDC must never call it.
        verifiedRoutes.insert(connection); visibleAt[connection] = now
    }
    mutating func commit(request id: UUID, session: UUID, now: Double) throws {
        expire(now: now)
        guard phase == .switching, accepts(id, session, now: now), let request,
              request.routes.allSatisfy({ route in
                  guard let time = visibleAt[route.connection] else { return false }
                  return now >= time && now - time < Self.visibilityLease
              }) else { throw KVMError("The selected screens have not all confirmed their picture. Input remains paused.") }
        controlOwner = request.focusComputer; phase = .active
    }
    mutating func renewVisible(connection: UUID, by peer: UUID, request id: UUID, session: UUID, now: Double) {
        guard phase == .active, let request, request.id == id, request.session == session,
              routeObservers[connection] == peer, now.isFinite, let previous = visibleAt[connection], now >= previous else { return }
        // An expired route cannot be resurrected by a late read; re-prepare it.
        guard now - previous < Self.visibilityLease else { fail("A screen's visible input could no longer be confirmed."); return }
        visibleAt[connection] = now
    }
    mutating func canForward(to peer: UUID, now: Double) -> Bool {
        expire(now: now)
        guard phase == .active, now.isFinite, let request, controlOwner == peer else { return false }
        guard request.routes.allSatisfy({ route in
            guard let time = visibleAt[route.connection] else { return false }
            return now >= time && now - time < Self.visibilityLease
        }) else { fail("A screen's visible input could no longer be confirmed."); return false }
        return true
    }
    mutating func peerDisconnected(_ peer: UUID) {
        if request?.participants.contains(peer) == true { fail("A computer disconnected. Use local control while Perch reconnects.") }
    }
    mutating func routeInvalidated(_ connection: UUID) {
        if routeObservers[connection] != nil { fail("A screen's input changed or could not be confirmed.") }
    }
    mutating func expire(now: Double) {
        if (phase == .preparing || phase == .switching), let request,
           !now.isFinite || now < request.deadline - 10 || now >= request.deadline { fail("The desk handoff timed out. Input remains local or paused.") }
    }
    mutating func fail(_ message: String) { phase = .paused(message); controlOwner = nil; verifiedRoutes = []; visibleAt = [:] }
    mutating func recoverLocally() { request = nil; phase = .idle; controlOwner = nil; prepared = []; verifiedRoutes = []; visibleAt = [:]; routeObservers = [:] }
}
