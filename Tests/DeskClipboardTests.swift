import AppKit
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
    init(_ id: UUID = UUID()) { localID = id }
    func name(of peer: UUID) -> String { names[peer] ?? "Unknown" }
    func send(_ data: Data, to peer: UUID) -> Bool {
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
}

/// Two or three Macs of a desk, each with its own clipboard, in memory.
private final class ClipboardDesk {
    struct Mac {
        let id: UUID
        let link: DeskClipboardFakeLink
        let store: DeskClipboardFakeStore
        let clipboard: DeskClipboard
    }
    var macs: [Mac] = []
    var permitted: [UUID: Bool] = [:]
    /// Macs outside `answering` behave like a Perch without clipboard support:
    /// the message reaches them and nothing handles it.
    init(names: [String], answering: Set<Int>? = nil) {
        for name in names {
            let link = DeskClipboardFakeLink(), store = DeskClipboardFakeStore()
            let clipboard = DeskClipboard(link: link, pasteboard: DeskPasteboardAccess(store: store, timeout: 0.3))
            clipboard.timings = .init(query: 0.3, reply: 0.6, stall: 0.6, total: 20, serveStall: 1.5, hello: 30, tick: 0.05)
            link.names[link.localID] = name
            macs.append(.init(id: link.localID, link: link, store: store, clipboard: clipboard))
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
    func stop() { macs.forEach { $0.clipboard.stop() } }
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
    try check(DeskClipboardPolicy.assess([[text, DeskClipboardMarker.fileURL, tiff]]) == .withheld(.files),
              "A copy of files was offered as its name and icon")
    try check(DeskClipboardPolicy.assess([["com.example.private"]]) == .withheld(.unsupported), "An app's private type was offered")
    try check(DeskClipboardPolicy.assess([]) == .withheld(.noCopy), "An empty pasteboard was offered")
    try check(DeskClipboardPolicy.assess([[tiff, png, text, "public.html", rtf]]) == .share([[.plainText, .richText, .html, .png]]),
              "Text did not keep every representation, or more than one image representation was chosen")
    try check(DeskClipboardPolicy.assess([[tiff]]) == .share([[.tiff]]), "A TIFF-only image was not shared")
    do {
        let store = DeskClipboardFakeStore(), access = DeskPasteboardAccess(store: store, timeout: 1)
        store.copy([[(text, Data("hunter2".utf8)), (DeskClipboardMarker.concealed, Data())]])
        var outcome: Result<DeskClipboardContent, DeskClipboardReason>?
        access.read(expecting: store.changeCount, limits: .init()) { outcome = $0 }
        try wait("concealed read") { outcome != nil }
        guard case .failure(.concealed)? = outcome else { throw AppError(message: "A concealed copy was read for sending: \(String(describing: outcome))") }
        try check(store.dataReads == 0, "A concealed copy's data was read into Perch (\(store.dataReads) reads)")
    }
    print("PASS: shared clipboard never offers concealed, transient, generated or file copies; only text, rich text and one image representation")

    // MARK: The wire

    let transfer = UUID(), copyID = UUID(), key = SymmetricKey(size: .bits256)
    let messages: [DeskClipboardMessage] = [
        .hello(formats: [1], reply: false), .ask(query: UUID()), .offer(query: UUID(), copy: copyID, age: 1234),
        .withheld(query: UUID(), reason: .concealed, age: 9), .withheld(query: UUID(), reason: .noCopy, age: nil),
        .fetch(transfer: transfer, copy: copyID, key: Data(repeating: 3, count: 32)), .ack(transfer: transfer, next: 4),
        .refuse(transfer: transfer, reason: .tooLarge), .cancel(transfer: transfer, reason: .timedOut)]
    for message in messages {
        let envelope = try DeskClipboardWire.encode(message, format: 1)
        try check(envelope.count == DeskClipboardWire.controlSize, "A control message was not exactly one kilobyte: \(message)")
        try check(try DeskClipboardWire.decode(envelope, format: 1) == message, "A message did not survive the wire: \(message)")
    }
    // Format negotiation: only the negotiated format is accepted, and before a
    // hello nothing but a hello is.
    let ask = try DeskClipboardWire.encode(.ask(query: UUID()), format: 1)
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

    try check(DeskClipboard.wireFormat(for: .ask(query: UUID()), negotiated: nil) == nil,
              "A clipboard message could be sent to a Mac that never said it shares copies")
    try check(DeskClipboard.wireFormat(for: .hello(formats: [1], reply: false), negotiated: nil) == 0, "A hello could not be sent to a new Mac")
    try check(DeskClipboard.wireFormat(for: .ask(query: UUID()), negotiated: 1) == 1, "A negotiated format was not used")
    do {
        // A Mac running a Perch without clipboard support (2.0.297 on the
        // Studio): it receives the hello and routes it nowhere.
        let desk = ClipboardDesk(names: ["MacBook", "Studio"], answering: [0])
        let new = desk.macs[0], old = desk.macs[1]
        new.store.copy([[(text, Data("never sent".utf8))]])
        new.clipboard.start()
        defer { desk.stop() }
        settle(0.2)
        new.clipboard.keyboardArrived()
        settle(0.2)
        new.clipboard.keyboardArrived()
        let toOld = new.link.messages(to: old.id)
        try check(!toOld.isEmpty, "The older Mac was not even greeted")
        try check(toOld.allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A clipboard message other than a hello was sent to a Mac that never said it shares copies: \(toOld)")
        try check(toOld.count == 1, "The older Mac was greeted more than once inside the greeting interval: \(toOld.count)")
        try check(new.clipboard.lastDecision == .notAsking(.notSupported), "Not asking an older Mac was not decided and named: \(String(describing: new.clipboard.lastDecision))")
        // A Mac that asks without having greeted is not answered at all.
        let intruder = try DeskClipboardWire.encode(.ask(query: UUID()), format: 1)
        new.clipboard.receive(DeskClipboardWire.prefix + intruder, peer: old.id)
        settle(0.1)
        try check(new.link.messages(to: old.id).allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A Mac that never greeted was answered")
        // A Mac that speaks only a newer format is treated the same way.
        new.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.hello(formats: [2], reply: false), format: 0)), peer: old.id)
        settle(0.1)
        new.clipboard.keyboardArrived()
        settle(0.1)
        try check(new.link.messages(to: old.id).allSatisfy { if case .hello? = $0 { return true }; return false },
                  "A Mac with no format in common was sent more than a hello")
        try check(new.clipboard.decisions.contains(.peerCannot("Studio", .format)), "A Mac with no format in common was not named")
    }
    print("PASS: shared clipboard sends an older Perch nothing but a hello, ignores a Mac that never greeted, and refuses a Mac with no format in common")

    // MARK: Copy here, paste there

    do {
        // Only this scenario's decisions are compared with the log.
        PerchLog.reset(); logged = []
        let desk = ClipboardDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        b.store.copy([[(text, Data("already on the Studio".utf8))]])
        desk.start()
        defer { desk.stop() }
        try wait("both Macs greet") { a.link.messages(to: b.id).contains { if case .hello? = $0 { return true }; return false } && b.clipboard.decisions.contains(.peerSupports("MacBook", format: 1)) }
        let canary = "PERCH-CANARY-" + UUID().uuidString
        let canaryText = Data((canary + String(repeating: "q", count: 12_345 - canary.utf8.count)).utf8)
        try check(canaryText.count == 12_345, "Canary fixture")
        let richText = Data("{\\rtf1 \(canary)}".utf8)
        a.store.copy([[(text, canaryText), (rtf, richText), ("com.example.private", Data("app private".utf8))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("text arrives") { b.store.current.first?.first?.data == canaryText }
        let arrived = b.store.current
        try check(arrived.count == 1 && arrived[0].map(\.type) == [text, rtf] && arrived[0][1].data == richText,
                  "The copy did not arrive whole, or an app's private type came with it: \(arrived.map { $0.map(\.type) })")
        guard case .received(let from, _, let size)? = b.clipboard.lastDecision, from == "MacBook", size == "under 64 KB" else {
            throw AppError(message: "Receiving was not decided and named: \(String(describing: b.clipboard.lastDecision))")
        }
        try wait("sender records it") { if case .sent? = a.clipboard.lastDecision { return true }; return false }
        // The same copy is not fetched twice.
        b.clipboard.keyboardArrived()
        try wait("second arrival") { b.clipboard.lastDecision == .alreadyHere(from: "MacBook") }
        // A password never travels, and its data is never read.
        let before = b.store.current.first?.first?.data, reads = a.store.dataReads
        a.store.copy([[(text, Data("correct horse battery staple".utf8)), (DeskClipboardMarker.concealed, Data())]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("concealed copy withheld") { b.clipboard.lastDecision == .notShared(from: "MacBook", .concealed) }
        try check(b.store.current.first?.first?.data == before && a.store.dataReads == reads, "A concealed copy crossed the desk or was read")
        try check(a.clipboard.lastDecision == .withheld(to: "Studio", .concealed), "Withholding was not named on the Mac that copied")
        for (marker, reason) in [(DeskClipboardMarker.transient, DeskClipboardReason.transient), (DeskClipboardMarker.autoGenerated, .autoGenerated)] {
            a.store.copy([[(text, Data("temporary".utf8)), (marker, Data())]])
            settle(0.15)
            b.clipboard.keyboardArrived()
            try wait("\(reason) copy withheld") { b.clipboard.lastDecision == .notShared(from: "MacBook", reason) }
        }
        a.store.copy([[(DeskClipboardMarker.fileURL, Data("file:///x".utf8)), (text, Data("x".utf8))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("files withheld") { b.clipboard.lastDecision == .notShared(from: "MacBook", .files) }
        // Something copied on this Mac later is never overwritten by an older copy.
        a.store.copy([[(text, Data("older, from the MacBook".utf8))]])
        settle(0.15)
        b.store.copy([[(text, Data("newer, on the Studio".utf8))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("own newer copy wins") { b.clipboard.lastDecision == .newestHere }
        try check(b.store.current.first?.first?.data == Data("newer, on the Studio".utf8), "An older copy replaced a newer one")
        // An image big enough to need many chunks arrives byte for byte, paced.
        let image = bytes(700_000)
        a.store.copy([[(png, image), (tiff, bytes(900_000))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("image arrives", seconds: 10) { b.store.current.first?.first?.data == image }
        try check(b.store.current[0].map(\.type) == [png], "More than one image representation crossed")
        // Too large: named by the Mac that holds it.
        a.store.copy([[(text, Data(repeating: 65, count: 3 * 1024 * 1024))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("too large refused") { if case .refusedBy("MacBook", _, .tooLarge)? = b.clipboard.lastDecision { return true }; return false }
        // The copy changes between the offer and the fetch: refused, not mixed.
        a.store.copy([[(text, Data("first".utf8))]])
        settle(0.15)
        a.link.intercept = nil
        b.link.intercept = { _, message in
            if case .fetch? = message { a.store.copy([[(text, Data("second".utf8))]]) }
            return false
        }
        b.clipboard.keyboardArrived()
        // Whether the MacBook notices the change before or while reading, the
        // refusal names it: the copy offered is no longer the one there.
        try wait("changed copy refused") {
            if case .refusedBy("MacBook", _, let reason)? = b.clipboard.lastDecision { return reason == .changed || reason == .unknownCopy }
            return false
        }
        b.link.intercept = nil
        // Something copied on this Mac while a fetch is on its way wins.
        settle(0.15)
        a.link.intercept = { _, message in
            if case .manifest? = message { b.store.copy([[(text, Data("typed here meanwhile".utf8))]]) }
            return false
        }
        b.clipboard.keyboardArrived()
        try wait("newer local copy wins during a fetch") { b.clipboard.lastDecision?.reason == .newerHere }
        try check(b.store.current.first?.first?.data == Data("typed here meanwhile".utf8), "A fetched copy replaced one made here meanwhile")
        a.link.intercept = nil
        // Sharing off: on this Mac nothing is asked; on the other, it says so.
        desk.permitted[b.id] = false
        let sentBefore = b.link.sent.count
        b.clipboard.keyboardArrived()
        try check(b.clipboard.lastDecision == .notAsking(.sharingOffHere) && b.link.sent.count == sentBefore, "A Mac with sharing off asked the desk")
        desk.permitted[b.id] = true
        desk.permitted[a.id] = false
        b.clipboard.keyboardArrived()
        try wait("sharing off on the other Mac") { b.clipboard.lastDecision == .notShared(from: "MacBook", .sharingOff) }
        desk.permitted[a.id] = true

        // Logs: never contents, never exact sizes, never types.
        let clipboardLines = logged.filter { $0.category == DeskClipboardDecision.category }.map(\.message)
        for line in clipboardLines {
            for forbidden in [canary, "12345", "12,345", text, rtf, png, "hunter2", "horse", "700000", "700,000"] {
                try check(!line.contains(forbidden), "The decision log revealed \(forbidden): \(line)")
            }
        }
        // Decision and log cannot disagree: every decision's own line is what
        // was logged, and every logged line is some decision's line.
        let decided = Set((a.clipboard.decisions + b.clipboard.decisions).map(\.line))
        for decision in a.clipboard.decisions + b.clipboard.decisions {
            try check(clipboardLines.contains(decision.line), "A decision was not logged as decided: \(decision.line)")
        }
        for line in clipboardLines { try check(decided.contains(line), "A logged line matches no decision: \(line)") }
    }
    // Every reason reads distinctly, and every refusal names its own.
    let reasons = DeskClipboardReason.allCases
    try check(Set(reasons.map(\.text)).count == reasons.count, "Two reasons read the same")
    for reason in reasons {
        for decision in [DeskClipboardDecision.notShared(from: "Studio", reason), .refusedBy("Studio", transfer: UUID(), reason),
                         .failed(from: "Studio", transfer: UUID(), reason, detail: nil), .withheld(to: "Studio", reason),
                         .refused(to: "Studio", transfer: UUID(), reason), .peerCannot("Studio", reason), .notAsking(reason)] {
            try check(decision.reason == reason && decision.line.hasSuffix(" because " + reason.text), "A decision's logged reason disagreed with it: \(decision.line)")
        }
    }
    print("PASS: shared clipboard end to end: copy on one Mac, keyboard arrives on the other, the newest copy is fetched once; concealed, transient, generated, file, oversized and changed copies are refused by name; newer local copies always win; logs hold no contents, types or exact sizes and always match the decision")

    // MARK: A slow or dead Mac never hangs the paste or the main thread

    do {
        let desk = ClipboardDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        b.store.copy([[(text, Data("what the Studio had".utf8))]])
        desk.start()
        defer { desk.stop() }
        try wait("greeting") { b.clipboard.decisions.contains(.peerSupports("MacBook", format: 1)) && a.clipboard.decisions.contains(.peerSupports("Studio", format: 1)) }
        let original = Data("what the Studio had".utf8)
        // Dead: the other Mac never answers.
        a.store.copy([[(text, Data("unreachable".utf8))]])
        settle(0.15)
        b.link.intercept = { _, message in if case .ask? = message { return true }; return false }
        var gap = try mainGap {
            b.clipboard.keyboardArrived()
            try wait("no answer") { b.clipboard.lastDecision == .noAnswer }
        }
        try check(gap < 0.3, "Waiting for a dead Mac stalled the main thread for \(gap) s")
        b.link.intercept = nil
        // Answers, then goes silent before sending anything.
        a.link.intercept = { _, message in
            switch message { case .manifest?, .chunk?: return true; default: return false }
        }
        gap = try mainGap {
            b.clipboard.keyboardArrived()
            try wait("reply timeout") { if case .failed(_, _, .timedOut, "no reply")? = b.clipboard.lastDecision { return true }; return false }
        }
        try check(gap < 0.3 && b.store.current.first?.first?.data == original, "A silent Mac stalled the main thread (\(gap) s) or changed the paste")
        // Stalls halfway through.
        a.store.copy([[(png, bytes(500_000))]])
        settle(0.15)
        a.link.intercept = { _, message in if case .chunk(_, let index, _, _)? = message { return index >= 2 }; return false }
        b.clipboard.keyboardArrived()
        try wait("stall timeout") { if case .failed(_, _, .timedOut, "stalled")? = b.clipboard.lastDecision { return true }; return false }
        try check(b.store.current.first?.first?.data == original, "A stalled transfer left part of a copy behind")
        try wait("sender stops") { if case .stoppedSending(_, _, .timedOut)? = a.clipboard.lastDecision { return true }; if case .stoppedSending(_, _, .cancelled)? = a.clipboard.lastDecision { return true }; return false }
        // Slow: every chunk held back. The paste keeps what was there, at once,
        // until the whole verified copy is in; the main thread never waits.
        a.link.intercept = nil
        a.link.chunkDelay = 0.12
        let slow = bytes(1_500_000)
        a.store.copy([[(png, slow)]])
        settle(0.15)
        var pastedMeanwhile: [Data?] = [], progress: [Double] = []
        gap = try mainGap {
            b.clipboard.keyboardArrived()
            try wait("slow transfer", seconds: 10) {
                pastedMeanwhile.append(b.store.current.first?.first?.data)
                if let value = b.clipboard.progress { progress.append(value) }
                return b.store.current.first?.first?.data == slow
            }
        }
        try check(progress.contains { $0 > 0 && $0 < 1 } && zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 },
                  "A large copy on its way showed no steady progress: \(progress)")
        try check(b.clipboard.progress == nil, "Progress outlived the transfer")
        try check(gap < 0.3, "A slow transfer stalled the main thread for \(gap) s")
        try check(pastedMeanwhile.allSatisfy { $0 == original || $0 == slow }, "A paste during a transfer saw a partial copy")
        try check(pastedMeanwhile.filter { $0 == original }.count > 5, "The fixture never pasted while the slow transfer was on its way")
        a.link.chunkDelay = 0
        // The app that copied is hung: its data never comes. Perch's main
        // thread carries on, and the other Mac is told why.
        a.store.readDelay = 1.2
        a.store.copy([[(text, Data("promised by a hung app".utf8))]])
        settle(0.15)
        gap = try mainGap {
            b.clipboard.keyboardArrived()
            try wait("hung app refused") { if case .refusedBy("MacBook", _, .readTimedOut)? = b.clipboard.lastDecision { return true }; return false }
        }
        try check(gap < 0.3, "A hung app stalled Perch's main thread for \(gap) s")
        a.store.readDelay = 0
        settle(1.3)
        // Once the hung read finally returns, the pasteboard is usable again.
        a.store.copy([[(text, Data("after the hang".utf8))]])
        settle(0.15)
        b.clipboard.keyboardArrived()
        try wait("recovered after a hang") { b.store.current.first?.first?.data == Data("after the hang".utf8) }
        // Pacing: while the desk link's queue is full, no chunk is added to it.
        a.link.queued = DeskClipboard.paceLimit
        a.store.copy([[(png, bytes(300_000))]])
        settle(0.15)
        let chunksBefore = a.link.messages(to: b.id).filter { if case .chunk? = $0 { return true }; return false }.count
        b.clipboard.keyboardArrived()
        let manifestsBefore = a.link.messages(to: b.id).filter { if case .manifest? = $0 { return true }; return false }.count
        try wait("manifest while paced") { a.link.messages(to: b.id).filter { if case .manifest? = $0 { return true }; return false }.count > manifestsBefore }
        settle(0.2)
        try check(a.link.messages(to: b.id).filter { if case .chunk? = $0 { return true }; return false }.count == chunksBefore, "Chunks were queued onto a full desk link")
        a.link.queued = 0
        try wait("paced transfer resumes") { if case .received? = b.clipboard.lastDecision { return true }; return false }
    }
    // One chunk as the desk link carries it fits the pacing allowance, which
    // stays far below the size at which the transport closes a link.
    let chunkEnvelope = try DeskClipboardWire.encode(DeskClipboardWire.seal(bytes(200_000), transfer: transfer, copy: copyID, key: key, format: 1).chunk(0, key: key), format: 1)
    let onWire = try KVMMessageFramer.encode(JSONEncoder().encode(KVMDeskMessage.application(DeskClipboardWire.prefix + chunkEnvelope)))
    try check(onWire.count <= DeskClipboard.chunkWireBytes, "A chunk takes \(onWire.count) bytes on the desk link, more than the pacing allows for")
    // A chunk is queued only if it still fits under the pacing limit, so the
    // clipboard never holds more than half of what the link allows; the rest
    // stays free for pointer traffic.
    try check(DeskClipboard.paceLimit <= KVMPeerTransport.sendLimit / 2, "Clipboard pacing leaves no room below the transport's limit")
    print("PASS: shared clipboard never hangs: a dead, silent, stalled or slow Mac and a hung app cost a timeout with a named reason, the paste keeps its old content until a verified copy is complete, the main thread never waits, and the desk link is paced below its limit")

    // MARK: Rate limits and keyboard arrival

    do {
        let desk = ClipboardDesk(names: ["MacBook", "Studio"])
        let a = desk.macs[0], b = desk.macs[1]
        desk.start()
        defer { desk.stop() }
        try wait("greeting") { a.clipboard.decisions.contains(.peerSupports("Studio", format: 1)) }
        // Copied after Perch started, so its age is known and it is offered.
        a.store.copy([[(text, Data("x".utf8))]])
        settle(0.15)
        for _ in 0..<25 { a.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.ask(query: UUID()), format: 1)), peer: b.id) }
        try wait("rate limit") { a.clipboard.decisions.contains(.withheld(to: "Studio", .rateLimited)) }
        // The twenty allowed questions share one look at the pasteboard, and
        // every one is answered honestly.
        try wait("questions answered") { a.link.messages(to: b.id).filter { if case .offer? = $0 { return true }; return false }.count == 20 }
        try check(!a.clipboard.decisions.contains(.withheld(to: "Studio", .readTimedOut)), "A burst of questions was answered as a pasteboard timeout")
        let fetches = (0..<2).map { _ in UUID() }
        for id in fetches {
            a.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.fetch(transfer: id, copy: UUID(), key: Data(count: 32)), format: 1)), peer: b.id)
        }
        try wait("unknown copy refused") { a.clipboard.decisions.contains { if case .refused(_, fetches[0], .unknownCopy) = $0 { return true }; return false } }
        // One copy at a time to each Mac: a second fetch while one is being sent is refused.
        guard let offered = a.link.messages(to: b.id).compactMap({ message -> UUID? in if case .offer(_, let copy, _)? = message { return copy }; return nil }).last else {
            throw AppError(message: "No offer was made to the fixture")
        }
        let first = UUID(), second = UUID()
        for id in [first, second] {
            a.clipboard.receive(DeskClipboardWire.prefix + (try DeskClipboardWire.encode(.fetch(transfer: id, copy: offered, key: Data(count: 32)), format: 1)), peer: b.id)
        }
        try wait("busy refused") { a.clipboard.decisions.contains(.refused(to: "Studio", transfer: second, .busy)) }
        try check(!a.clipboard.decisions.contains { if case .refused(_, first, _) = $0 { return true }; return false }, "The first fetch was refused too")
    }
    do {
        let link = DeskClipboardFakeLink(), store = DeskClipboardFakeStore()
        let clipboard = DeskClipboard(link: link, pasteboard: DeskPasteboardAccess(store: store, timeout: 0.3))
        clipboard.permitted = { true }
        clipboard.timings.tick = 60
        var keyboard: UUID?
        clipboard.keyboardComputer = { keyboard }
        clipboard.start(); defer { clipboard.stop() }
        settle(0.1)
        let other = UUID(), me = link.localID
        func arrivals() -> Int { clipboard.decisions.filter { $0 == .notAsking(.notSupported) }.count }
        for (value, expected) in [(nil, 0), (other, 0), (nil, 0), (me, 1), (me, 1), (nil, 1), (me, 1), (other, 1), (me, 2)] as [(UUID?, Int)] {
            keyboard = value; clipboard.keyboardMoved()
            try check(arrivals() == expected, "Keyboard arrival miscounted at \(String(describing: value)): \(arrivals()) not \(expected)")
        }
    }
    print("PASS: shared clipboard rate-limits questions, refuses unknown copies, and asks exactly once each time the keyboard arrives from another Mac")

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
    board.clearContents()
    let concealedItem = NSPasteboardItem()
    concealedItem.setString("s3cret", forType: .string)
    concealedItem.setData(Data(), forType: .init(DeskClipboardMarker.concealed))
    board.writeObjects([concealedItem])
    try check(DeskClipboardPolicy.assess(system.itemTypes()) == .withheld(.concealed), "A real concealed marker was not seen")
    print("PASS: shared clipboard pasteboard adapter writes plain data only and sees a password manager's concealed marker, on a private pasteboard")
}
