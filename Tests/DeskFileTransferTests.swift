import AppKit
import CryptoKit

/// Files copied on one Mac, brought over to another and pasted there, pinned
/// without Finder: every file operation runs against temporary folders.
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
        // At start, a staged copy the clipboard still lists is kept, the rest go.
        let restarted = DeskFileStaging(root: staging.root)
        restarted.adopt([staging.folder(second).appendingPathComponent("f")], changeCount: 9)
        try check(restarted.onClipboard?.id == second && restarted.onClipboard?.changeCount == 9, "A staged copy still on the clipboard was not kept at start")
        let other = DeskFileStaging(root: staging.root)
        other.adopt([root.appendingPathComponent("elsewhere/f")], changeCount: 9)
        try check(other.onClipboard == nil, "A file outside staging was taken for a staged copy")
    }
    print("PASS: shared files' staging rule: failed copies go at once, the copy on the clipboard stays, one that left the clipboard goes ten minutes later, strays go at start, and only Perch's own private folders are ever removed")

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
    func announced(_ label: String) throws {
        try wait(label) { b.clipboard.waiting?.what.kind == .files && b.clipboard.waiting?.copy != known }
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
            if case .fileFetch? = message { try? Data("changed".utf8).write(to: photos.appendingPathComponent(secretName)) }
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
    try refused("too large", .tooLarge) { copyFiles([photos.appendingPathComponent(secretName)]) }
    b.clipboard.fileLimits = DeskFileLimits()
    // The second file stalls: the first, already verified, goes too.
    let smallFile = photos.appendingPathComponent("small.txt")
    try Data("small".utf8).write(to: smallFile)
    var fetches = 0
    try refused("stall on the second file", .timedOut) {
        copyFiles([smallFile, photos.appendingPathComponent(secretName)])
        b.link.intercept = { _, message in if case .fileFetch? = message { fetches += 1 }; return false }
        a.link.intercept = { _, message in if case .chunk(_, let index, _, _)? = message { return fetches >= 2 && index >= 3 }; return false }
    }
    a.link.intercept = nil; b.link.intercept = nil
    // Cancel while files come: the sender stops and nothing stays.
    a.link.chunkDelay = 0.05
    let before = staged.present()
    copyFiles([photos.appendingPathComponent(secretName)])
    try announced("cancel announced")
    b.clipboard.bringOverHere()
    try wait("files moving") { (b.clipboard.bringOverProgress ?? 0) > 0.05 }
    b.fakes.last?.cancel()
    try wait("the sender stops") { a.clipboard.decisions.contains { if case .stoppedSending(_, _, .cancelled) = $0 { return true }; return false } }
    try wait("cancel cleans up") { staged.present() == before }
    try check(b.store.files == brought && b.fakes.last?.isClosed == true, "Cancel left files behind or changed the clipboard")
    a.link.chunkDelay = 0
    // Something copied here while files are on their way wins; none of them stay.
    fetches = 0
    try refused("newer local copy", .newerHere, holds: []) {
        copyFiles([smallFile, photos.appendingPathComponent(secretName)])
        b.link.intercept = { _, message in
            if case .fileFetch? = message { fetches += 1; if fetches == 2 { b.store.copy([[(type: "public.utf8-plain-text", data: Data("typed here".utf8))]]) } }
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
    // Links and folders are refused by name.
    let linked = photos.appendingPathComponent("linked.jpg")
    try fm.createSymbolicLink(at: linked, withDestinationURL: photos.appendingPathComponent(secretName))
    try refused("a link", .links) { copyFiles([linked]) }
    try refused("a folder", .folders) { copyFiles([photos]) }
    // A hostile name from the other Mac never reaches the disk as sent.
    let hostile = photos.appendingPathComponent("..evil.txt")
    try Data("x".utf8).write(to: hostile)
    copyFiles([hostile])
    try announced("hostile name announced")
    try check(try bring("hostile name").phase == .done, "A file with a hostile name was not brought over")
    try check(b.store.files.map(\.lastPathComponent) == ["evil.txt"] && !listing(b.store.files[0].deletingLastPathComponent()).contains { $0.hasPrefix(".") },
              "A hostile name reached the disk: \(b.store.files)")
    // Filenames and exact sizes never reach the log.
    for mac in [a, b] {
        for decision in mac.clipboard.decisions {
            try check(!decision.line.contains("CANARY") && !decision.line.contains("evil") && !decision.line.contains("700000") && !decision.line.contains("700,000"),
                      "The decision log revealed a file name or size: \(decision.line)")
        }
    }
    print("PASS: shared files end to end: announced by count and size, brought over into Perch's staging folder with steady progress, whole or not at all, marked as downloaded and as received, then pasted as files; changed files, no room, too much, a stall, cancel, a newer local copy, links and folders refused by name with nothing left behind; hostile names made safe; the main thread never waits; no file names in the log")
}
