import AppKit
import CryptoKit

/// Files and folders copied on one Mac, brought over to another and pasted
/// there, pinned without Finder: every file operation runs against temporary
/// folders.
func runDeskFileTransferTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func wait(_ what: String, seconds: Double = 8, until predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        guard predicate() else { throw AppError(message: "Files: timed out waiting for " + what) }
    }
    func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    func bytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("perch-file-tests-" + UUID().uuidString).standardizedFileURL
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        // Unreadable fixtures are made readable again so they can be removed.
        if let walker = fm.enumerator(atPath: root.path) { for case let path as String in walker { chmod(root.appendingPathComponent(path).path, 0o755) } }
        try? fm.removeItem(at: root)
    }
    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name).standardizedFileURL
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func put(_ data: Data, _ url: URL, mode: mode_t? = nil) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let mode { chmod(url.path, mode) }
    }
    func listing(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
    func info(_ url: URL) -> stat? { var value = stat(); return lstat(url.path, &value) == 0 ? value : nil }
    func permissions(_ url: URL) -> mode_t? { info(url).map { $0.st_mode & 0o7777 } }
    func isLink(_ url: URL) -> Bool { info(url).map { $0.st_mode & S_IFMT == S_IFLNK } ?? false }
    func isFolder(_ url: URL) -> Bool { info(url).map { $0.st_mode & S_IFMT == S_IFDIR } ?? false }
    func linkTarget(_ url: URL) -> String? { try? fm.destinationOfSymbolicLink(atPath: url.path) }
    /// Whether the item carries a download quarantine mark: "flags;time;agent;id".
    func marked(_ url: URL) -> Bool {
        guard let value = quarantined(url) else { return false }
        let fields = value.split(separator: ";", omittingEmptySubsequences: false)
        return fields.count >= 3 && fields[0].count == 4 && UInt16(fields[0], radix: 16) != nil
    }
    func quarantined(_ url: URL) -> String? {
        let size = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, "com.apple.quarantine", &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
        return String(decoding: buffer, as: UTF8.self)
    }
    func sha(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    let d = { (path: [String]) in DeskTreeEntry(path: path, kind: .directory) }
    let f = { (path: [String], size: UInt64) in DeskTreeEntry(path: path, kind: .file(size: size, mode: 0o644)) }
    let l = { (path: [String], to: String) in DeskTreeEntry(path: path, kind: .link(target: to)) }

    // MARK: Names from another Mac are made safe, or refused

    let names: [(String, String?)] = [
        ("Report.pdf", "Report.pdf"), ("../../etc/passwd", "-..-etc-passwd"), ("/etc/passwd", "-etc-passwd"),
        ("..", nil), (".", nil), ("", nil), ("   ", nil), ("\n", nil), ("...", nil),
        (".hidden", "hidden"), ("..twice", "twice"), (" .spaced ", "spaced"), ("a/b", "a-b"), ("colon:name", "colon-name"),
        ("nul\u{0}byte", "nul-byte"), ("bell\u{7}", "bell-"), ("line\u{2028}break", "line-break"),
        ("invoice\u{202E}fdp.exe", "invoice-fdp.exe"), ("e\u{301}te\u{301}.txt", "\u{e9}t\u{e9}.txt"),
        (String(repeating: "a", count: 240), String(repeating: "a", count: 240)), (String(repeating: "a", count: 241), nil),
        (String(repeating: "\u{e9}", count: 121), nil)]
    for (raw, expected) in names {
        let safe = DeskFileNames.sanitize(raw)
        try check(safe == expected, "The received name \(raw.debugDescription) became \(String(describing: safe)), not \(String(describing: expected))")
        if let safe {
            try check(!safe.contains("/") && !safe.hasPrefix(".") && safe != ".." && safe.utf8.count <= DeskFileNames.maximumLength,
                      "A made-safe name is still unsafe: \(safe.debugDescription)")
            let destination = root.appendingPathComponent(safe).standardizedFileURL
            try check(destination.deletingLastPathComponent().path == root.path, "A received name reached outside its folder: \(safe.debugDescription)")
        }
    }
    // Inside a copied folder a leading dot is part of what was copied (".git"),
    // but "." and ".." are never names.
    let innerNames: [(String, String?)] = [(".git", ".git"), (".gitignore", ".gitignore"), ("..", nil), (".", nil), ("", nil),
                                           ("a/b", "a-b"), ("../x", "..-x"), ("...", "..."), ("tab\tname", "tab-name"), ("rtl\u{202E}", "rtl-")]
    for (raw, expected) in innerNames {
        let safe = DeskFileNames.sanitizeInner(raw)
        try check(safe == expected, "The received inner name \(raw.debugDescription) became \(String(describing: safe)), not \(String(describing: expected))")
    }
    try check(DeskFileNames.candidates("Report.pdf", limit: 3) == ["Report.pdf", "Report 2.pdf", "Report 3.pdf"] &&
              DeskFileNames.candidates("Makefile", limit: 2) == ["Makefile", "Makefile 2"], "Collision names moved")
    print("PASS: shared files make every received name safe: slashes, colons, controls and direction overrides replaced, leading dots refused at the top but kept inside folders, \".\" and \"..\" and empty or overlong names refused, nothing lands outside its folder")

    // MARK: The list on the wire

    let limits = DeskFileLimits()
    let sample = DeskTreeList(entries: [
        d(["Project"]), d(["Project", "empty"]), .init(path: ["Project", "run.sh"], kind: .file(size: 12, mode: 0o755)),
        l(["Project", "latest"], "run.sh"), f(["Notes.txt"], 0)])
    try check(try DeskTreeList.decode(sample.encoded(), limits: limits) == sample, "A list of files and folders did not survive the wire")
    try check(sample.descriptor == .init(kind: .folders, count: 2, small: false, size: DeskClipboardPolicy.sizeIndex(12)) && sample.total == 12 && sample.fileCount == 2,
              "A copy holding a folder was not described as two items with folders: \(sample.descriptor)")
    try check(DeskTreeList(entries: [f(["a"], 1), f(["b"], 1)]).descriptor.kind == .files, "A copy of files only was described as folders")
    func declines(_ list: DeskTreeList, _ limits: DeskFileLimits, _ reason: DeskClipboardReason, _ label: String) throws {
        do { _ = try DeskTreeList.decode(list.encoded(), limits: limits); throw AppError(message: "\(label) was accepted") }
        catch let declined as DeskClipboardReason { try check(declined == reason, "\(label) was declined as \(declined), not \(reason)") }
    }
    var few = limits; few.entries = 4
    try declines(sample, few, .tooMany, "A list over the item limit")
    var shallow = limits; shallow.depth = 1
    try declines(sample, shallow, .tooDeep, "A list over the depth limit")
    var smallFile = limits; smallFile.perFile = 11
    try declines(sample, smallFile, .fileTooLarge, "A list with a file over the per-file limit")
    var smallTotal = limits; smallTotal.total = 11
    try declines(DeskTreeList(entries: [f(["a"], 6), f(["b"], 6)]), smallTotal, .tooLarge, "A list over the total limit")
    try check((try? DeskTreeList.decode(sample.encoded() + Data([0]), limits: limits)) == nil, "Trailing bytes after a list were accepted")
    try check((try? DeskTreeList.decode(DeskTreeList(entries: []).encoded(), limits: limits)) == nil, "An empty list was accepted")
    try check((try? DeskTreeList.decode(DeskTreeList(entries: [.init(path: ["x"], kind: .file(size: 1, mode: 0o4755))]).encoded(), limits: limits)) == nil,
              "A setuid mode was accepted from the wire")
    try check((try? DeskTreeList.decode(DeskTreeList(entries: [.init(path: [], kind: .directory)]).encoded(), limits: limits)) == nil, "An empty path was accepted")
    print("PASS: shared files' list survives the wire and declines, by name, more than 10,000 items, more than 32 levels, a file over 1 GB, more than 2 GB in all, trailing bytes, empty lists and paths, and setuid modes")

    // MARK: Where links lead, worked out within the copy alone

    let table: [[String]: DeskTreeEntry.Kind] = [
        ["P"]: .directory, ["P", "bin"]: .directory, ["P", "bin", "tool"]: .file(size: 1, mode: 0o755), ["P", "lib"]: .directory,
        ["P", "lib", "current"]: .link(target: "../bin"), ["P", "loop"]: .link(target: "loop2"), ["P", "loop2"]: .link(target: "loop"),
        ["P", "out"]: .link(target: "../Q")]
    let inside: [([String], String)] = [(["P", "lib", "x"], "../bin/tool"), (["P", "x"], "lib/current/tool"), (["P", "x"], "bin"),
                                        (["P", "x"], "./bin/./tool"), (["P", "lib", "x"], ".."), (["P", "x"], "bin//tool")]
    let outside: [([String], String, String)] = [
        (["P", "x"], "../Q", "climbs above its top folder"), (["P", "lib", "x"], "../../etc", "climbs two levels out"),
        (["P", "x"], "/etc/passwd", "is absolute"), (["P", "x"], "missing", "leads nowhere"), (["P", "x"], "bin/tool/more", "goes through a file"),
        (["P", "x"], "loop", "loops"), (["P", "x"], "out", "leads through a link that climbs out"), (["P"], "bin", "is the top-level item"),
        (["P", "x"], "", "is empty"), (["P", "x"], "../P/bin", "climbs out and back")]
    for (path, to) in inside {
        try check(DeskTreeLinks.resolvesInside(link: path, target: to, table: table), "A link to \(to) inside the copy was refused")
    }
    for (path, to, why) in outside {
        try check(!DeskTreeLinks.resolvesInside(link: path, target: to, table: table), "A link that \(why) (\(to)) was taken to stay inside")
    }
    print("PASS: shared files keep a link only when, within the copy itself, it resolves to something inside its own top folder: absolute links, climbing out, leading nowhere, through a file, loops and links leading out are refused")

    // MARK: The sending Mac: what it sends, never following a link

    let source = try folder("source")
    let project = source.appendingPathComponent("Project")
    let toolBytes = Data("#!/bin/sh\necho hi\n".utf8)
    try put(Data("ref: refs/heads/main".utf8), project.appendingPathComponent(".git/HEAD"))
    try put(toolBytes, project.appendingPathComponent("bin/tool"), mode: 0o755)
    try put(Data("read me".utf8), project.appendingPathComponent("docs/readme.txt"))
    try fm.createDirectory(at: project.appendingPathComponent("docs/empty"), withIntermediateDirectories: true)
    try fm.createSymbolicLink(atPath: project.appendingPathComponent("current").path, withDestinationPath: "bin")
    try URL.writeBookmarkData(try project.appendingPathComponent("docs/readme.txt").bookmarkData(options: .suitableForBookmarkFile),
                              to: project.appendingPathComponent("Readme alias"))
    // A setuid bit on the sender is never carried.
    let setuid = chmod(project.appendingPathComponent("bin/tool").path, 0o4755) == 0 && (permissions(project.appendingPathComponent("bin/tool")) ?? 0) & 0o4000 != 0
    let secret = try folder("outside")
    try put(Data("outside the copy".utf8), secret.appendingPathComponent("secret.txt"))
    guard case .success(let examined) = DeskSourceTree.examine([project], limits: limits) else { throw AppError(message: "A plain project folder was not accepted for sending") }
    let paths = examined.list.entries.map { $0.path.joined(separator: "/") }
    try check(Set(paths) == ["Project", "Project/.git", "Project/.git/HEAD", "Project/Readme alias", "Project/bin", "Project/bin/tool", "Project/current",
                             "Project/docs", "Project/docs/empty", "Project/docs/readme.txt"],
              "The project was not listed exactly, hidden files and empty folders included: \(paths.sorted())")
    for (index, entry) in examined.list.entries.enumerated() where entry.path.count > 1 {
        try check(examined.list.entries[..<index].contains { $0.path == Array(entry.path.dropLast()) && $0.kind == .directory },
                  "\(entry.path.joined(separator: "/")) was listed before its folder")
    }
    try check(!paths.contains { $0.hasPrefix("Project/current/") }, "A link inside the copy was followed on the sending Mac")
    try check(examined.list.entries.first { $0.path == ["Project", "current"] }?.kind == .link(target: "bin"), "A relative link inside the copy was not kept as a link")
    try check(examined.list.entries.first { $0.path == ["Project", "bin", "tool"] }?.kind == .file(size: UInt64(toolBytes.count), mode: 0o755),
              "An executable lost its permission bits, or kept setuid (set on the fixture: \(setuid))")
    try check(examined.files.count == 4 && examined.total == examined.files.reduce(0) { $0 + $1.size }, "The files to stream do not match the list")
    // Refused by name, before anything is sent.
    func refuses(_ urls: [URL], _ reason: DeskClipboardReason, limits: DeskFileLimits = DeskFileLimits(), amount: UInt64? = nil, limit: UInt64? = nil,
                 _ label: String) throws {
        switch DeskSourceTree.examine(urls, limits: limits) {
        case .success: throw AppError(message: "\(label) was accepted for sending")
        case .failure(let refusal):
            try check(refusal.reason == reason, "\(label) was refused as \(refusal.reason), not \(reason)")
            if let amount { try check(refusal.amount == amount, "\(label) was refused with \(String(describing: refusal.amount)), not \(amount)") }
            if let limit { try check(refusal.limit == limit, "\(label) was refused with the limit \(String(describing: refusal.limit)), not \(limit)") }
        }
    }
    func variant(_ name: String, _ make: (URL) throws -> Void) throws -> URL {
        let top = source.appendingPathComponent(name)
        try put(Data("x".utf8), top.appendingPathComponent("file.txt"))
        try make(top)
        return top
    }
    try refuses([try variant("Escapes") { try fm.createSymbolicLink(atPath: $0.appendingPathComponent("escape").path, withDestinationPath: "../outside") }],
                .linkOutside, "A folder holding a link that climbs out of it")
    try refuses([try variant("Absolute") { try fm.createSymbolicLink(atPath: $0.appendingPathComponent("abs").path, withDestinationPath: secret.path) }],
                .linkOutside, "A folder holding an absolute link")
    try refuses([try variant("Dangling") { try fm.createSymbolicLink(atPath: $0.appendingPathComponent("gone").path, withDestinationPath: "nowhere") }],
                .linkOutside, "A folder holding a link to nothing")
    let topLink = source.appendingPathComponent("Top link")
    try fm.createSymbolicLink(atPath: topLink.path, withDestinationPath: project.path)
    try refuses([topLink], .links, "A link selected directly")
    let topAlias = source.appendingPathComponent("Top alias")
    try URL.writeBookmarkData(try project.bookmarkData(options: .suitableForBookmarkFile), to: topAlias)
    try refuses([topAlias], .links, "An alias selected directly")
    try refuses([try variant("Pipe") { _ = mkfifo($0.appendingPathComponent("pipe").path, 0o644) }], .unsupported, "A folder holding a named pipe")
    try refuses([try variant("Locked") { try put(Data("x".utf8), $0.appendingPathComponent("locked.txt"), mode: 0o000) }], .unreadable, "A folder holding an unreadable file")
    try refuses([source.appendingPathComponent("missing")], .unreadable, "A missing item")
    var three = limits; three.entries = 3
    try refuses([project], .tooMany, limits: three, limit: 3, "More items than the limit")
    var two = limits; two.depth = 2
    try refuses([project], .tooDeep, limits: two, limit: 2, "Folders deeper than the limit")
    var tiny = limits; tiny.perFile = 10
    try refuses([try variant("Big") { try put(bytes(100), $0.appendingPathComponent("big.bin")) }], .fileTooLarge, limits: tiny, amount: 100, limit: 10,
                "A file over the per-file limit")
    var little = limits; little.total = 20
    try refuses([project], .tooLarge, limits: little, amount: examined.total, limit: 20, "More than the total limit")
    // Two selected items with one name keep both, under distinct names.
    let twin = try folder("twin/Project")
    try put(Data("twin".utf8), twin.appendingPathComponent("a.txt"))
    guard case .success(let twins) = DeskSourceTree.examine([project, twin], limits: limits) else { throw AppError(message: "Two folders with one name were refused") }
    try check(twins.list.entries.filter { $0.path.count == 1 }.map { $0.path[0] } == ["Project", "Project 2"], "Two selected items with one name were merged")
    print("PASS: shared files examine a folder without following any link: hidden files, empty folders, executables (never setuid) and inner relative links kept; links leading out, absolute or nowhere, a selected link or alias, pipes, unreadable files and more than the limits refused by name with the amount over")

    // MARK: The sending Mac: the stream of the files' contents

    let streamed = try folder("streamed/Stream")
    let parts = [Data(), bytes(100), bytes(DeskClipboardWire.chunkSize), bytes(150_000), Data()]
    for (index, part) in parts.enumerated() { try put(part, streamed.appendingPathComponent("f\(index)")) }
    guard case .success(let streamTree) = DeskSourceTree.examine([streamed], limits: limits) else { throw AppError(message: "The stream fixture was refused") }
    let padded = UInt64(DeskClipboardWire.bucket(Int(streamTree.total)))
    let reader = DeskTreeReader(streamTree, padded: padded)
    var stream = Data(), digests: [(chunk: Int, index: UInt32, digest: Data)] = [], chunk = 0
    while UInt64(stream.count) < padded {
        guard case .success(let next) = reader.next() else { throw AppError(message: "An unchanged file stopped the stream") }
        try check(next.data.count == min(DeskClipboardWire.chunkSize, Int(padded) - stream.count), "A chunk of the stream had the wrong length")
        stream.append(next.data)
        digests += next.digests.map { (chunk, $0.index, $0.digest) }
        chunk += 1
    }
    let joined = parts.reduce(Data(), +)
    try check(stream.prefix(joined.count) == joined && stream.dropFirst(joined.count).allSatisfy { $0 == 0 }, "The stream is not the files' contents, then zeros")
    try check(digests.map(\.index) == [0, 1, 2, 3, 4] && zip(digests, parts).allSatisfy { $0.digest == sha($1) }, "A file's digest was missing, wrong or out of order")
    var end = 0
    for (index, part) in parts.enumerated() {
        // An empty file is complete where the stream reaches it.
        end += part.count
        try check(digests[index].chunk == max(0, end - 1) / DeskClipboardWire.chunkSize, "File \(index)'s digest did not follow the chunk holding its last byte")
    }
    guard case .failure = reader.next() else { throw AppError(message: "The stream went on past its end") }
    // Changed, or swapped for a link, since it was examined: the stream stops.
    let changing = DeskTreeReader(streamTree, padded: padded)
    try put(bytes(100), streamed.appendingPathComponent("f1"))
    guard case .failure(.changed) = changing.next() else { throw AppError(message: "A file changed since it was examined was sent") }
    try fm.removeItem(at: streamed.appendingPathComponent("f1"))
    try fm.createSymbolicLink(atPath: streamed.appendingPathComponent("f1").path, withDestinationPath: secret.appendingPathComponent("secret.txt").path)
    let swapped = DeskTreeReader(streamTree, padded: padded)
    switch swapped.next() {
    case .failure(.links), .failure(.changed): break
    default: throw AppError(message: "A file swapped for a link since it was examined was read through the link")
    }
    print("PASS: shared files stream every file's bytes in list order, a chunk at a time, each file's digest right after the chunk with its last byte, and stop when a file changes or is swapped for a link")

    // MARK: The receiving Mac: a hostile list is refused before anything is written

    func plan(_ entries: [DeskTreeEntry], _ limits: DeskFileLimits = DeskFileLimits()) -> Result<DeskTreePlan, DeskClipboardRefusal> {
        DeskTreePlan.make(DeskTreeList(entries: entries), limits: limits)
    }
    let hostile: [(String, [DeskTreeEntry], DeskClipboardReason)] = [
        // The tar attack, both ways: a link, then a file written through it.
        ("an absolute link, then a file through it", [d(["P"]), l(["P", "a"], "/Users/x/.ssh"), f(["P", "a", "authorized_keys"], 10)], .linkOutside),
        ("a link inside, then a file through it", [d(["P"]), d(["P", "sub"]), l(["P", "a"], "sub"), f(["P", "a", "authorized_keys"], 10)], .unsafeName),
        ("a file through a file", [d(["P"]), f(["P", "x"], 1), f(["P", "x", "y"], 1)], .unsafeName),
        ("a folder that was never listed", [d(["P"]), f(["P", "missing", "x"], 1)], .unsafeName),
        ("a file before its folder", [f(["P", "x"], 1), d(["P"])], .unsafeName),
        ("a climb by name", [d(["P"]), d(["P", ".."]), f(["P", "..", "x"], 1)], .unsafeName),
        ("a dot by name", [d(["P"]), d(["P", "."])], .unsafeName),
        ("an empty name", [d(["P"]), f(["P", ""], 1)], .unsafeName),
        ("two names that become one", [d(["P"]), f(["P", "a:b"], 1), f(["P", "a-b"], 1)], .unsafeName),
        ("the same path twice", [d(["P"]), f(["P", "x"], 1), f(["P", "x"], 1)], .unsafeName),
        ("an absolute link", [d(["P"]), l(["P", "a"], "/etc")], .linkOutside),
        ("a link climbing out", [d(["P"]), d(["P", "q"]), l(["P", "q", "a"], "../../x")], .linkOutside),
        ("a link to nothing", [d(["P"]), l(["P", "a"], "nowhere")], .linkOutside),
        ("a link selected directly", [l(["a"], "b")], .links),
        ("a file over the per-file limit", [f(["big"], limits.perFile + 1)], .fileTooLarge),
        ("more than the total", [f(["a"], limits.perFile), f(["b"], limits.perFile), f(["c"], 1)], .tooLarge),
        ("too deep", (1...33).map { depth in d((0..<depth).map { "d\($0)" }) }, .tooDeep)]
    for (label, entries, reason) in hostile {
        guard case .failure(let refusal) = plan(entries) else { throw AppError(message: "A hostile list was accepted: \(label)") }
        try check(refusal.reason == reason, "A hostile list (\(label)) was refused as \(refusal.reason), not \(reason)")
    }
    var twoItems = limits; twoItems.entries = 2
    guard case .failure(let crowd) = plan([d(["P"]), f(["P", "a"], 1), f(["P", "b"], 1)], twoItems), crowd.reason == .tooMany else {
        throw AppError(message: "A list over this Mac's item limit was accepted")
    }
    // Accepted lists are made safe exactly.
    guard case .success(let safe) = plan([f([".bashrc"], 3), f(["bashrc"], 4), d(["P"]), f(["P", "../../etc/passwd"], 5), d(["P", "sub"]), f(["P", "sub", "x"], 6),
                                          l(["P", "cur"], "sub"), l(["P", "y"], "cur/x"), d(["P", "sub:dir"]), l(["P", "z"], "sub:dir")]) else {
        throw AppError(message: "A safe list was refused")
    }
    try check(safe.tops == ["bashrc", "bashrc 2", "P"], "Top-level names were not made safe and distinct: \(safe.tops)")
    try check(safe.files.map { $0.path.joined(separator: "/") } == ["bashrc", "bashrc 2", "P/..-..-etc-passwd", "P/sub/x"], "Inner names were not made safe: \(safe.files)")
    try check(safe.directories == [["P"], ["P", "sub"], ["P", "sub-dir"]] && safe.total == 18, "Folders or the total moved: \(safe.directories)")
    try check(safe.links == [.init(path: ["P", "cur"], target: "sub"), .init(path: ["P", "y"], target: "cur/x"), .init(path: ["P", "z"], target: "sub-dir")],
              "Links were not kept, or their targets not made safe like the names they lead to: \(safe.links)")
    print("PASS: shared files refuse a hostile list before writing anything: a file through a link (the tar attack, absolute or inside), through a file or an unlisted folder, out of order, \".\", \"..\", empty, colliding or repeated names, links leading out or nowhere, a selected link, and anything over the limits; safe lists are made safe exactly")

    // MARK: The receiving Mac: writing a copy

    let writing = DeskFileStaging(root: root.appendingPathComponent("writing"))
    let photo = bytes(90_000), script = Data("#!/bin/sh\n".utf8), note = bytes(3000)
    let album = DeskTreeList(entries: [
        d(["Album"]), d(["Album", ".hidden"]), d(["Album", "empty"]), d(["Album", "sub"]),
        .init(path: ["Album", "sub", "photo.jpg"], kind: .file(size: UInt64(photo.count), mode: 0o644)),
        .init(path: ["Album", "run.sh"], kind: .file(size: UInt64(script.count), mode: 0o755)),
        .init(path: ["Album", "zero"], kind: .file(size: 0, mode: 0o600)),
        .init(path: ["Album", "readonly"], kind: .file(size: 1, mode: 0o444)),
        l(["Album", "latest"], "sub/photo.jpg"), f(["Notes.txt"], UInt64(note.count))])
    let contents = [photo, script, Data(), Data("r".utf8), note]
    guard case .success(let albumPlan) = DeskTreePlan.make(album, limits: limits) else { throw AppError(message: "A safe album was refused") }
    func write(_ plan: DeskTreePlan, _ contents: [Data], piece: Int = 7000, digests: [Data]? = nil) throws -> (id: UUID, urls: [URL]) {
        let id = UUID()
        try writing.prepare(id)
        let writer = try DeskTreeWriter(root: writing.folder(id), plan: plan)
        defer { writer.close() }
        let all = contents.reduce(Data(), +)
        var offset = 0
        while offset < all.count { let next = min(all.count, offset + piece); try writer.append(all[offset..<next]); offset = next }
        for (index, content) in contents.enumerated() { try writer.verify(index, digest: digests?[index] ?? sha(content)) }
        try check(plan.links.allSatisfy { !isLink(writing.folder(id).appendingPathComponent($0.path.joined(separator: "/"))) }, "A link was created before every file was in place")
        return (id, try writer.finish())
    }
    let written = try write(albumPlan, contents)
    let base = writing.folder(written.id)
    try check(written.urls == [base.appendingPathComponent("Album"), base.appendingPathComponent("Notes.txt")], "The copy's top-level items are not what goes on the clipboard: \(written.urls)")
    let albumURL = base.appendingPathComponent("Album")
    try check(listing(albumURL) == [".hidden", "empty", "latest", "readonly", "run.sh", "sub", "zero"] && isFolder(albumURL.appendingPathComponent("empty")) &&
              isFolder(albumURL.appendingPathComponent(".hidden")), "The folder's shape, empty and hidden folders included, was not kept: \(listing(albumURL))")
    try check((try Data(contentsOf: albumURL.appendingPathComponent("sub/photo.jpg"))) == photo && (try Data(contentsOf: base.appendingPathComponent("Notes.txt"))) == note &&
              (try Data(contentsOf: albumURL.appendingPathComponent("zero"))).isEmpty, "Files did not arrive whole")
    try check(permissions(albumURL.appendingPathComponent("run.sh")) == 0o755 && permissions(albumURL.appendingPathComponent("zero")) == 0o600 &&
              permissions(albumURL.appendingPathComponent("readonly")) == 0o444, "Permission bits were not kept")
    try check(isLink(albumURL.appendingPathComponent("latest")) && linkTarget(albumURL.appendingPathComponent("latest")) == "sub/photo.jpg", "A link inside the copy was not recreated as a link")
    for item in ["Album", "Album/.hidden", "Album/empty", "Album/sub", "Album/sub/photo.jpg", "Album/run.sh", "Album/zero", "Album/readonly", "Notes.txt"] {
        try check(marked(base.appendingPathComponent(item)), "\(item) was not marked as downloaded: \(String(describing: quarantined(base.appendingPathComponent(item))))")
    }
    try check(!(fm.enumerator(atPath: base.path)?.allObjects as? [String] ?? []).contains { $0.contains(".perch-") }, "A partial file was left behind")
    // A wrong digest, too many bytes, or too few: never complete.
    func failsToWrite(_ label: String, _ body: () throws -> Void) throws {
        do { try body(); throw AppError(message: "\(label) was written") }
        catch let reason as DeskClipboardReason { try check(reason == .corrupt, "\(label) failed as \(reason), not as damaged") }
    }
    try failsToWrite("A file with the wrong digest") { _ = try write(albumPlan, contents, digests: contents.map { _ in Data(repeating: 0, count: 32) }) }
    try failsToWrite("More bytes than listed") { _ = try write(albumPlan, contents + [Data([1])]) }
    try failsToWrite("Fewer bytes than listed") { _ = try write(albumPlan, [photo]) }
    // A link planted on disk where a listed folder is, after the folders were
    // created: the file is never written through it.
    let target = try folder("planted-target")
    guard case .success(let nested) = DeskTreePlan.make(DeskTreeList(entries: [d(["P"]), d(["P", "a"]), f(["P", "a", "authorized_keys"], 10)]), limits: limits) else {
        throw AppError(message: "The planted-link fixture was refused")
    }
    let plantedID = UUID()
    try writing.prepare(plantedID)
    let planted = try DeskTreeWriter(root: writing.folder(plantedID), plan: nested)
    let plantedAt = writing.folder(plantedID).appendingPathComponent("P/a")
    try fm.removeItem(at: plantedAt)
    try fm.createSymbolicLink(atPath: plantedAt.path, withDestinationPath: target.path)
    let wroteThrough: Bool
    do { try planted.append(Data(repeating: 65, count: 10)); try planted.verify(0, digest: sha(Data(repeating: 65, count: 10))); wroteThrough = true }
    catch { wroteThrough = false }
    planted.close()
    try check(!wroteThrough && listing(target).isEmpty, "A file was written through a link planted in the staging folder: \(listing(target))")
    print("PASS: shared files write a copy whole: its shape, empty and hidden folders, contents, permission bits and links kept, every file and folder marked as downloaded, links created last, nothing partial left; a wrong digest or length never completes, and no file is ever written through a link planted where a folder was")

    // MARK: Received files go on the pasteboard as files

    // Plain file URLs, which every app reads as files, on a private pasteboard.
    let fileBoard = NSPasteboard(name: NSPasteboard.Name("local.scott.perch.selftest.files." + UUID().uuidString))
    defer { fileBoard.releaseGlobally() }
    try check(fileBoard.name != .general, "The file pasteboard test must use a private pasteboard")
    let onBoard = try folder("on-board")
    let first = onBoard.appendingPathComponent("One.txt"), second = onBoard.appendingPathComponent("Two")
    try Data("1".utf8).write(to: first); try fm.createDirectory(at: second, withIntermediateDirectories: true)
    let fileStore = SystemDeskPasteboard(fileBoard)
    _ = fileStore.replace(with: [[(type: DeskClipboardMarker.fileURL, data: first.dataRepresentation)], [(type: DeskClipboardMarker.fileURL, data: second.dataRepresentation)]])
    let read = fileBoard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    try check(read.map(\.standardizedFileURL) == [first, second].map(\.standardizedFileURL), "Received files and folders were not readable as files: \(read)")
    try check(DeskClipboardPolicy.assess(fileStore.itemTypes()) == .files, "Received files would not be shared on in turn")
    print("PASS: shared files and folders go on the pasteboard as plain file URLs that apps read as files, on a private pasteboard")

    // MARK: Staged files: when they are removed

    let rule = DeskFileStaging.removable
    let (kept, left, orphan, active) = (UUID(), UUID(), UUID(), UUID())
    let present: Set<UUID> = [kept, left, orphan, active]
    try check(rule(present, kept, active, [left: 100], 100 + DeskFileStaging.grace - 1) == [orphan],
              "Rule: only a copy found with no record may go at once")
    try check(rule(present, kept, active, [left: 100], 100 + DeskFileStaging.grace) == [orphan, left],
              "Rule: a copy that left the clipboard did not go after ten minutes")
    try check(!rule(present, kept, nil, [kept: 0], 1_000_000).contains(kept), "Rule: the copy on the clipboard was removed")
    try check(!rule(present, nil, active, [:], 1_000_000).contains(active), "Rule: the copy on its way here was removed")
    do {
        let staging = DeskFileStaging(root: root.appendingPathComponent("staging-rule"))
        let first = UUID(), second = UUID(), stray = UUID()
        for id in [first, second, stray] { try staging.prepare(id); try Data("x".utf8).write(to: staging.folder(id).appendingPathComponent("f")) }
        try fm.createDirectory(at: staging.root.appendingPathComponent("not a copy"), withIntermediateDirectories: true)
        // A staged folder holding a link is removed as a link, never through it.
        let kept = try folder("kept-outside")
        try put(Data("keep".utf8), kept.appendingPathComponent("keep.txt"))
        try fm.createSymbolicLink(atPath: staging.folder(stray).appendingPathComponent("link").path, withDestinationPath: kept.path)
        try check(staging.present() == [first, second, stray], "Staged copies were not listed exactly: \(staging.present())")
        try check((try? staging.prepare(first)) == nil, "A staging folder was reused rather than refused")
        try check((try fm.attributesOfItem(atPath: staging.folder(first).path)[.posixPermissions] as? NSNumber)?.intValue == 0o700, "A staging folder is not private")
        staging.placed(first, changeCount: 5, now: 10)
        staging.placed(second, changeCount: 6, now: 20)
        try check(staging.onClipboard?.id == second && staging.leftAt[first] == 20, "Replacing the staged copy on the clipboard did not start the first one's ten minutes")
        staging.clipboardChanged(to: 6, now: 30)
        try check(staging.onClipboard?.id == second, "An unchanged clipboard let its staged copy go")
        staging.clipboardChanged(to: 7, now: 40)
        try check(staging.onClipboard == nil && staging.leftAt[second] == 40, "Copying something else did not start the staged copy's ten minutes")
        let gone = DeskFileStaging.removable(present: staging.present(), onClipboard: nil, active: nil, leftAt: staging.leftAt, now: 20 + DeskFileStaging.grace)
        try check(gone == [first, stray], "The wrong staged copies were due: \(gone)")
        gone.forEach(staging.remove)
        try check(staging.present() == [second] && listing(staging.root).contains("not a copy"), "Removing staged copies took the wrong folders")
        try check(listing(kept) == ["keep.txt"], "Removing a staged copy followed a link inside it")
        // At start, a staged copy the clipboard still lists is kept, the rest go.
        let restarted = DeskFileStaging(root: staging.root)
        restarted.adopt([staging.folder(second).appendingPathComponent("f")], changeCount: 9)
        try check(restarted.onClipboard?.id == second && restarted.onClipboard?.changeCount == 9, "A staged copy still on the clipboard was not kept at start")
        let other = DeskFileStaging(root: staging.root)
        other.adopt([root.appendingPathComponent("elsewhere/f")], changeCount: 9)
        try check(other.onClipboard == nil, "A file outside staging was taken for a staged copy")
    }
    print("PASS: shared files' staging rule: failed copies go at once, the copy on the clipboard stays, one that left the clipboard goes ten minutes later, strays go at start, only Perch's own private folders are ever removed, and links inside are removed as links")

    // MARK: End to end: brought over into staging, then pasted as files

    let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio"])
    let a = desk.macs[0], b = desk.macs[1]
    desk.start()
    defer { desk.stop() }
    try wait("greeting") { desk.greeted() }
    let staged = b.clipboard.staging
    let photos = try folder("photos")
    let big = bytes(700_000), secretName = "CANARY-\(UUID().uuidString.prefix(8)).jpg"
    try big.write(to: photos.appendingPathComponent(secretName))
    try Data().write(to: photos.appendingPathComponent(".empty-marker"))
    func copyFiles(_ urls: [URL], text: String? = nil) {
        a.store.copy(urls.map { url in [(type: DeskClipboardMarker.fileURL, data: url.dataRepresentation)] + (text.map { [(type: "public.utf8-plain-text", data: Data($0.utf8))] } ?? []) })
    }
    /// A copy of files announced on the MacBook; wait until the Studio knows
    /// of that copy, not an earlier one still waiting.
    var known: UUID?
    func announced(_ label: String, kind: DeskClipboardDescriptor.Kind = .files) throws {
        try wait(label) { b.clipboard.waiting?.what.kind == kind && b.clipboard.waiting?.copy != known }
        known = b.clipboard.waiting?.copy
    }
    /// Bring it over on the Studio, and wait for the popup to end.
    func bring(_ label: String) throws -> DeskPasteProgress {
        let shown = b.fakes.presented.count
        b.clipboard.bringOverHere()
        try wait(label) { b.fakes.presented.count > shown && b.fakes.last?.phase != .moving }
        return b.fakes.last!
    }
    copyFiles([photos.appendingPathComponent(secretName), photos.appendingPathComponent(".empty-marker")], text: secretName)
    try announced("files announced")
    try check(b.clipboard.waiting?.what.count == 2 && b.link.count(DeskClipboardTests.isFetch) == 0, "Files were fetched before being brought over")
    var gap = 0.0, progress: [Double] = []
    do {
        var last = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in let now = ProcessInfo.processInfo.systemUptime; gap = max(gap, now - last); last = now }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        a.link.chunkDelay = 0.05
        b.clipboard.bringOverHere()
        try wait("files arrive") {
            if let value = b.clipboard.bringOverProgress { progress.append(value) }
            return b.fakes.last?.phase == .done
        }
        a.link.chunkDelay = 0
    }
    try check(gap < 0.3, "Bringing files over stalled the main thread for \(gap) s")
    try check(progress.contains { $0 > 0 && $0 < 1 }, "Files on their way showed no progress")
    try check(b.fakes.last?.title == "2 files from MacBook", "The popup said \(b.fakes.last?.title ?? "nothing")")
    let brought = b.store.files
    try check(brought.map(\.lastPathComponent) == [secretName, "empty-marker"], "The pasteboard does not hold the files that arrived: \(brought)")
    try check(brought.allSatisfy { $0.standardizedFileURL.path.hasPrefix(staged.root.path + "/") }, "Files were not staged in Perch's own folder: \(brought)")
    try check(b.store.current.allSatisfy { $0.map(\.type) == [DeskClipboardMarker.fileURL, DeskClipboardMarker.received] },
              "A file's name or icon was pasted beside it, or the files were not marked as received")
    try check((try Data(contentsOf: brought[0])) == big && (try Data(contentsOf: brought[1])).isEmpty, "Files did not arrive whole")
    try check(marked(brought[0]) && marked(brought[1]), "Received files were not marked as downloaded")
    try check(listing(brought[0].deletingLastPathComponent()) == [secretName, "empty-marker"].sorted(), "Something besides the files was left in staging")
    try check(staged.onClipboard != nil && staged.present().count == 1, "The staged copy on the clipboard is not the one recorded")
    try check(b.clipboard.waiting == nil, "What was waiting stayed after the files came")
    // Received files are never announced back.
    settle(0.3)
    try check(b.link.count(DeskClipboardTests.isCopied) == 0, "Received files were announced again")
    // A folder keeps its shape.
    let trip = photos.appendingPathComponent("Trip")
    let day1 = bytes(200_000)
    try put(day1, trip.appendingPathComponent("Day 1/IMG_0001.jpg"))
    try put(Data("#!/bin/sh\n".utf8), trip.appendingPathComponent("tools/resize.sh"), mode: 0o755)
    try fm.createDirectory(at: trip.appendingPathComponent("Day 2"), withIntermediateDirectories: true)
    try put(Data("x".utf8), trip.appendingPathComponent(".DS_Store"))
    try fm.createSymbolicLink(atPath: trip.appendingPathComponent("first").path, withDestinationPath: "Day 1/IMG_0001.jpg")
    copyFiles([trip])
    try announced("folder announced", kind: .folders)
    let folderPopup = try bring("folder")
    try check(folderPopup.phase == .done && folderPopup.title == "A folder from MacBook", "The folder's popup said \(folderPopup.title), \(folderPopup.line ?? "")")
    let tripHere = b.store.files
    try check(tripHere.map(\.lastPathComponent) == ["Trip"] && isFolder(tripHere[0]), "The folder did not arrive as one folder: \(tripHere)")
    try check(listing(tripHere[0]) == [".DS_Store", "Day 1", "Day 2", "first", "tools"] && listing(tripHere[0].appendingPathComponent("Day 2")).isEmpty &&
              (try Data(contentsOf: tripHere[0].appendingPathComponent("Day 1/IMG_0001.jpg"))) == day1 &&
              permissions(tripHere[0].appendingPathComponent("tools/resize.sh")) == 0o755 &&
              linkTarget(tripHere[0].appendingPathComponent("first")) == "Day 1/IMG_0001.jpg",
              "The folder lost its shape, an empty folder, a file, a permission or a link: \(listing(tripHere[0]))")
    try check(marked(tripHere[0]) && marked(tripHere[0].appendingPathComponent("Day 2")) && marked(tripHere[0].appendingPathComponent("Day 1/IMG_0001.jpg")),
              "A received folder or a file in it was not marked as downloaded")
    let stagedCopy = staged.onClipboard!.id
    func refused(_ label: String, _ reason: DeskClipboardReason, holds expected: [URL]? = nil, prepare: () throws -> Void) throws {
        let before = staged.present(), holding = b.store.files
        try prepare()
        try announced(label + " announced")
        let popup = try bring(label)
        try check(popup.phase == .failed && popup.line == DeskPasteProgress.line(for: reason, from: "MacBook"),
                  "\(label): the popup said \(popup.line ?? "nothing"), not \(DeskPasteProgress.line(for: reason, from: "MacBook"))")
        try wait(label + " cleans up") { staged.present() == before }
        try check(b.store.files == (expected ?? holding), "\(label) changed what this Mac's clipboard holds")
    }
    // Changed between listing and sending: refused, nothing left.
    try refused("changed file", .changed) {
        copyFiles([photos.appendingPathComponent(secretName)])
        b.link.intercept = { _, message in
            if case .treeFetch? = message { try? Data("changed".utf8).write(to: photos.appendingPathComponent(secretName)) }
            return false
        }
    }
    b.link.intercept = nil
    try big.write(to: photos.appendingPathComponent(secretName))
    // No room: declined before anything is written.
    b.clipboard.freeSpace = { _ in 1000 }
    try refused("no room", .noSpace) { copyFiles([photos.appendingPathComponent(secretName)]) }
    b.clipboard.freeSpace = { _ in nil }
    // More than this Mac accepts: declined by name.
    b.clipboard.fileLimits.total = 1000
    try refused("too large here", .tooLarge) { copyFiles([photos.appendingPathComponent(secretName)]) }
    b.clipboard.fileLimits = DeskFileLimits()
    // The stream stalls after the first file: the first, already verified, goes too.
    let smallText = photos.appendingPathComponent("small.txt")
    try Data("small".utf8).write(to: smallText)
    try refused("a stall after the first file", .timedOut) {
        copyFiles([smallText, photos.appendingPathComponent(secretName)])
        a.link.intercept = { _, message in if case .chunk(_, let index, _, _)? = message { return index >= 3 }; return false }
    }
    a.link.intercept = nil
    // Cancel while files come: the sender stops and nothing stays.
    a.link.chunkDelay = 0.05
    let before = staged.present(), holding = b.store.files
    copyFiles([photos.appendingPathComponent(secretName)])
    try announced("cancel announced")
    b.clipboard.bringOverHere()
    try wait("files moving") { (b.clipboard.bringOverProgress ?? 0) > 0.05 }
    b.fakes.last?.cancel()
    try wait("the sender stops") { a.clipboard.decisions.contains { if case .stoppedSending(_, _, .cancelled) = $0 { return true }; return false } }
    try wait("cancel cleans up") { staged.present() == before }
    try check(b.store.files == holding && b.fakes.last?.isClosed == true, "Cancel left files behind or changed the clipboard")
    a.link.chunkDelay = 0
    // Something copied here while files are on their way wins; none of them stay.
    try refused("newer local copy", .newerHere, holds: []) {
        copyFiles([smallText, photos.appendingPathComponent(secretName)])
        b.link.intercept = { _, message in
            if case .treeFetch? = message { b.store.copy([[(type: "public.utf8-plain-text", data: Data("typed here".utf8))]]) }
            return false
        }
    }
    b.link.intercept = nil
    try check(b.store.first == Data("typed here".utf8), "Files replaced a copy made here meanwhile")
    // That copy here is now the newest: once this Mac sees it, the staged copy
    // has left the clipboard and is kept for its ten minutes, not removed at once.
    try wait("the new copy is seen") { staged.onClipboard == nil }
    try check(staged.onClipboard == nil && staged.leftAt[stagedCopy] != nil && staged.present().contains(stagedCopy),
              "The staged copy was removed at once, or its ten minutes did not start, when something else was copied")
    // What cannot come is invisible when copied, and explained when brought over.
    var fetchesSoFar = b.link.count(DeskClipboardTests.isFetch)
    func explained(_ label: String, _ refusal: DeskClipboardRefusal, prepare: () throws -> Void) throws {
        let sent = a.link.sent.count, waitingBefore = b.clipboard.waiting
        try prepare()
        try wait(label + " is kept on the MacBook") { a.clipboard.lastDecision == .notAnnounced(refusal.reason) }
        settle(0.15)
        try check(a.link.sent.count == sent && b.clipboard.waiting == waitingBefore, "\(label) was announced, or changed what waits on the Studio")
        let popup = try bring(label)
        let expected = DeskPasteProgress.explain(refusal, from: "MacBook")
        try check(popup.phase == .informed && popup.title == expected && popup.line == nil && !popup.canCancel,
                  "\(label): the popup said \(popup.title) (\(popup.phase)), not \(expected)")
        try check(b.link.count(DeskClipboardTests.isFetch) == fetchesSoFar, "\(label) was asked for")
    }
    let linked = photos.appendingPathComponent("linked.jpg")
    try fm.createSymbolicLink(at: linked, withDestinationURL: photos.appendingPathComponent(secretName))
    try explained("a link", .init(.links)) { copyFiles([linked]) }
    let leaky = photos.appendingPathComponent("Leaky")
    try put(Data("x".utf8), leaky.appendingPathComponent("a.txt"))
    try fm.createSymbolicLink(atPath: leaky.appendingPathComponent("escape").path, withDestinationPath: "../Trip")
    try explained("a folder with a link leading out", .init(.linkOutside)) { copyFiles([leaky]) }
    a.clipboard.fileLimits.total = 1024
    try explained("too large there", .init(.tooLarge, amount: UInt64(big.count), limit: 1024)) { copyFiles([photos.appendingPathComponent(secretName)]) }
    a.clipboard.fileLimits = DeskFileLimits()
    fetchesSoFar = b.link.count(DeskClipboardTests.isFetch)
    // A hostile name from the other Mac never reaches the disk as sent.
    let hostileName = photos.appendingPathComponent("..evil.txt")
    try Data("x".utf8).write(to: hostileName)
    copyFiles([hostileName])
    try announced("hostile name announced")
    try check(try bring("hostile name").phase == .done, "A file with a hostile name was not brought over")
    try check(b.store.files.map(\.lastPathComponent) == ["evil.txt"] && !listing(b.store.files[0].deletingLastPathComponent()).contains { $0.hasPrefix(".") },
              "A hostile name reached the disk: \(b.store.files)")
    // Filenames and exact sizes never reach the log.
    for mac in [a, b] {
        for decision in mac.clipboard.decisions {
            for forbidden in ["CANARY", "evil", "Trip", "Leaky", "IMG_", "700000", "700,000", "200000"] {
                try check(!decision.line.contains(forbidden), "The decision log revealed a file name or size: \(decision.line)")
            }
        }
    }
    print("PASS: shared files and folders end to end: announced by count and size, brought over into Perch's staging folder with steady progress, a folder with its shape, permissions and inner links, whole or not at all, marked as downloaded and as received, then pasted as files; changed files, no room, too much, a stall, cancel and a newer local copy refused by name with nothing left behind; a link, a folder with a link leading out and a copy over the sender's limit never announced and explained on ⌃⌥⌘V; hostile names made safe; the main thread never waits; no names or sizes in the log")
}
