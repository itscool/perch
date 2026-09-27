import Foundation
import CryptoKit
import CoreServices

/// Files copied on one Mac and pasted on another: Stage 2 of the shared
/// clipboard. Its problems are storage problems, not transfer problems, so the
/// transfer is the Stage 1 path and everything here is about the disk:
///
/// - **When and where.** Only when ⌃⌥⌘V brings them over (Scott's design,
///   September 27, 2026). The files are staged in a folder of Perch's own
///   (`DeskFileStaging`) and the pasteboard then holds them as files, so any
///   ordinary paste in Finder, Mail or anything else puts them where the person
///   is. The staging folder is on this Mac's own volume, so Finder's paste
///   clones rather than copies. File promises were tried and set aside: on an
///   ordinary pasteboard (rather than a drag) the standard receiver never asked
///   the provider to write, in one process or across two.
/// - **Names.** Every received name is made safe before it touches the disk:
///   slashes, colons, control and direction-override characters are replaced,
///   leading dots and surrounding spaces removed, and a name with nothing safe
///   left, or too long, refuses the whole copy. A peer can never write outside
///   the folder files are staged in.
/// - **Partial files.** Each file arrives into a hidden temporary file beside its
///   destination, created exclusively, and its length and SHA-256 are verified.
///   Only once every file of the copy is verified are they moved into place,
///   each with one atomic rename. A partial file never appears under its final
///   name, and a failed or cancelled copy removes everything it wrote.
/// - **Collisions.** An existing file is never overwritten: the rename refuses
///   to replace anything, and "Report 2.pdf", "Report 3.pdf" and so on are tried.
/// - **Quarantine.** Received files are marked as downloaded (com.apple.quarantine),
///   before they get their final name, so Gatekeeper treats them like downloads.
/// - **Links, aliases and folders are refused** on the sending Mac, by name. A
///   link would silently send whatever it points at, which may not be what was
///   copied; folders are left for a later version.
enum DeskFileNames {
    /// Characters that can make a name display differently from what it is.
    private static let directionControls: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
    /// Longest name accepted, in UTF-8 bytes, leaving room for " 999" below the
    /// 255 bytes a Mac volume allows.
    static let maximumLength = 240

    /// A received name made safe, or nil when nothing safe is left.
    static func sanitize(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        // Surrounding spaces and line breaks go first, so a name that is only
        // those is refused rather than turned into a dash.
        for scalar in raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            let category = scalar.properties.generalCategory
            let unsafe = scalar == "/" || scalar == ":" || category == .control || category == .lineSeparator ||
                category == .paragraphSeparator || directionControls.contains(scalar.value)
            scalars.append(unsafe ? "-" : scalar)
        }
        var name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst(); name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !name.isEmpty, name.utf8.count <= maximumLength else { return nil }
        return name
    }

    /// The candidate names for `name`: itself, then "name 2.ext", "name 3.ext", …
    static func candidates(_ name: String, limit: Int = 999) -> [String] {
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        return [name] + (2...max(2, limit)).map { ext.isEmpty || base.isEmpty ? "\(name) \($0)" : "\(base) \($0).\(ext)" }
    }
}

/// First values, Scott's to change.
struct DeskFileLimits {
    var perFile: UInt64 = 1024 * 1024 * 1024
    var total: UInt64 = 2 * 1024 * 1024 * 1024
    var count = 100
    /// Longest name accepted on the wire, before it is made safe.
    var nameBytes = 1024
}

/// Content kind 2: the names and sizes of the files a copy holds. Their data
/// follows file by file, only when they are pasted.
struct DeskFileList: Equatable {
    struct Entry: Equatable { let name: String; let size: UInt64 }
    var files: [Entry]
    var total: UInt64 { files.reduce(0) { $0 + $1.size } }
    static let kind: UInt8 = 2

    func encoded() -> Data {
        var w = DeskClipboardWire.Writer()
        w.u8(Self.kind); w.u32(UInt32(files.count))
        for file in files { w.bytes(Data(file.name.utf8)); w.u64(file.size) }
        return w.data
    }

    static func decode(_ payload: Data, limits: DeskFileLimits) throws -> Self {
        typealias F = DeskClipboardWire.Failure
        var r = DeskClipboardWire.Reader(payload)
        guard try r.u8() == kind else { throw F.malformed("content kind") }
        let count = Int(try r.u32())
        guard count >= 1 else { throw F.malformed("file count") }
        // More files, or larger ones, than this Mac accepts: declined by name.
        guard count <= limits.count else { throw DeskClipboardReason.tooLarge }
        var files: [Entry] = [], total: UInt64 = 0
        for _ in 0..<count {
            guard let name = String(data: try r.bytes(max: limits.nameBytes), encoding: .utf8) else { throw F.malformed("file name is not UTF-8") }
            let size = try r.u64()
            guard size <= limits.perFile else { throw DeskClipboardReason.tooLarge }
            total += size
            guard total <= limits.total else { throw DeskClipboardReason.tooLarge }
            files.append(.init(name: name, size: size))
        }
        guard r.atEnd else { throw F.malformed("trailing content") }
        return Self(files: files)
    }
}

