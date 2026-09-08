import Foundation
import Darwin

struct LidActivityEntry: Codable, Equatable {
    var id = UUID()
    var date: Date
    var source: String
    var message: String
    init(date: Date = Date(), source: String, message: String) {
        self.date = date; self.source = String(source.prefix(40)); self.message = String(message.prefix(512))
    }
}

/// A single bounded journal shared by the supervisor and its independent watchdog.
/// Atomic replacement lets the app read history even when the helper is offline.
/// Only the root helpers write; all paths are fixed, with no user-supplied content.
final class LidActivityStore {
    static let directory = "/var/db/local.scott.perch.lid-activity"
    static let limit = 1024
    static let lifetime: TimeInterval = 24 * 60 * 60
    static let byteLimit = 4 * 1024 * 1024
    let directory: String
    private let owner: uid_t
    init(directory: String = LidActivityStore.directory, owner: uid_t = 0) { self.directory = directory; self.owner = owner }
    static func retained(_ entries: [LidActivityEntry], now: Date) -> [LidActivityEntry] {
        Array(entries.filter { $0.date <= now && now.timeIntervalSince($0.date) < lifetime }
            .enumerated().sorted { $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date }
            .suffix(limit).map(\.element))
    }
    private func failure(_ action: String) -> Error { AppError(message: "Lid activity could not \(action). \(String(cString: strerror(errno)))") }
    private func checked(_ fd: Int32, directory: Bool = false) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & 0o022 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG), directory || info.st_nlink == 1 else {
            throw AppError(message: "Lid activity storage has unexpected ownership or file permissions.")
        }
    }
    private func openDirectory(create: Bool) throws -> Int32 {
        if create {
            guard geteuid() == owner else { throw AppError(message: "Only the lid helper can write activity.") }
            if mkdir(directory, 0o755) != 0 && errno != EEXIST { throw failure("create its folder") }
        }
        let fd = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("open its folder") }
        do { try checked(fd, directory: true); return fd } catch { close(fd); throw error }
    }
    private func load(_ directoryFD: Int32) throws -> [LidActivityEntry] {
        let fd = openat(directoryFD, "events.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return [] }
        guard fd >= 0 else { throw failure("read its history") }; defer { close(fd) }
        try checked(fd)
        var info = stat(); guard fstat(fd, &info) == 0, info.st_size <= Self.byteLimit else { throw AppError(message: "Lid activity history exceeds its size limit.") }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw failure("read its history") }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
            guard data.count <= Self.byteLimit else { throw AppError(message: "Lid activity history exceeds its size limit.") }
        }
        return try JSONDecoder().decode([LidActivityEntry].self, from: data)
    }
    func read(now: Date = Date()) throws -> [LidActivityEntry] {
        let fd = try openDirectory(create: false); defer { close(fd) }
        return Self.retained(try load(fd), now: now)
    }
    func append(_ entries: [LidActivityEntry], now: Date = Date()) throws {
        let directoryFD = try openDirectory(create: true); defer { close(directoryFD) }
        let lockFD = openat(directoryFD, "writer.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw failure("open its writer lock") }; defer { close(lockFD) }
        try checked(lockFD)
        guard flock(lockFD, LOCK_EX) == 0 else { throw failure("lock its history") }
        defer { flock(lockFD, LOCK_UN) }
        let previous = try load(directoryFD)
        let retained = Self.retained(previous + entries, now: now)
        if retained == previous { return }
        let data = try JSONEncoder().encode(retained)
        guard data.count <= Self.byteLimit else { throw AppError(message: "Lid activity history exceeds its size limit.") }
        let temporary = ".events-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw failure("save its history") }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count-offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("save its history") }; offset += count
            }
        }
        guard fsync(fd) == 0, renameat(directoryFD, temporary, directoryFD, "events.json") == 0 else { throw failure("finish saving its history") }
    }
}

/// Disk work never runs on the power-control loop. The pending queue is bounded
/// too, so slow storage cannot exhaust memory or delay a safety deadline.
final class LidActivityRecorder {
    let source: String
    private let store: LidActivityStore
    private let queue = DispatchQueue(label: "local.scott.perch.lid-activity", qos: .utility)
    private let lock = NSLock()
    private var pending: [LidActivityEntry] = []
    private var scheduled = false
    private var last: LidActivityEntry?
    private var storageError: String?
    var error: String? { lock.lock(); defer { lock.unlock() }; return storageError }
    init(source: String, store: LidActivityStore = LidActivityStore()) { self.source = source; self.store = store }
    func record(_ message: String, date: Date = Date(), coalesce: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if coalesce, let last, last.message == message, date.timeIntervalSince(last.date) >= 0, date.timeIntervalSince(last.date) < 60 { return }
        let entry = LidActivityEntry(date: date, source: source, message: message)
        last = entry; pending.append(entry)
        if pending.count > LidActivityStore.limit { pending.removeFirst(pending.count - LidActivityStore.limit) }
        schedule()
    }
    func prune() { lock.lock(); defer { lock.unlock() }; schedule() }
    /// Used only after watchdog cleanup, immediately before that process exits.
    /// A broken disk must never keep recovery alive indefinitely.
    func finish(timeout: TimeInterval = 0.25) {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        _ = done.wait(timeout: .now()+timeout)
    }
    private func schedule() {
        guard !scheduled else { return }; scheduled = true
        queue.async { [self] in
            while true {
                lock.lock(); let batch = pending; pending.removeAll(); lock.unlock()
                var failure: String?
                do { try store.append(batch) } catch { failure = error.localizedDescription }
                lock.lock(); storageError = failure
                if pending.isEmpty { scheduled = false; lock.unlock(); return }
                lock.unlock()
            }
        }
    }
}
