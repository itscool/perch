import Foundation
import Darwin

struct FileRevision: Equatable {
    let inode: UInt64, size: Int64, modified: Int64, nanos: Int64, changed: Int64, changeNanos: Int64
    static func read(_ url: URL) -> FileRevision? {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { return nil }
        return .init(inode: s.st_ino, size: s.st_size, modified: Int64(s.st_mtimespec.tv_sec), nanos: Int64(s.st_mtimespec.tv_nsec), changed: Int64(s.st_ctimespec.tv_sec), changeNanos: Int64(s.st_ctimespec.tv_nsec))
    }
}
// Polling still notices atomic replacement immediately; unchanged files are not decoded again.
enum JSONFileCache {
    struct Entry { let revision: FileRevision?; let result: Result<Any, Error> }
    static let lock = NSLock()
    struct Key: Hashable { let path: String; let type: ObjectIdentifier }
    static var entries: [Key: Entry] = [:]
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let revision = FileRevision.read(url)
        let key = Key(path: url.path, type: ObjectIdentifier(type))
        lock.lock(); defer { lock.unlock() }
        if let entry = entries[key], entry.revision == revision {
            if let value = try entry.result.get() as? T { return value }
        }
        let result = Result<T, Error> { try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        if entries.count >= 64 { entries.removeAll(keepingCapacity: true) }
        entries[key] = Entry(revision: revision, result: result.map { $0 as Any })
        return try result.get()
    }
}
