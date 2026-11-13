import Foundation
import CryptoKit
import CoreServices

/// Files and folders copied on one Mac and brought over to another: the
/// storage half of the shared clipboard. The transfer is the clipboard's own
/// path; everything here is about trees on disk.
///
/// - **When and where.** Only when ⌃⌥⌘V brings them over (Scott's design,
///   September 27, 2026). The copy is staged in a folder of Perch's own
///   (`DeskFileStaging`) and the pasteboard then holds its top-level items as
///   files, so any ordinary paste in Finder, Mail or anything else puts them
///   where the person is. File promises were tried and set aside: on an
///   ordinary pasteboard the standard receiver never asked the provider to write.
/// - **Folders keep their shape** (Scott, November 2026: "let's do folders"),
///   empty folders included, within limits: 2 GB in all, 1 GB a file, 10,000
///   items, 32 levels deep.
/// - **Links are never followed on the sending Mac**, so nothing outside the
///   selection is ever read or sent. A link inside a copied folder is sent as a
///   link only when it is relative and resolves, within the copy itself, to
///   something inside its own top-level folder: app bundles and projects hold
///   such links; one that leads outside would be a leak and refuses the copy. A
///   link or alias selected directly is refused.
/// - **Names.** Every name in every path is made safe before it touches the
///   disk. A peer can never write outside the folder a copy is staged in.
/// - **The tar attack** ("a link entry, then a file written through it", say
///   `a -> /Users/x/.ssh` then `a/authorized_keys`) is answered three times:
///   the list is refused if anything sits inside something that is not a folder
///   or if a link leads outside; everything is written through file descriptors
///   opened without following links, so no path component can be one; and
///   links are created last, after every folder and file is in place.
/// - **Whole or not at all.** Each file arrives into a hidden temporary file,
///   created exclusively, checked against its length and SHA-256, then given its
///   name. The copy is put on the clipboard only once all of it is in place; a
///   failed or cancelled copy removes everything it wrote.
/// - **Quarantine and permissions.** Every file and folder is marked as
///   downloaded, so Gatekeeper treats them like downloads. Regular files keep
///   their permission bits, without setuid, setgid or sticky, so an executable
///   still runs; nothing else is carried over.
enum DeskFileNames {
    /// Characters that can make a name display differently from what it is.
    private static let directionControls: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
    /// Longest name accepted, in UTF-8 bytes, leaving room for " 999" below the
    /// 255 bytes a Mac volume allows.
    static let maximumLength = 240