/// One file on the sending Mac, as it was when its copy was examined. It is sent
/// only while it is still that same regular file.
struct DeskSourceFile: Equatable {
    let path: String
    let name: String
    let size: UInt64
    let device: UInt64
    let inode: UInt64
    let modified: Double

    /// Examine the files a copy names. Links, aliases and folders refuse the copy
    /// by name; so does anything over the limits.
    static func examine(_ urls: [URL], limits: DeskFileLimits) -> Result<[DeskSourceFile], DeskClipboardReason> {
        guard !urls.isEmpty else { return .failure(.noCopy) }
        guard urls.count <= limits.count else { return .failure(.tooLarge) }
        var files: [DeskSourceFile] = [], total: UInt64 = 0
        for url in urls {
            guard url.isFileURL else { return .failure(.unsupported) }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return .failure(.unreadable) }
            switch info.st_mode & S_IFMT {
            // A link would silently send whatever it points at.
            case S_IFLNK: return .failure(.links)
            case S_IFDIR: return .failure(.folders)
            case S_IFREG: break
            default: return .failure(.unsupported)
            }
            // A Finder alias is a regular file that stands for another one.
            if (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true { return .failure(.links) }
            guard access(url.path, R_OK) == 0 else { return .failure(.unreadable) }
            let size = UInt64(max(0, info.st_size))
            total += size
            guard size <= limits.perFile, total <= limits.total else { return .failure(.tooLarge) }
            files.append(.init(path: url.path, name: url.lastPathComponent, size: size, device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                               modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9))
        }
        return .success(files)
    }

    /// Open for sending, refusing a link swapped in since, or any change.
    func open() -> Result<Int32, DeskClipboardReason> {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return .failure(errno == ELOOP ? .links : .changed) }
        guard unchanged(fd) else { close(fd); return .failure(.changed) }
        return .success(fd)
    }

    func unchanged(_ fd: Int32) -> Bool {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        return UInt64(info.st_dev) == device && UInt64(info.st_ino) == inode && UInt64(max(0, info.st_size)) == size && modified == self.modified
    }

    /// SHA-256 of the whole file, read once before sending so the manifest can
    /// carry it. Off the main thread.
    static func digest(_ fd: Int32, size: UInt64) -> Data? {
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var offset: UInt64 = 0
        while offset < size {
            let wanted = Int(min(UInt64(buffer.count), size - offset))
            let got = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, wanted, off_t(offset)) }
            guard got > 0 else { return nil }
            hasher.update(data: buffer[0..<got])
            offset += UInt64(got)
        }
        return Data(hasher.finalize())
    }

    /// Chunk `index` of the padded stream: file bytes, then zeros.
    static func chunk(_ fd: Int32, index: UInt32, size: UInt64, padded: UInt64) -> Data? {
        let start = UInt64(index) * UInt64(DeskClipboardWire.chunkSize)
        guard start < padded else { return nil }
        let length = Int(min(UInt64(DeskClipboardWire.chunkSize), padded - start))
        var data = Data(count: length)
        if start < size {
            let real = Int(min(UInt64(length), size - start))
            var filled = 0
            while filled < real {
                let got = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + filled, real - filled, off_t(start) + off_t(filled)) }
                guard got > 0 else { return nil }
                filled += got
            }
        }
        return data
    }
}

/// Where one received file is written: a hidden temporary file beside its
/// destination, moved into place only once it is whole and verified. Used on
/// one serial queue.
final class DeskFileSink {
    let directory: URL
    let name: String
    let size: UInt64
    let temporary: URL
    private var fd: Int32 = -1
    private var hasher = SHA256()
    private(set) var written: UInt64 = 0

    init(directory: URL, name: String, size: UInt64, transfer: UUID) {
        self.directory = directory.standardizedFileURL; self.name = name; self.size = size
        temporary = self.directory.appendingPathComponent(".perch-" + transfer.uuidString + ".partial")
    }

