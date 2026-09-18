import AppKit
import ColorSync
import Darwin
import IOKit

/// Software display disabling does NOT honor application-lifetime restoration on
/// the tested Mac. The independent guardian must own recovery before any disable.
struct DeskDesktopRecord: Codable, Equatable {
    let identity: String
    let display: UInt32
    let mode: Int32
    let x: Int32
    let y: Int32
    let owner: ProcessIdentity
    var expires: TimeInterval
    var physical: DeskDesktopPhysicalIdentity? = nil
    var bootTime: Int64 = ProcessTable.bootTime
}
struct DeskDesktopPhysicalIdentity: Codable, Equatable {
    let path: String
    let registryID: UInt64
    let edid: String
}
enum DeskDesktopRecovery {
    static let lifetime: TimeInterval = 8
    static let journal = SafetyFiles.base.appendingPathComponent("desktop-recovery.json")
    static let lockURL = SafetyFiles.base.appendingPathComponent("desktop-recovery.lock")
    typealias Enable = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError
    private static let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let enable: Enable? = framework.flatMap { dlsym($0, "SLSConfigureDisplayEnabled") }.map { unsafeBitCast($0, to: Enable.self) }
    private typealias Info = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private static let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
    private static let info: Info? = coreDisplay.flatMap { dlsym($0, "CoreDisplay_DisplayCreateInfoDictionary") }.map { unsafeBitCast($0, to: Info.self) }
    static func identity(_ id: UInt32) -> String? {
        if let uuid = DisplayIdentity(id: id).uuid { return uuid }
        guard let values = info?(id)?.takeRetainedValue() as? [String: Any], let uuid = values["kCGDisplayUUID"] as? String, uuid != "00000000-0000-0000-0000-000000000000" else { return nil }; return uuid
    }
    static func physicalIdentity(_ id: UInt32) -> DeskDesktopPhysicalIdentity? {
        guard let values = info?(id)?.takeRetainedValue() as? [String: Any], let path = values["IODisplayLocation"] as? String else { return nil }
        return physicalIdentity(path: path)
    }
    static func physicalIdentity(path: String) -> DeskDesktopPhysicalIdentity? {
        guard path.utf8.count < 4096, path.hasPrefix("IOService:") else { return nil }
        let service = path.withCString { IORegistryEntryFromPath(kIOMainPortDefault, $0) }
        guard service != 0 else { return nil }; defer { IOObjectRelease(service) }
        var entry: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entry) == KERN_SUCCESS,
              let edid = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "EDID UUID" as CFString, kCFAllocatorDefault, UInt32(kIORegistryIterateRecursively)) as? String,
              !edid.isEmpty, edid.utf8.count <= 256 else { return nil }
        return .init(path: path, registryID: entry, edid: edid)
    }
    /// How long a background caller waits for the recovery lock before giving up.
    static let lockPatience: TimeInterval = 2
    static func locked<T>(_ action: (inout [DeskDesktopRecord]) throws -> T) throws -> T {
        try SafetyFiles.prepare()
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw KVMError("Desktop recovery lock is unavailable.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG else { throw KVMError("Desktop recovery lock is unavailable.") }
        // The once-a-second display bookkeeping holds this lock briefly on its own
        // thread. A monitor switch arriving in that moment used to be refused as
        // "busy", and the write went nowhere. Off the main thread, wait a moment
        // for it instead; on the main thread, never block.
        var acquired = flock(fd, LOCK_EX | LOCK_NB) == 0
        if !acquired && !Thread.isMainThread {
            let deadline = ProcessInfo.processInfo.systemUptime + Self.lockPatience
            while !acquired && ProcessInfo.processInfo.systemUptime < deadline {
                usleep(20_000)
                acquired = flock(fd, LOCK_EX | LOCK_NB) == 0
            }
        }
        guard acquired else { throw KVMError("Desktop recovery is busy.") }
        defer { flock(fd, LOCK_UN) }
        var records: [DeskDesktopRecord] = []
        if FileManager.default.fileExists(atPath: journal.path) {
            let handle = open(journal.path, O_RDONLY | O_NOFOLLOW)
            guard handle >= 0 else { throw KVMError("Desktop recovery journal is unavailable.") }
            defer { close(handle) }
            var state = stat()
            guard fstat(handle, &state) == 0, state.st_uid == getuid(), state.st_mode & S_IFMT == S_IFREG, state.st_size <= 65536 else { throw KVMError("Desktop recovery journal is invalid.") }
            let file = FileHandle(fileDescriptor: handle, closeOnDealloc: false)
            records = try JSONDecoder().decode([DeskDesktopRecord].self, from: file.readToEnd() ?? Data())
            guard records.count <= 16, Set(records.map(\.identity)).count == records.count,
                  records.allSatisfy({ UUID(uuidString: $0.identity) != nil && $0.display != 0 && $0.expires.isFinite && $0.owner.uid == getuid() }) else { throw KVMError("Desktop recovery records are invalid.") }
        }
        return try action(&records)
    }
    static func save(_ records: [DeskDesktopRecord]) throws {
        try SafetyFiles.write(records, to: journal, durable: true)
    }
    static func setEnabled(_ id: UInt32, _ value: Bool) throws {
        guard let enable else { throw KVMError("Software display connection is unavailable on this Mac.") }
        var transaction: CGDisplayConfigRef?
        let started = CGBeginDisplayConfiguration(&transaction)
        guard started == .success, let transaction else { throw KVMError("macOS could not begin a display change (\(started.rawValue)).") }
        let result = enable(transaction, id, value)
        guard result == .success else { CGCancelDisplayConfiguration(transaction); throw KVMError("macOS rejected the display change (\(result.rawValue)).") }
        // This avoids writing permanent preferences, but the private mutation
        // still requires explicit restoration. Do not remove the recovery lease.
        let completed = CGCompleteDisplayConfiguration(transaction, .forAppOnly)
        guard completed == .success else { throw KVMError("macOS could not finish the display change (\(completed.rawValue)).") }
    }
    static func restore(_ record: DeskDesktopRecord) throws -> Bool {
        // A reboot undid every software disconnection; a display that is back
        // online under a different ID (replug, sleep) needs nothing either. A
        // record that can never be restored must not block that display forever.
        guard record.bootTime == ProcessTable.bootTime else { return true }
        let observed = identity(record.display)
        if observed != record.identity, DisplayIdentity.online().contains(where: { $0.id != record.display && $0.isOnline && identity($0.id) == record.identity }) { return true }
        if observed != record.identity {
            // Software disconnection blanks CoreGraphics identity. The physical
            // registry endpoint and EDID must still match, within the same boot.
            guard observed == nil, CGDisplayIsOnline(record.display) == 0,
                  record.bootTime == ProcessTable.bootTime, let physical = record.physical,
                  physicalIdentity(path: physical.path) == physical else { return false }
        }
        if CGDisplayIsOnline(record.display) == 0 { try setEnabled(record.display, true) }
        guard CGDisplayIsOnline(record.display) != 0, identity(record.display) == record.identity else { return false }
        // Enable must commit first: a mode transaction on a disabled display
        // fails with CGError 1000. Preserve mode/position only if still available.
        let modes = CGDisplayCopyAllDisplayModes(record.display, nil) as? [CGDisplayMode] ?? []
        guard let mode = modes.first(where: { $0.ioDisplayModeID == record.mode }) else { return true }
        let bounds = CGDisplayBounds(record.display)
        if CGDisplayCopyDisplayMode(record.display)?.ioDisplayModeID == record.mode && bounds.origin == CGPoint(x: Int(record.x), y: Int(record.y)) { return true }
        var transaction: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&transaction) == .success, let transaction else { return false }
        guard CGConfigureDisplayWithDisplayMode(transaction, record.display, mode, nil) == .success,
              CGConfigureDisplayOrigin(transaction, record.display, record.x, record.y) == .success else { CGCancelDisplayConfiguration(transaction); return false }
        return CGCompleteDisplayConfiguration(transaction, .forAppOnly) == .success
    }
    static func expired(_ record: DeskDesktopRecord, now: TimeInterval, owner: ProcessIdentity?) -> Bool {
        !now.isFinite || now >= record.expires || record.expires > now + lifetime || owner != record.owner
    }
    static func recover() {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        try? locked { records in
            let before = records
            records.removeAll { record in
                guard expired(record, now: ProcessInfo.processInfo.systemUptime, owner: ProcessTable.inspect(record.owner.pid)?.identity) else { return false }
                return (try? restore(record)) == true
            }
            if records != before { try save(records) }
        }
    }
}
