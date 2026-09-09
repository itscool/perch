import Foundation
import Darwin
import IOKit

/// A journal is written before a persistent setting can change. Only an override
/// that started from normal system sleep is owned, so its recovery value is off.
struct LidOverrideRecord: Codable, Equatable {
    var version = 1
    let token: String
    var previousDisabled = false
    var valid: Bool { version == 1 && UUID(uuidString: token) != nil && !previousDisabled }
}

struct LidOverrideRecoveryLease: Codable {
    let token: String
    let boot: String
    let expires: Double
    let pid: Int32
    let birth: UInt64
    func fresh(token: String, boot: String, now: Double, birth: UInt64?) -> Bool {
        self.token == token && self.boot == boot && self.birth == birth &&
        expires.isFinite && now.isFinite && now >= 0 && now < expires && expires <= now + 6
    }
}

struct LidOverrideStore {
    let directory: URL
    let lockPath: String
    let leasePath: String
    var owner: uid_t = 0
    static let live = Self(directory: URL(fileURLWithPath: "/var/db/local.scott.perch.lid-override"),
                           lockPath: "/var/run/local.scott.perch.lid-override.lock",
                           leasePath: "/var/run/local.scott.perch.lid-override.lease")
    var recordPath: String { directory.appendingPathComponent("owned.json").path }
    func secureFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_uid == owner && info.st_mode & S_IFMT == S_IFREG &&
            info.st_mode & 0o022 == 0 && info.st_nlink == 1
    }
    var ownsOverride: Bool { secureDirectory && secureFile(recordPath) }
    private var secureDirectory: Bool {
        var info = stat()
        return lstat(directory.path, &info) == 0 && info.st_uid == owner &&
            info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o022 == 0
    }
    func prepareDirectory() throws {
        guard mkdir(directory.path, 0o755) == 0 || errno == EEXIST, secureDirectory else {
            throw AppError(message: "The lid recovery directory is unavailable or unsafe.")
        }
    }
    func read<T: Decodable>(_ type: T.Type, path: String) throws -> T {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw AppError(message: "The lid recovery record could not be opened.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o022 == 0, info.st_nlink == 1, info.st_size > 0, info.st_size <= 2048 else {
            throw AppError(message: "The lid recovery record is invalid.")
        }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count == bytes.count else { throw AppError(message: "The lid recovery record is incomplete.") }
        return try JSONDecoder().decode(type, from: Data(bytes))
    }
    func record() throws -> LidOverrideRecord {
        guard secureDirectory else { throw AppError(message: "The lid recovery directory is unsafe.") }
        let value = try read(LidOverrideRecord.self, path: recordPath)
        guard value.valid else { throw AppError(message: "Lid recovery needs attention: the ownership record is unrecognized.") }
        return value
    }
    func write<T: Encodable>(_ value: T, path: String, durable: Bool) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 2048 else { throw AppError(message: "The lid recovery record is too large.") }
        let temporary = path + "." + UUID().uuidString
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AppError(message: "Could not write the lid recovery record.") }
        defer { close(fd); unlink(temporary) }
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count,
              !durable || fsync(fd) == 0, rename(temporary, path) == 0 else {
            throw AppError(message: "Could not save the lid recovery record.")
        }
        if durable { try syncDirectory() }
    }
    private func syncDirectory() throws {
        let fd = open(directory.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw AppError(message: "Could not synchronize lid recovery.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw AppError(message: "Could not synchronize lid recovery.") }
    }
    func reserve(token: String, disabled: Bool) throws {
        guard UUID(uuidString: token) != nil else { throw AppError(message: "Invalid lid session.") }
        try prepareDirectory()
        if ownsOverride {
            guard try record().token == token else { throw AppError(message: "An earlier lid override still needs recovery.") }
            return
        }
        // Never take ownership of another app's or the user's existing override.
        guard !FileManager.default.fileExists(atPath: recordPath), !disabled else {
            throw AppError(message: "A system sleep override already exists. Review sleep reset before enabling lid protection.")
        }
        try write(LidOverrideRecord(token: token), path: recordPath, durable: true)
    }
    func finish(disabled: Bool) throws {
        guard !disabled else { throw AppError(message: "macOS has not confirmed removal of the sleep override. Recovery will retry.") }
        guard ownsOverride else { return }
        _ = try record()
        guard unlink(recordPath) == 0 else { throw AppError(message: "Could not finish lid recovery. Recovery will retry.") }
        try syncDirectory()
    }
}

/// A process-owned POSIX lock survives exec into pmset. Cleanup can identify and
/// stop the exact lock holder before restoring sleep, preventing a delayed enable
/// from writing after cleanup. Main helper processes never hold this lock.
enum LidOverrideLock {
    static func acquire(path: String, owner: uid_t, recover: Bool,
                        mayStop: (Int32) -> Bool, now: () -> Double = { LidGuardClock.now }) throws -> Int32 {
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw AppError(message: "Could not open the lid control lock.") }
        var retained = false
        defer { if !retained { close(fd) } }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o022 == 0, info.st_nlink == 1 else { throw AppError(message: "Unsafe lid control lock.") }
        let end = now() + 1
        repeat {
            var request = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
            if fcntl(fd, F_SETLK, &request) == 0 { retained = true; return fd }
            guard errno == EAGAIN || errno == EACCES else { throw AppError(message: "Could not lock lid control.") }
            if recover {
                guard fcntl(fd, F_GETLK, &request) == 0 else { throw AppError(message: "Could not identify the pending lid command.") }
                if request.l_type != F_UNLCK, request.l_pid > 1 {
                    guard mayStop(request.l_pid) else { throw AppError(message: "The pending lid command could not be safely stopped.") }
                    // Recheck the lock's owner after identity validation.
                    let pid = request.l_pid
                    request.l_type = Int16(F_WRLCK)
                    guard fcntl(fd, F_GETLK, &request) == 0 else { throw AppError(message: "Could not recheck the lid command.") }
                    if request.l_pid == pid && request.l_type != F_UNLCK && mayStop(pid) { _ = kill(pid, SIGKILL) }
                }
            }
            usleep(10_000)
        } while now() < end
        throw AppError(message: "The previous lid command has not stopped. Recovery will retry.")
    }
}

