import Foundation
import Security
import Darwin

@objc protocol LidGuardProtocol {
    func status(_ reply: @escaping (Data) -> Void)
    func setEnabled(_ enabled: Bool, reply: @escaping (Data) -> Void)
    func renew(_ token: String, reply: @escaping (Data) -> Void)
    func prepareRestart(_ token: String, targetIdentity: String, reply: @escaping (Data) -> Void)
    func cancelRestart(_ token: String, ticket: String, reply: @escaping (Data) -> Void)
    func resumeRestart(_ ticket: String, reply: @escaping (Data) -> Void)
}
struct LidGuardReply: Codable { var status: LidGuardStatus; var token: String?; var restart: LidRestartTicket? = nil; var restartError: String? = nil }
struct LidGuardLease: Codable {
    var token: String?; var expires: Double; var deadline: Double?
    func acceptsRenewal(_ supplied: String, now: Double) -> Bool { token == supplied && expires.isFinite && now.isFinite && now >= 0 && now < expires }
}
struct LidGuardAck: Codable { var token: String?; var time: Double; var allowed: Bool }
struct LidGuardWatchdogState {
    private(set) var lease = LidGuardLease(token: nil, expires: 0, deadline: nil)
    private var policy = LidGuardPolicy()
    mutating func receive(_ next: LidGuardLease, now: Double) -> Bool {
        guard next.expires.isFinite, next.expires >= 0, next.expires <= now + 6,
              next.token == nil || UUID(uuidString: next.token!) != nil,
              next.deadline == nil || (next.deadline!.isFinite && next.deadline! >= 0) else { return false }
        if next.token != lease.token { policy = LidGuardPolicy() }
        lease = next; return true
    }
    mutating func evaluate(_ observation: LidObservation, now: Double, channelAlive: Bool) -> LidGuardDecision {
        policy.constrainDeadline(lease.deadline)
        return policy.step(observation, now: now, authorized: channelAlive && lease.expires > now && lease.token != nil)
    }
}

enum LidGuardOwnership {
    static let path = "/var/run/local.scott.perch.lid.active"
    static var exists: Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_uid == 0 && info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1
    }
    static var token: String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW); guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat(), bytes = [UInt8](repeating: 0, count: 64)
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { return nil }
        let count = read(fd, &bytes, bytes.count)
        guard count == 36, let value = String(bytes: bytes.prefix(count), encoding: .utf8), UUID(uuidString: value) != nil else { return nil }
        return value
    }
    static func claim(_ token: String) throws {
        guard UUID(uuidString: token) != nil else { throw AppError(message: "Invalid lid session.") }
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw AppError(message: "A prior lid session still needs cleanup. Restart the lid helper before enabling it.") }
        defer { close(fd) }
        let bytes = Array(token.utf8)
        guard bytes.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == bytes.count else { throw AppError(message: "Could not record the lid session.") }
    }
    static func release(_ enforcer: LidGuardEnforcer, sleep: Bool, now: Double, expectedToken: String? = nil) throws {
        guard exists, expectedToken == nil || token == expectedToken else { return }
        try enforcer.apply(.init(preventLidSleep: false, requestSleep: sleep, remaining: nil, detail: "Stopped"), now: now, forceRelease: true)
        guard unlink(path) == 0 || errno == ENOENT else { throw AppError(message: "Could not finish recording lid cleanup.") }
    }
}

/// Newline frames are bounded and nonblocking so a broken watchdog cannot wedge
/// the supervisor. Only a private parent/child pipe can renew this lease.
final class LidGuardPipe {
    let input: Int32
    let output: Int32
    var buffer = Data()
    var ended = false
    init(input: Int32, output: Int32) {
        self.input = input; self.output = output
        _ = fcntl(input, F_SETFL, O_NONBLOCK); _ = fcntl(output, F_SETFL, O_NONBLOCK)
        signal(SIGPIPE, SIG_IGN)
    }
    func receive<T: Decodable>(_ type: T.Type) -> [T] {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = read(input, &bytes, bytes.count)
        if count == 0 { ended = true }
        if count > 0 { buffer.append(contentsOf: bytes.prefix(count)) }
        if buffer.count > 8192 { ended = true; buffer.removeAll(); return [] }
        var values: [T] = []
        while let newline = buffer.firstIndex(of: 10) {
            let frame = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard frame.count <= 2048, let value = try? JSONDecoder().decode(T.self, from: frame) else { ended = true; return [] }
            values.append(value)
        }
        return values
    }
    func send<T: Encodable>(_ value: T) -> Bool {
        guard var bytes = try? JSONEncoder().encode(value), bytes.count <= 2048 else { return false }
        bytes.append(10)
        return bytes.withUnsafeBytes { write(output, $0.baseAddress, $0.count) == $0.count }
    }
}