    /// A received top-level name made safe, or nil when nothing safe is left.
    /// Leading dots go too, so nothing pasted is hidden.
    static func sanitize(_ raw: String) -> String? {
        guard var name = neutralise(raw) else { return nil }
        while name.hasPrefix(".") { name.removeFirst(); name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !name.isEmpty else { return nil }
        return name
    }

    /// A name inside a copied folder, made safe the same way, except that a
    /// leading dot is kept: inside a folder it is part of what was copied
    /// (".git", ".gitignore") and hides nothing at the top. "." and ".." are
    /// still refused.
    static func sanitizeInner(_ raw: String) -> String? {
        guard let name = neutralise(raw), name != ".", name != ".." else { return nil }
        return name
    }

    private static func neutralise(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        // Surrounding spaces and line breaks go first, so a name that is only
        // those is refused rather than turned into a dash.
        for scalar in raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            let category = scalar.properties.generalCategory
            let unsafe = scalar == "/" || scalar == ":" || category == .control || category == .lineSeparator ||
                category == .paragraphSeparator || directionControls.contains(scalar.value)
            scalars.append(unsafe ? "-" : scalar)
        }
        let name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
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

/// How much a copy of files may hold. The size caps are Scott's (confirmed
/// November 2026); the item count and depth are his for folders.
struct DeskFileLimits {
    var perFile: UInt64 = 1024 * 1024 * 1024
    var total: UInt64 = 2 * 1024 * 1024 * 1024
    /// Files, folders and links together, top level included.
    var entries = 10_000
    /// Levels below and including the top-level item.
    var depth = 32
    /// Longest name accepted on the wire, before it is made safe.
    var nameBytes = 1024
    /// Longest link target accepted.
    var targetBytes = 1024
}

/// One item of a copied tree, as the wire carries it.
struct DeskTreeEntry: Equatable {
    enum Kind: Equatable {
        case directory
        /// `mode`: the sender's permission bits, carried without setuid,
        /// setgid or sticky.
        case file(size: UInt64, mode: UInt16)
        case link(target: String)
    }
    /// Its names from the top-level item down: ["Project", "src", "main.c"].
    var path: [String]
    var kind: Kind
}

/// Content kind 2: every file, folder and link a copy holds, parents before
/// what they contain. The files' contents follow as one stream, in this order.
struct DeskTreeList: Equatable {
    var entries: [DeskTreeEntry]
    static let kind: UInt8 = 2
    var total: UInt64 { entries.reduce(0) { if case .file(let size, _) = $1.kind { return $0 + size }; return $0 } }
    var fileCount: Int { entries.filter { if case .file = $0.kind { return true }; return false }.count }
    /// What the copy is, for its announcement: files, or files and folders, by
    /// how many items were selected, and a size bucket.
    var descriptor: DeskClipboardDescriptor {
        let tops = entries.filter { $0.path.count == 1 }
        let folders = tops.contains { $0.kind == .directory }
        return .init(kind: folders ? .folders : .files, count: max(1, tops.count), small: false,
                     size: DeskClipboardPolicy.sizeIndex(Int(clamping: total)))
    }

    func encoded() -> Data {
        var w = DeskClipboardWire.Writer()
        w.u8(Self.kind); w.u32(UInt32(entries.count))
        for entry in entries {
            switch entry.kind {
            case .directory: w.u8(1)
            case .file: w.u8(2)
            case .link: w.u8(3)
            }
            w.u8(UInt8(clamping: entry.path.count))
            for name in entry.path { w.bytes(Data(name.utf8)) }
            switch entry.kind {
            case .directory: break
            case .file(let size, let mode): w.u64(size); w.u32(UInt32(mode))
            case .link(let target): w.bytes(Data(target.utf8))
            }
        }
        return w.data
    }

    /// Read a list, declining by name (`DeskClipboardReason`) anything over
    /// this Mac's limits. The structure itself is checked by `DeskTreePlan`.
    static func decode(_ payload: Data, limits: DeskFileLimits) throws -> Self {
        typealias F = DeskClipboardWire.Failure
        var r = DeskClipboardWire.Reader(payload)
        guard try r.u8() == kind else { throw F.malformed("content kind") }
        let count = Int(try r.u32())
        guard count >= 1 else { throw F.malformed("empty list") }
        guard count <= limits.entries else { throw DeskClipboardReason.tooMany }
        var entries: [DeskTreeEntry] = []
        entries.reserveCapacity(count)
        var total: UInt64 = 0
        for _ in 0..<count {
            let type = try r.u8(), depth = Int(try r.u8())
            guard depth >= 1 else { throw F.malformed("empty path") }
            guard depth <= limits.depth else { throw DeskClipboardReason.tooDeep }
            let path = try (0..<depth).map { _ -> String in
                guard let name = String(data: try r.bytes(max: limits.nameBytes), encoding: .utf8) else { throw F.malformed("name is not UTF-8") }
                return name
            }
            switch type {
            case 1: entries.append(.init(path: path, kind: .directory))
            case 2:
                let size = try r.u64(), mode = try r.u32()
                guard mode <= 0o777 else { throw F.malformed("mode") }
                guard size <= limits.perFile else { throw DeskClipboardReason.fileTooLarge }
                total += size
                guard total <= limits.total else { throw DeskClipboardReason.tooLarge }
                entries.append(.init(path: path, kind: .file(size: size, mode: UInt16(mode))))
            case 3:
                guard let target = String(data: try r.bytes(max: limits.targetBytes), encoding: .utf8) else { throw F.malformed("link is not UTF-8") }
                entries.append(.init(path: path, kind: .link(target: target)))
            default: throw F.malformed("entry kind")
            }
        }
        guard r.atEnd else { throw F.malformed("trailing content") }
        return Self(entries: entries)
    }
}

/// Where links lead, worked out within a copy alone, never on a disk.
enum DeskTreeLinks {
    /// Whether the link at `path` with this target resolves, through the copy's
    /// own folders and links, to something that exists inside its own
    /// top-level item. Absolute targets, a climb above the top-level item, a
    /// missing item, a file used as a folder and link loops all fail.
    static func resolvesInside(link path: [String], target: String, table: [[String]: DeskTreeEntry.Kind]) -> Bool {
        guard path.count >= 2, !target.isEmpty, !target.hasPrefix("/") else { return false }
        var current = Array(path.dropLast())
        var queue = target.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var hops = 0
        while !queue.isEmpty {
            let name = queue.removeFirst()
            switch name {
            case ".": continue
            case "..":
                // The top-level item is the boundary: climbing past it leaves the copy.
                guard current.count > 1 else { return false }
                current.removeLast()
            default:
                let candidate = current + [name]
                switch table[candidate] {
                case nil: return false
                case .directory?: current = candidate
                case .file?:
                    // A file cannot be gone through as if it were a folder.
                    guard queue.isEmpty else { return false }
                    current = candidate
                case .link(let next)?:
                    hops += 1
                    guard hops <= 32, !next.isEmpty, !next.hasPrefix("/") else { return false }
                    queue = next.split(separator: "/", omittingEmptySubsequences: true).map(String.init) + queue
                }
            }
        }
        return true
    }
}

/// A copy of files and folders on the sending Mac, as it was when examined.
/// Its files are sent only while each is still that same regular file.
struct DeskSourceTree {
    struct File: Equatable {
        let path: String
        let size: UInt64
        let device: UInt64
        let inode: UInt64
        let modified: Double

        init(path: String, info: stat) {
            self.path = path
            size = UInt64(max(0, info.st_size)); device = UInt64(info.st_dev); inode = UInt64(info.st_ino)
            modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
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
            return File(path: path, info: info) == self
        }
    }
    var list: DeskTreeList
    /// The regular files, in the order their contents are streamed.
    var files: [File]
    var total: UInt64 { list.total }

    /// Look at what a copy names, never following a link, and stop at the
    /// first thing that refuses it. Metadata only: no file's contents are read,
    /// and the walk stops past 10,000 items or 32 levels.
    static func examine(_ urls: [URL], limits: DeskFileLimits) -> Result<DeskSourceTree, DeskClipboardRefusal> {
        guard !urls.isEmpty else { return .failure(.init(.noCopy)) }
        var entries: [DeskTreeEntry] = [], files: [File] = [], total: UInt64 = 0
        var tops: Set<String> = []
        func add(_ entry: DeskTreeEntry) -> DeskClipboardRefusal? {
            guard entries.count < limits.entries else { return .init(.tooMany, limit: UInt64(limits.entries)) }
            entries.append(entry)
            return nil
        }
        func file(_ path: String, _ names: [String], _ info: stat) -> DeskClipboardRefusal? {
            let size = UInt64(max(0, info.st_size))
            guard size <= limits.perFile else { return .init(.fileTooLarge, amount: size, limit: limits.perFile) }
            guard access(path, R_OK) == 0 else { return .init(.unreadable) }
            total += size
            files.append(File(path: path, info: info))
            return add(.init(path: names, kind: .file(size: size, mode: UInt16(info.st_mode & 0o777))))
        }
        for url in urls {
            guard url.isFileURL else { return .failure(.init(.unsupported)) }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return .failure(.init(.unreadable)) }
            // Two selected items with the same name get distinct names in the copy.
            let top = DeskFileNames.candidates(url.lastPathComponent).first { !tops.contains($0) } ?? UUID().uuidString
            tops.insert(top)
            switch info.st_mode & S_IFMT {
            case S_IFLNK: return .failure(.init(.links))
            case S_IFREG:
                // A Finder alias is a regular file that stands for another one.
                if (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true { return .failure(.init(.links)) }
                if let refusal = file(url.path, [top], info) { return .failure(refusal) }
            case S_IFDIR:
                if let refusal = add(.init(path: [top], kind: .directory)) { return .failure(refusal) }
                // Depth first, parents before what they hold, names in order.
                var stack: [(path: String, names: [String])] = [(url.path, [top])]
                while let (folder, names) = stack.popLast() {
                    guard let children = DeskSourceTree.names(in: folder) else { return .failure(.init(.unreadable)) }
                    var below: [(path: String, names: [String])] = []
                    for child in children {
                        let path = folder + "/" + child, inner = names + [child]
                        guard inner.count <= limits.depth else { return .failure(.init(.tooDeep, limit: UInt64(limits.depth))) }
                        var childInfo = stat()
                        guard lstat(path, &childInfo) == 0 else { return .failure(.init(.unreadable)) }
                        switch childInfo.st_mode & S_IFMT {
                        case S_IFREG:
                            if let refusal = file(path, inner, childInfo) { return .failure(refusal) }
                        case S_IFDIR:
                            if let refusal = add(.init(path: inner, kind: .directory)) { return .failure(refusal) }
                            below.append((path, inner))
                        case S_IFLNK:
                            // Read where it points; never go there.
                            var buffer = [CChar](repeating: 0, count: limits.targetBytes + 1)
                            let length = readlink(path, &buffer, limits.targetBytes + 1)
                            guard length > 0, length <= limits.targetBytes else { return .failure(.init(.linkOutside)) }
                            let target = String(decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            if let refusal = add(.init(path: inner, kind: .link(target: target))) { return .failure(refusal) }
                        default: return .failure(.init(.unsupported))
                        }
                    }
                    // Popped in reverse, so the first child's folder is walked first.
                    stack.append(contentsOf: below.reversed())
                }
            default: return .failure(.init(.unsupported))
            }
        }
        guard total <= limits.total else { return .failure(.init(.tooLarge, amount: total, limit: limits.total)) }
        // The table of the whole copy is built only when there is a link to resolve.
        let links = entries.filter { if case .link = $0.kind { return true }; return false }
        if !links.isEmpty {
            let table = Dictionary(entries.map { ($0.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
            for entry in links {
                if case .link(let target) = entry.kind, !DeskTreeLinks.resolvesInside(link: entry.path, target: target, table: table) {
                    return .failure(.init(.linkOutside))
                }
            }
        }
        return .success(.init(list: .init(entries: entries), files: files))
    }

    /// A folder's names, sorted, straight from the file system (cheaper than
    /// FileManager for a folder of thousands). Nil when it cannot be read.
    static func names(in path: String) -> [String]? {
        guard let folder = opendir(path) else { return nil }
        defer { closedir(folder) }
        var names: [String] = []
        while let entry = readdir(folder) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != ".", name != ".." { names.append(name) }
        }
        return names.sorted()
    }
}

/// Reads a copy's files as one stream on the sending Mac, a chunk at a time,
/// in list order, each file opened only when the stream reaches it, never
/// through a link, and checked unchanged before and after. Used on one serial
/// queue. Memory: one chunk.
final class DeskTreeReader {
    let files: [DeskSourceTree.File]
    let padded: UInt64
    private var index = 0
    private var fd: Int32 = -1
    private var offset: UInt64 = 0
    private var hasher = SHA256()
    private var produced: UInt64 = 0
    init(_ tree: DeskSourceTree, padded: UInt64) { files = tree.files; self.padded = padded }
    deinit { close() }

    /// The next chunk, and the SHA-256 of every file whose last byte is in it.
    func next() -> Result<(data: Data, digests: [(index: UInt32, digest: Data)]), DeskClipboardReason> {
        guard produced < padded else { return .failure(.corrupt) }
        let length = Int(min(UInt64(DeskClipboardWire.chunkSize), padded - produced))
        var data = Data(), digests: [(index: UInt32, digest: Data)] = []
        data.reserveCapacity(length)
        var buffer = [UInt8](repeating: 0, count: DeskClipboardWire.chunkSize)
        func begin() -> DeskClipboardReason? {
            switch files[index].open() {
            case .failure(let reason): return reason
            case .success(let opened): fd = opened; offset = 0; hasher = SHA256(); return nil
            }
        }
        func end() -> DeskClipboardReason? {
            let same = files[index].unchanged(fd)
            Darwin.close(fd); fd = -1
            guard same else { return .changed }
            digests.append((UInt32(index), Data(hasher.finalize())))
            index += 1
            return nil
        }
        while index < files.count {
            if fd < 0, let failure = begin() { close(); return .failure(failure) }
            let file = files[index]
            if offset == file.size {
                if let failure = end() { close(); return .failure(failure) }
                continue
            }
            guard data.count < length else { break }
            let want = Int(min(UInt64(length - data.count), file.size - offset))
            let got = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, want, off_t(offset)) }
            guard got > 0 else { close(); return .failure(.changed) }
            data.append(contentsOf: buffer[0..<got])
            hasher.update(data: buffer[0..<got])
            offset += UInt64(got)
        }
        if data.count < length { data.append(Data(count: length - data.count)) }
        produced += UInt64(length)
        return .success((data, digests))
    }

    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }
}

/// A received list, checked and made safe: what will be written where. The
/// one place a hostile list is refused.
struct DeskTreePlan: Equatable {
    struct File: Equatable { let path: [String]; let size: UInt64; let mode: UInt16 }
    struct Link: Equatable { let path: [String]; let target: String }
    /// Parents before what they hold.
    var directories: [[String]]
    /// In stream order.
    var files: [File]
    var links: [Link]
    /// The top-level names, in order: what goes on the clipboard.
    var tops: [String]
    var total: UInt64

    static func make(_ list: DeskTreeList, limits: DeskFileLimits) -> Result<DeskTreePlan, DeskClipboardRefusal> {
        guard !list.entries.isEmpty else { return .failure(.init(.unsupported)) }
        guard list.entries.count <= limits.entries else { return .failure(.init(.tooMany, limit: UInt64(limits.entries))) }
        var original: [[String]: DeskTreeEntry.Kind] = [:]
        var topNames: [String: String] = [:], usedTops: Set<String> = []
        var placed: [[String]: DeskTreeEntry.Kind] = [:]
        var plan = DeskTreePlan(directories: [], files: [], links: [], tops: [], total: 0)
        for entry in list.entries {
            let path = entry.path
            guard !path.isEmpty else { return .failure(.init(.unsafeName)) }
            guard path.count <= limits.depth else { return .failure(.init(.tooDeep, limit: UInt64(limits.depth))) }
            guard original[path] == nil else { return .failure(.init(.unsafeName)) }
            // Everything below the top sits inside a folder named earlier in the
            // list. A file, or a link, can never be a parent: this is what stops
            // "a -> elsewhere" followed by "a/file".
            if path.count > 1 {
                guard original[Array(path.dropLast())] == .directory else { return .failure(.init(.unsafeName)) }
            }
            original[path] = entry.kind
            let top: String
            if path.count == 1 {
                // A link or alias selected directly is never brought over.
                if case .link = entry.kind { return .failure(.init(.links)) }
                guard let safe = DeskFileNames.sanitize(path[0]),
                      let unique = DeskFileNames.candidates(safe).first(where: { !usedTops.contains($0) }) else { return .failure(.init(.unsafeName)) }
                usedTops.insert(unique); topNames[path[0]] = unique; plan.tops.append(unique)
                top = unique
            } else {
                guard let known = topNames[path[0]] else { return .failure(.init(.unsafeName)) }
                top = known
            }
            var safe = [top]
            for name in path.dropFirst() {
                guard let clean = DeskFileNames.sanitizeInner(name) else { return .failure(.init(.unsafeName)) }
                safe.append(clean)
            }
            // Two names that become the same once made safe would overwrite.
            guard placed[safe] == nil else { return .failure(.init(.unsafeName)) }
            switch entry.kind {
            case .directory:
                placed[safe] = .directory; plan.directories.append(safe)
            case .file(let size, let mode):
                guard size <= limits.perFile else { return .failure(.init(.fileTooLarge, amount: size, limit: limits.perFile)) }
                plan.total += size
                guard plan.total <= limits.total else { return .failure(.init(.tooLarge, amount: plan.total, limit: limits.total)) }
                placed[safe] = entry.kind; plan.files.append(.init(path: safe, size: size, mode: mode & 0o777))
            case .link(let target):
                guard !target.isEmpty, !target.hasPrefix("/"), target.utf8.count <= limits.targetBytes else { return .failure(.init(.linkOutside)) }
                var parts: [String] = []
                for part in target.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
                    if part == "." || part == ".." { parts.append(part); continue }
                    guard let clean = DeskFileNames.sanitizeInner(part) else { return .failure(.init(.unsafeName)) }
                    parts.append(clean)
                }
                let safeTarget = parts.joined(separator: "/")
                placed[safe] = .link(target: safeTarget); plan.links.append(.init(path: safe, target: safeTarget))
            }
        }
        // Checked by this Mac, against the copy as it will be written: the
        // other Mac's word that its links stay inside is not taken.
        for link in plan.links where !DeskTreeLinks.resolvesInside(link: link.path, target: link.target, table: placed) {
            return .failure(.init(.linkOutside))
        }
        return .success(plan)
    }
}

/// Writes a planned copy into its staging folder. Every folder and file is
/// reached through file descriptors opened from the staging folder without
/// following links, so no component on the way can be a link, whatever has
/// appeared on disk since; links are created last, after everything else.
/// Used on one serial queue; holds at most one file open, plus the folder it
/// is in, at a time.
final class DeskTreeWriter {
    let root: URL
    let plan: DeskTreePlan
    private var rootFD: Int32 = -1
    private var mark = Data()
    private var index = 0
    private var file: (fd: Int32, parent: Int32, temporary: String, written: UInt64, hasher: SHA256)?
    /// Files whose bytes are all here, waiting for their digest.
    private var arrived: [Int: (digest: Data, temporary: String)] = [:]
    private(set) var verified = 0
    /// The folder the last file was in, kept open for the next one: files
    /// arrive folder by folder, so each folder is reached once, not twice per
    /// file. A descriptor already open stays on the folder this copy created,
    /// whatever is put at its path later.
    private var folder: (path: [String], fd: Int32)?

