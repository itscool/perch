import AppKit
import CryptoKit

/// Files copied on one Mac and pasted on another, pinned without Finder: the
/// pasting app is played by calling the promise handler from a background
/// queue with a folder, exactly as a file promise is fulfilled.
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
    defer { try? fm.removeItem(at: root) }
    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name).standardizedFileURL
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func listing(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
    /// Whether the file carries a download quarantine mark: "flags;time;agent;id".
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
    try check(DeskFileNames.candidates("Report.pdf", limit: 3) == ["Report.pdf", "Report 2.pdf", "Report 3.pdf"] &&
              DeskFileNames.candidates("Makefile", limit: 2) == ["Makefile", "Makefile 2"], "Collision names moved")
    print("PASS: shared files make every received name safe: slashes, colons, controls and direction overrides replaced, leading dots and empty or overlong names refused, nothing lands outside its folder")

    // MARK: Landing on disk: atomic, never overwriting, quarantined, cleaned up

    let landing = try folder("landing")
    let payload = bytes(150_000)
    let digest = Data(SHA256.hash(data: payload))
    try Data("already here".utf8).write(to: landing.appendingPathComponent("Report.pdf"))
    let sink = DeskFileSink(directory: landing, name: "Report.pdf", size: UInt64(payload.count), transfer: UUID())
    try sink.create()
    try sink.append(payload.prefix(50_000))
    try check(!listing(landing).contains { $0.hasPrefix("Report") && $0 != "Report.pdf" }, "A partial file appeared under a final name")
    try sink.append(payload.suffix(from: 50_000))
    let landed = try sink.finish(digest: digest)
    try check(landed.lastPathComponent == "Report 2.pdf" && (try Data(contentsOf: landed)) == payload, "A received file did not land whole beside the existing one: \(landed.lastPathComponent)")
    try check((try Data(contentsOf: landing.appendingPathComponent("Report.pdf"))) == Data("already here".utf8), "An existing file was overwritten")
    try check(marked(landed), "A received file was not marked as downloaded: \(String(describing: quarantined(landed)))")
    try check(listing(landing) == ["Report 2.pdf", "Report.pdf"], "Something besides the received file was left behind: \(listing(landing))")
    // A third copy takes the next free name.
    let third = DeskFileSink(directory: landing, name: "Report.pdf", size: UInt64(payload.count), transfer: UUID())
    try third.create(); try third.append(payload)
    try check(try third.finish(digest: digest).lastPathComponent == "Report 3.pdf", "The next free name was not used")
    // A wrong digest, a stop halfway and too many bytes all leave nothing behind.
    let wrong = DeskFileSink(directory: landing, name: "Wrong.bin", size: UInt64(payload.count), transfer: UUID())
    try wrong.create(); try wrong.append(payload)
    do { _ = try wrong.finish(digest: Data(repeating: 0, count: 32)); throw AppError(message: "A file with the wrong digest was kept") }
    catch let reason as DeskClipboardReason { try check(reason == .corrupt, "A wrong digest was refused for the wrong reason: \(reason)") }
    wrong.discard()
    let halfway = DeskFileSink(directory: landing, name: "Halfway.bin", size: UInt64(payload.count), transfer: UUID())
    try halfway.create(); try halfway.append(payload.prefix(1000)); halfway.discard(); halfway.discard()
    let overflow = DeskFileSink(directory: landing, name: "Overflow.bin", size: 10, transfer: UUID())
    try overflow.create()
    try check((try? overflow.append(Data(count: 11))) == nil, "A file was allowed to grow past its promised size")
    overflow.discard()
    try check(listing(landing) == ["Report 2.pdf", "Report 3.pdf", "Report.pdf"], "A failed file left something behind: \(listing(landing))")
    // A link planted where the partial file goes is never followed.
    let planted = UUID()
    let target = root.appendingPathComponent("target-outside")
    try Data("do not touch".utf8).write(to: target)
    try fm.createSymbolicLink(at: landing.appendingPathComponent(".perch-" + planted.uuidString + ".partial"), withDestinationURL: target)
    try check((try? DeskFileSink(directory: landing, name: "Planted.bin", size: 4, transfer: planted).create()) == nil, "A planted link was opened for writing")
    try check((try Data(contentsOf: target)) == Data("do not touch".utf8), "A planted link was written through")
    try fm.removeItem(at: landing.appendingPathComponent(".perch-" + planted.uuidString + ".partial"))
    print("PASS: shared files land atomically under a new name, never overwrite, are marked as downloaded, leave nothing behind on failure, and never write through a planted link")

    // MARK: What the sending Mac refuses to send

    let source = try folder("source")
    let plain = source.appendingPathComponent("plain.txt")
    try Data("plain file".utf8).write(to: plain)
    let link = source.appendingPathComponent("link.txt")
    try fm.createSymbolicLink(at: link, withDestinationURL: plain)
    let alias = source.appendingPathComponent("alias.txt")
    try URL.writeBookmarkData(try plain.bookmarkData(options: .suitableForBookmarkFile), to: alias)
    let sub = try folder("source/sub")
    let limits = DeskFileLimits()
    guard case .success(let examined) = DeskSourceFile.examine([plain], limits: limits), examined.first?.size == 10 else {
        throw AppError(message: "A plain file was not accepted for sending")
    }
    for (url, reason) in [(link, DeskClipboardReason.links), (alias, .links), (sub, .folders), (source.appendingPathComponent("missing"), .unreadable)] {
        guard case .failure(let refused) = DeskSourceFile.examine([plain, url], limits: limits), refused == reason else {
            throw AppError(message: "\(url.lastPathComponent) was not refused as \(reason)")
        }
    }
    var small = limits; small.perFile = 5
    guard case .failure(.tooLarge) = DeskSourceFile.examine([plain], limits: small) else { throw AppError(message: "A file over the per-file cap was accepted") }
    var few = limits; few.count = 1
    guard case .failure(.tooLarge) = DeskSourceFile.examine([plain, plain], limits: few) else { throw AppError(message: "Too many files were accepted") }
    // Changed since it was examined, or swapped for a link: not sent.
    guard case .success(let fd) = examined[0].open() else { throw AppError(message: "An unchanged file would not open") }
    close(fd)
    try Data("plain file, changed".utf8).write(to: plain)
    guard case .failure(.changed) = examined[0].open() else { throw AppError(message: "A changed file was opened for sending") }
    try fm.removeItem(at: plain); try fm.createSymbolicLink(at: plain, withDestinationURL: source.appendingPathComponent("alias.txt"))
    guard case .failure(.links) = examined[0].open() else { throw AppError(message: "A file swapped for a link was opened for sending") }
    // The wire: names and sizes, bounded.
    let list = DeskFileList(files: [.init(name: "a.txt", size: 3), .init(name: "empty", size: 0)])
    try check(try DeskFileList.decode(list.encoded(), limits: limits) == list, "A file list did not survive the wire")
    try check((try? DeskFileList.decode(DeskFileList(files: [.init(name: "big", size: limits.perFile + 1)]).encoded(), limits: limits)) == nil, "A file over the cap was listed")
    try check((try? DeskFileList.decode(DeskFileList(files: []).encoded(), limits: limits)) == nil, "An empty file list was accepted")
    try check((try? DeskFileList.decode(list.encoded() + Data([0]), limits: limits)) == nil, "Trailing bytes after a file list were accepted")
    print("PASS: shared files refuse links, aliases, folders, unreadable, oversized and too many files by name, and never send a file changed or swapped for a link since it was examined")

    // MARK: Received files go on the pasteboard as files

    // Plain file URLs, which every app reads as files, on a private pasteboard.
    let fileBoard = NSPasteboard(name: NSPasteboard.Name("local.scott.perch.selftest.files." + UUID().uuidString))
    defer { fileBoard.releaseGlobally() }
    try check(fileBoard.name != .general, "The file pasteboard test must use a private pasteboard")
    let onBoard = try folder("on-board")
    let first = onBoard.appendingPathComponent("One.txt"), second = onBoard.appendingPathComponent("Two.txt")
    try Data("1".utf8).write(to: first); try Data("2".utf8).write(to: second)
    let fileStore = SystemDeskPasteboard(fileBoard)
    _ = fileStore.replace(with: [[(type: DeskClipboardMarker.fileURL, data: first.dataRepresentation)], [(type: DeskClipboardMarker.fileURL, data: second.dataRepresentation)]])
    let read = fileBoard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    try check(read.map(\.standardizedFileURL) == [first, second].map(\.standardizedFileURL), "Received files were not readable as files: \(read)")
    try check(DeskClipboardPolicy.assess(fileStore.itemTypes()) == .files, "Received files would not be shared on in turn")
    print("PASS: shared files go on the pasteboard as plain file URLs that apps read as files, on a private pasteboard")

    // MARK: End to end, into Downloads when the keyboard arrives

    let desk = ClipboardFileDesk()
    let a = desk.a, b = desk.b
    let downloads = try folder("Downloads")
    b.clipboard.receiveFolder = { downloads }
    a.clipboard.receiveFolder = { nil }
    desk.start()
    defer { desk.stop() }
    try wait("greeting") { b.clipboard.decisions.contains(.peerSupports("MacBook", format: 1)) && a.clipboard.decisions.contains(.peerSupports("Studio", format: 1)) }
    /// The keyboard arrives on the Studio; wait for its decision.
    func arrive(_ what: String, until done: @escaping (DeskClipboardDecision) -> Bool) throws {
        let before = b.clipboard.lastDecision
        b.clipboard.keyboardArrived()
        try wait(what) { guard let now = b.clipboard.lastDecision, now != before else { return false }; return done(now) }
    }
    func received(_ decision: DeskClipboardDecision) -> Bool { if case .received = decision { return true }; return false }
    func copy(_ urls: [URL], text: String? = nil) {
        a.store.copy(urls.map { url in [(type: DeskClipboardMarker.fileURL, data: url.dataRepresentation)] + (text.map { [(type: "public.utf8-plain-text", data: Data($0.utf8))] } ?? []) })
        settle(0.15)
    }
    let photos = try folder("photos")
    let big = bytes(700_000), secretName = "CANARY-\(UUID().uuidString.prefix(8)).jpg"
    try big.write(to: photos.appendingPathComponent(secretName))
    try Data().write(to: photos.appendingPathComponent(".empty-marker"))
    try Data("already downloaded".utf8).write(to: downloads.appendingPathComponent(secretName))
    let clipboardBefore = b.store.current.count
    var gap = 0.0
    do {
        var last = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in let now = ProcessInfo.processInfo.systemUptime; gap = max(gap, now - last); last = now }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        a.link.chunkDelay = 0.05
        copy([photos.appendingPathComponent(secretName), photos.appendingPathComponent(".empty-marker")], text: secretName)
        var progress: [Double] = []
        let before = b.clipboard.lastDecision
        b.clipboard.keyboardArrived()
        try wait("files arrive") {
            if let value = b.clipboard.fileProgress { progress.append(value) }
            guard let now = b.clipboard.lastDecision, now != before else { return false }
            return received(now)
        }
        a.link.chunkDelay = 0
        try check(progress.contains { $0 > 0 && $0 < 1 }, "Files on their way showed no progress")
    }
    try check(gap < 0.3, "Bringing files stalled the main thread for \(gap) s")
    let renamed = secretName.replacingOccurrences(of: ".jpg", with: " 2.jpg")
    try check(b.store.files.map(\.lastPathComponent) == [renamed, "empty-marker"] && clipboardBefore == 0,
              "The pasteboard does not hold the files that arrived: \(b.store.files)")
    try check(b.store.current.allSatisfy { $0.count == 1 }, "A file's name or icon was pasted beside it")
    try check((try Data(contentsOf: downloads.appendingPathComponent(renamed))) == big && (try Data(contentsOf: downloads.appendingPathComponent("empty-marker"))).isEmpty,
              "Files did not arrive whole")
    try check((try Data(contentsOf: downloads.appendingPathComponent(secretName))) == Data("already downloaded".utf8), "An existing download was overwritten")
    try check(marked(downloads.appendingPathComponent(renamed)) && marked(downloads.appendingPathComponent("empty-marker")), "Received files were not marked as downloaded")
    try check(listing(downloads) == [renamed, secretName, "empty-marker"].sorted(), "Something besides the files was left: \(listing(downloads))")
    let settled = listing(downloads)
    // The MacBook asking back finds it already has that copy.
    a.clipboard.keyboardArrived()
    try wait("already there") { if case .alreadyHere? = a.clipboard.lastDecision { return true }; return false }
    // Changed on the MacBook between listing and sending: refused, nothing left.
    copy([photos.appendingPathComponent(secretName)])
    b.link.intercept = { _, message in
        if case .fileFetch? = message { try? Data("changed".utf8).write(to: photos.appendingPathComponent(secretName)) }
        return false
    }
    try arrive("changed file refused") { $0.reason == .changed }
    b.link.intercept = nil
    try check(listing(downloads) == settled, "A refused file left something behind: \(listing(downloads))")
    // No room: declined before anything is written.
    try big.write(to: photos.appendingPathComponent(secretName))
    copy([photos.appendingPathComponent(secretName)])
    b.clipboard.freeSpace = { _ in 1000 }
    try arrive("no room") { $0.reason == .noSpace }
    b.clipboard.freeSpace = { _ in nil }
    try check(listing(downloads) == settled, "Files were started without room")
    // More than this Mac accepts: declined by name.
    b.clipboard.fileLimits.total = 1000
    copy([photos.appendingPathComponent(secretName)])
    try arrive("too large declined") { $0.reason == .tooLarge }
    b.clipboard.fileLimits = DeskFileLimits()
    // The second file stalls: the first, already verified, goes too.
    let smallFile = photos.appendingPathComponent("small.txt")
    try Data("small".utf8).write(to: smallFile)
    copy([smallFile, photos.appendingPathComponent(secretName)])
    var fetches = 0
    b.link.intercept = { _, message in if case .fileFetch? = message { fetches += 1 }; return false }
    a.link.intercept = { _, message in if case .chunk(_, let index, _, _)? = message { return fetches >= 2 && index >= 3 }; return false }
    try arrive("stall") { $0.reason == .timedOut }
    a.link.intercept = nil; b.link.intercept = nil
    try wait("partial files removed") { listing(downloads) == settled }
    // Something copied here while files are on their way wins; none of them stay.
    copy([smallFile, photos.appendingPathComponent(secretName)])
    fetches = 0
    b.link.intercept = { _, message in
        if case .fileFetch? = message { fetches += 1; if fetches == 2 { b.store.copy([[(type: "public.utf8-plain-text", data: Data("typed here".utf8))]]) } }
        return false
    }
    try arrive("newer local copy") { $0.reason == .newerHere }
    b.link.intercept = nil
    try wait("batch removed") { listing(downloads) == settled }
    try check(b.store.current.first?.first?.data == Data("typed here".utf8), "Files replaced a copy made here meanwhile")
    // Links and folders are refused by name.
    let linked = photos.appendingPathComponent("linked.jpg")
    try fm.createSymbolicLink(at: linked, withDestinationURL: photos.appendingPathComponent(secretName))
    copy([linked])
    try arrive("link refused") { if case .refusedBy("MacBook", _, .links) = $0 { return true }; return false }
    copy([photos])
    try arrive("folder refused") { if case .refusedBy("MacBook", _, .folders) = $0 { return true }; return false }
    // A hostile name from the other Mac never reaches the disk as sent.
    let hostile = photos.appendingPathComponent("..evil.txt")
    try Data("x".utf8).write(to: hostile)
    copy([hostile])
    try arrive("hostile name made safe", until: received)
    try check(b.store.files.map(\.lastPathComponent) == ["evil.txt"] && listing(downloads).contains("evil.txt") && !listing(downloads).contains { $0.hasPrefix(".") },
              "A hostile name reached the disk: \(listing(downloads))")
    // Filenames and exact sizes never reach the log.
    for line in desk.logged where line.category == DeskClipboardDecision.category {
        try check(!line.message.contains("CANARY") && !line.message.contains("evil") && !line.message.contains("700000") && !line.message.contains("700,000"),
                  "The decision log revealed a file name or size: \(line.message)")
    }
    print("PASS: shared files end to end: brought into Downloads when the keyboard arrives, whole or not at all, beside existing files, marked as downloaded, then pasted as files; changed files, no room, too much, a stall, a newer local copy, links and folders refused by name with nothing left behind; hostile names made safe; the main thread never waits; no file names in the log")
}