/// The watchdog never enables an override. It independently observes lid/power
/// and can only release our session and request sleep if the supervisor hangs.
func runLidGuardWatchdog() -> Never {
    guard geteuid() == 0 else { exit(1) }
    let channel = LidGuardPipe(input: STDIN_FILENO, output: STDOUT_FILENO)
    let activity = LidActivityRecorder(source: "Watchdog")
    let hardware = MacLidGuardHardware(), enforcer = LidGuardEnforcer(MacLidGuardHardware(), log: { activity.record($0, coalesce: true) })
    activity.record("Independent lid watchdog started.")
    var state = LidGuardWatchdogState()
    while true {
        let now = LidGuardClock.now
        for next in channel.receive(LidGuardLease.self) {
            guard state.receive(next, now: now) else { channel.ended = true; break }
        }
        let observation = hardware.observe()
        let lease = state.lease
        let fresh = !channel.ended && lease.expires > now
        let decision = state.evaluate(observation, now: now, channelAlive: !channel.ended)
        if !decision.preventLidSleep, let token = lease.token {
            if LidGuardOwnership.token == token { activity.record("Watchdog recovery: \(decision.detail)", coalesce: true) }
            do { try LidGuardOwnership.release(enforcer, sleep: decision.requestSleep, now: now, expectedToken: token) }
            catch { activity.record("Watchdog cleanup failed: \(error.localizedDescription)", coalesce: true) }
        }
        _ = channel.send(LidGuardAck(token: lease.token, time: now, allowed: lease.token == nil ? fresh : decision.preventLidSleep))
        if channel.ended && (!LidGuardOwnership.exists || LidGuardOwnership.token != lease.token) { activity.record("Watchdog finished recovery after its supervisor connection ended."); activity.finish(); exit(0) }
        usleep(250_000)
    }
}

