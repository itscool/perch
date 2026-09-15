import Foundation
import Darwin

/// Bounded, identity-checked file access.
///
/// Records that another process, a root helper or a restart hands to Perch are
/// read through one no-follow descriptor whose owner, type, link count, mode
/// and size are checked before a single byte is decoded. Writes replace the
/// file atomically with a private mode, and can be made durable with an fsync
/// of the file and its directory for journals that must survive a crash.
enum SecureFile {
    struct Expectation {
        var owner: uid_t? = getuid()
        var maximumBytes: Int
        /// Reject files that group or world can write (mode & 0o022).
        var requirePrivate = false
        /// Reject hard-linked files.
        var singleLink = true
        /// Reject empty files.
        var nonEmpty = true
    }
    struct Rejected: LocalizedError {
        let path: String
        let reason: String
        var errorDescription: String? { reason }
    }

    /// Read the whole file after checking it against `expectation`.
    static func read(_ path: String, _ expectation: Expectation) throws -> Data {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Rejected(path: path, reason: "The file could not be opened.") }
        defer { close(fd) }
        return try read(descriptor: fd, path: path, expectation)
    }
    /// Read a file relative to an already-opened, already-checked directory.
    static func read(in directory: Int32, _ name: String, _ expectation: Expectation) throws -> Data {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Rejected(path: name, reason: "The file could not be opened.") }
        defer { close(fd) }
        return try read(descriptor: fd, path: name, expectation)
    }
    private static func read(descriptor fd: Int32, path: String, _ expectation: Expectation) throws -> Data {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Rejected(path: path, reason: "The file is not a regular file.") }
        if let owner = expectation.owner, info.st_uid != owner { throw Rejected(path: path, reason: "The file has unexpected ownership.") }
        if expectation.requirePrivate, info.st_mode & 0o022 != 0 { throw Rejected(path: path, reason: "The file is writable by other users.") }
        if expectation.singleLink, info.st_nlink != 1 { throw Rejected(path: path, reason: "The file is hard-linked.") }
        if expectation.nonEmpty, info.st_size <= 0 { throw Rejected(path: path, reason: "The file is empty.") }
        guard info.st_size <= expectation.maximumBytes else { throw Rejected(path: path, reason: "The file is larger than allowed.") }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size)), count = 0
        while count < bytes.count {
            let size = bytes.withUnsafeMutableBytes { buffer in Darwin.read(fd, buffer.baseAddress!.advanced(by: count), buffer.count - count) }
            if size == 0 { break }
            if size < 0 { if errno == EINTR { continue }; throw Rejected(path: path, reason: "The file could not be read.") }
            count += size
        }
        guard count == bytes.count else { throw Rejected(path: path, reason: "The file changed while it was being read.") }
        return Data(bytes)
    }

    /// Replace `url` atomically with `data`, owner-only by default.
    /// `durable` also fsyncs the file and its directory; `protection` keeps the
    /// file readable across restarts under macOS's after-first-unlock class.
    static func writeAtomically(_ data: Data, to url: URL, mode: Int = 0o600, durable: Bool = false, protection: Bool = false) throws {
        var options: Data.WritingOptions = [.atomic]
        if protection { options.insert(.completeFileProtectionUntilFirstUserAuthentication) }
        try data.write(to: url, options: options)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        guard durable else { return }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw Rejected(path: url.path, reason: "Could not open the directory to synchronize it.") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw Rejected(path: url.path, reason: "Could not synchronize the directory.") }
    }
    static func writeAtomically<T: Encodable>(_ value: T, to url: URL, mode: Int = 0o600, durable: Bool = false, protection: Bool = false) throws {
        try writeAtomically(try JSONEncoder().encode(value), to: url, mode: mode, durable: durable, protection: protection)
    }
    /// True when the path resolves to itself, that is, no symbolic link is involved.
    static func isDirect(_ url: URL) -> Bool {
        url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL
    }
}
