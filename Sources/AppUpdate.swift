import AppKit
import Security

struct AppUpdateCandidate: Codable, Equatable {
    let directory: URL
    let target: URL
    let identity: String
    let oldIdentity: String
    let build: Int
    // nil decodes legacy build-68/69 update records. A plain restart never moves a bundle.
    var restartOnly: Bool? = nil
    var staged: URL { restartOnly == true ? target : directory.appendingPathComponent("Perch.app") }
    var record: URL { directory.appendingPathComponent("restart.json") }
}
struct AppUpdateRecord: Codable {
    let candidate: AppUpdateCandidate
    let oldPID: Int32
    let oldBirth: UInt64
    let ticket: LidRestartTicket?
    let expires: Double
    let attempt: String
}
struct AppUpdateReceipt: Codable { let identity: String; let message: String; let resumed: Bool }

/// Verified restart worker, retaining the legacy local-update transaction only
/// for upgrades from builds 68–69. Plain restarts never install or copy an app.
final class AppUpdate {
    static let shared = AppUpdate()
    static var base: URL { SafetyFiles.base.appendingPathComponent("Updates", isDirectory: true) }
    static let noticeKey = "perchRestartNotice"
    static func sameLocation(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.path == right.standardizedFileURL.path
    }
    private(set) var candidate: AppUpdateCandidate?
    private(set) var busy = false
    private(set) var message = UserDefaults.standard.string(forKey: noticeKey) ?? ""
    static func identity(_ app: URL, requirement: String) throws -> String {
        var code: SecStaticCode?, rule: SecRequirement?, info: CFDictionary?
        guard app.pathExtension == "app", sameLocation(app, app.resolvingSymlinksInPath()),
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), rule) == errSecSuccess,
              SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let bytes = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data, bytes.count == 20 else {
            throw AppError(message: "Perch could not verify this app’s signature. Restore an intact copy signed by the same publisher.")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func appInfo(_ app: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), data.count < 65_536 else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }
    static func validateTarget(_ app: URL) throws {
        let fm = FileManager.default, parent = app.deletingLastPathComponent()
        let attributes = try fm.attributesOfItem(atPath: app.path)
        guard app.pathExtension == "app", sameLocation(app, app.resolvingSymlinksInPath()),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              attributes[.ownerAccountID] as? UInt32 == getuid(), fm.isWritableFile(atPath: parent.path),
              fm.isWritableFile(atPath: app.path), !app.path.hasPrefix("/System/"), !app.path.hasPrefix("/Volumes/") else {
            throw AppError(message: "This copy cannot update in place. Move Perch to a writable Applications folder and open that copy first.")
        }
    }
    func restartCurrentApp() {
        guard !busy, !PerchUpdater.shared.busy, !SettingsWindow.shared.testing, !LidHelperUpdate.shared.busy,
              !LidGuardClient.shared.changing else { return }
        do {
            let target = Bundle.main.bundleURL
            guard let requirement = HelperStatusIPC.requirement else { throw AppError(message: "This Perch copy has no verifiable signing identity.") }
            let hash = try Self.identity(target, requirement: requirement)
            try FileManager.default.createDirectory(at: Self.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard Self.sameLocation(Self.base, Self.base.resolvingSymlinksInPath()) else { throw AppError(message: "The restart folder must not be a symbolic link.") }
            let directory = Self.base.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            candidate = AppUpdateCandidate(directory: directory, target: target, identity: hash, oldIdentity: hash,
                build: Int(Self.appInfo(target)["CFBundleVersion"] as? String ?? "0") ?? 0, restartOnly: true)
            restart()
        } catch { message = "Perch is still running. " + error.localizedDescription }
    }
    static func canRestart(active: Bool, lidOpen: Bool, recordedSession: Bool, overrideOff: Bool) -> Bool {
        active || lidOpen || (!recordedSession && overrideOff)
    }
    static func stage(_ source: URL, target: URL) throws -> AppUpdateCandidate {
        guard let requirement = HelperStatusIPC.requirement else { throw AppError(message: "This Perch copy has no verifiable signing identity.") }
        try validateTarget(target)
        let oldIdentity = try identity(target, requirement: requirement)
        let current = appInfo(target), proposed = appInfo(source)
        guard proposed["CFBundleIdentifier"] as? String == current["CFBundleIdentifier"] as? String,
              let build = Int(proposed["CFBundleVersion"] as? String ?? ""), build > (Int(current["CFBundleVersion"] as? String ?? "0") ?? 0),
              proposed["PerchLidProtocolVersion"] as? Int == LidGuardCompatibility.protocolVersion else {
            throw AppError(message: "Choose a newer Perch app that supports this update handoff.")
        }
        let hash = try identity(source, requirement: requirement)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sameLocation(base, base.resolvingSymlinksInPath()) else { throw AppError(message: "The update staging folder must not be a symbolic link.") }
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let candidate = AppUpdateCandidate(directory: directory, target: target, identity: hash, oldIdentity: oldIdentity, build: build)
        do {
            try FileManager.default.copyItem(at: source, to: candidate.staged)
            guard try identity(candidate.staged, requirement: requirement) == hash else { throw AppError(message: "The update changed during preparation. Choose it again.") }
            return candidate
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func restart() {
        guard !busy, !SettingsWindow.shared.testing, let candidate else { return }
        do {
            if candidate.restartOnly != true { try Self.validateTarget(candidate.target) }
            guard let requirement = HelperStatusIPC.requirement,
                  try Self.identity(candidate.staged, requirement: requirement) == candidate.identity,
                  try Self.identity(candidate.target, requirement: requirement) == candidate.oldIdentity else {
                throw AppError(message: "The app changed after preparation. Try restarting again.")
            }
            let active = LidGuardClient.shared.active
            // Closed-lid restart is safe with a confirmed owned handoff or
            // fresh native evidence that no override/session needs preserving.
            let lidOpen = MacLidGuardHardware().observe().closed == false
            let overrideOff = (try? LidSleepOverride.verify(false)) != nil
            guard Self.canRestart(active: active, lidOpen: lidOpen,
                recordedSession: LidGuardOwnership.recorded, overrideOff: candidate.restartOnly == true && overrideOff) else {
                throw AppError(message: "The lid session cannot be handed over. Open the lid before restarting, or review Keep awake.")
            }
            guard let birth = ProcessCPUReader.birth(getpid()) else { throw AppError(message: "Could not identify this app process. Try restarting again.") }
            busy = true; message = "Preparing to restart…"
            let launch: (LidRestartTicket?) -> Void = { ticket in
                do {
                    let record = AppUpdateRecord(candidate: candidate, oldPID: getpid(), oldBirth: birth, ticket: ticket, expires: LidGuardClock.now + 30, attempt: UUID().uuidString)
                    try JSONEncoder().encode(record).write(to: candidate.record, options: .atomic)
                    let worker = Process(); worker.executableURL = candidate.staged.appendingPathComponent("Contents/MacOS/Perch")
                    worker.arguments = ["--apply-update", candidate.record.path]
                    worker.standardInput = FileHandle.nullDevice; worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
                    try worker.run()
                    // A successful spawn is not proof that the worker loaded
                    // or verified its inputs. Keep the old app until its ack.
                    DispatchQueue.global(qos: .userInitiated).async {
                        let deadline = LidGuardClock.now + 3
                        var ready = false
                        while worker.isRunning && LidGuardClock.now < deadline {
                            ready = (try? String(contentsOf: candidate.directory.appendingPathComponent("ready-" + record.attempt), encoding: .utf8)) == candidate.identity
                            if ready { break }
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                        DispatchQueue.main.async {
                            if ready { NSApp.terminate(nil) }
                            else {
                                try? Data().write(to: candidate.directory.appendingPathComponent("cancel-" + record.attempt))
                                if let ticket { LidGuardClient.shared.cancelRestart(ticket.id) }
                                self.candidate = nil; self.busy = false
                                self.message = "Restart did not confirm readiness. Perch is still running. Try Restart Perch again."
                            }
                        }
                    }
                } catch {
                    if let ticket { LidGuardClient.shared.cancelRestart(ticket.id) }
                    self.busy = false; self.message = "Perch is still running. " + error.localizedDescription
                }
            }
            if active {
                LidGuardClient.shared.prepareForRestart(identity: candidate.identity) { result in
                    switch result {
                    case .success(let ticket): launch(ticket)
                    case .failure(let error): self.busy = false; self.message = error.localizedDescription
                    }
                }
            } else { launch(nil) }
        } catch { message = error.localizedDescription }
    }
    static func readRecord(_ path: String) throws -> AppUpdateRecord {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.lastPathComponent == "restart.json", sameLocation(url.deletingLastPathComponent().deletingLastPathComponent(), base),
              UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) != nil,
              sameLocation(url, url.resolvingSymlinksInPath()) else { throw AppError(message: "Invalid update record location.") }
        // Read through one bounded no-follow descriptor. Foundation's broad
        // attributes query also reads extended attributes that this protocol
        // neither needs nor should put on the restart's critical path.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw AppError(message: "The update record could not be opened.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size > 0, info.st_size < 16_384 else { throw AppError(message: "Invalid update record.") }
        var bytes = [UInt8](repeating: 0, count: 16_384), count = 0
        while count < bytes.count {
            let size = bytes.withUnsafeMutableBytes { buffer in Darwin.read(fd, buffer.baseAddress!.advanced(by: count), buffer.count-count) }
            if size == 0 { break }
            if size < 0 { if errno == EINTR { continue }; throw AppError(message: "The update record could not be read.") }
            count += size
        }
        guard count == Int(info.st_size) else { throw AppError(message: "The update record changed while reading it.") }
        let record = try JSONDecoder().decode(AppUpdateRecord.self, from: Data(bytes.prefix(count)))
        guard sameLocation(record.candidate.record, url) else { throw AppError(message: "The update record does not match its staging directory.") }
        guard record.oldPID > 1, UUID(uuidString: record.attempt) != nil else { throw AppError(message: "The update process identity is invalid.") }
        guard record.expires.isFinite, record.expires > LidGuardClock.now,
              record.expires <= LidGuardClock.now + 31,
              record.ticket == nil || (record.ticket!.targetIdentity == record.candidate.identity && record.ticket!.deadline.isFinite && record.ticket!.deadline <= LidGuardClock.now + 60) else {
            throw AppError(message: "The prepared restart expired. Open Perch and try restarting again.")
        }
        return record
    }
    /// Called only by the staged user-owned worker. File replacement rolls back
    /// if moving the new bundle fails; a launch/claim failure retains the backup
    /// and reports failure without granting more lid time or enabling a session.
    static func runWorker(_ path: String) throws {
        guard !SettingsWindow.shared.testing, getuid() >= 501 else { throw AppError(message: "Update worker unavailable.") }
        let record = try readRecord(path), c = record.candidate
        guard LidGuardIdentity.current == c.identity, sameLocation(Bundle.main.bundleURL, c.staged),
              let requirement = HelperStatusIPC.requirement else { throw AppError(message: "The prepared update identity changed.") }
        guard try identity(c.staged, requirement: requirement) == c.identity,
              try identity(c.target, requirement: requirement) == c.oldIdentity else { throw AppError(message: "The prepared app changed before worker startup.") }
        try c.identity.write(to: c.directory.appendingPathComponent("ready-" + record.attempt), atomically: true, encoding: .utf8)
        let cancelled = c.directory.appendingPathComponent("cancel-" + record.attempt)
        let deadline = min(record.expires, LidGuardClock.now + 20)
        while ProcessCPUReader.birth(record.oldPID) == record.oldBirth && LidGuardClock.now < deadline {
            guard !FileManager.default.fileExists(atPath: cancelled.path) else { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !FileManager.default.fileExists(atPath: cancelled.path) else { return }
        guard ProcessCPUReader.birth(record.oldPID) != record.oldBirth else { throw AppError(message: "Perch did not exit. The restart was canceled.") }
        var finished = false
        var launched: Process?
        defer {
            if !finished, launched?.isRunning != true, let hash = try? identity(c.target, requirement: requirement), hash == c.oldIdentity || hash == c.identity {
                let recovery = Process(); recovery.executableURL = c.target.appendingPathComponent("Contents/MacOS/Perch")
                recovery.arguments = ["--show-updates"]
                try? recovery.run()
            }
        }
        guard try identity(c.staged, requirement: requirement) == c.identity,
              try identity(c.target, requirement: requirement) == c.oldIdentity else { throw AppError(message: "The app changed before restart.") }
        var backup: URL?
        if c.restartOnly != true {
            try validateTarget(c.target)
            let saved = c.target.deletingLastPathComponent().appendingPathComponent(".Perch-update-backup-" + c.directory.lastPathComponent + ".app")
            try replace(staged: c.staged, target: c.target, backup: saved)
            backup = saved
        }
        let resultPath = c.directory.appendingPathComponent("result.json")
        UserDefaults.standard.set("Checking restart completion…", forKey: noticeKey)
        // Launch the exact verified executable and retain its process handle.
        // LaunchServices request acceptance does not itself identify or confirm
        // the required fresh process.
        let app = Process(); app.executableURL = c.target.appendingPathComponent("Contents/MacOS/Perch")
        app.arguments = ["--complete-update", path]
        try app.run(); launched = app
        let claimDeadline = min(record.ticket?.deadline ?? record.expires, LidGuardClock.now + 15)
        while LidGuardClock.now < claimDeadline {
            if let data = try? Data(contentsOf: resultPath), data.count < 8192,
               let result = try? JSONDecoder().decode(AppUpdateReceipt.self, from: data), result.identity == c.identity {
                if result.resumed, let backup { try? FileManager.default.removeItem(at: backup) }
                finished = true
                return
            }
            guard app.isRunning else { throw AppError(message: "Perch exited before confirming startup. Try opening Perch again.") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AppError(message: "Restart completion was not confirmed. Open Perch and review Keep awake.")
    }
    static func replace(staged: URL, target: URL, backup: URL, move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        try move(target, backup)
        do { try move(staged, target) }
        catch { try move(backup, target); throw error }
    }
    static func completeLaunch(completion: @escaping () -> Void) {
        guard !SettingsWindow.shared.testing, let i = CommandLine.arguments.firstIndex(of: "--complete-update"), CommandLine.arguments.count == i + 2 else { completion(); return }
        do {
            let record = try readRecord(CommandLine.arguments[i+1]), c = record.candidate
            guard sameLocation(Bundle.main.bundleURL, c.target), LidGuardIdentity.current == c.identity else { throw AppError(message: "Restart identity did not match the prepared update.") }
            let complete: (Result<Void, Error>) -> Void = { result in
                defer { completion() }
                let success: Bool, message: String
                switch result {
                case .success:
                    success = true
                    let outcome = c.restartOnly == true ? "Perch restarted." : "Updated to \(PerchVersion.current)."
                    message = outcome + (record.ticket == nil ? " Your saved choices were kept." : " The lid session resumed with its existing battery deadline. Continued sleep prevention remains unverified.")
                case .failure(let error): success = false; message = "Perch opened, but the lid session was not resumed. " + error.localizedDescription
                }
                var visibleMessage = message
                do { try JSONEncoder().encode(AppUpdateReceipt(identity: c.identity, message: message, resumed: success)).write(to: c.directory.appendingPathComponent("result.json"), options: .atomic) }
                catch { visibleMessage += " Restart completion could not be recorded. Review Keep awake." }
                UserDefaults.standard.set(visibleMessage, forKey: noticeKey); shared.message = visibleMessage
            }
            if let ticket = record.ticket { LidGuardClient.shared.resumeAfterRestart(ticket.id, completion: complete) }
            else { complete(.success(())) }
        } catch {
            let message = "Restart was not confirmed. " + error.localizedDescription
            UserDefaults.standard.set(message, forKey: noticeKey); shared.message = message
            completion()
        }
    }
}