    /// Opens the staging folder and creates every folder of the plan.
    init(root: URL, plan: DeskTreePlan) throws {
        self.root = root.standardizedFileURL; self.plan = plan
        rootFD = Darwin.open(self.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw DeskClipboardReason.writeFailed }
        // The system's own download mark, made once on this copy's private
        // folder and given to every item through its descriptor.
        try DeskTreeWriter.quarantine(self.root)
        let size = getxattr(self.root.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { throw DeskClipboardReason.quarantine }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(self.root.path, "com.apple.quarantine", &bytes, size, 0, XATTR_NOFOLLOW) == size else { throw DeskClipboardReason.quarantine }
        mark = Data(bytes)
        for folder in plan.directories {
            let parent = try open(Array(folder.dropLast()))
            defer { if parent != rootFD { Darwin.close(parent) } }
            guard mkdirat(parent, folder.last!, 0o755) == 0 else { throw DeskClipboardReason.writeFailed }
            let made = openat(parent, folder.last!, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard made >= 0 else { throw DeskClipboardReason.writeFailed }
            defer { Darwin.close(made) }
            try stamp(made)
        }
        try completeEmpty()
    }
    deinit { close() }

    /// The folder at `path`, reached one name at a time without following links.
    private func open(_ path: [String]) throws -> Int32 {
        var fd = rootFD
        for name in path {
            let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd != rootFD { Darwin.close(fd) }
            guard next >= 0 else { throw errno == ELOOP || errno == ENOTDIR ? DeskClipboardReason.linkOutside : DeskClipboardReason.writeFailed }
            fd = next
        }
        return fd
    }

    /// The folder a file goes in: the root, the one kept open, or reached anew.
    private func parent(_ path: [String]) throws -> Int32 {
        guard !path.isEmpty else { return rootFD }
        if let folder, folder.path == path { return folder.fd }
        if let old = folder { Darwin.close(old.fd); folder = nil }
        let fd = try open(path)
        folder = (path, fd)
        return fd
    }

    private func stamp(_ fd: Int32) throws {
        guard mark.withUnsafeBytes({ fsetxattr(fd, "com.apple.quarantine", $0.baseAddress, mark.count, 0, 0) }) == 0 else { throw DeskClipboardReason.quarantine }
    }

    private func begin() throws {
        let entry = plan.files[index]
        let parent = try self.parent(Array(entry.path.dropLast()))
        let temporary = ".perch-" + UUID().uuidString + ".partial"
        let fd = openat(parent, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DeskClipboardReason.writeFailed }
        file = (fd, parent, temporary, 0, SHA256())
    }

    private func end() {
        guard let current = file else { return }
        Darwin.close(current.fd)
        arrived[index] = (Data(current.hasher.finalize()), current.temporary)
        file = nil
        index += 1
    }

    /// Empty files at the stream's position are complete as soon as it reaches them.
    private func completeEmpty() throws {
        while file == nil, index < plan.files.count, plan.files[index].size == 0 {
            try begin()
            end()
        }
    }

    /// The next bytes of the stream, padding already removed.
    func append(_ data: Data) throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard index < plan.files.count else { throw DeskClipboardReason.corrupt }
            if file == nil { try begin() }
            guard var current = file else { throw DeskClipboardReason.writeFailed }
            let size = plan.files[index].size
            let take = min(data.endIndex - offset, Int(size - current.written))
            let wrote = data[offset..<offset + take].withUnsafeBytes { Darwin.write(current.fd, $0.baseAddress, take) }
            guard wrote == take else { throw DeskClipboardReason.writeFailed }
            current.hasher.update(data: data[offset..<offset + take])
            current.written += UInt64(take)
            offset += take
            file = current
            if current.written == size { end(); try completeEmpty() }
        }
        try completeEmpty()
    }

