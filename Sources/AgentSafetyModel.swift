import Foundation
import Darwin

struct AgentTarget: Codable, Equatable {
    var id: String
    var name: String
    var kind: String // app, cli, executable
    var match: String
    var enabled: Bool = true
    func matchesApp(bundleID: String?, name: String?) -> Bool {
        if id == "app:chatgpt" && bundleID == "com.openai.codex" { return false }
        return bundleID == match || name == match
    }
    /// Shared runtime names must not become broad agent roots through either
    /// catalog import or the custom executable picker. Existing choices are kept.
    static func isGeneralPurposeExecutable(_ name: String) -> Bool {
        let name = name.lowercased()
        let fixed: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh", "osascript", "launchd", "java", "dotnet", "env", "perch", "perchguard"]
        return fixed.contains(name) || name.range(of: "^(pythonw?|pypy|ruby|perl|node(js)?|bun|deno|php|lua(jit)?)([0-9]+(\\.[0-9]+)*)?$", options: .regularExpression) != nil
    }
    static var defaults: [AgentTarget] { [
        .init(id: "app:codex", name: "Codex", kind: "app", match: "com.openai.codex"),
        .init(id: "app:chatgpt", name: "ChatGPT", kind: "app", match: "ChatGPT"),
        .init(id: "app:claude", name: "Claude desktop", kind: "app", match: "Claude"),
        .init(id: "cli:codex", name: "Codex CLI", kind: "cli", match: "codex"),
        .init(id: "cli:claude", name: "Claude Code", kind: "cli", match: "claude")
    ] }
}

struct SafetyConfiguration: Codable, Equatable {
    var targets = AgentTarget.defaults
    var shortcut = PanicShortcut()
    var resetAgentPermissions = true
    var resetAllPermissions: Bool? = true
    var navigation: NavigationPreferences?
    var navigationProfiles: [NavigationKeyboardProfile]?
    var keepAwake = false
    var reverseTrackpad = false
    var reverseWheel = false
    var swapModifiers = false
    static func load() -> Self {
        guard FileManager.default.fileExists(atPath: SafetyFiles.config.path) else { return Self() }
        if let value = try? SafetyFiles.read(Self.self, from: SafetyFiles.config) { return AgentCatalog.available()?.suggestions(for: value) ?? value }
        // Never silently expand a damaged configuration to the default target list.
        var disabled = Self()
        disabled.targets = []
        return disabled
    }
    func save() throws { try SafetyFiles.write(self, to: SafetyFiles.config) }
}

struct ProcessIdentity: Codable, Hashable {
    let pid: Int32
    let uid: UInt32
    let seconds: UInt64
    let microseconds: UInt64
}
struct AgentProcess: Codable, Equatable {
    let identity: ProcessIdentity
    let parent: Int32
    let executable: String
    var name: String { String(executable.split(separator: "/").last ?? "") }
}
struct TrackedAgent: Codable, Equatable {
    let process: AgentProcess
    let targetID: String
}

struct AgentTracker {
    private(set) var tracked: [ProcessIdentity: TrackedAgent] = [:]
    private(set) var revision: UInt64 = 0
    mutating func replace(with values: [ProcessIdentity: TrackedAgent]) {
        guard tracked != values else { return }
        tracked = values; revision &+= 1
    }
    mutating func insert(_ value: TrackedAgent) {
        let identity = value.process.identity
        guard tracked[identity] != value else { return }
        tracked[identity] = value; revision &+= 1
    }
    mutating func remove(_ identity: ProcessIdentity) {
        if tracked.removeValue(forKey: identity) != nil { revision &+= 1 }
    }
    mutating func update(processes: [AgentProcess], roots: [ProcessIdentity: String], enabledTargets: Set<String>, excluded: Set<ProcessIdentity>) {
        let live = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity, $0) })
        var next = tracked.filter { live[$0.key] != nil && enabledTargets.contains($0.value.targetID) && !excluded.contains($0.key) }
        for (identity, target) in roots where enabledTargets.contains(target) && !excluded.contains(identity) {
            if let process = live[identity] { next[identity] = TrackedAgent(process: process, targetID: target) }
        }
        var added = true
        while added {
            added = false
            let parents = Dictionary(uniqueKeysWithValues: next.values.map { ($0.process.identity.pid, $0.targetID) })
            for process in processes where next[process.identity] == nil && !excluded.contains(process.identity) {
                if let target = parents[process.parent] {
                    next[process.identity] = TrackedAgent(process: process, targetID: target)
                    added = true
                }
            }
        }
        replace(with: next)
    }
}