final class LidGuardService: NSObject, NSXPCListenerDelegate {
    static let name = "local.scott.perch.lid"
    static let restartName = name + ".restart"
    private let restartListener = NSXPCListener(machServiceName: restartName)
    private let owner: uid_t
    private let listener = NSXPCListener(machServiceName: name)
    private let hardware = MacLidGuardHardware()
    private let activity = LidActivityRecorder(source: "Lid helper")
    private var activityTracker = LidActivityTracker()
    private var powerObserver: LidPowerNotifications?
    private var lastActivityPrune: Double = 0
    private let idleAwake = Awake()
    private lazy var enforcer = LidGuardEnforcer(hardware, log: { [weak self] in self?.activity.record($0, coalesce: true) })
    private var child: Process?
    private var pipes: [Pipe] = []
    private var channel: LidGuardPipe?
    private var ack: LidGuardAck?
    private var policy = LidGuardPolicy()
    private var token: String?
    private var leaseEnds: Double = 0
    private let restartLock = NSLock()
    private var restart = LidRestartHandoff()
    private var startingUntil: Double?
    private var snapshot = LidGuardStatus(updatedAt: 0, armed: false, remaining: nil, detail: "Lid protection is off.")
    private var connections: [NSXPCConnection] = []
    init(owner: uid_t) { self.owner = owner; super.init(); listener.delegate = self; restartListener.delegate = self }
    func run() -> Never {
        guard geteuid() == 0 else { exit(1) }
        activity.record("Lid helper started (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")). Previous gaps in observation cannot be reconstructed.")
        powerObserver = LidPowerNotifications(activity: activity, observe: { [weak self] in
            guard let self else { return }
            for message in self.activityTracker.observe(self.hardware.observe(), now: LidGuardClock.now) { self.activity.record(message) }
        }, sleepBeginning: { [weak self] in self?.systemSleepBegan() })
        powerObserver?.start()
        // Launchd restarts begin disarmed; old UI preferences cannot re-arm us.
        do {
            let observation = hardware.observe()
            try LidGuardOwnership.release(enforcer, sleep: observation.closed != false && observation.power != .external, now: LidGuardClock.now)
            let toChild = Pipe(), fromChild = Pipe(), process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--lid-watchdog"]
            process.standardInput = toChild; process.standardOutput = fromChild; process.standardError = FileHandle.nullDevice
            try process.run(); toChild.fileHandleForReading.closeFile(); fromChild.fileHandleForWriting.closeFile()
            pipes = [toChild, fromChild]; child = process
            channel = LidGuardPipe(input: fromChild.fileHandleForReading.fileDescriptor, output: toChild.fileHandleForWriting.fileDescriptor)
        } catch { snapshot.detail = error.localizedDescription; snapshot.error = error.localizedDescription; activity.record("Helper startup failed: \(error.localizedDescription)") }
        listener.resume(); restartListener.resume()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        withExtendedLifetime(self) { RunLoop.main.run() }; exit(0)
    }
    private func systemSleepBegan() {
        guard token != nil, snapshot.armed, !policy.stopped else { return }
        let now = LidGuardClock.now
        let remaining = policy.deadline.map { " Battery deadline had \(LidActivityTracker.seconds($0 - now)) remaining." } ?? " No battery countdown was active."
        activity.record("Sleep interrupted an active lid session. This helper had not requested sleep in the session; check earlier Watchdog entries too.\(remaining) macOS does not provide the cause in this notification.")
        policy.systemSleepBegan()
        snapshot = .init(updatedAt: now, armed: false, remaining: nil, detail: policy.sleepInterruption!, error: policy.sleepInterruption)
        // The next supervised tick releases the command. Never perform power
        // mutations inside the macOS notification callback.
    }
    private func tick() {
        let now = LidGuardClock.now
        if let channel { for value in channel.receive(LidGuardAck.self) { ack = value } }
        let observation = hardware.observe()
        for message in activityTracker.observe(observation, now: now) { activity.record(message) }
        if now - lastActivityPrune >= 60 { activity.prune(); lastActivityPrune = now }
        if token != nil {
            let watched = child?.isRunning == true && channel?.ended == false && ack.map { now >= $0.time && now - $0.time < 2 && ($0.token == token && $0.allowed) } == true
            if let until = startingUntil, !watched, now < until {
                _ = channel?.send(LidGuardLease(token: token, expires: min(now+3, leaseEnds), deadline: nil)); return
            }
            if !policy.stopped && (now >= leaseEnds || !watched) {
                activity.record(now >= leaseEnds ? "App heartbeat expired. Ending lid protection." : "Independent watchdog confirmation was lost. Ending lid protection.")
            }
            let decision = policy.step(observation, now: now, authorized: now < leaseEnds && watched)
            for message in activityTracker.decision(decision, observation: observation, deadline: policy.deadline, now: now) { activity.record(message) }
            do {
                // Recheck after the watchdog handshake: the power source or lid
                // may have changed since the initial enable request.
                if startingUntil != nil && decision.preventLidSleep { try LidGuardStart.validate(observation) }
                try idleAwake.set(decision.preventLidSleep)
                if decision.preventLidSleep {
                    if startingUntil != nil { try LidGuardOwnership.claim(token!) }
                    guard LidGuardOwnership.token == token else { throw AppError(message: "The watchdog ended this lid session. Enable it again with the lid open or external power connected.") }
                }
                startingUntil = nil
                try enforcer.apply(decision, now: now)
                if decision.preventLidSleep && LidGuardOwnership.token != token {
                    try enforcer.apply(.init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external, remaining: nil, detail: "Watchdog ended this session"), now: LidGuardClock.now)
                    throw AppError(message: "The watchdog ended this session before lid control was confirmed.")
                }
                if !decision.preventLidSleep { try LidGuardOwnership.release(enforcer, sleep: decision.requestSleep, now: now); token = nil; restartLock.withLock { restart.clear() } }
                snapshot = .init(updatedAt: now, armed: decision.preventLidSleep, remaining: decision.remaining, detail: decision.detail, error: policy.sleepInterruption)
            } catch {
                activity.record("Lid session failed: \(error.localizedDescription)", coalesce: true)
                token = nil
                restartLock.withLock { restart.clear() }
                try? idleAwake.set(false)
                try? enforcer.apply(.init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external, remaining: nil, detail: "Lid control failed"), now: LidGuardClock.now)
                try? LidGuardOwnership.release(enforcer, sleep: observation.closed != false && observation.power != .external, now: now)
                snapshot = .init(updatedAt: now, armed: false, remaining: nil, detail: error.localizedDescription, error: error.localizedDescription)
            }
        } else {
            if LidGuardOwnership.exists {
                do { try LidGuardOwnership.release(enforcer, sleep: observation.closed != false && observation.power != .external, now: now) }
                catch { snapshot.detail = error.localizedDescription; snapshot.error = error.localizedDescription; activity.record("Lid cleanup failed: \(error.localizedDescription)", coalesce: true) }
            }
            snapshot.updatedAt = now
        }
        snapshot.activityError = activity.error
        if channel?.send(LidGuardLease(token: token, expires: min(now+3, token == nil ? now+3 : leaseEnds), deadline: policy.deadline)) == false { ack = nil }
    }
    private func encoded(restartError: String? = nil) -> Data { (try? JSONEncoder().encode(LidGuardReply(status: snapshot, token: token, restart: restartLock.withLock { restart.pending }, restartError: restartError))) ?? Data() }
    func status(_ reply: @escaping (Data) -> Void) { DispatchQueue.main.async { reply(self.encoded()) } }
    func renew(_ token: String, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            let now = LidGuardClock.now
            // A late renewal cannot resurrect an expired lease.
            if self.restartLock.withLock({ self.restart.pending == nil }), LidGuardLease(token: self.token, expires: self.leaseEnds, deadline: nil).acceptsRenewal(token, now: now) { self.leaseEnds = now + 5 }
            reply(self.encoded())
        }
    }
    func prepareRestart(_ supplied: String, targetIdentity: String, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.tick()
            do {
                let now = LidGuardClock.now
                let ticket = try self.restartLock.withLock {
                    try self.restart.prepare(identity: targetIdentity, now: now,
                        active: self.token == supplied && self.snapshot.armed && !self.policy.stopped && now < self.leaseEnds)
                }
                self.leaseEnds = ticket.deadline
                self.activity.record("Update restart allowance started: 60 seconds maximum. Battery and watchdog deadlines remain active.", coalesce: true)
                self.tick(); reply(self.encoded())
            } catch { reply(self.encoded(restartError: error.localizedDescription)) }
        }
    }
    func resumeRestart(_ ticket: String, pinnedConnection: String?, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.tick()
            do {
                let now = LidGuardClock.now
                try self.restartLock.withLock { try self.restart.claim(ticket, pinnedConnection: pinnedConnection, now: now,
                    active: self.snapshot.armed && self.token != nil && !self.policy.stopped && now < self.leaseEnds) }
                self.leaseEnds = now + 5
                self.activity.record("Updated Perch reclaimed the lid session. Normal heartbeats resumed; battery deadline preserved.")
                self.tick(); reply(self.encoded())
            } catch { reply(self.encoded(restartError: error.localizedDescription)) }
        }
    }
    func cancelRestart(_ supplied: String, ticket: String, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.tick()
            let now = LidGuardClock.now
            if self.token == supplied && self.snapshot.armed && now < self.leaseEnds &&
                self.restartLock.withLock({ self.restart.pending != nil && (ticket.isEmpty || self.restart.pending?.id == ticket) }) {
                self.restartLock.withLock { self.restart.clear() }
                self.leaseEnds = now + 5
                self.activity.record("Update cancelled before restart. Normal app heartbeat restored.")
            }
            reply(self.encoded())
        }
    }
    func setEnabled(_ enabled: Bool, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            let now = LidGuardClock.now, observation = self.hardware.observe()
            do {
                if enabled && self.token == nil {
                    self.activity.record("Enable lid protection requested.")
                    try LidGuardStart.validate(observation)
                    guard self.child?.isRunning == true, self.channel?.ended == false, let ack = self.ack, now >= ack.time, now - ack.time < 2 else { throw AppError(message: "The lid watchdog is unavailable. Repair the lid helper before relying on this mode.") }
                    guard try !sleepDisabled() else { throw AppError(message: "The old system-wide sleep override is still on. Remove it with Review sleep reset before enabling the 60-second mode.") }
                    self.policy = LidGuardPolicy(); self.activityTracker.endSession(); let token = UUID().uuidString
                    self.token = token; self.leaseEnds = now + 5; self.startingUntil = now + 1
                    // Wait for an independent watchdog acknowledgment before
                    // enabling the hardware bit or displaying Ready.
                    self.snapshot = .init(updatedAt: now, armed: false, remaining: nil, detail: "Starting lid watchdog…")
                    _ = self.channel?.send(LidGuardLease(token: token, expires: now+3, deadline: nil))
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.4) {
                        if let channel = self.channel { for value in channel.receive(LidGuardAck.self) { self.ack = value } }
                        self.tick(); reply(self.encoded())
                    }
                    return
                } else if !enabled {
                    self.activity.record("Disable lid protection requested.")
                    self.token = nil
                    self.restartLock.withLock { self.restart.clear() }
                    try self.idleAwake.set(false)
                    try LidGuardOwnership.release(self.enforcer, sleep: observation.closed != false && observation.power != .external, now: now)
                    self.snapshot = .init(updatedAt: now, armed: false, remaining: nil, detail: "Lid protection is off. Normal macOS lid behavior applies.")
                    self.activityTracker.endSession(); self.activity.record("Lid protection disabled.")
                }
            } catch { self.snapshot = .init(updatedAt: now, armed: false, remaining: nil, detail: error.localizedDescription, error: error.localizedDescription); self.activity.record("Lid setting failed: \(error.localizedDescription)") }
            reply(self.encoded())
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == owner, let requirement = HelperStatusIPC.requirement else { return false }
        let ticket = listener === restartListener ? restartLock.withLock { restart.pending } : nil
        guard listener !== restartListener || ticket != nil else { return false }
        // Normal status/cancellation connections remain available to the old
        // app after a transport failure. The dedicated claim endpoint is pinned.
        // Only a newly connected instance of the exact staged executable can
        // claim the allowance. Existing old-app connections are not eligible.
        connection.setCodeSigningRequirement(requirement + (ticket.map { " and cdhash H\"\($0.targetIdentity)\"" } ?? ""))
        connection.exportedInterface = NSXPCInterface(with: LidGuardProtocol.self)
        connection.exportedObject = LidGuardConnection(service: self, pinnedTicket: ticket?.id)
        // Only the configured user and matching signed Perch code can call the
        // narrow interface. It accepts no paths, commands or timer durations.
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        guard connections.count < 4 else { return false }; connections.append(connection)
        connection.invalidationHandler = { [weak self, weak connection] in guard let self else { return }; objc_sync_enter(self); self.connections.removeAll { $0 === connection }; objc_sync_exit(self) }
        connection.resume(); return true
    }
}

private final class LidGuardConnection: NSObject, LidGuardProtocol {
    let service: LidGuardService
    let pinnedTicket: String?
    init(service: LidGuardService, pinnedTicket: String?) { self.service = service; self.pinnedTicket = pinnedTicket }
    func status(_ reply: @escaping (Data) -> Void) { service.status(reply) }
    func renew(_ token: String, reply: @escaping (Data) -> Void) { service.renew(token, reply: reply) }
    func setEnabled(_ enabled: Bool, reply: @escaping (Data) -> Void) { service.setEnabled(enabled, reply: reply) }
    func prepareRestart(_ token: String, targetIdentity: String, reply: @escaping (Data) -> Void) { service.prepareRestart(token, targetIdentity: targetIdentity, reply: reply) }
    func cancelRestart(_ token: String, ticket: String, reply: @escaping (Data) -> Void) { service.cancelRestart(token, ticket: ticket, reply: reply) }
    func resumeRestart(_ ticket: String, reply: @escaping (Data) -> Void) { service.resumeRestart(ticket, pinnedConnection: pinnedTicket, reply: reply) }
}
