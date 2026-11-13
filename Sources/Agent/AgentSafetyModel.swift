import Foundation
import Darwin

/// Perch's settings shared with its background helpers: staying awake, keypad
/// navigation, and trackpad, wheel and modifier preferences. The file keeps its
/// historical name and location so existing settings carry over.
///
/// It also held the Agent Kill Switch's targets, shortcut and privacy-reset
/// choices until that feature was removed on November 12, 2026. Older files
/// still decode: the unknown keys are ignored.
struct SafetyConfiguration: Codable, Equatable {
    var keypadNavigation: Bool? = nil
    var navigation: NavigationPreferences?
    var navigationProfiles: [NavigationKeyboardProfile]?
    var keepAwake = false
    var reverseTrackpad = false
    var reverseWheel = false
    var swapModifiers = false
    static func load() -> Self {
        guard FileManager.default.fileExists(atPath: SafetyFiles.config.path) else { return Self() }
        return (try? SafetyFiles.read(Self.self, from: SafetyFiles.config)) ?? Self()
    }
    func save() throws { try SafetyFiles.write(self, to: SafetyFiles.config) }
}

struct ProcessIdentity: Codable, Hashable {
    let pid: Int32
    let uid: UInt32
    let seconds: UInt64
    let microseconds: UInt64
}
/// One running process, identified so a reused PID is never mistaken for it.
struct AgentProcess: Codable, Equatable {
    let identity: ProcessIdentity
    let parent: Int32
    let executable: String
    var name: String { String(executable.split(separator: "/").last ?? "") }
}

struct GuardianMaintenanceCounts: Codable {
    var configurationReads: UInt64 = 0
    var requestScans: UInt64 = 0
    var checkpointSorts: UInt64 = 0
    var checkpointWrites: UInt64 = 0
}

/// What the Agent Kill Switch left on disk. Read once by the helper so that
/// launch jobs it switched off are switched back on before the file goes; the
/// feature itself is gone.
struct SafetyState: Codable, Equatable {
    var locked = false
    var disabledJobs: [String] = []
}
struct SafetyStatus: Codable {
    var timestamp = Date()
    var watcherPID: Int32 = getpid()
    var helperBuild: String = HelperBuild.current
    var statusProtocol: Int = HelperBuild.protocolVersion
    var desktopRecoverySupported: Bool? = true
    var inputTrusted: Bool?
    var inputActive: Bool
    var keepAwakeActive: Bool
    var message: String
    var error: String?
    var maintenance: GuardianMaintenanceCounts? = nil
    var compatible: Bool { HelperBuild.compatible(build: helperBuild, protocolVersion: statusProtocol) }
    var fresh: Bool { compatible && Date().timeIntervalSince(timestamp) < 4 }
}
struct SafetyRequest: Codable {
    let id: UUID
    var timestamp = Date()
    let action: String
}

enum SafetyFiles {
    static let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Safety", isDirectory: true)
    static let config: URL = base.appendingPathComponent("config.json")
    static let state: URL = base.appendingPathComponent("state.json")
    static let requests: URL = base.appendingPathComponent("requests", isDirectory: true)
    static let helperApp: URL = base.appendingPathComponent("Perch Helper.app")
    static let binary: URL = helperApp.appendingPathComponent("Contents/MacOS/Perch")
    /// Files only the Agent Kill Switch wrote: its event history, report,
    /// installed agent catalog and shortcut test lease. Removed once the
    /// helper has put back anything the feature switched off.
    static let retired: [URL] = ["events.jsonl", "events-previous.jsonl", "Safety report.txt", "agents.json", "shortcut-test-lease.json"]
        .map { base.appendingPathComponent($0) }
    static func prepare() throws {
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
    }
    static func write<T: Encodable>(_ value: T, to url: URL, durable: Bool = false) throws {
        try prepare()
        try SecureFile.writeAtomically(value, to: url, durable: durable)
    }
    /// Recovery state must survive a crash: fsync the file and its directory.
    static func writeRecoveryState(_ value: SafetyState) throws {
        try write(value, to: state, durable: true)
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONFileCache.read(type, from: url)
    }
    static func send(_ action: String) throws {
        let request = SafetyRequest(id: UUID(), action: action)
        try write(request, to: requests.appendingPathComponent(request.id.uuidString + ".json"))
    }
}

enum ProcessTable {
    static var bootTime: Int64 {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return Int64(boot.tv_sec)
    }
    /// Signal a process only if it is still the one identified, so a reused PID
    /// is never signalled by mistake.
    static func signal(_ process: AgentProcess, _ signal: Int32) -> String {
        guard process.identity.pid != getpid(), process.identity.uid == getuid() else { return "refused: protected process or different user" }
        guard let live = inspect(process.identity.pid) else { return "already exited" }
        guard live.identity == process.identity else { return "skipped: PID reused" }
        if kill(process.identity.pid, signal) == 0 { return "sent" }
        return errno == ESRCH ? "already exited" : "failed: \(String(cString: strerror(errno)))"
    }
    static func inspect(_ pid: Int32) -> AgentProcess? {
        var info = proc_bsdinfo()
        guard pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), info.pbi_status != 5 else { return nil }
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 4 * Int(MAXPATHLEN)) { path in
            guard proc_pidpath(pid, path.baseAddress, UInt32(path.count)) > 0 else { return nil }
            return AgentProcess(identity: .init(pid: pid, uid: info.pbi_uid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec), parent: Int32(info.pbi_ppid), executable: String(cString: path.baseAddress!))
        }
    }
    static func snapshot() -> [AgentProcess] {
        let count = max(1024, Int(proc_listallpids(nil, 0)) + 256)
        var pids = [Int32](repeating: 0, count: count)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return pids.prefix(max(0, Int(actual))).compactMap(inspect)
    }
}