struct GuardianMaintenanceCounts: Codable {
    var configurationReads: UInt64 = 0
    var requestScans: UInt64 = 0
    var checkpointSorts: UInt64 = 0
    var checkpointWrites: UInt64 = 0
}

struct SafetyState: Codable, Equatable {
    var locked = false
    var trackingSince = Date()
    var bootTime: Int64 = ProcessTable.bootTime
    var tracked: [TrackedAgent] = []
    var disabledJobs: [String] = []
}
struct SafetyStatus: Codable {
    var timestamp = Date()
    var watcherPID: Int32 = getpid()
    var helperBuild: String = HelperBuild.current
    var statusProtocol: Int = HelperBuild.protocolVersion
    var locked: Bool
    var pendingLaunchJobs: Int
    var shortcutActive: Bool
    var inputTrusted: Bool?
    var inputActive: Bool
    var keepAwakeActive: Bool
    var trackedCount: Int
    var targets: [String]
    var message: String
    var testResultID: String?
    var testUntil: Date?
    var error: String?
    var eventCoverage: String? = nil
    var processEventCount: Int? = nil
    var eventLastSeen: Date? = nil
    var eventConnected: Bool? = nil
    var eventDiagnostics: String? = nil
    var eventSessionID: String? = nil
    var maintenance: GuardianMaintenanceCounts? = nil
    var registeredShortcut: PanicShortcut? = nil
    var compatible: Bool { HelperBuild.compatible(build: helperBuild, protocolVersion: statusProtocol) }
    var fresh: Bool { compatible && Date().timeIntervalSince(timestamp) < 4 }
}
struct SafetyRequest: Codable {
    let id: UUID
    var timestamp = Date()
    let action: String
}
struct SafetyEvent: Codable {
    var timestamp = Date()
    let action: String
    let pid: Int32?
    let name: String
    let result: String
}

enum SafetyFiles {
    static let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Safety", isDirectory: true)
    static let config: URL = base.appendingPathComponent("config.json")
    static let state: URL = base.appendingPathComponent("state.json")
    static let requests: URL = base.appendingPathComponent("requests", isDirectory: true)
    static let history: URL = base.appendingPathComponent("events.jsonl")
    static let report: URL = base.appendingPathComponent("Safety report.txt")
    static let helperApp: URL = base.appendingPathComponent("Perch Helper.app")
    static let binary: URL = helperApp.appendingPathComponent("Contents/MacOS/Perch")
    static func prepare() throws {
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try prepare()
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func writeRecoveryState(_ value: SafetyState) throws {
        try write(value, to: state)
        let handle = try FileHandle(forWritingTo: state)
        defer { try? handle.close() }
        try handle.synchronize()
        let directory = open(base.path, O_RDONLY)
        guard directory >= 0 else { throw AppError(message: "Could not open the recovery directory.") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw AppError(message: "Could not synchronize launch-job recovery.") }
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
    static func signal(_ process: AgentProcess, _ signal: Int32) -> String {
        guard process.identity.pid != getpid(), process.identity.uid == getuid() else { return "refused: protected process or different user" }
        guard let live = inspect(process.identity.pid) else { return "already exited" }
        guard live.identity == process.identity else { return "skipped: PID reused" }
        if kill(process.identity.pid, signal) == 0 { return "sent" }
        return errno == ESRCH ? "already exited" : "failed: \(String(cString: strerror(errno)))"
    }
    // Inspect only the executable/script portion of node arguments. Never persist command lines.
    static func nodeScript(_ process: AgentProcess) -> String? {
        guard process.name == "node" || process.name == "bun" else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, process.identity.pid]
        var bytes = [UInt8](repeating: 0, count: 262144)
        var size = bytes.count
        guard sysctl(&mib, u_int(mib.count), &bytes, &size, nil, 0) == 0, size > 4 else { return nil }
        var index = 4
        while index < size && bytes[index] != 0 { index += 1 }
        while index < size && bytes[index] == 0 { index += 1 }
        // argv[0] is the runtime; argv[1] is the script in the supported launchers.
        while index < size && bytes[index] != 0 { index += 1 }
        index += 1
        let start = index
        while index < size && bytes[index] != 0 { index += 1 }
        guard start < index else { return nil }
        return String(bytes: bytes[start..<index], encoding: .utf8)
    }
}
