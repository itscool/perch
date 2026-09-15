import Foundation
import Darwin

/// An installer allowance is never renewable. Its durable record outlives both
/// replaced jobs; a separate launchd job restores sleep on failure or reboot.
struct LidMaintenanceRecord: Codable, Equatable {
    static let limit: Double = 60
    let token: String
    let previousToken: String?
    let boot: String
    let started: Double
    var expires: Double
    let resume: Bool
    var countdown: LidCountdown?
    var batteryDeadline: Double?
    var guardPID: Int32? = nil
    var guardBirth: UInt64? = nil
    var guardUpdatedAt: Double? = nil
    var fresh: Bool { fresh(boot: LidSleepOverride.boot, now: LidGuardClock.now) }
    func fresh(boot: String, now: Double) -> Bool {
        self.boot == boot && !boot.isEmpty && started.isFinite && expires.isFinite &&
        now.isFinite && now >= started && now < expires && expires <= started + Self.limit
    }
}

enum LidMaintenance {
    static let name = "local.scott.perch.lid.update-recovery"
    static let bundle = "/Library/PrivilegedHelperTools/Perch Lid Update Guard.app"
    static let binary = bundle + "/Contents/MacOS/Perch"
    static var path: String { LidSleepOverride.store.directory.appendingPathComponent("maintenance.json").path }
    private static var observedPolicy: (String, LidGuardPolicy)?
    static var record: LidMaintenanceRecord? { try? LidSleepOverride.store.read(LidMaintenanceRecord.self, path: path) }
    static func guardReady(_ value: LidMaintenanceRecord) -> Bool {
        guard let pid = value.guardPID, let birth = value.guardBirth, let updated = value.guardUpdatedAt,
              updated.isFinite, LidGuardClock.now >= updated, LidGuardClock.now - updated < 3 else { return false }
        return ProcessCPUReader.birth(pid) == birth
    }
    static var holding: Bool {
        guard let value = record, value.fresh, guardReady(value) else { return false }
        return (try? LidSleepOverride.store.record().token) == value.token
    }
    static func note(_ message: String) {
        let activity = LidActivityRecorder(source: "Helper update")
        activity.record(message); activity.finish()
    }
    /// Lid update steps wait longer than ordinary launchctl calls and fail
    /// with one explanation, whichever step it was.
    static let launchdTimeout: TimeInterval = 8
    static func require(_ outcome: LaunchdJob.Outcome) throws {
        switch outcome {
        case .ok: return
        case .timedOut: throw AppError(message: "Lid update command timed out. Independent recovery remains installed.")
        case .failed, .error: throw AppError(message: "Lid update command failed. Independent recovery remains installed.")
        }
    }
    static func waitForUnload(now: () -> Double, pause: () -> Void, reap: () -> Void, unloaded: () throws -> Bool) throws {
        let started = now(), deadline = started + 10
        while true {
            let time = now()
            guard time.isFinite, time >= started, time < deadline else {
                throw AppError(message: "The previous lid helper has not stopped. Update aborted; sleep recovery remains active.")
            }
            // The old helper can be waiting for our ownership lock while
            // launchd waits for it to exit. Reap before waiting for bootout.
            reap()
            if try unloaded() { return }
            pause()
        }
    }
    static func checkStart(observation: LidObservation, disabled: Bool, previousToken: String?, status: LidGuardReply?, now: Double) throws -> (Bool, LidCountdown?, Double?) {
        guard observation.closed != nil, observation.power != .unknown else { throw AppError(message: "Could not read lid and power state before updating.") }
        guard !disabled || previousToken != nil else { throw AppError(message: "Another sleep override is active. Perch cannot take ownership of it for an update.") }
        if disabled {
            guard let status, status.token == previousToken, status.status.armed, status.status.error == nil,
                  now >= status.status.updatedAt, now - status.status.updatedAt < 3 else {
                throw AppError(message: "The current lid session could not be captured. Retry the helper update while Perch is connected to it.")
            }
            let countdown = status.status.countdown
            // remaining is rounded up for display; subtract one second so a
            // transfer never extends an existing battery deadline.
            let deadline = countdown?.active == true ? nil : status.status.remaining.map { status.status.updatedAt + Double(max(0, $0 - 1)) }
            guard countdown?.active != true || countdown!.deadline > now,
                  deadline == nil || deadline! > now else { throw AppError(message: "The current lid timer has finished. Reconnect power or open the lid before updating.") }
            return (true, countdown, deadline)
        }
        guard observation.closed == false || observation.power == .external else { throw AppError(message: "Connect power or open the lid before installing lid protection without an active session.") }
        return (false, nil, nil)
    }
    /// Read through the existing helper's user-only authenticated endpoint AFTER
    /// administrator authorization. This child drops privilege and only reads.
    static func snapshotAsUser(owner: uid_t) throws -> Data? {
        guard geteuid() == 0, owner >= 501, let account = getpwuid(owner),
              setgid(account.pointee.pw_gid) == 0, setuid(owner) == 0,
              let requirement = CodeIdentity.designatedRequirement else { throw AppError(message: "Could not read the existing lid session as its owner.") }
        let connection = NSXPCConnection(machServiceName: LidGuardService.name, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: LidGuardProtocol.self)
        connection.resume(); defer { connection.invalidate() }
        let lock = NSLock(); var ended = false; var result: Data?
        let finish: (Data?) -> Void = { data in lock.withLock { result = data; ended = true } }
        if let remote = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil) }) as? LidGuardProtocol { remote.status(finish) }
        let until = Date().addingTimeInterval(2)
        while !lock.withLock({ ended }) && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return lock.withLock { result.flatMap { $0.count <= 4096 ? $0 : nil } }
    }
    static func capture(owner: uid_t) throws -> LidGuardReply? {
        guard owner >= 501 else { throw AppError(message: "Invalid lid-session owner.") }
        let output: Subprocess.Output
        do { output = try Subprocess.run(binary, ["--lid-maintenance-snapshot", String(owner)], timeout: 3, capture: .collect(maximumBytes: 8192)) }
        catch is Subprocess.Timeout { throw AppError(message: "The current lid helper did not respond. Retry the update.") }
        catch is Subprocess.Oversized { return nil }
        guard output.succeeded, let text = output.text, let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return try? JSONDecoder().decode(LidGuardReply.self, from: data)
    }
    static func begin(owner: uid_t, token: String) throws {
        guard geteuid() == 0, Bundle.main.bundleIdentifier != "local.perch.functional-review" else { throw AppError(message: "Administrator authorization is required.") }
        let store = LidSleepOverride.store
        try store.prepareDirectory()
        guard !FileManager.default.fileExists(atPath: path) else { throw AppError(message: "A previous helper update still needs recovery. Retry in a few seconds.") }
        try require(LaunchdJob.system(name).print(timeout: launchdTimeout))
        let snapshot = try capture(owner: owner)
        let fd = try LidOverrideLock.acquire(path: store.lockPath, owner: 0, recover: false, mayStop: { _ in false })
        defer { close(fd) }
        guard UUID(uuidString: token) != nil, !FileManager.default.fileExists(atPath: path) else { throw AppError(message: "Another helper update is already in progress.") }
        let now = LidGuardClock.now, previous = try? store.record().token
        let disabled = try LidSleepOverride.systemDisabled()
        try LidSleepOverride.verify(disabled)
        let captured = try checkStart(observation: MacLidGuardHardware().observe(), disabled: disabled, previousToken: previous, status: snapshot, now: now)
        let value = LidMaintenanceRecord(token: token, previousToken: previous, boot: LidSleepOverride.boot,
            started: now, expires: now + LidMaintenanceRecord.limit, resume: captured.0, countdown: captured.1, batteryDeadline: captured.2)
        // Recovery records both tokens BEFORE either old job is stopped.
        try store.write(value, path: path, durable: true)
        // Explicit launch plus an acknowledgment avoids relying on a filesystem
        // notification: PathState alone can lose its initial change event.
        try require(LaunchdJob.system(name).kickstart(timeout: launchdTimeout))
        let readyBy = LidGuardClock.now + 3
        while record.map({ $0.token == token && guardReady($0) }) != true {
            guard LidGuardClock.now < readyBy else { throw AppError(message: "Independent update recovery did not confirm readiness. Nothing will be replaced.") }
            usleep(25_000)
        }
        let jobs = [LidGuardInstall.recoveryName, LidGuardService.name]
        var unloaders: [Process] = []
        defer { for process in unloaders where process.isRunning { process.terminate() } }
        for job in jobs { unloaders.append(try LaunchdJob.system(job).spawnBootout()) }
        try waitForUnload(now: { LidGuardClock.now }, pause: { usleep(25_000) }, reap: {
            // Only root-owned processes at the exact replaced executable;
            // ProcessTable rechecks PID birth immediately before signalling.
            for process in ProcessTable.snapshot() where process.executable == LidGuardInstall.binary {
                _ = ProcessTable.signal(process, SIGKILL)
            }
        }, unloaded: {
            guard unloaders.allSatisfy({ !$0.isRunning }),
                  !ProcessTable.snapshot().contains(where: { $0.executable == LidGuardInstall.binary }) else { return false }
            // A job that is still loaded, or a launchctl that will not answer,
            // both mean the old helper has not gone yet.
            return !jobs.contains { [.ok, .timedOut].contains(LaunchdJob.system($0).print(timeout: launchdTimeout)) }
        })
        guard value.fresh, record.map(guardReady) == true else { throw AppError(message: "The helper update allowance expired or lost independent recovery.") }
        // Old queued workers still carry the old token and will fail their
        // post-lock token check. Old watchdogs cannot release this new owner.
        if LidGuardOwnership.exists { guard unlink(LidGuardOwnership.path) == 0 else { throw AppError(message: "Could not transfer lid ownership.") } }
        try LidGuardOwnership.claim(value.token)
        try store.write(LidOverrideRecord(token: value.token), path: store.recordPath, durable: true)
        // No hardware write while holding the serialization lock. The caller
        // invokes maintenance-enable after this command exits and releases it.
    }
    static func enable() throws {
        guard let value = record, value.fresh, (try? LidSleepOverride.store.record().token) == value.token else { throw AppError(message: "The helper update allowance is unavailable.") }
        try LidSleepOverride.set(true)
        try LidSleepOverride.verify(true)
        note("Temporary sleep protection started for helper replacement: at most 60 seconds. Existing lid/countdown deadlines remain active.")
    }
    static func editRecord(_ edit: (inout LidMaintenanceRecord?) throws -> Void) throws {
        let fd = try LidOverrideLock.acquire(path: path + ".lock", owner: 0, recover: false, mayStop: { _ in false })
        defer { close(fd) }
        var current = record
        let before = current
        try edit(&current)
        if let current { if current != before { try LidSleepOverride.store.write(current, path: path, durable: true) } }
        else { guard unlink(path) == 0 || errno == ENOENT else { throw AppError(message: "Could not finish helper-update recovery.") } }
    }
    static func removeRecord() throws { try editRecord { $0 = nil } }
    static func completeAdoption(token: String) throws -> LidMaintenanceRecord {
        var captured: LidMaintenanceRecord?
        try editRecord { current in
            guard let value = current, value.token == token, value.fresh else { throw AppError(message: "The helper update expired before the session resumed.") }
            captured = value; current = nil
        }
        return captured!
    }
    /// New helper consumes this only after its independent watchdog is ready.
    /// The same token and original deadlines remain authoritative.
    static func adoption() -> LidMaintenanceRecord? {
        guard let value = record, value.fresh, value.resume, guardReady(value),
              (try? LidSleepOverride.store.record().token) == value.token else { return nil }
        return value
    }
    @discardableResult static func finish(success: Bool, token: String) throws -> Bool {
        guard let value = record, value.token == token else { return false }
        if success && value.resume && value.fresh { return true } // App claims it; otherwise guard expires.
        try recover(force: true)
        return false
    }
    static func recover(force: Bool = false) throws {
        guard geteuid() == 0 else { return }
        guard let value = record else {
            if FileManager.default.fileExists(atPath: path) {
                _ = try LidSleepOverride.recover(force: false)
                if !LidSleepOverride.owned { try removeRecord() }
            }
            return
        }
        var expired = force || !value.fresh
        let observation = MacLidGuardHardware().observe()
        if !expired {
            if observedPolicy?.0 != value.token {
                var policy = LidGuardPolicy()
                policy.restoreMaintenance(deadline: value.batteryDeadline, countdown: value.countdown)
                observedPolicy = (value.token, policy)
            }
            let decision = observedPolicy!.1.step(observation, now: LidGuardClock.now, authorized: true)
            expired = !decision.preventLidSleep
            if expired { note("Watchdog recovery: " + decision.detail) }
            if !expired {
                let policy = observedPolicy!.1
                try editRecord { current in
                    guard var latest = current, latest.token == value.token, latest.fresh else { return }
                    if latest.guardUpdatedAt.map({ LidGuardClock.now - $0 >= 1 }) ?? true {
                        latest.guardPID = getpid(); latest.guardBirth = ProcessCPUReader.birth(getpid()); latest.guardUpdatedAt = LidGuardClock.now
                    }
                    latest.countdown = policy.countdown
                    latest.batteryDeadline = policy.deadline
                    current = latest
                }
                return
            }
        }
        let token = try? LidSleepOverride.store.record().token
        guard token == nil || token == value.token || token == value.previousToken else {
            try removeRecord(); return // A newer independent session owns the bit.
        }
        // Invalidate but retain the record until cleanup succeeds, including
        // failed pmset readback. PathState keeps independent recovery running.
        var revoked = false
        try editRecord { current in
            guard var latest = current, latest.token == value.token else { return }
            latest.expires = 0; current = latest; revoked = true
        }
        guard revoked else { return }
        _ = try LidSleepOverride.recover(force: true)
        try LidGuardOwnership.release(LidGuardEnforcer(MacLidGuardHardware()), sleep: false, now: LidGuardClock.now)
        if observation.closed != false && observation.power != .external { try MacLidGuardHardware().requestSleep() }
        try removeRecord()
        note(force ? "Helper update allowance ended. Normal system sleep restored." : "Helper update timed out or was interrupted. Independent recovery restored normal system sleep.")
    }
}