    func create() throws {
        fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DeskClipboardReason.writeFailed }
    }

    func append(_ data: Data) throws {
        guard fd >= 0, written + UInt64(data.count) <= size else { throw DeskClipboardReason.corrupt }
        var sent = 0
        while sent < data.count {
            let wrote = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, data.count - sent) }
            guard wrote > 0 else { throw DeskClipboardReason.writeFailed }
            sent += wrote
        }
        hasher.update(data: data)
        written += UInt64(data.count)
    }

    /// Verify, mark as downloaded, and move into place.
    func finish(digest: Data) throws -> URL {
        try verify(digest: digest)
        return try place()
    }

    /// Close the file and check it is exactly what the manifest described.
    func verify(digest: Data) throws {
        guard fd >= 0 else { throw DeskClipboardReason.writeFailed }
        let closed = close(fd); fd = -1
        guard closed == 0 else { throw DeskClipboardReason.writeFailed }
        guard written == size, DeskClipboardWire.validMAC(Data(hasher.finalize()), digest) else { throw DeskClipboardReason.corrupt }
    }

    /// Mark a verified file as downloaded and move it into place under a name
    /// that does not exist yet. Returns where the file now is.
    func place() throws -> URL {
        try Self.quarantine(temporary)
        for candidate in DeskFileNames.candidates(name) {
            let destination = directory.appendingPathComponent(candidate)
            // Belt and braces: whatever the name, the file stays in its folder.
            guard destination.deletingLastPathComponent().standardizedFileURL.path == directory.path else { throw DeskClipboardReason.unsafeName }
            if renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return destination }
            guard errno == EEXIST else { throw DeskClipboardReason.writeFailed }
        }
        throw DeskClipboardReason.writeFailed
    }

    /// Remove the partial file. Safe to call more than once.
    func discard() {
        if fd >= 0 { close(fd); fd = -1 }
        unlink(temporary.path)
    }

    static func quarantine(_ url: URL) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [kLSQuarantineAgentNameKey as String: "Perch",
                                       kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String]
        var target = url
        try target.setResourceValues(values)
        // The mark is what Gatekeeper reads; a volume that cannot hold it means
        // the file is not delivered at all.
        guard getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) > 0 else { throw DeskClipboardReason.quarantine }
    }
}

/// Where another Mac's files wait to be pasted: a folder of Perch's own with
/// one subfolder per copy, on this Mac's own volume (in Application Support,
/// kept out of backups) so Finder's paste can clone rather than copy.
///
/// When staged files are removed. The rule, pinned by tests:
/// 1. A copy that failed or was cancelled: at once, partial files and all.
/// 2. The copy this Mac's clipboard holds: never, while it holds it.
/// 3. A copy that has left the clipboard, because something else was copied
///    here: ten minutes later, so a paste still copying out of it can finish.
/// 4. Anything else found in the folder (left from before Perch last quit and
///    no longer on the clipboard): at once.
final class DeskFileStaging {
    static let grace: Double = 600
    let root: URL
    private(set) var onClipboard: (id: UUID, changeCount: Int)?
    private(set) var leftAt: [UUID: Double] = [:]
    init(root: URL) { self.root = root.standardizedFileURL }
    static var standard: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Desk/Clipboard", isDirectory: true)
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Create a copy's folder, private to this user. On the disk queue.
    func prepare(_ id: UUID) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var marked = root; try? marked.setResourceValues(values)
        // A fresh name, never an existing one: nothing is written through a
        // folder or link someone else put here.
        guard mkdir(folder(id).path, 0o700) == 0 else { throw DeskClipboardReason.writeFailed }
    }

    /// A copy's files are now what the clipboard holds. The one before starts
    /// its ten minutes.
    func placed(_ id: UUID, changeCount: Int, now: Double) {
        if let previous = onClipboard, previous.id != id { leftAt[previous.id] = now }
        onClipboard = (id, changeCount); leftAt[id] = nil
    }

    /// The clipboard changed. If it no longer holds the staged copy, that copy
    /// starts its ten minutes.
    func clipboardChanged(to changeCount: Int, now: Double) {
        guard let current = onClipboard, current.changeCount != changeCount else { return }
        leftAt[current.id] = now
        onClipboard = nil
    }

    /// At start: the staged copy the clipboard still lists, if any, is kept.
    func adopt(_ urls: [URL], changeCount: Int) {
        let base = root.path + "/"
        for url in urls {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base), let first = path.dropFirst(base.count).split(separator: "/").first,
                  let id = UUID(uuidString: String(first)) else { continue }
            onClipboard = (id, changeCount); return
        }
    }

    /// Which of the staged copies present may go now.
    static func removable(present: Set<UUID>, onClipboard: UUID?, active: UUID?, leftAt: [UUID: Double], now: Double) -> Set<UUID> {
        present.filter { id in
            guard id != onClipboard, id != active else { return false }
            guard let left = leftAt[id] else { return true }
            return now - left >= grace
        }
    }

    /// The staged copies on disk: folders named for a copy, nothing else.
    func present() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return Set(names.compactMap(UUID.init(uuidString:)))
    }

    /// Remove a staged copy. On the disk queue.
    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Forget what is gone.
    func forget(_ ids: Set<UUID>) { for id in ids { leftAt[id] = nil } }
}
