import AppKit
import Carbon
import CryptoKit

/// A pasteboard in memory. The real one holds what the person copied, which may
/// be a password, so no test here ever reads or writes it.
final class DeskClipboardFakeStore: DeskPasteboardStore {
    private let lock = NSLock()
    private var items: [[(type: String, data: Data)]] = []
    private var count = 0
    private var reads = 0
    /// Seconds a data read blocks the pasteboard queue: an app that promised
    /// its copy and is slow, or hung, handing it over.
    var readDelay: Double {
        get { lock.lock(); defer { lock.unlock() }; return delay }
        set { lock.lock(); delay = newValue; lock.unlock() }
    }
    private var delay: Double = 0
    var dataReads: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var changeCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    var current: [[(type: String, data: Data)]] { lock.lock(); defer { lock.unlock() }; return items }
    /// The first item's first representation: what a paste of text would give.
    var first: Data? { current.first?.first?.data }
    /// Someone copies on this Mac.
    func copy(_ value: [[(type: String, data: Data)]]) { lock.lock(); items = value; count += 1; lock.unlock() }
    func itemTypes() -> [[String]] { lock.lock(); defer { lock.unlock() }; return items.map { $0.map(\.type) } }
    func data(item: Int, type: String) -> Data? {
        lock.lock(); reads += 1; let wait = delay; lock.unlock()
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        lock.lock(); defer { lock.unlock() }
        guard items.indices.contains(item) else { return nil }
        return items[item].first { $0.type == type }?.data
    }
    func replace(with value: [[(type: String, data: Data)]]) -> Int { lock.lock(); defer { lock.unlock() }; items = value; count += 1; return count }
    /// The files this pasteboard holds, as the file URLs any app pastes.
    var files: [URL] { current.compactMap { item in item.first { $0.type == DeskClipboardMarker.fileURL }.flatMap { URL(dataRepresentation: $0.data, relativeTo: nil) } } }
    /// Whether what it holds carries Perch's received mark.
    var marked: Bool { current.contains { $0.contains { $0.type == DeskClipboardMarker.received } } }
}

/// A desk link in memory. Delivers on the main queue, as the real transport does.
final class DeskClipboardFakeLink: DeskClipboardLink {
    let localID: UUID
    var peers: Set<UUID> = []
    var names: [UUID: String] = [:]
    var queued = 0
    /// Everything this Mac put on the wire, by recipient.
    var sent: [(peer: UUID, data: Data)] = []
    var deliver: ((UUID, Data) -> Void)?
    /// Return true to lose a message; the hook may also act on it first.
    var intercept: ((UUID, DeskClipboardMessage?) -> Bool)?
    /// Seconds to hold each chunk before delivering it: a slow peer.
    var chunkDelay: Double = 0
    /// Replace a message on its way out: a peer that says one thing and sends another.
    var rewrite: ((DeskClipboardMessage) -> DeskClipboardMessage?)?
    init(_ id: UUID = UUID()) { localID = id }
    func name(of peer: UUID) -> String { names[peer] ?? "Unknown" }
    func send(_ data: Data, to peer: UUID) -> Bool {
        var data = data
        if let rewrite, let original = DeskClipboardTests.peek(data), let changed = rewrite(original),
           let envelope = try? DeskClipboardWire.encode(changed, format: 1) { data = DeskClipboardWire.prefix + envelope }
        sent.append((peer, data))
        let message = DeskClipboardTests.peek(data)
        if intercept?(peer, message) == true { return true }
        let delay: Double
        if case .chunk? = message { delay = chunkDelay } else { delay = 0 }
        let deliver = self.deliver
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { deliver?(peer, data) }
        return true
    }
    func queuedBytes(to peer: UUID) -> Int? { peers.contains(peer) ? queued : nil }
    /// Every message sent to `peer`, decoded without regard to format.
    func messages(to peer: UUID) -> [DeskClipboardMessage?] { sent.filter { $0.peer == peer }.map { DeskClipboardTests.peek($0.data) } }
    /// How many messages of one kind this Mac sent to anyone.
    func count(_ matches: (DeskClipboardMessage) -> Bool) -> Int { sent.compactMap { DeskClipboardTests.peek($0.data) }.filter(matches).count }
}

enum DeskClipboardTests {
    static func peek(_ data: Data) -> DeskClipboardMessage? {
        guard data.starts(with: DeskClipboardWire.prefix) else { return nil }
        let envelope = Data(data.dropFirst(DeskClipboardWire.prefix.count))
        for format in [nil] + DeskClipboardWire.formats.map({ Optional($0) }) + [UInt8(2)].map({ Optional($0) }) {
            if let message = try? DeskClipboardWire.decode(envelope, format: format) { return message }
        }
        return nil
    }
    static func isCopied(_ message: DeskClipboardMessage) -> Bool { if case .copied = message { return true }; return false }
    static func isFetch(_ message: DeskClipboardMessage) -> Bool {
        switch message { case .fetch, .fileFetch: return true; default: return false }
    }
    static func isContent(_ message: DeskClipboardMessage) -> Bool {
        switch message { case .manifest, .chunk: return true; default: return false }
    }
}

/// Stands in, on one Mac, for the popup.
final class DeskPasteFakes: DeskPastePresenting {
    var presented: [DeskPasteProgress] = []
    var last: DeskPasteProgress? { presented.last }
    func present(_ progress: DeskPasteProgress) { presented.append(progress) }
}

/// Two or three Macs of a desk, each with its own clipboard, in memory.
final class DeskClipboardTestDesk {
    struct Mac {
        let id: UUID
        let link: DeskClipboardFakeLink
        let store: DeskClipboardFakeStore
        let clipboard: DeskClipboard
        let fakes: DeskPasteFakes
    }
    var macs: [Mac] = []
    var permitted: [UUID: Bool] = [:]
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-clipboard-desk-" + UUID().uuidString).standardizedFileURL
    /// Macs outside `answering` behave like a Perch without clipboard support:
    /// the message reaches them and nothing handles it.
    init(names: [String], answering: Set<Int>? = nil) {
        for name in names {
            let link = DeskClipboardFakeLink(), store = DeskClipboardFakeStore(), fakes = DeskPasteFakes()
            let staging = DeskFileStaging(root: root.appendingPathComponent(name + "-staging"))
            let clipboard = DeskClipboard(link: link, pasteboard: DeskPasteboardAccess(store: store, timeout: 0.3), staging: staging)
            clipboard.timings = .init(reply: 0.6, stall: 0.6, total: 20, serveStall: 1.5, hello: 30, tick: 0.05)
            clipboard.presenter = fakes
            link.names[link.localID] = name
            macs.append(.init(id: link.localID, link: link, store: store, clipboard: clipboard, fakes: fakes))
        }
        let handling = Set(macs.enumerated().filter { answering?.contains($0.offset) ?? true }.map(\.element.id))
        for mac in macs {
            for other in macs where other.id != mac.id { mac.link.peers.insert(other.id); mac.link.names[other.id] = other.link.names[other.id] }
            permitted[mac.id] = true
            let id = mac.id
            mac.clipboard.permitted = { [weak self] in self?.permitted[id] ?? false }
            mac.link.deliver = { [weak self] to, data in
                guard handling.contains(to), let target = self?.macs.first(where: { $0.id == to }) else { return }
                target.clipboard.receive(data, peer: id)
            }
        }
    }
    func start() { macs.forEach { $0.clipboard.start() } }
    func stop() { macs.forEach { $0.clipboard.stop() }; try? FileManager.default.removeItem(at: root) }
    /// Every Mac has greeted every other.
    func greeted() -> Bool {
        macs.allSatisfy { mac in macs.filter { $0.id != mac.id }.allSatisfy { other in mac.clipboard.decisions.contains(.peerSupports(other.link.names[other.id] ?? "", format: 1)) } }
    }
}