    /// A file's SHA-256 arrived: check it, then give the file its permission
    /// bits, the download mark and its name, refusing to replace anything.
    func verify(_ fileIndex: Int, digest: Data) throws {
        guard let done = arrived.removeValue(forKey: fileIndex) else { throw DeskClipboardReason.corrupt }
        guard DeskClipboardWire.validMAC(done.digest, digest) else { throw DeskClipboardReason.corrupt }
        let entry = plan.files[fileIndex]
        let parent = try self.parent(Array(entry.path.dropLast()))
        let fd = openat(parent, done.temporary, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DeskClipboardReason.writeFailed }
        // Marked first: once a file is read-only, its mark could not be set.
        let marked = mark.withUnsafeBytes { fsetxattr(fd, "com.apple.quarantine", $0.baseAddress, mark.count, 0, 0) }
        let modeSet = fchmod(fd, mode_t(entry.mode & 0o777))
        Darwin.close(fd)
        guard modeSet == 0 else { throw DeskClipboardReason.writeFailed }
        guard marked == 0 else { throw DeskClipboardReason.quarantine }
        guard renameatx_np(parent, done.temporary, parent, entry.path.last!, UInt32(RENAME_EXCL)) == 0 else { throw DeskClipboardReason.writeFailed }
        verified += 1
    }

    var complete: Bool { index == plan.files.count && verified == plan.files.count && file == nil }

    /// Everything is in place: create the links, last, and say where the copy's
    /// top-level items are.
    func finish() throws -> [URL] {
        guard complete else { throw DeskClipboardReason.corrupt }
        for link in plan.links {
            let parent = try self.parent(Array(link.path.dropLast()))
            guard symlinkat(link.target, parent, link.path.last!) == 0 else { throw DeskClipboardReason.writeFailed }
        }
        return plan.tops.map { root.appendingPathComponent($0) }
    }

    func close() {
        if let current = file { Darwin.close(current.fd); file = nil }
        if let open = folder { Darwin.close(open.fd); folder = nil }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    static func quarantine(_ url: URL) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [kLSQuarantineAgentNameKey as String: "Perch",
                                       kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String]
        var target = url
        try target.setResourceValues(values)
        // The mark is what Gatekeeper reads; a volume that cannot hold it means
        // the copy is not delivered at all.
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

    /// Remove a staged copy, links removed as links. On the disk queue.
    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Forget what is gone.
    func forget(_ ids: Set<UUID>) { for id in ids { leftAt[id] = nil } }
}