enum LidSleepOverride {
    static let store = LidOverrideStore.live
    static var owned: Bool { store.ownsOverride }
    static var boot: String {
        var value = timeval(), size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return "" }
        return "\(value.tv_sec):\(value.tv_usec)"
    }
    static func systemDisabled() throws -> Bool {
        typealias Copy = @convention(c) () -> Unmanaged<CFDictionary>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            throw AppError(message: "macOS power settings are unavailable.")
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOPMCopySystemPowerSettings"),
              let settings = unsafeBitCast(symbol, to: Copy.self)()?.takeRetainedValue() as? [String: Any] else {
            throw AppError(message: "Could not read the system sleep setting.")
        }
        guard let value = settings["SleepDisabled"] else { return false }
        guard let number = value as? NSNumber, number == 0 || number == 1 else {
            throw AppError(message: "Unrecognized system sleep setting.")
        }
        return number.boolValue
    }
    static func liveDisabled() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw AppError(message: "The live system sleep state is unavailable.") }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else {
            // Absence is not proof that a persistent setting has reached powerd.
            throw AppError(message: "macOS did not provide the live sleep override state.")
        }
        return value
    }
    static func verify(_ disabled: Bool) throws {
        guard try systemDisabled() == disabled, try liveDisabled() == disabled else {
            throw AppError(message: "macOS has not confirmed the sleep override \(disabled ? "is active" : "was removed").")
        }
    }
    static func pulse(token: String, until: Double) throws {
        guard geteuid() == 0, UUID(uuidString: token) != nil, !boot.isEmpty,
              let birth = ProcessCPUReader.birth(getpid()) else { throw AppError(message: "Could not establish independent lid recovery.") }
        try store.write(LidOverrideRecoveryLease(token: token, boot: boot, expires: min(until, LidGuardClock.now + 3),
                                                 pid: getpid(), birth: birth), path: store.leasePath, durable: false)
    }
    static func worker(_ mode: String, token: String, deadline: Double) throws {
        guard geteuid() == 0, ["on", "off", "finish"].contains(mode), deadline.isFinite,
              deadline > LidGuardClock.now, deadline <= LidGuardClock.now + 4 else { throw AppError(message: "Invalid lid control request.") }
        let fd = try LidOverrideLock.acquire(path: store.lockPath, owner: 0, recover: mode != "on", mayStop: { pid in
            guard (try? store.record().token) == token,
                  pid != getpid(), let birth = ProcessCPUReader.birth(pid) else { return false }
            var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return false }
            let path = String(cString: bytes)
            return (path == Bundle.main.executablePath || path == LidGuardInstall.binary || path == "/usr/bin/pmset") && ProcessCPUReader.birth(pid) == birth
        })
        defer { close(fd) }
        if mode == "finish" {
            if store.ownsOverride {
                guard try store.record().token == token else { throw AppError(message: "A newer lid session owns recovery.") }
            }
            try verify(false); try store.finish(disabled: false); return
        }
        if mode == "on" {
            guard LidGuardOwnership.token == token, LidGuardClock.now < deadline else { throw AppError(message: "The lid session ended before its command could run.") }
            try store.reserve(token: token, disabled: systemDisabled())
        } else {
            guard store.ownsOverride else { return }
            let recorded = try store.record()
            guard token == recorded.token else { throw AppError(message: "Lid recovery belongs to a different session.") }
            // Revoke before allowing any waiting enable command to proceed.
            if LidGuardOwnership.token == token { _ = unlink(LidGuardOwnership.path) }
        }
        guard LidGuardClock.now < deadline else { throw AppError(message: "The lid command expired before applying.") }
        // Exec keeps the lock and PID. Cleanup never has to guess which child
        // might still write a persistent setting after its parent dies.
        _ = fcntl(fd, F_SETFD, 0)
        let strings = ["/usr/bin/pmset", "-a", "disablesleep", mode == "on" ? "1" : "0"]
        let arguments = strings.map { strdup($0) }
        defer { arguments.forEach { free($0) } }
        var pointers = arguments + [nil]
        execv(strings[0], &pointers)
        throw AppError(message: "Could not execute macOS power control.")
    }
    private static func run(_ mode: String, token: String) throws {
        guard geteuid() == 0, Bundle.main.bundleIdentifier != "local.perch.functional-review", let binary = Bundle.main.executableURL else {
            throw AppError(message: "The authorized lid helper is required.")
        }
        let task = Process(), ended = DispatchSemaphore(value: 0)
        task.executableURL = binary
        task.arguments = ["--lid-override-worker", mode, token, String(LidGuardClock.now + 3)]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in ended.signal() }
        try task.run()
        guard ended.wait(timeout: .now() + 2) == .success else {
            if task.isRunning { _ = kill(task.processIdentifier, SIGKILL) }
            _ = ended.wait(timeout: .now() + 0.5)
            throw AppError(message: "macOS power control timed out. The recovery record is retained for retry.")
        }
        guard task.terminationStatus == 0 else { throw AppError(message: "macOS power control failed. Review Lid activity; recovery will retry if needed.") }
    }
    static func set(_ enabled: Bool) throws {
        if enabled {
            try requireRecoveryJob()
            guard let token = LidGuardOwnership.token else { throw AppError(message: "The lid watchdog ended this session.") }
            try run("on", token: token)
            try waitForReadback(true)
        } else if owned {
            let record = try store.record()
            try run("off", token: record.token)
            try waitForReadback(false)
            try run("finish", token: record.token)
        }
    }
    private static func requireRecoveryJob() throws {
        let path = "/Library/LaunchDaemons/\(LidGuardInstall.recoveryName).plist"
        guard store.secureFile(path), let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 8192,
              let job = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              job["ProgramArguments"] as? [String] == [LidGuardInstall.binary, "--lid-recover"],
              job["RunAtLoad"] as? Bool == true, job["StartInterval"] as? Int == 5,
              job["ThrottleInterval"] as? Int == 1 else {
            throw AppError(message: "Independent sleep recovery is not installed. Repair lid protection before enabling it.")
        }
        let task = Process(), ended = DispatchSemaphore(value: 0)
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/" + LidGuardInstall.recoveryName]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in ended.signal() }; try task.run()
        guard ended.wait(timeout: .now() + 0.5) == .success else {
            if task.isRunning { _ = kill(task.processIdentifier, SIGKILL) }
            throw AppError(message: "Could not confirm independent sleep recovery is loaded.")
        }
        guard task.terminationStatus == 0 else { throw AppError(message: "Independent sleep recovery is not loaded. Repair lid protection before enabling it.") }
    }
    private static func waitForReadback(_ disabled: Bool) throws {
        let end = LidGuardClock.now + 0.75
        repeat {
            if (try? verify(disabled)) != nil { return }
            usleep(25_000)
        } while LidGuardClock.now < end
        try verify(disabled)
    }
    /// Separate launchd recovery also runs at boot, when /var/run was cleared.
    /// It never enables protection and does not rely on the menu or supervisor.
    static func recover(force: Bool) throws -> Bool {
        guard owned else { return false }
        let record = try store.record()
        if !force, LidGuardOwnership.token == record.token,
           let lease = try? store.read(LidOverrideRecoveryLease.self, path: store.leasePath),
           lease.fresh(token: record.token, boot: boot, now: LidGuardClock.now, birth: ProcessCPUReader.birth(lease.pid)) { return false }
        try set(false)
        return true
    }
}