/// Two Macs with file-capable fake pasteboards.
private final class ClipboardFileDesk {
    struct Mac { let id: UUID; let link: DeskClipboardFakeLink; let store: DeskClipboardFakeStore; let clipboard: DeskClipboard }
    let a: Mac, b: Mac
    var permitted: [UUID: Bool] = [:]
    var logged: [PerchLog.Entry] = []
    private let savedSink = PerchLog.sink
    init() {
        func make(_ name: String) -> Mac {
            let link = DeskClipboardFakeLink(), store = DeskClipboardFakeStore()
            let clipboard = DeskClipboard(link: link, pasteboard: DeskPasteboardAccess(store: store, timeout: 1))
            clipboard.timings = .init(query: 0.3, reply: 0.8, stall: 0.6, total: 20, serveStall: 1.5, hello: 30, tick: 0.05)
            link.names[link.localID] = name
            return Mac(id: link.localID, link: link, store: store, clipboard: clipboard)
        }
        a = make("MacBook"); b = make("Studio")
        for (mac, other) in [(a, b), (b, a)] {
            mac.link.peers = [other.id]; mac.link.names[other.id] = other.link.names[other.id]
            permitted[mac.id] = true
            let id = mac.id
            mac.clipboard.permitted = { [weak self] in self?.permitted[id] ?? false }
            mac.link.deliver = { [weak self] to, data in
                guard let self else { return }
                (to == self.a.id ? self.a : self.b).clipboard.receive(data, peer: id)
            }
        }
        PerchLog.reset()
        PerchLog.sink = { [weak self] in self?.logged.append($0) }
    }
    func start() { a.clipboard.start(); b.clipboard.start() }
    func stop() { a.clipboard.stop(); b.clipboard.stop(); PerchLog.sink = savedSink; PerchLog.reset() }
}