/// Time that moves only when told, for the popup's timing.
final class DeskManualTime {
    var now = 0.0
    private var pending: [(at: Double, work: () -> Void)] = []
    func after(_ delay: Double, _ work: @escaping () -> Void) { pending.append((now + delay, work)) }
    func advance(to time: Double) {
        now = time
        while let index = pending.indices.filter({ pending[$0].at <= now }).min(by: { pending[$0].at < pending[$1].at }) {
            pending.remove(at: index).work()
        }
    }
}

func runDeskClipboardTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func wait(_ what: String, seconds: Double = 5, until predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        guard predicate() else { throw AppError(message: "Clipboard: timed out waiting for " + what) }
    }
    func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    /// The longest the main thread went without running a 10 ms timer while
    /// `body` ran: a blocked main thread shows up as a long gap.
    func mainGap(_ body: () throws -> Void) rethrows -> Double {
        var last = ProcessInfo.processInfo.systemUptime, worst = 0.0
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime; worst = max(worst, now - last); last = now
        }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        try body()
        return worst
    }
    let text = "public.utf8-plain-text", rtf = "public.rtf", png = "public.png", tiff = "public.tiff"
    func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) ^ seed })
    }
    let savedSink = PerchLog.sink
    var logged: [PerchLog.Entry] = []
    PerchLog.reset()
    PerchLog.sink = { logged.append($0) }
    defer { PerchLog.sink = savedSink; PerchLog.reset() }

    // MARK: What is never offered

    // Concealed, transient and generated copies are withheld on sight, on any
    // item, alongside anything else, before a byte of their data is read.
    let marked: [(String, DeskClipboardReason)] = [
        (DeskClipboardMarker.concealed, .concealed), (DeskClipboardMarker.transient, .transient),
        (DeskClipboardMarker.autoGenerated, .autoGenerated), ("com.agilebits.onepassword", .concealed),
        ("de.petermaurer.TransientPasteboardType", .transient)]
    for (marker, reason) in marked {
        try check(DeskClipboardPolicy.assess([[text, marker]]) == .withheld(reason), "A copy marked \(marker) was offered")
        try check(DeskClipboardPolicy.assess([[text, png], [text, marker]]) == .withheld(reason), "A mark on a second item did not withhold the copy (\(marker))")
    }
    try check(DeskClipboardPolicy.assess([[text, DeskClipboardMarker.fileURL, tiff]]) == .files,
              "A copy of files was offered as its name and icon")
    try check(DeskClipboardPolicy.assess([["com.example.private"]]) == .withheld(.unsupported), "An app's private type was offered")
    try check(DeskClipboardPolicy.assess([]) == .withheld(.noCopy), "An empty pasteboard was offered")
    try check(DeskClipboardPolicy.assess([[tiff, png, text, "public.html", rtf]]) == .share([[.plainText, .richText, .html, .png]]),
              "Text did not keep every representation, or more than one image representation was chosen")
    try check(DeskClipboardPolicy.assess([[tiff]]) == .share([[.tiff]]), "A TIFF-only image was not shared")
    try check(DeskClipboardPolicy.assess([[text, DeskClipboardMarker.received]]) == .withheld(.received), "A copy Perch received was offered again")
    try check(DeskClipboardPolicy.assess([[text], [DeskClipboardMarker.fileURL, DeskClipboardMarker.received]]) == .withheld(.received), "A marked copy of files was offered again")
    do {
        let store = DeskClipboardFakeStore(), access = DeskPasteboardAccess(store: store, timeout: 1)
        store.copy([[(text, Data("hunter2".utf8)), (DeskClipboardMarker.concealed, Data())]])
        var outcome: Result<DeskClipboardSnapshot, DeskClipboardReason>?
        access.read(expecting: store.changeCount, limits: .init(), fileLimits: .init()) { outcome = $0 }
        try wait("concealed read") { outcome != nil }
        guard case .failure(.concealed)? = outcome else { throw AppError(message: "A concealed copy was read for sending: \(String(describing: outcome))") }
        try check(store.dataReads == 0, "A concealed copy's data was read into Perch (\(store.dataReads) reads)")
    }
    print("PASS: shared clipboard never offers concealed, transient, generated or received copies, never a file's name or icon in place of the file; only text, rich text and one image representation")

    // MARK: The wire

    let transfer = UUID(), copyID = UUID(), key = SymmetricKey(size: .bits256)
    let messages: [DeskClipboardMessage] = [
        .hello(formats: [1], reply: false), .bringOver, .copied(copy: copyID, age: 1234, what: .init(kind: .image, count: 3, small: false, size: 4)),
        .copied(copy: copyID, age: 5, what: .init(kind: .text, count: 1, small: true, size: 1)), .copied(copy: copyID, age: 9, what: nil),
        .fileFetch(transfer: transfer, copy: copyID, index: 2, key: Data(repeating: 4, count: 32)),
        .fetch(transfer: transfer, copy: copyID, key: Data(repeating: 3, count: 32)), .ack(transfer: transfer, next: 4),
        .refuse(transfer: transfer, reason: .tooLarge), .cancel(transfer: transfer, reason: .timedOut)]
    for message in messages {
        let envelope = try DeskClipboardWire.encode(message, format: 1)
        try check(envelope.count == DeskClipboardWire.controlSize, "A control message was not exactly one kilobyte: \(message)")
        try check(try DeskClipboardWire.decode(envelope, format: 1) == message, "A message did not survive the wire: \(message)")
    }
    // Format negotiation: only the negotiated format is accepted, and before a
    // hello nothing but a hello is.
    let ask = try DeskClipboardWire.encode(.copied(copy: UUID(), age: 1, what: nil), format: 1)
    for format in [nil, UInt8(2)] {
        do { _ = try DeskClipboardWire.decode(ask, format: format); throw AppError(message: "A message in another format was accepted") }
        catch let failure as DeskClipboardWire.Failure { try check(failure == .format, "Another format was refused for the wrong reason: \(failure)") }
    }
    var hello = try DeskClipboardWire.encode(.hello(formats: [1], reply: true), format: 1)
    try check(try DeskClipboardWire.decode(hello, format: nil) == .hello(formats: [1], reply: true), "A hello needed a format first")
    hello[1] = 1
    try check((try? DeskClipboardWire.decode(hello, format: nil)) == nil, "A hello in a negotiated format's header was accepted")
    var padded = ask; padded[padded.count - 1] = 1
    try check((try? DeskClipboardWire.decode(padded, format: 1)) == nil, "Non-empty padding was accepted")
    try check((try? DeskClipboardWire.decode(ask + Data(count: 1), format: 1)) == nil, "An envelope of another size was accepted")
    try check((try? DeskClipboardWire.decode(ask + Data(count: DeskClipboardWire.chunkEnvelopeSize - ask.count), format: 1)) == nil,
              "A control message padded to a chunk's size was accepted")
    var unknown = ask; unknown[2] = 99
    try check((try? DeskClipboardWire.decode(unknown, format: 1)) == nil, "An unknown message type was accepted")

    // Padding hides length inside a bucket: different lengths in one bucket put
    // exactly the same sizes on the wire, and a text copy looks like an image.
    try check(DeskClipboardWire.bucket(1) == 4096 && DeskClipboardWire.bucket(4097) == 5120 && DeskClipboardWire.bucket(65536) == 65536,
              "Size buckets moved")
    for n in stride(from: 1, to: 3_000_000, by: 7919) {
        let b = DeskClipboardWire.bucket(n)
        try check(b >= n && (n <= 4096 || Double(b) <= Double(n) * 1.25 + 1), "Bucket \(b) does not fit \(n) within a quarter")
    }
    func shape(_ payload: Data) throws -> [Int] {
        let parcel = DeskClipboardWire.seal(payload, transfer: UUID(), copy: UUID(), key: key, format: 1)
        return [try DeskClipboardWire.encode(.manifest(parcel.manifest), format: 1).count] +
            (try (0..<parcel.manifest.chunkCount).map { try DeskClipboardWire.encode(parcel.chunk($0, key: key), format: 1).count })
    }
    let short = try shape(bytes(70_000)), long = try shape(bytes(80_000))
    try check(short == long && short.count > 2 && Set(short.dropFirst()) == [DeskClipboardWire.chunkEnvelopeSize],
              "Two lengths in one bucket looked different on the wire: \(short) vs \(long)")
    let asText = DeskClipboardContent(items: [[.init(type: .plainText, data: Data(repeating: 65, count: 900))]]).encoded()
    let asImage = DeskClipboardContent(items: [[.init(type: .png, data: bytes(1_000))]]).encoded()
    try check(try shape(asText) == shape(asImage), "A text copy and an image copy looked different on the wire")

    // Compression: never below the threshold, only when it helps, and bounded
    // on the way back in.
    try check(DeskClipboardWire.compress(Data(repeating: 1, count: DeskClipboardWire.compressionThreshold - 1)) == nil, "Content below the threshold was compressed")
    try check(DeskClipboardWire.compress(bytes(100_000)) == nil, "Incompressible content was sent compressed")
    let repetitive = Data(String(repeating: "Perch shares copies between Macs. ", count: 4000).utf8)
    let sealed = DeskClipboardWire.seal(repetitive, transfer: transfer, copy: copyID, key: key, format: 1)
    try check(sealed.manifest.compressed && Int(sealed.manifest.encodedLength) < repetitive.count, "Compressible content above the threshold was not compressed")
    let bomb = DeskClipboardWire.compress(Data(count: 20_000_000))!
    try check(DeskClipboardWire.decompress(bomb, exactly: 1000) == nil && DeskClipboardWire.decompress(bomb, exactly: 20_000_001) == nil,
              "Content that expands past its declared size was accepted")
    try check(DeskClipboardWire.decompress(bomb, exactly: 20_000_000)?.count == 20_000_000, "Honest compressed content did not expand")

    // MARK: Reassembly refuses anything that does not follow the manifest

    func parcel(_ size: Int = 200_000, transfer: UUID = transfer) -> DeskClipboardWire.Parcel {
        DeskClipboardWire.seal(bytes(size), transfer: transfer, copy: copyID, key: key, format: 1)
    }
    func assembly(_ p: DeskClipboardWire.Parcel, key k: SymmetricKey = key) throws -> DeskClipboardAssembly {
        try DeskClipboardAssembly(p.manifest, transfer: transfer, copy: copyID, key: k, format: 1, maximumPayload: 40 << 20)
    }
    func deliver(_ a: DeskClipboardAssembly, _ message: DeskClipboardMessage) throws {
        guard case .chunk(let t, let index, let data, let mac) = message else { throw AppError(message: "Not a chunk") }
        try a.accept(transfer: t, index: index, data: data, mac: mac)
    }
    func refuses(_ expected: String, _ body: () throws -> Void) throws {
        do { try body(); throw AppError(message: "Reassembly accepted what it must refuse: \(expected)") }
        catch let failure as DeskClipboardAssembly.Failure {
            try check(failure.detail.contains(expected), "Reassembly refused for the wrong reason: \(failure.detail), expected \(expected)")
        }
    }
    let good = parcel()
    try check(good.manifest.chunkCount >= 4, "The reassembly fixture needs several chunks")
    let whole = try assembly(good)
    for index in 0..<good.manifest.chunkCount { try deliver(whole, good.chunk(index, key: key)) }
    try check(try whole.finish() == good.stream.prefix(Int(good.manifest.encodedLength)), "Honest chunks did not reassemble")
    try refuses("failed authentication") {
        let a = try assembly(good)
        try deliver(a, good.chunk(0, key: key))
        guard case .chunk(let t, let i, var data, let mac) = good.chunk(1, key: key) else { return }
        data[100] ^= 1
        try a.accept(transfer: t, index: i, data: data, mac: mac)
    }
    try refuses("chunk 1 arrived before chunk 0") { try deliver(try assembly(good), good.chunk(1, key: key)) }
    try refuses("chunk 0 arrived again") { let a = try assembly(good); try deliver(a, good.chunk(0, key: key)); try deliver(a, good.chunk(0, key: key)) }
    try refuses("chunk 3 arrived before chunk 2") {
        let a = try assembly(good); try deliver(a, good.chunk(0, key: key)); try deliver(a, good.chunk(1, key: key)); try deliver(a, good.chunk(3, key: key))
    }
    try refuses("chunks are missing") { let a = try assembly(good); try deliver(a, good.chunk(0, key: key)); _ = try a.finish() }
    try refuses("belongs to another transfer") { try deliver(try assembly(good), parcel(transfer: UUID()).chunk(0, key: key)) }
    try refuses("failed authentication") { try deliver(try assembly(good), good.chunk(0, key: SymmetricKey(size: .bits256))) }
    try refuses("authentication failed") { _ = try assembly(good, key: SymmetricKey(size: .bits256)) }
    try refuses("authentication failed") { var m = good.manifest; m.chunkCount += 1; _ = try DeskClipboardAssembly(m, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 40 << 20) }
    func resigned(_ change: (inout DeskClipboardManifest) -> Void) -> DeskClipboardManifest {
        var m = good.manifest; change(&m); m.mac = DeskClipboardWire.manifestMAC(m, format: 1, key: key); return m
    }
    try refuses("chunk count disagrees") { _ = try DeskClipboardAssembly(resigned { $0.chunkCount += 1 }, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 40 << 20) }
    try refuses("not padded to its size bucket") { _ = try DeskClipboardAssembly(resigned { $0.paddedLength -= 1 }, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 40 << 20) }
    try refuses("declares a size") { _ = try DeskClipboardAssembly(good.manifest, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 1000) }
    // A hostile 64-bit length is refused, never converted into a crash.
    try refuses("declares a size") { _ = try DeskClipboardAssembly(resigned { $0.payloadLength = .max; $0.encodedLength = .max; $0.paddedLength = .max }, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 40 << 20) }
    try refuses("lengths disagree") { _ = try DeskClipboardAssembly(resigned { $0.paddedLength = .max }, transfer: transfer, copy: copyID, key: key, format: 1, maximumPayload: 40 << 20) }
    try refuses("describes a different copy") { _ = try DeskClipboardAssembly(good.manifest, transfer: transfer, copy: UUID(), key: key, format: 1, maximumPayload: 40 << 20) }
    try refuses("content digest does not match") {
        // A sender that lies consistently: a valid manifest over a wrong digest.
        let lying = DeskClipboardWire.Parcel(manifest: resigned { $0.digest = Data(repeating: 0, count: 32) }, stream: good.stream, format: 1)
        let a = try assembly(lying)
        for index in 0..<lying.manifest.chunkCount { try deliver(a, lying.chunk(index, key: key)) }
        _ = try a.finish()
    }
    let limits = DeskClipboardLimits()
    var tag = DeskClipboardContent(items: [[.init(type: .plainText, data: Data("x".utf8))]]).encoded()
    tag[6] = 99
    try check((try? DeskClipboardContent.decode(tag, limits: limits)) == nil, "A type outside the allowlist was decoded")
    let valid = DeskClipboardContent(items: [[.init(type: .plainText, data: Data("x".utf8))]]).encoded()
    try check((try? DeskClipboardContent.decode(valid + Data([0]), limits: limits)) == nil, "Trailing content was accepted")
    try check((try? DeskClipboardContent.decode(DeskClipboardContent(items: [[.init(type: .plainText, data: Data([0xff, 0xfe]))]]).encoded(), limits: limits)) == nil,
              "Plain text that is not UTF-8 was accepted")
    try check((try? DeskClipboardContent.decode(DeskClipboardContent(items: [[.init(type: .png, data: Data([1])), .init(type: .tiff, data: Data([2]))]]).encoded(), limits: limits)) == nil,
              "Two image representations of one item were accepted")
    print("PASS: shared clipboard wire: one kilobyte control and 64 KB chunk envelopes, padding hides length and kind, bounded compression, one negotiated format; reassembly refuses corruption, reordering, replay, missing chunks, other transfers and a wrong digest")

    // MARK: Version gating

    try check(DeskClipboard.wireFormat(for: .copied(copy: UUID(), age: 0, what: nil), negotiated: nil) == nil,
              "A clipboard message could be sent to a Mac that never said it shares copies")
    try check(DeskClipboard.wireFormat(for: .hello(formats: [1], reply: false), negotiated: nil) == 0, "A hello could not be sent to a new Mac")
    try check(DeskClipboard.wireFormat(for: .bringOver, negotiated: 1) == 1, "A negotiated format was not used")
    do {
        // A Mac running a Perch without clipboard support (2.0.297 on the
        // Studio): it receives the hello and routes it nowhere.
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio"], answering: [0])
        let new = desk.macs[0], old = desk.macs[1]
        new.clipboard.start()
        defer { desk.stop() }
        settle(0.2)
        new.store.copy([[(text, Data("never sent".utf8))]])
        settle(0.3)
        new.store.copy([[(png, bytes(5000))]])
        settle(0.3)
        new.clipboard.bringOver(keyboard: old.id)
        let toOld = new.link.messages(to: old.id)
        try check(!toOld.isEmpty, "The older Mac was not even greeted")
        try check(toOld.allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A clipboard message other than a hello was sent to a Mac that never said it shares copies: \(toOld)")
        try check(toOld.count == 1, "The older Mac was greeted more than once inside the greeting interval: \(toOld.count)")
        try check(new.clipboard.decisions.contains(.peerCannot("Studio", .notSupported)), "Not sending to an older Mac was not named")
        // A Mac that announces without having greeted is not listened to.
        let intruder = try DeskClipboardWire.encode(.copied(copy: UUID(), age: 0, what: .init(kind: .text, count: 1, small: true)), format: 1)
        new.clipboard.receive(DeskClipboardWire.prefix + intruder, peer: old.id)
        settle(0.1)
        try check(new.clipboard.waiting == nil && new.link.messages(to: old.id).allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A Mac that never greeted was listened to or answered")
        // A Mac that speaks only a newer format is treated the same way.
        new.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.hello(formats: [2], reply: false), format: 0)), peer: old.id)
        settle(0.1)
        new.store.copy([[(text, Data("still never sent".utf8))]])
        settle(0.3)
        try check(new.link.messages(to: old.id).allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A Mac with no format in common was sent more than a hello")
        try check(new.clipboard.decisions.contains(.peerCannot("Studio", .format)), "A Mac with no format in common was not named")
    }
    print("PASS: shared clipboard sends an older Perch nothing but a hello, whatever is copied or brought over, ignores a Mac that never greeted, and refuses a Mac with no format in common")

    // MARK: Small text goes straight onto the other Macs' clipboards

    do {
        // Only this scenario's decisions are compared with the log.
        PerchLog.reset(); logged = []
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio", "Mini"])
        let a = desk.macs[0], b = desk.macs[1], c = desk.macs[2]
        // Default (d): the Mini's sharing is off, so no content reaches it.
        desk.permitted[c.id] = false
        b.store.copy([[(text, Data("already on the Studio".utf8))]])
        c.store.copy([[(text, Data("already on the Mini".utf8))]])
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        let canary = "PERCH-CANARY-" + UUID().uuidString
        let canaryText = Data((canary + String(repeating: "q", count: 12_345 - canary.utf8.count)).utf8)
        let richText = Data("{\\rtf1 \(canary)}".utf8)
        a.store.copy([[(text, canaryText), (rtf, richText), ("com.example.private", Data("app private".utf8))]])
        try wait("small text arrives on its own") { b.store.first == canaryText }
        let arrived = b.store.current
        try check(arrived.count == 1 && arrived[0].map(\.type) == [text, rtf, DeskClipboardMarker.received] && arrived[0][1].data == richText,
                  "The copy did not arrive whole and marked, or an app's private type came with it: \(arrived.map { $0.map(\.type) })")
        try check(b.fakes.presented.isEmpty, "Small text showed a popup")
        try wait("what was waiting clears on the Studio") { b.clipboard.waiting == nil }
        settle(0.2)
        try check(c.store.first == Data("already on the Mini".utf8) && c.link.count(DeskClipboardTests.isFetch) == 0,
                  "Small text reached a Mac whose sharing is off")
        try check(a.link.count { if case .copied = $0 { return true }; return false } == 2, "A copy was not announced exactly once to each other Mac")
        // Scott's line, 64 KB of text in all: exactly that moves on its own, one byte more waits.
        a.store.copy([[(text, Data(repeating: 66, count: DeskClipboardDescriptor.smallText))]])
        try wait("64 KB of text arrives") { b.store.first?.count == DeskClipboardDescriptor.smallText }
        let fetchesBefore = b.link.count(DeskClipboardTests.isFetch)
        a.store.copy([[(text, Data(repeating: 67, count: 16_000)), (rtf, Data(repeating: 68, count: DeskClipboardDescriptor.smallText - 15_999))]])
        try wait("one byte over waits") { b.clipboard.waiting?.what.kind == .text }
        settle(0.2)
        try check(b.link.count(DeskClipboardTests.isFetch) == fetchesBefore && b.store.first?.count == DeskClipboardDescriptor.smallText,
                  "Text over 64 KB in all moved without being brought over")
        try check(b.clipboard.waiting?.what.small == false && b.clipboard.waiting?.what.sizeText == "64 KB to 1 MB", "What waits did not say its kind and size")

        // Never a password, never anything temporary or generated: nothing about
        // them leaves the Mac, and what was waiting elsewhere stays as it was.
        let waitingBefore = b.clipboard.waiting
        for (marker, reason) in [(DeskClipboardMarker.concealed, DeskClipboardReason.concealed), (DeskClipboardMarker.transient, .transient),
                                 (DeskClipboardMarker.autoGenerated, .autoGenerated)] {
            let announcements = a.link.count(DeskClipboardTests.isCopied), reads = a.store.dataReads
            a.store.copy([[(text, Data("correct horse battery staple".utf8)), (marker, Data())]])
            try wait("\(reason) copy kept here") { a.clipboard.lastDecision == .notAnnounced(reason) }
            settle(0.15)
            try check(a.link.count(DeskClipboardTests.isCopied) == announcements && a.store.dataReads == reads,
                      "A copy marked \(marker) was announced or read")
            try check(b.clipboard.waiting == waitingBefore && b.store.first?.count == DeskClipboardDescriptor.smallText, "A \(reason) copy changed another Mac")
        }
        // A newer copy nobody can bring over still clears what was waiting (default (b)).
        a.store.copy([[("com.example.private", Data("app private".utf8))]])
        try wait("an unsupported copy clears what waits") { b.clipboard.waiting == nil && b.clipboard.lastDecision == .newerElsewhere(from: "MacBook") }

        // Logs: never contents, never exact sizes, never types.
        let clipboardLines = logged.filter { $0.category == DeskClipboardDecision.category }.map(\.message)
        for line in clipboardLines {
            for forbidden in [canary, "12345", "12,345", "65536", "65,536", text, rtf, png, "horse", "com.example"] {
                try check(!line.contains(forbidden), "The decision log revealed \(forbidden): \(line)")
            }
        }
        // Decision and log cannot disagree: every decision's own line is what
        // was logged, and every logged line is some decision's line.
        let all = desk.macs.flatMap { $0.clipboard.decisions }
        let decided = Set(all.map(\.line))
        for decision in all { try check(clipboardLines.contains(decision.line), "A decision was not logged as decided: \(decision.line)") }
        for line in clipboardLines { try check(decided.contains(line), "A logged line matches no decision: \(line)") }
    }
    // Every reason reads distinctly, and every refusal names its own.
    let reasons = DeskClipboardReason.allCases
    try check(Set(reasons.map(\.text)).count == reasons.count, "Two reasons read the same")
    for reason in reasons {
        for decision in [DeskClipboardDecision.notAnnounced(reason), .refusedBy("Studio", transfer: UUID(), reason),
                         .failed(from: "Studio", transfer: UUID(), reason, detail: nil), .discarded(transfer: UUID(), reason),
                         .notBringing(reason), .refused(to: "Studio", transfer: UUID(), reason), .peerCannot("Studio", reason)] {
            try check(decision.reason == reason && decision.line.hasSuffix(" because " + reason.text), "A decision's logged reason disagreed with it: \(decision.line)")
        }
        let line = DeskPasteProgress.line(for: reason, from: "Studio")
        try check(!line.isEmpty && line.count <= 48, "The popup's line for \(reason) is empty or long: \(line)")
    }
    print("PASS: shared clipboard pushes small text: a copy of 64 KB of text or less lands on every other Mac with sharing on, silently and marked, one byte more only waits; passwords, temporary and generated copies leave no trace; logs hold no contents, types or exact sizes and always match the decision")

    // MARK: A received copy is never sent on

    do {
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio", "Mini"])
        let a = desk.macs[0], b = desk.macs[1], c = desk.macs[2]
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        a.store.copy([[(text, Data("from the MacBook".utf8))]])
        try wait("both receive it") { b.store.first == Data("from the MacBook".utf8) && c.store.first == Data("from the MacBook".utf8) }
        let echoesBefore = b.link.count(DeskClipboardTests.isCopied) + c.link.count(DeskClipboardTests.isCopied)
        settle(0.6)
        try check(b.link.count(DeskClipboardTests.isCopied) + c.link.count(DeskClipboardTests.isCopied) == echoesBefore,
                  "A received copy was announced again: it would echo back or be relayed")
        try check(a.store.first == Data("from the MacBook".utf8) && a.link.count(DeskClipboardTests.isFetch) == 0, "A copy echoed back to the Mac it came from")
        // Even when the clipboard's own count moves without Perch noticing the
        // write (a slow clipboard), the mark alone stops it.
        let stray = b.store.current
        b.store.copy(stray)
        settle(0.6)
        try check(b.link.count(DeskClipboardTests.isCopied) + c.link.count(DeskClipboardTests.isCopied) == echoesBefore,
                  "A marked copy was announced after its count changed")
        // And it is never served: asking the Studio for it is refused.
        let asked = UUID()
        b.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.fetch(transfer: asked, copy: UUID(), key: Data(count: 32)), format: 1)), peer: c.id)
        try wait("a received copy is not served") { b.clipboard.decisions.contains(.refused(to: "Mini", transfer: asked, .unknownCopy)) }
        // Something copied fresh on the Studio is its own, and is announced.
        b.store.copy([[(text, Data("typed on the Studio".utf8))]])
        try wait("a fresh copy goes out") { a.store.first == Data("typed on the Studio".utf8) }
    }
    print("PASS: shared clipboard never echoes: a received copy carries Perch's mark and is never announced, relayed or served, even when the clipboard changes under it; a fresh copy on that Mac goes out as usual")

    // MARK: Everything else is announced, not sent

    do {
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        let folder = desk.root.appendingPathComponent("announced")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileA = folder.appendingPathComponent("A.mov"), fileB = folder.appendingPathComponent("B.mov")
        try bytes(300_000).write(to: fileA); try bytes(300_000).write(to: fileB)
        let cases: [(String, [[(type: String, data: Data)]], DeskClipboardDescriptor.Kind, Int, String)] = [
            ("a photo", [[(png, bytes(700_000)), (tiff, bytes(900_000))]], .image, 1, "64 KB to 1 MB"),
            ("three photos", [[(png, bytes(2000))], [(png, bytes(2000))], [(tiff, bytes(2000))]], .image, 3, "under 64 KB"),
            ("long text", [[(text, Data(repeating: 65, count: 2_000_000))]], .text, 1, "1 to 8 MB"),
            ("two files", [[(DeskClipboardMarker.fileURL, fileA.dataRepresentation)], [(DeskClipboardMarker.fileURL, fileB.dataRepresentation)]], .files, 2, "64 KB to 1 MB")]
        for (label, copied, kind, count, size) in cases {
            let fetches = b.link.count(DeskClipboardTests.isFetch), content = a.link.count(DeskClipboardTests.isContent), before = b.store.first
            let known = b.clipboard.waiting?.copy
            a.store.copy(copied)
            try wait(label) { b.clipboard.waiting?.what.kind == kind && b.clipboard.waiting?.copy != known }
            settle(0.2)
            try check(b.link.count(DeskClipboardTests.isFetch) == fetches && a.link.count(DeskClipboardTests.isContent) == content && b.store.first == before,
                      "\(label) moved without being brought over")
            try check(b.clipboard.waiting?.what.count == count && b.clipboard.waiting?.what.sizeText == size,
                      "\(label) was announced as \(String(describing: b.clipboard.waiting?.what))")
        }
        try check(b.fakes.presented.isEmpty, "An announcement showed a popup")
        // A Mac that says its copy is small text but sends more is refused.
        a.link.rewrite = { message in
            if case .copied(let copy, let age, _) = message { return .copied(copy: copy, age: age, what: .init(kind: .text, count: 1, small: true, size: 1)) }
            return nil
        }
        a.store.copy([[(png, bytes(1000))]])
        try wait("a picture claimed as small text is refused") {
            if case .failed(_, _, .corrupt, "more than small text arrived unasked")? = b.clipboard.lastDecision { return true }; return false
        }
        a.store.copy([[(text, Data(repeating: 70, count: 100_000))]])
        try wait("long text claimed as small is refused") {
            if case .failed(_, _, .corrupt, let detail)? = b.clipboard.lastDecision { return detail?.contains("declares a size") == true }; return false
        }
        try check(!b.store.marked || b.store.first?.count != 100_000, "Content larger than small text landed unasked")
        a.link.rewrite = nil
    }
    print("PASS: shared clipboard only announces everything else: photos, long text and files say their kind, count and size bucket and move nothing until brought over; a Mac that claims small text and sends more is refused")

    // MARK: Bringing it over

    do {
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        b.store.copy([[(text, Data("what the Studio had".utf8))]])
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        let original = Data("what the Studio had".utf8)
        /// Copy on the MacBook and wait until the Studio knows of that copy.
        func copyOnMacBook(_ label: String, _ items: [[(type: String, data: Data)]]) throws {
            let before = b.clipboard.waiting?.copy
            a.store.copy(items)
            try wait(label) { b.clipboard.waiting != nil && b.clipboard.waiting?.copy != before }
        }
        // Default (c): nothing waiting, nothing happens.
        let sentBefore = b.link.sent.count
        b.clipboard.bringOverHere()
        try check(b.clipboard.lastDecision == .nothingWaiting && b.fakes.presented.isEmpty && b.link.sent.count == sentBefore,
                  "Bring over with nothing waiting did something")
        let image = bytes(700_000)
        try copyOnMacBook("photo waits", [[(png, image), (tiff, bytes(900_000))]])
        var gap = try mainGap {
            b.clipboard.bringOverHere()
            b.clipboard.bringOverHere()
            try wait("photo arrives") { b.store.first == image }
        }
        try check(gap < 0.3, "Bringing a photo over stalled the main thread for \(gap) s")
        try check(b.fakes.presented.count == 1, "Pressing twice showed two popups or none: \(b.fakes.presented.count)")
        let popup = b.fakes.presented[0]
        try check(popup.title == "A photo from MacBook", "The popup said \(popup.title)")
        try check(b.store.current[0].map(\.type) == [png, DeskClipboardMarker.received], "More than one image representation, or no mark, arrived")
        try wait("popup finishes and closes") { popup.phase == .done && popup.line == "Ready to paste" && popup.isClosed }
        try check(b.clipboard.waiting == nil, "What was waiting stayed after it was brought over")
        // Too large: named by the Mac that holds it; it will never come, so it stops waiting.
        try copyOnMacBook("long text waits", [[(text, Data(repeating: 65, count: 3 * 1024 * 1024))]])
        b.clipboard.bringOverHere()
        try wait("too large refused") { b.fakes.last?.phase == .failed }
        try check(b.fakes.last?.line == "Too large to bring over" && b.store.first == image && b.clipboard.waiting == nil,
                  "Too large was not named, left something behind, or kept waiting")
        // Failure pastes nothing: the other Mac leaves halfway.
        let second = bytes(1_500_000)
        try copyOnMacBook("second photo waits", [[(png, second)]])
        a.link.chunkDelay = 0.05
        b.clipboard.bringOverHere()
        try wait("halfway") { (b.clipboard.bringOverProgress ?? 0) > 0.1 }
        b.link.peers.remove(a.id); b.clipboard.peersChanged()
        try wait("leaving is named") { b.fakes.last?.phase == .failed }
        try check(b.fakes.last?.line == "Couldn’t reach MacBook" && b.store.first == image && b.clipboard.waiting == nil,
                  "A Mac leaving mid-transfer left part of a copy, said something else, or kept waiting")
        b.link.peers.insert(a.id); b.clipboard.peersChanged()
        a.link.chunkDelay = 0
        // Cancel stops it, on both Macs, and changes nothing here.
        try copyOnMacBook("third photo waits", [[(png, bytes(1_600_000))]])
        a.link.chunkDelay = 0.05
        b.clipboard.bringOverHere()
        try wait("moving") { (b.clipboard.bringOverProgress ?? 0) > 0.05 }
        b.fakes.last?.cancel()
        try check(b.fakes.last?.isClosed == true && b.fakes.last?.canCancel == false, "Cancel did not close the popup")
        try wait("the sender stops") { a.clipboard.decisions.contains { if case .stoppedSending(_, _, .cancelled) = $0 { return true }; return false } }
        settle(0.4)
        try check(b.store.first == image && b.clipboard.waiting != nil, "Cancel left part of a copy, or forgot what waits")
        a.link.chunkDelay = 0
        // Slow: the main thread never waits, and nothing changes here until the verified copy is complete.
        a.link.chunkDelay = 0.1
        let slow = bytes(1_500_000)
        try copyOnMacBook("slow photo waits", [[(png, slow)]])
        var seen: [Data?] = [], progress: [Double] = []
        gap = try mainGap {
            b.clipboard.bringOverHere()
            try wait("slow photo arrives", seconds: 10) {
                seen.append(b.store.first)
                if let value = b.clipboard.bringOverProgress { progress.append(value) }
                return b.store.first == slow
            }
        }
        try check(gap < 0.3, "A slow transfer stalled the main thread for \(gap) s")
        try check(seen.allSatisfy { $0 == image || $0 == slow } && seen.filter { $0 == image }.count > 5, "A partial copy was visible, or the transfer was not slow")
        try check(progress.contains { $0 > 0 && $0 < 1 } && zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 }, "Progress did not move steadily: \(progress)")
        a.link.chunkDelay = 0
        // Dead: asked, never answers.
        try copyOnMacBook("dead photo waits", [[(png, bytes(200_000))]])
        a.link.intercept = { _, message in switch message { case .manifest?, .chunk?: return true; default: return false } }
        gap = try mainGap {
            b.clipboard.bringOverHere()
            try wait("no reply is named") { b.fakes.last?.phase == .failed }
        }
        try check(gap < 0.3 && b.fakes.last?.line == "Couldn’t reach MacBook" && b.clipboard.waiting != nil, "A silent Mac stalled the main thread, or was not named")
        a.link.intercept = nil
        // Pacing: while the desk link's queue is full, no chunk is added to it.
        a.link.queued = DeskClipboard.paceLimit
        let chunks = a.link.count { if case .chunk = $0 { return true }; return false }
        b.clipboard.bringOverHere()
        try wait("manifest while paced") { a.link.count { if case .manifest = $0 { return true }; return false } > 0 && b.fakes.last?.phase == .moving }
        settle(0.2)
        try check(a.link.count { if case .chunk = $0 { return true }; return false } == chunks, "Chunks were queued onto a full desk link")
        a.link.queued = 0
        try wait("paced transfer resumes") { b.fakes.last?.phase == .done }
    }
    let chunkEnvelope = try DeskClipboardWire.encode(DeskClipboardWire.seal(bytes(200_000), transfer: transfer, copy: copyID, key: key, format: 1).chunk(0, key: key), format: 1)
    let onWire = try KVMMessageFramer.encode(JSONEncoder().encode(KVMDeskMessage.application(DeskClipboardWire.prefix + chunkEnvelope)))
    try check(onWire.count <= DeskClipboard.chunkWireBytes, "A chunk takes \(onWire.count) bytes on the desk link, more than the pacing allows for")
    try check(DeskClipboard.paceLimit <= KVMPeerTransport.sendLimit / 2, "Clipboard pacing leaves no room below the transport's limit")
    print("PASS: shared clipboard brings over with the popup: nothing waiting does nothing; a photo arrives marked with steady progress and the popup says Ready to paste and closes; too large, a Mac leaving, cancel and a silent Mac are named and change nothing; a slow Mac never stalls the main thread; the desk link is paced below its limit")

    // MARK: Which Mac brings it over, and when what waits clears

    try check(DeskClipboard.bringOverTarget(keyboard: nil, local: copyID) == copyID, "Without sharing running, bring over did not act here")
    let elsewhere = UUID()
    try check(DeskClipboard.bringOverTarget(keyboard: elsewhere, local: copyID) == elsewhere, "Bring over did not act for the Mac typing goes to")
    try check(DeskClipboard.bringOverTarget(keyboard: copyID, local: copyID) == copyID, "Bring over left the Mac typing goes to")
    do {
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio", "Mini"])
        let a = desk.macs[0], b = desk.macs[1], c = desk.macs[2]
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        let photo = bytes(300_000)
        a.store.copy([[(png, photo)]])
        try wait("photo waits on both") { b.clipboard.waiting != nil && c.clipboard.waiting != nil }
        // Default (a): ⌃⌥⌘V pressed on the Mini's keyboard while typing goes to
        // the Studio brings it to the Studio, not the Mini.
        c.clipboard.bringOver(keyboard: b.id)
        try wait("the Studio brings it over") { b.store.first == photo }
        try check(c.store.first != photo && c.fakes.presented.isEmpty && b.fakes.presented.count == 1,
                  "Bring over acted on the Mac whose keyboard was pressed rather than where typing goes")
        try check(c.clipboard.decisions.contains(.askedToBringOver(on: "Studio")) && c.clipboard.waiting != nil, "Asking the Studio was not named, or the Mini forgot what waits")
        // Pressed where typing goes: here.
        c.clipboard.bringOver(keyboard: c.id)
        try wait("the Mini brings it over itself") { c.store.first == photo }
        // Default (b): a newer copy anywhere clears what waits, small text included.
        a.store.copy([[(png, bytes(3000))]])
        try wait("new photo waits") { b.clipboard.waiting?.copy != nil && b.clipboard.waiting?.what.size == DeskClipboardPolicy.sizeIndex(3000) }
        c.store.copy([[(text, Data("newer, from the Mini".utf8))]])
        try wait("small text replaces it") { b.clipboard.waiting == nil && a.clipboard.waiting == nil && b.store.first == Data("newer, from the Mini".utf8) }
        // A copy made here clears what waits here.
        a.store.copy([[(png, bytes(4000))]])
        try wait("waits again") { b.clipboard.waiting != nil }
        b.store.copy([[(text, Data("typed on the Studio".utf8))]])
        try wait("a copy here clears it") { b.clipboard.waiting == nil }
        // The Mac holding it leaves: it clears.
        a.store.copy([[(png, bytes(5000))]])
        try wait("waits once more") { c.clipboard.waiting?.peer == a.id }
        c.link.peers.remove(a.id); c.clipboard.peersChanged()
        try check(c.clipboard.waiting == nil, "What waited stayed after the Mac holding it left")
        c.link.peers.insert(a.id); c.clipboard.peersChanged()
        // The same copy announced again, even as if a moment newer, changes nothing.
        if let again = b.clipboard.waiting {
            let fetches = b.link.count(DeskClipboardTests.isFetch)
            b.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.copied(copy: again.copy, age: 0, what: again.what), format: 1)), peer: a.id)
            settle(0.05)
            try check(b.clipboard.waiting == again && b.link.count(DeskClipboardTests.isFetch) == fetches, "A copy announced again was taken for a new one")
        }
        // An announcement older than what this Mac already has changes nothing.
        let known = b.clipboard.waiting
        b.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.copied(copy: UUID(), age: 60_000, what: .init(kind: .image, count: 1, small: false, size: 2)), format: 1)), peer: a.id)
        settle(0.05)
        try check(b.clipboard.waiting == known, "An older copy replaced a newer one")
        // Sharing off here: no bring over, and it says why.
        desk.permitted[b.id] = false
        b.clipboard.bringOverHere()
        try check(b.clipboard.lastDecision == .notBringing(.sharingOffHere), "Bring over ran with sharing off")
        desk.permitted[b.id] = true
    }
    print("PASS: shared clipboard brings over for the Mac typing goes to, whichever keyboard pressed ⌃⌥⌘V; what waits clears when anything newer is copied on any Mac, when a copy is made here, and when the Mac holding it leaves; an older announcement changes nothing")

    // MARK: A hung app on the copying Mac

    do {
        let desk = DeskClipboardTestDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        desk.start()
        defer { desk.stop() }
        try wait("greetings") { desk.greeted() }
        a.store.readDelay = 1.2
        let gap = mainGap {
            a.store.copy([[(text, Data("promised by a hung app".utf8))]])
            settle(0.8)
        }
        try check(gap < 0.3, "A hung app stalled Perch's main thread for \(gap) s")
        try check(b.store.first != Data("promised by a hung app".utf8), "The fixture's app was not hung")
        a.store.readDelay = 0
        // Once the hung read returns, the copy goes out after all.
        try wait("recovered after a hang", seconds: 4) { b.store.first == Data("promised by a hung app".utf8) }
    }
    print("PASS: shared clipboard survives a hung app: the copying Mac's main thread never waits for it, and the copy goes out once the app hands it over")

    // MARK: The popup, as logic

    do {
        let time = DeskManualTime()
        func make(_ title: String = "A photo from Studio") -> (DeskPasteProgress, () -> Int, () -> Int) {
            var changes = 0, closes = 0
            let p = DeskPasteProgress(title: title, clock: { time.now }, after: { time.after($0, $1) })
            p.changed = { changes += 1 }; p.closed = { closes += 1 }
            return (p, { changes }, { closes })
        }
        time.now = 10
        var (p, changes, closes) = make()
        p.advance(to: 0.001); p.advance(to: 0.005)
        try check(changes() == 0, "The popup redrew for less than a percent")
        p.advance(to: 0.5); p.advance(to: 0.4)
        try check(p.fraction == 0.5 && changes() == 1, "Progress went backwards or did not redraw")
        time.advance(to: 10.1)
        p.finish()
        try check(p.phase == .done && p.line == "Ready to paste" && p.fraction == 1 && !p.canCancel, "Finishing did not say it is ready")
        time.advance(to: 11.05)
        try check(closes() == 0, "The popup closed before it had been read")
        time.advance(to: 11.1)
        try check(closes() == 1 && p.isClosed, "The popup did not close itself once done")
        p.fail("late"); p.close()
        try check(p.line == "Ready to paste" && closes() == 1, "A finished popup changed or closed twice")
        // Over the cable, done within one frame: still on screen for half a second.
        time.now = 20
        (p, changes, closes) = make()
        time.advance(to: 20.01)
        p.finish()
        time.advance(to: 20.49)
        try check(closes() == 0, "A fast transfer flashed the popup")
        time.advance(to: 21.01)
        try check(closes() == 1, "A fast transfer's popup stayed open")
        // A failure: one line, three seconds, then gone.
        time.now = 30
        (p, _, closes) = make()
        p.fail("Couldn’t reach Studio")
        try check(p.phase == .failed && p.line == "Couldn’t reach Studio" && !p.canCancel, "A failure did not say what happened")
        time.advance(to: 32.9)
        try check(closes() == 0, "A failure closed before it could be read")
        time.advance(to: 33)
        try check(closes() == 1, "A failure's popup stayed open")
        // Cancel: the person's one action. Stops at once.
        time.now = 40
        var cancelled = 0
        (p, _, closes) = make()
        p.onCancel = { cancelled += 1 }
        try check(p.canCancel, "A popup on its way could not be cancelled")
        p.cancel(); p.cancel()
        try check(cancelled == 1 && closes() == 1 && p.phase == .cancelled, "Cancel did not stop and close exactly once")
        try check(DeskPasteProgress.title(.init(kind: .image, count: 1, small: false), from: "Studio") == "A photo from Studio" &&
                  DeskPasteProgress.title(.init(kind: .image, count: 3, small: false), from: "Studio") == "3 photos from Studio" &&
                  DeskPasteProgress.title(.init(kind: .files, count: 1, small: false), from: "Studio") == "A file from Studio" &&
                  DeskPasteProgress.title(.init(kind: .files, count: 3, small: false), from: "Studio") == "3 files from Studio" &&
                  DeskPasteProgress.title(.init(kind: .text, count: 1, small: false), from: "Studio") == "Text from Studio",
                  "The popup's words moved")
    }
    // The window: constructed, never shown, never key.
    let panel = DeskPastePanel.make()
    try check(!panel.canBecomeKey && !panel.canBecomeMain, "The popup could take focus")
    try check(panel.styleMask.contains(.nonactivatingPanel) && panel.becomesKeyOnlyIfNeeded && !panel.hidesOnDeactivate && panel.level == .floating,
              "The popup is not a floating, non-activating panel")
    try check(!panel.isVisible, "Constructing the popup showed it")
    print("PASS: shared clipboard popup: steady progress, Ready to paste, at least half a second on screen, closes itself, a failure's one line for three seconds, Cancel stops once and closes; the panel can never become key or activate Perch")

    // MARK: The bring-over shortcut

    var router = DeskKeyRouter()
    let v = Int64(kVK_ANSI_V), chord: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    func route(_ type: CGEventType, _ code: Int64, _ flags: CGEventFlags = [], repeating: Bool = false, sharing: Bool = true,
               bringOver: Shortcut? = DeskBringOverShortcut.shortcut, perchOwned: Bool = true) -> DeskKeyDisposition {
        router.route(type: type, keyCode: code, flags: flags, autorepeat: repeating, sharing: sharing, presets: [],
                     localShortcut: { code, flags in perchOwned && code == v && flags.contains(chord) }, bringOver: bringOver)
    }
    // Registered like Perch's other shortcuts, it would stay on the Mac whose
    // keyboard was pressed; bring over is recognised first, for the Mac typing goes to.
    try check(route(.keyDown, v, chord) == .bringOver, "⌃⌥⌘V did not bring over")
    try check(route(.keyDown, v, chord, repeating: true) == .consumed && route(.keyUp, v, chord) == .consumed,
              "A held ⌃⌥⌘V repeated or leaked its release to an app")
    try check(route(.keyDown, v, [.maskCommand]) == .forward && route(.keyUp, v) == .forward, "An ordinary paste was taken for bring over")
    try check(route(.keyDown, v, chord, bringOver: nil) == .local, "With bring over stepped aside, the shortcut holding its keys lost them")
    try check(route(.keyDown, v, chord, sharing: false) == .local, "Bring over acted with sharing off")
    try check(router.consumedKeys.isEmpty || route(.keyUp, v) != .forward, "Key routing kept stale held keys")
    // Its place among Perch's shortcuts: others see it, and it steps aside for one already there.
    let registry = ShortcutRegistry()
    registry.provide(ShortcutRegistry.Source.deskClipboard) { [unowned registry] in DeskBringOverShortcut.claims(in: registry) }
    try check(registry.problem(with: DeskBringOverShortcut.shortcut, excluding: ShortcutRegistry.Source.emergency)?.contains(DeskBringOverShortcut.owner) == true,
              "Another Perch shortcut could take ⌃⌥⌘V")
    try check(DeskBringOverShortcut.active(in: registry) == DeskBringOverShortcut.shortcut, "Bring over stepped aside with nothing in its way")
    registry.provide(ShortcutRegistry.Source.countdown) { [ShortcutClaim(owner: "the countdown", shortcut: DeskBringOverShortcut.shortcut)] }
    try check(DeskBringOverShortcut.active(in: registry) == nil, "Bring over took keys another Perch shortcut already holds")
    try check(registry.problem(with: DeskBringOverShortcut.shortcut, excluding: ShortcutRegistry.Source.countdown) == nil,
              "A shortcut that held ⌃⌥⌘V first was reported as conflicting with bring over")
    try check(DeskBringOverShortcut.shortcut.title.contains("V") && DeskBringOverShortcut.shortcut.modifiers == .standard, "Bring over is not ⌃⌥⌘V")
    print("PASS: shared clipboard's ⌃⌥⌘V is recognised before Perch's other shortcuts so it acts for the Mac typing goes to, never reaches an app, leaves ⌘V alone, is claimed among Perch's shortcuts and steps aside for one already holding its keys")

    // MARK: What the menu bar icon will read

    do {
        var group = KVMGroup.sample()
        let local = group.computers[0].id, other = group.computers.count > 1 ? group.computers[1].id : UUID()
        if group.computers.count < 2 { group.computers.append(.init(id: other, name: "Studio")) }
        let preset = group.presets.first { preset in
            preset.assignments.contains { a in group.connections.first { $0.id == a.connection }?.computer == other }
        }
        let what = DeskClipboardDescriptor(kind: .image, count: 1, small: false, size: 3)
        let status = DeskShareStatus.make(waitingFrom: "Studio", waiting: what, sharingOn: true, online: [local, other], local: local, group: group, activePreset: preset?.id)
        try check(status.waitingFrom == "Studio" && status.waiting == what && status.sharingOn && status.connected == 1, "The icon's state lost a fact: \(status)")
        try check(status.onActiveDesk == (preset != nil), "Whether a connected Mac is in the active preset was wrong")
        let alone = DeskShareStatus.make(waitingFrom: nil, waiting: nil, sharingOn: false, online: [local], local: local, group: group, activePreset: nil)
        try check(alone == .init(waitingFrom: nil, waiting: nil, sharingOn: false, connected: 0, onActiveDesk: false), "A Mac alone showed company: \(alone)")
        let noPreset = DeskShareStatus.make(waitingFrom: nil, waiting: nil, sharingOn: true, online: [local, other], local: local, group: group, activePreset: nil)
        try check(noPreset.connected == 1 && !noPreset.onActiveDesk, "No active preset still counted a Mac as on it")
        let half = DeskShareStatus.make(waitingFrom: "Studio", waiting: nil, sharingOn: true, online: [local], local: local, group: group, activePreset: nil)
        try check(half.waitingFrom == nil && half.waiting == nil, "A name without a copy showed as waiting")
    }
    print("PASS: shared clipboard exposes one small state for the menu bar icon: what waits and from which Mac, Share on this Mac, how many Perches are connected and whether one is in the active preset")

    // MARK: The real pasteboard adapter, on a private pasteboard

    let name = NSPasteboard.Name("local.scott.perch.selftest." + UUID().uuidString)
    try check(name != .general && name != .find && name != .drag && name != .font && name != .ruler, "The adapter test must use a private pasteboard")
    let board = NSPasteboard(name: name)
    defer { board.releaseGlobally() }
    let system = SystemDeskPasteboard(board)
    let plain = Data("private pasteboard".utf8), picture = bytes(2048)
    let count = system.replace(with: [[(type: text, data: plain), (type: rtf, data: Data("{\\rtf1 x}".utf8))], [(type: png, data: picture)]])
    let types = system.itemTypes()
    try check(count == system.changeCount && types.count == 2 && Set(types[0]).isSuperset(of: [text, rtf]) && types[1].contains(png),
              "The pasteboard adapter did not write every item: \(types)")
    try check(system.data(item: 0, type: text) == plain && system.data(item: 1, type: png) == picture, "The pasteboard adapter did not read back what it wrote")
    // What Perch writes is plain data, already there: nothing is promised, so a
    // paste never calls back into Perch.
    try check(board.pasteboardItems?.first?.data(forType: .init(text)) == plain, "Written data was not immediately readable")
    // Written through the access layer, a received copy carries the mark and
    // reads back as received.
    let access = DeskPasteboardAccess(store: system, timeout: 1)
    var written: Result<Int, DeskClipboardReason>?
    access.write(DeskClipboardContent(items: [[.init(type: .plainText, data: plain)]]), marker: copyID, ifUnchanged: system.changeCount) { written = $0 }
    try wait("marked write") { written != nil }
    try check(DeskClipboardPolicy.assess(system.itemTypes()) == .withheld(.received) && system.data(item: 0, type: text) == plain,
              "A received copy on a real pasteboard was not recognised as received")
    board.clearContents()
    let concealedItem = NSPasteboardItem()
    concealedItem.setString("s3cret", forType: .string)
    concealedItem.setData(Data(), forType: .init(DeskClipboardMarker.concealed))
    board.writeObjects([concealedItem])
    try check(DeskClipboardPolicy.assess(system.itemTypes()) == .withheld(.concealed), "A real concealed marker was not seen")
    print("PASS: shared clipboard pasteboard adapter writes plain data only, marks what it received so it is recognised, and sees a password manager's concealed marker, on a private pasteboard")
}
