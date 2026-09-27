import Foundation
import CryptoKit

extension DeskClipboardReason: Error {}

/// The desk as the clipboard sees it: paired Macs with a live authenticated link.
protocol DeskClipboardLink: AnyObject {
    var localID: UUID { get }
    /// Paired Macs with a live authenticated link, never including this one.
    var peers: Set<UUID> { get }
    func name(of peer: UUID) -> String
    func send(_ data: Data, to peer: UUID) -> Bool
    /// Bytes still waiting to leave for this peer; nil when there is no link.
    func queuedBytes(to peer: UUID) -> Int?
}

/// The desk's own authenticated links.
final class DeskClipboardNodeLink: DeskClipboardLink {
    let node: KVMDeskNode
    init(_ node: KVMDeskNode) { self.node = node }
    var localID: UUID { node.localID }
    var peers: Set<UUID> {
        guard node.isMember else { return [] }
        return node.online.filter { $0 != node.localID && node.hasApplicationLink(to: $0) }
    }
    func name(of peer: UUID) -> String { node.group.computers.first { $0.id == peer }?.name ?? String(peer.uuidString.prefix(8)) }
    func send(_ data: Data, to peer: UUID) -> Bool { node.sendApplication(data, peer: peer) }
    func queuedBytes(to peer: UUID) -> Int? { node.queuedBytes(to: peer) }
}

/// This Mac's pasteboard, as plain synchronous calls. Only `DeskPasteboardAccess`
/// calls it, and only on its own queue. Tests use a fake or a private named
/// pasteboard, never the real one.
protocol DeskPasteboardStore: AnyObject {
    var changeCount: Int { get }
    /// The types of each item, in order.
    func itemTypes() -> [[String]]
    func data(item: Int, type: String) -> Data?
    /// Replace everything with these items. Returns the new change count.
    func replace(with items: [[(type: String, data: Data)]]) -> Int
}

/// What a copy is, once read for sending.
enum DeskClipboardSnapshot {
    case content(DeskClipboardContent)
    case files([DeskSourceFile])
}

/// Every pasteboard read and write happens here, on one serial queue, never on
/// the main thread, and every one has a deadline.
///
/// Reading another app's copy can mean waiting for that app: many put a promise
/// on the pasteboard and render the data only when it is read. If that app is
/// slow or hung, the wait happens on this queue while the main thread, which
/// carries the desk's connections and the shared pointer, carries on. After a
/// deadline the caller is told "did not hand it over in time", and while one
/// request is stuck the rest fail at once instead of queueing behind it.
final class DeskPasteboardAccess {
    struct Inspection: Equatable {
        let changeCount: Int
        let assessment: DeskClipboardPolicy.Assessment
    }
    let store: DeskPasteboardStore
    var timeout: Double
    private let queue = DispatchQueue(label: "Perch.desk.pasteboard", qos: .userInitiated)
    private var pending = 0
    private var stuck = false
    private final class Once { var done = false }
    init(store: DeskPasteboardStore, timeout: Double = 2) { self.store = store; self.timeout = timeout }

    private func run<T>(_ work: @escaping (DeskPasteboardStore) -> T, late: T, _ done: @escaping (T) -> Void) {
        guard !stuck, pending < 8 else { done(late); return }
        pending += 1
        let once = Once(), store = self.store
        queue.async { [weak self] in
            let value = work(store)
            DispatchQueue.main.async { [weak self] in
                if let self { self.pending -= 1; if self.pending == 0 { self.stuck = false } }
                guard !once.done else { return }
                once.done = true; done(value)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard !once.done else { return }
            once.done = true; self?.stuck = true; done(late)
        }
    }

    func poll(_ done: @escaping (Int?) -> Void) { run({ $0.changeCount }, late: nil, done) }

    /// What the newest copy is, from its types alone. No data is read.
    func inspect(limits: DeskClipboardLimits, _ done: @escaping (Inspection?) -> Void) {
        run({ store in Inspection(changeCount: store.changeCount, assessment: DeskClipboardPolicy.assess(store.itemTypes(), limits: limits)) }, late: nil, done)
    }

    /// The copy with this change count, or why it cannot be sent. The markers
    /// are checked again at the moment of reading, before any data is.
    func read(expecting changeCount: Int, limits: DeskClipboardLimits, fileLimits: DeskFileLimits,
              _ done: @escaping (Result<DeskClipboardSnapshot, DeskClipboardReason>) -> Void) {
        run({ store in
            guard store.changeCount == changeCount else { return .failure(.changed) }
            let result: Result<DeskClipboardSnapshot, DeskClipboardReason>
            switch DeskClipboardPolicy.assess(store.itemTypes(), limits: limits) {
            case .withheld(let reason): return .failure(reason)
            case .files:
                // Only the names of the files are read here; their contents
                // follow one file at a time, once the names are in.
                let urls = store.itemTypes().indices.compactMap { index in
                    store.data(item: index, type: DeskClipboardMarker.fileURL).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                }
                result = DeskSourceFile.examine(urls, limits: fileLimits).map { .files($0) }
            case .share(let plan):
                var items: [[DeskClipboardContent.Representation]] = [], total = 0
                for (index, types) in plan.enumerated() {
                    var item: [DeskClipboardContent.Representation] = []
                    for type in types {
                        guard let data = store.data(item: index, type: type.identifier), !data.isEmpty else { continue }
                        total += data.count
                        guard data.count <= limits.cap(type), total <= limits.total else { return .failure(.tooLarge) }
                        item.append(.init(type: type, data: data))
                    }
                    if !item.isEmpty { items.append(item) }
                }
                guard !items.isEmpty else { return .failure(.unsupported) }
                result = .success(.content(DeskClipboardContent(items: items)))
            }
            // The copy must not have changed while it was being read.
            guard store.changeCount == changeCount else { return .failure(.changed) }
            return result
        }, late: .failure(.readTimedOut), done)
    }

    /// Put a copy on the pasteboard only if nothing was copied here since the
    /// fetch began: something newer made on this Mac always wins.
    func write(_ content: DeskClipboardContent, ifUnchanged expected: Int, _ done: @escaping (Result<Int, DeskClipboardReason>) -> Void) {
        replace(content.items.map { item in item.map { (type: $0.type.identifier, data: $0.data) } }, ifUnchanged: expected, done)
    }

    /// Replace the pasteboard with these items (received files as file URLs,
    /// for example) on the same terms.
    func replace(_ items: [[(type: String, data: Data)]], ifUnchanged expected: Int, _ done: @escaping (Result<Int, DeskClipboardReason>) -> Void) {
        run({ store in
            guard store.changeCount == expected else { return .failure(.newerHere) }
            return .success(store.replace(with: items))
        }, late: .failure(.writeFailed), done)
    }
}

/// Copy on one Mac of the desk, paste on another.
///
/// **Nothing is sent when you copy.** When the keyboard arrives on this Mac, it
/// asks the other Macs which copy is their newest and how long ago it was made,
/// and fetches the newest one only if it is newer than this Mac's own.
///
/// **The paste never waits for the network.** Perch's desk connections and its
/// input event tap both run on the main run loop. A pasteboard data promise is
/// answered synchronously on the main thread while the pasting app waits; one
/// that waited there for network data arriving on that same main thread would
/// deadlock, and would freeze the shared pointer for everyone while it did. So
/// text, rich text and images are never promised. The copy is fetched when the
/// keyboard arrives (a click moves the keyboard, so this is still on demand,
/// never on every copy) and written as ordinary data once it is complete and
/// verified. A paste only ever reads data already on this Mac: before the fetch
/// finishes it pastes what was there before, and a slow or dead peer costs a
/// timeout here, never a hang there. Pasteboard reads and writes happen off the
/// main thread with deadlines (`DeskPasteboardAccess`); so do compression, the
/// content digest and decoding. Only small bounded steps run on main.
///
/// **Files land in Downloads**, the way AirDrop delivers, when the keyboard
/// arrives: their names first, then each file streamed to disk, verified, and
/// moved into place only once the whole copy is here. The pasteboard then holds
/// those files, so any app pastes them as files, and a paste never waits for
/// the network. See `DeskFileTransfer.swift`.
///
/// **An older Perch is never sent anything but a hello.** Desk application
/// messages are routed by their tag; a Perch without clipboard support routes
/// this tag nowhere and ignores it (checked against the 2.0.297 sources). Every
/// other clipboard message waits until that Mac has answered with a format both
/// speak; `send` enforces that in one place.
final class DeskClipboard {
    struct Timings {
        /// How long to wait for the other Macs to say what they have.
        var query = 1.0
        /// From asking for a copy to its manifest arriving.
        var reply = 5.0
        /// Between chunks.
        var stall = 5.0
        /// A whole copy of text, rich text or images.
        var total = 120.0
        /// Serving side: between acknowledgements.
        var serveStall = 10.0
        /// How often a Mac that has not answered is greeted again.
        var hello = 30.0
        var tick = 0.5
        /// Reading a file through once to take its digest before sending it:
        /// allowed this long per gigabyte, on top of `reply`.
        var digestPerGigabyte = 10.0
    }
    /// Chunks in flight beyond the last acknowledgement. Pointer messages share
    /// the connection and queue behind whatever is in flight, so this bounds
    /// what a long transfer adds to the pointer's delay: four chunks is about
    /// a quarter of a megabyte, some 15 ms over Wi-Fi and nothing over a cable,
    /// while still filling the link at the desk's round-trip times.
    static let window: UInt32 = 4
    /// One chunk as the link carries it: the 64 KB envelope, base64 inside the
    /// desk message, plus framing. Rounded up.
    static let chunkWireBytes = 90 * 1024
    /// Stay far below the send queue size at which the desk closes a link, and
    /// keep little queued ahead of the pointer.
    static let paceLimit = 256 * 1024
    /// Space left free on the destination beyond the file itself.
    static let spaceMargin: UInt64 = 64 * 1024 * 1024

    let link: DeskClipboardLink
    let pasteboard: DeskPasteboardAccess
    var limits = DeskClipboardLimits()
    var fileLimits = DeskFileLimits()
    var timings = Timings()
    /// Whether this Mac takes part now: keyboard and mouse sharing is on here,
    /// and ready (not locked, access granted).
    var permitted: () -> Bool = { false }
    /// Which Mac typing goes to while sharing is active; nil when it is not.
    var keyboardComputer: () -> UUID? = { nil }
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var after: (Double, @escaping () -> Void) -> Void = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    /// Where received files land: this Mac's Downloads folder.
    var receiveFolder: () -> URL? = { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
    /// Free space where files are about to land.
    var freeSpace: (URL) -> UInt64? = { directory in
        (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
    }
    /// Heavy, pure work: sealing, digests, decompression, decoding.
    var work = DispatchQueue(label: "Perch.desk.clipboard", qos: .userInitiated)
    /// Every file read and write, in order.
    let disk = DispatchQueue(label: "Perch.desk.files", qos: .userInitiated)
    private(set) var lastDecision: DeskClipboardDecision?
    private(set) var decisions: [DeskClipboardDecision] = []

    private var formats: [UUID: UInt8] = [:]
    /// Macs that greeted with no format in common with this one.
    private var incompatible: Set<UUID> = []
    private var helloSent: [UUID: Double] = [:]
    private var noted: [UUID: DeskClipboardReason] = [:]

    private struct Copy { let id: UUID; let changeCount: Int; let at: Double? }
    /// This Mac's newest copy. `at` is nil for what was already on the
    /// pasteboard when Perch started: its age is unknown, so it is never offered
    /// and counts as older than any copy whose age is known.
    private var copy: Copy?
    private var lastKeyboard: UUID?

    private enum Answer {
        case offer(copy: UUID, at: Double)
        case withheld(DeskClipboardReason, at: Double?)
        var at: Double? { switch self { case .offer(_, let at): return at; case .withheld(_, let at): return at } }
    }
    private struct Query { let id: UUID; var waiting: Set<UUID>; var answers: [UUID: Answer] }
    private var query: Query?

    private struct Incoming {
        let id: UUID, peer: UUID, copy: UUID, copyAt: Double, key: SymmetricKey
        /// This Mac's change count when the fetch began.
        let expected: Int
        let started: Double
        var lastProgress: Double
        var assembly: DeskClipboardAssembly?
        var finishing = false
    }
    private var incoming: Incoming?

    /// What this Mac sends: a sealed copy held in memory, or one file read from
    /// disk a chunk at a time.
    private struct Outgoing {
        let peer: UUID, key: SymmetricKey, format: UInt8
        let file: Bool
        var lastAck: Double
        var parcel: DeskClipboardWire.Parcel?
        var manifest: DeskClipboardManifest?
        var descriptor: Int32?
        var reading = false
        var next: UInt32 = 0
        var acked: UInt32 = 0
        var paced = false
    }
    private var outgoing: [UUID: Outgoing] = [:]

    /// The files behind this Mac's newest copy, as examined when another Mac
    /// asked for their names. Only these can be sent.
    private var served: (copy: UUID, files: [DeskSourceFile])?

    /// Another Mac's copy of files on its way into this Mac's Downloads folder.
    private struct FileIncoming {
        let id: UUID, key: SymmetricKey, sink: DeskFileSink, size: UInt64
        let started: Double
        var lastProgress: Double
        var assembly: DeskClipboardAssembly?
        var written: UInt32 = 0
        var finishing = false
    }
    private struct FileBatch {
        let id: UUID, peer: UUID, copy: UUID, copyAt: Double
        /// This Mac's change count when the fetch began.
        let expected: Int
        let folder: URL
        let files: [DeskFileList.Entry]
        let started: Double
        var total: UInt64 { files.reduce(0) { $0 + $1.size } }
        var index = 0
        var current: FileIncoming?
        /// Verified, waiting to be moved into place together.
        var done: [DeskFileSink] = []
        var received: UInt64 = 0
        /// Every file is here and being moved into place. From here the copy
        /// finishes on its own terms: its pasteboard write already refuses if
        /// anything newer was copied, and then removes what it placed.
        var placing = false
    }
    private var batch: FileBatch?

    private var askTimes: [UUID: [Double]] = [:]
    private var fetchTimes: [UUID: [Double]] = [:]
    private var fileFetchTimes: [UUID: [Double]] = [:]
    private var inbound: [UUID: (start: Double, count: Int)] = [:]
    private var timer: Timer?

    init(link: DeskClipboardLink, pasteboard: DeskPasteboardAccess) {
        self.link = link; self.pasteboard = pasteboard
    }
    deinit { timer?.invalidate() }

    /// Whether a transfer is under way in either direction, for tests and status.
    var busy: Bool { incoming != nil || batch != nil || !outgoing.isEmpty || query != nil }
    /// How much of the copy on its way here has arrived, 0 to 1, while one is.
    var progress: Double? { incoming.map { $0.assembly?.fraction ?? 0 } }
    /// How much of a copy of files on its way here has arrived, 0 to 1.
    var fileProgress: Double? { batch.map { $0.total == 0 ? 0 : Double($0.received) / Double($0.total) } }

    func start() {
        guard timer == nil else { return }
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        timer = MainTimer.every(timings.tick) { [weak self] in self?.tick() }
        announce()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if incoming != nil { fail(.cancelled) }
        failBatch(.cancelled)
        for id in Array(outgoing.keys) { stopSending(id, .cancelled, tell: true) }
        query = nil
    }

    // MARK: The one gate

    /// The format to send `message` in to a Mac that negotiated `negotiated`,
    /// or nil when it must not be sent at all. A hello goes to anyone; every
    /// other message only to a Mac that answered with a format both speak.
    static func wireFormat(for message: DeskClipboardMessage, negotiated: UInt8?) -> UInt8? {
        if case .hello = message { return 0 }
        return negotiated
    }

    @discardableResult private func send(_ message: DeskClipboardMessage, to peer: UUID) -> Bool {
        guard peer != link.localID, link.peers.contains(peer) else { return false }
        guard let format = Self.wireFormat(for: message, negotiated: formats[peer]) else {
            note(peer, refusal(peer))
            return false
        }
        guard let envelope = try? DeskClipboardWire.encode(message, format: format) else { return false }
        return link.send(DeskClipboardWire.prefix + envelope, to: peer)
    }

    /// Why a Mac is not sent copies: it never said it shares them, or it
    /// speaks only formats this Mac does not.
    private func refusal(_ peer: UUID) -> DeskClipboardReason {
        formats[peer] != nil || incompatible.contains(peer) ? .format : .notSupported
    }

    private func note(_ peer: UUID, _ reason: DeskClipboardReason) {
        guard noted[peer] != reason else { return }
        noted[peer] = reason
        decide(.peerCannot(link.name(of: peer), reason))
    }

    @discardableResult private func decide(_ decision: DeskClipboardDecision) -> DeskClipboardDecision {
        lastDecision = decision
        decisions.append(decision)
        if decisions.count > 64 { decisions.removeFirst(decisions.count - 64) }
        PerchLog.note(DeskClipboardDecision.category, decision.line)
        return decision
    }

    // MARK: Receiving

    /// Handle a desk application message. Returns false when it is not a
    /// clipboard message, so the caller routes it elsewhere.
    @discardableResult func receive(_ data: Data, peer: UUID) -> Bool {
        guard data.starts(with: DeskClipboardWire.prefix) else { return false }
        guard data.count <= DeskClipboardWire.prefix.count + DeskClipboardWire.chunkEnvelopeSize,
              peer != link.localID, link.peers.contains(peer), admit(peer) else { return true }
        do {
            handle(try DeskClipboardWire.decode(data.dropFirst(DeskClipboardWire.prefix.count), format: formats[peer]), from: peer)
        } catch DeskClipboardWire.Failure.format {
            note(peer, refusal(peer))
        } catch {
            if let incoming, incoming.peer == peer { fail(.corrupt, detail: "unreadable message") }
            if let batch, batch.peer == peer { failBatch(.corrupt, detail: "unreadable message") }
        }
        return true
    }

    /// A paired Mac may send at most this many clipboard messages a second.
    private func admit(_ peer: UUID) -> Bool {
        let now = clock()
        var entry = inbound[peer] ?? (now, 0)
        if now - entry.start >= 1 { entry = (now, 0) }
        entry.count += 1
        inbound[peer] = entry
        return entry.count <= 2000
    }

    private func handle(_ message: DeskClipboardMessage, from peer: UUID) {
        switch message {
        case .hello(let theirs, let reply): greeted(theirs, reply: reply, by: peer)
        case .ask(let id): answer(id, to: peer)
        case .offer(let id, let copy, let age): answered(id, by: peer, .offer(copy: copy, at: clock() - Double(age) / 1000))
        case .withheld(let id, let reason, let age): answered(id, by: peer, .withheld(reason, at: age.map { clock() - Double($0) / 1000 }))
        case .fetch(let transfer, let copy, let key): serve(transfer, copy: copy, key: key, to: peer)
        case .fileFetch(let transfer, let copy, let index, let key): serveFile(transfer, copy: copy, index: index, key: key, to: peer)
        case .manifest(let manifest):
            if batch?.current?.id == manifest.transfer { fileManifestArrived(manifest, from: peer) } else { manifestArrived(manifest, from: peer) }
        case .chunk(let transfer, let index, let data, let mac):
            if batch?.current?.id == transfer { fileChunkArrived(transfer, index: index, data: data, mac: mac, from: peer) }
            else { chunkArrived(transfer, index: index, data: data, mac: mac, from: peer) }
        case .ack(let transfer, let next): acknowledged(transfer, next: next, by: peer)
        case .refuse(let transfer, let reason), .cancel(let transfer, let reason):
            if let out = outgoing[transfer], out.peer == peer { stopSending(transfer, reason, tell: false) }
            else if let incoming, incoming.id == transfer, incoming.peer == peer {
                self.incoming = nil
                decide(.refusedBy(link.name(of: peer), transfer: transfer, reason))
            } else if let batch, batch.current?.id == transfer, batch.peer == peer {
                failBatch(reason, tell: false, refusedBy: true)
            }
        }
    }

    private func greeted(_ theirs: [UInt8], reply: Bool, by peer: UUID) {
        if let common = Set(theirs).intersection(DeskClipboardWire.formats).max() {
            incompatible.remove(peer)
            if formats[peer] != common {
                formats[peer] = common; noted[peer] = nil
                decide(.peerSupports(link.name(of: peer), format: common))
            }
        } else {
            formats[peer] = nil
            incompatible.insert(peer)
            note(peer, .format)
        }
        if !reply { send(.hello(formats: DeskClipboardWire.formats, reply: true), to: peer) }
    }

    /// Greet every Mac that has not yet said which formats it speaks. A Perch
    /// without clipboard support ignores the greeting and is greeted again only
    /// every `timings.hello` seconds.
    private func announce() {
        let now = clock()
        for peer in link.peers where formats[peer] == nil && !incompatible.contains(peer) {
            if let sent = helloSent[peer], now - sent < timings.hello { continue }
            helloSent[peer] = now
            send(.hello(formats: DeskClipboardWire.formats, reply: false), to: peer)
        }
    }

    /// The desk's online Macs changed. A Mac that left may come back running a
    /// different Perch, so what it said is forgotten.
    func peersChanged() {
        let online = link.peers
        for peer in Set(formats.keys).union(helloSent.keys).union(noted.keys).union(incompatible) where !online.contains(peer) {
            formats[peer] = nil; helloSent[peer] = nil; noted[peer] = nil; incompatible.remove(peer)
        }
        if let incoming, !online.contains(incoming.peer) { fail(.peerGone, tell: false) }
        if let batch, !online.contains(batch.peer) { failBatch(.peerGone, tell: false) }
        for (id, out) in outgoing where !online.contains(out.peer) { stopSending(id, .peerGone, tell: false) }
        if var query {
            query.waiting = query.waiting.intersection(online)
            self.query = query
            if query.waiting.isEmpty { settle(query.id) }
        }
        announce()
    }

    // MARK: This Mac's own copy

    private func observe(_ count: Int) {
        if let copy, copy.changeCount == count { return }
        let first = copy == nil
        copy = Copy(id: UUID(), changeCount: count, at: first ? nil : clock())
        // Files examined for an older copy can no longer be sent.
        served = nil
        // Something was copied here while a fetch was on its way: this Mac's
        // own newer copy wins, and the fetch is dropped at once.
        if !first, incoming != nil { fail(.newerHere) }
        if !first, batch != nil { failBatch(.newerHere) }
    }

    func tick() {
        announce()
        guard permitted() else {
            if incoming != nil { fail(.sharingOffHere) }
            failBatch(.sharingOffHere)
            for id in Array(outgoing.keys) { stopSending(id, .sharingOffHere, tell: true) }
            return
        }
        keyboardMoved()
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        let now = clock()
        for (id, out) in outgoing where now - out.lastAck > timings.serveStall { stopSending(id, .timedOut, tell: true) }
    }

    // MARK: Asking, when the keyboard arrives

    /// Typing may have moved. When it arrives on this Mac from another one, ask.
    /// Gaps while control changes hands are skipped, so a handoff reads as one move.
    func keyboardMoved() {
        guard let now = keyboardComputer() else { return }
        let previous = lastKeyboard
        lastKeyboard = now
        guard now == link.localID, let previous, previous != link.localID else { return }
        keyboardArrived()
    }

    func keyboardArrived() {
        guard permitted() else { decide(.notAsking(.sharingOffHere)); return }
        // One question at a time; the one in flight answers this arrival too.
        guard query == nil, incoming == nil, batch == nil else { return }
        guard copy != nil else { decide(.notAsking(.notReady)); return }
        let id = UUID()
        // Every online Mac is offered the question, and `send` alone decides who
        // may receive it. A Mac that never answered a hello is not asked.
        let asked = Set(link.peers.filter { send(.ask(query: id), to: $0) })
        guard !asked.isEmpty else { decide(.notAsking(.notSupported)); return }
        query = Query(id: id, waiting: asked, answers: [:])
        after(timings.query) { [weak self] in self?.settle(id) }
    }

    private func answered(_ id: UUID, by peer: UUID, _ answer: Answer) {
        guard var query, query.id == id, query.waiting.remove(peer) != nil else { return }
        query.answers[peer] = answer
        self.query = query
        if query.waiting.isEmpty { settle(id) }
    }

    /// Choose: the youngest copy on the desk wins, this Mac's own included.
    private func settle(_ id: UUID) {
        guard let query, query.id == id else { return }
        self.query = nil
        guard permitted() else { decide(.notAsking(.sharingOffHere)); return }
        guard !query.answers.isEmpty else { decide(.noAnswer); return }
        let named = query.answers.sorted { link.name(of: $0.key) < link.name(of: $1.key) }
        guard let best = named.compactMap({ peer, answer in answer.at.map { (peer: peer, answer: answer, at: $0) } }).max(by: { $0.at < $1.at }) else {
            // No Mac reported a copy whose age it knows. Name the first reason given.
            for (peer, answer) in named { if case .withheld(let reason, _) = answer { decide(.notShared(from: link.name(of: peer), reason)); return } }
            decide(.newestHere)
            return
        }
        if case .offer(let copyID, _) = best.answer, copyID == copy?.id { decide(.alreadyHere(from: link.name(of: best.peer))); return }
        if let own = copy?.at, own >= best.at { decide(.newestHere); return }
        switch best.answer {
        case .withheld(let reason, _): decide(.notShared(from: link.name(of: best.peer), reason))
        case .offer(let copyID, let at): fetch(copyID, at: at, from: best.peer)
        }
    }

    // MARK: Fetching a copy (or the names of its files)

    private func fetch(_ copyID: UUID, at: Double, from peer: UUID) {
        guard let expected = copy?.changeCount else { return }
        let transfer = UUID(), key = SymmetricKey(size: .bits256)
        incoming = Incoming(id: transfer, peer: peer, copy: copyID, copyAt: at, key: key, expected: expected,
                            started: clock(), lastProgress: clock())
        decide(.fetching(from: link.name(of: peer), transfer: transfer))
        guard send(.fetch(transfer: transfer, copy: copyID, key: key.withUnsafeBytes { Data($0) }), to: peer) else { fail(.peerGone, tell: false); return }
        watch(transfer)
    }

    private func watch(_ id: UUID) {
        after(max(0.02, min(timings.reply, timings.stall) / 5)) { [weak self] in
            guard let self, let incoming = self.incoming, incoming.id == id else { return }
            let now = self.clock()
            if now - incoming.started > self.timings.total { self.fail(.timedOut, detail: "took longer than Perch allows"); return }
            if !incoming.finishing {
                if incoming.assembly == nil, now - incoming.started > self.timings.reply { self.fail(.timedOut, detail: "no reply"); return }
                if incoming.assembly != nil, now - incoming.lastProgress > self.timings.stall { self.fail(.timedOut, detail: "stalled"); return }
            }
            self.watch(id)
        }
    }

    /// End this Mac's fetch, drop everything received so far, and say why.
    private func fail(_ reason: DeskClipboardReason, detail: String? = nil, tell: Bool = true) {
        guard let incoming else { return }
        self.incoming = nil
        if tell { send(.cancel(transfer: incoming.id, reason: reason), to: incoming.peer) }
        decide(.failed(from: link.name(of: incoming.peer), transfer: incoming.id, reason, detail: detail))
    }

    private func manifestArrived(_ manifest: DeskClipboardManifest, from peer: UUID) {
        guard let incoming, incoming.peer == peer, incoming.id == manifest.transfer, incoming.assembly == nil,
              let format = formats[peer] else { return }
        do {
            let assembly = try DeskClipboardAssembly(manifest, transfer: incoming.id, copy: incoming.copy, key: incoming.key,
                                                     format: format, maximumPayload: limits.total)
            self.incoming?.assembly = assembly
            self.incoming?.lastProgress = clock()
            send(.ack(transfer: incoming.id, next: 0), to: peer)
        } catch let failure as DeskClipboardAssembly.Failure {
            fail(.corrupt, detail: "manifest " + failure.detail)
        } catch { fail(.corrupt, detail: "manifest unreadable") }
    }

    private func chunkArrived(_ transfer: UUID, index: UInt32, data: Data, mac: Data, from peer: UUID) {
        // A chunk for a transfer this Mac is not receiving (an old one replayed,
        // or one already given up) is ignored.
        guard let incoming, incoming.peer == peer, incoming.id == transfer, !incoming.finishing else { return }
        guard let assembly = incoming.assembly else { fail(.corrupt, detail: "a chunk arrived before its manifest"); return }
        do { _ = try assembly.accept(transfer: transfer, index: index, data: data, mac: mac) }
        catch let failure as DeskClipboardAssembly.Failure { fail(.corrupt, detail: failure.detail); return }
        catch { fail(.corrupt, detail: "unreadable chunk"); return }
        self.incoming?.lastProgress = clock()
        send(.ack(transfer: transfer, next: assembly.next), to: peer)
        guard assembly.complete else { return }
        self.incoming?.finishing = true
        let limits = self.limits, fileLimits = self.fileLimits
        work.async { [weak self] in
            let result: Result<DeskClipboardPayload, DeskClipboardAssembly.Failure>
            do { result = .success(try DeskClipboardPayload.decode(try assembly.finish(), limits: limits, fileLimits: fileLimits)) }
            catch let failure as DeskClipboardAssembly.Failure { result = .failure(failure) }
            catch let reason as DeskClipboardReason { result = .failure(.declined(reason)) }
            catch { result = .failure(.content("does not follow the format")) }
            DispatchQueue.main.async { [weak self] in self?.finished(transfer, result) }
        }
    }

    private func finished(_ id: UUID, _ result: Result<DeskClipboardPayload, DeskClipboardAssembly.Failure>) {
        guard let incoming, incoming.id == id else { return }
        let from = link.name(of: incoming.peer)
        switch result {
        case .failure(.declined(let reason)):
            // Everything arrived intact; this Mac says no, by name.
            self.incoming = nil
            decide(.discarded(transfer: id, reason))
        case .failure(let failure): fail(.corrupt, detail: failure.detail)
        case .success(.content(let content)):
            pasteboard.write(content, ifUnchanged: incoming.expected) { [weak self] outcome in
                guard let self, self.incoming?.id == id else { return }
                self.incoming = nil
                switch outcome {
                case .success(let count):
                    self.copy = Copy(id: incoming.copy, changeCount: count, at: incoming.copyAt)
                    self.served = nil
                    self.decide(.received(from: from, transfer: id, size: DeskClipboardPolicy.sizeBucket(content.byteCount)))
                case .failure(let reason): self.decide(.discarded(transfer: id, reason))
                }
            }
        case .success(.files(let list)): beginBatch(list, from: incoming)
        }
    }

    // MARK: Bringing a copy's files

    /// The names have arrived. Make each safe, check there is room, then bring
    /// the files one by one into hidden temporary files.
    private func beginBatch(_ list: DeskFileList, from incoming: Incoming) {
        self.incoming = nil
        // A name that cannot be made safe refuses the whole copy rather than
        // inventing one.
        let safe = list.files.map { entry in DeskFileNames.sanitize(entry.name).map { DeskFileList.Entry(name: $0, size: entry.size) } }
        guard safe.allSatisfy({ $0 != nil }) else { decide(.discarded(transfer: incoming.id, .unsafeName)); return }
        guard let folder = receiveFolder()?.standardizedFileURL else { decide(.discarded(transfer: incoming.id, .writeFailed)); return }
        if let free = freeSpace(folder), free < list.total + Self.spaceMargin {
            decide(.discarded(transfer: incoming.id, .noSpace)); return
        }
        batch = FileBatch(id: incoming.id, peer: incoming.peer, copy: incoming.copy, copyAt: incoming.copyAt, expected: incoming.expected,
                          folder: folder, files: safe.compactMap { $0 }, started: clock())
        nextFile()
    }

    private func nextFile() {
        guard var batch, batch.current == nil else { return }
        guard batch.index < batch.files.count else { placeBatch(); return }
        let entry = batch.files[batch.index], index = batch.index
        let transfer = UUID(), key = SymmetricKey(size: .bits256)
        let sink = DeskFileSink(directory: batch.folder, name: entry.name, size: entry.size, transfer: transfer)
        batch.current = FileIncoming(id: transfer, key: key, sink: sink, size: entry.size, started: clock(), lastProgress: clock())
        self.batch = batch
        let batchID = batch.id, peer = batch.peer, copyID = batch.copy
        disk.async { [weak self] in
            let created: Bool
            do { try sink.create(); created = true } catch { created = false }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.current?.id == transfer else { if created { self?.disk.async { sink.discard() } }; return }
                guard created else { self.failBatch(.writeFailed, tell: false); return }
                guard self.send(.fileFetch(transfer: transfer, copy: copyID, index: UInt32(index), key: key.withUnsafeBytes { Data($0) }), to: peer) else {
                    self.failBatch(.peerGone, tell: false); return
                }
                self.watchFile(batchID, transfer)
            }
        }
    }

    private func watchFile(_ batchID: UUID, _ transfer: UUID) {
        after(max(0.02, min(timings.reply, timings.stall) / 5)) { [weak self] in
            guard let self, let batch = self.batch, batch.id == batchID, let file = batch.current, file.id == transfer else { return }
            let now = self.clock()
            if !file.finishing {
                // The other Mac reads the whole file once for its digest first.
                let reply = self.timings.reply + self.timings.digestPerGigabyte * Double(file.size) / 1e9
                if file.assembly == nil, now - file.started > reply { self.failBatch(.timedOut, detail: "no reply"); return }
                if file.assembly != nil, now - file.lastProgress > self.timings.stall { self.failBatch(.timedOut, detail: "stalled"); return }
            }
            self.watchFile(batchID, transfer)
        }
    }

    /// End the copy on its way here and remove everything it wrote: the file in
    /// progress and every verified one not yet in place.
    private func failBatch(_ reason: DeskClipboardReason, detail: String? = nil, tell: Bool = true, refusedBy: Bool = false) {
        guard let batch, !batch.placing else { return }
        self.batch = nil
        let sinks = batch.done + (batch.current.map { [$0.sink] } ?? [])
        disk.async { sinks.forEach { $0.discard() } }
        if tell, let current = batch.current { send(.cancel(transfer: current.id, reason: reason), to: batch.peer) }
        let from = link.name(of: batch.peer), transfer = batch.current?.id ?? batch.id
        decide(refusedBy ? .refusedBy(from, transfer: transfer, reason) : .failed(from: from, transfer: transfer, reason, detail: detail))
    }

    private func fileManifestArrived(_ manifest: DeskClipboardManifest, from peer: UUID) {
        guard let batch, batch.peer == peer, let file = batch.current, file.id == manifest.transfer, file.assembly == nil,
              let format = formats[peer] else { return }
        do {
            let assembly = try DeskClipboardAssembly(manifest, transfer: file.id, copy: batch.copy, key: file.key, format: format,
                                                     maximumPayload: Int(clamping: fileLimits.perFile), streaming: true)
            guard manifest.payloadLength == file.size else { failBatch(.corrupt, detail: "a file is not the size listed"); return }
            self.batch?.current?.assembly = assembly
            self.batch?.current?.lastProgress = clock()
            send(.ack(transfer: file.id, next: 0), to: peer)
        } catch let failure as DeskClipboardAssembly.Failure {
            failBatch(.corrupt, detail: "manifest " + failure.detail)
        } catch { failBatch(.corrupt, detail: "manifest unreadable") }
    }

    private func fileChunkArrived(_ transfer: UUID, index: UInt32, data: Data, mac: Data, from peer: UUID) {
        guard let batch, batch.peer == peer, let file = batch.current, file.id == transfer, !file.finishing else { return }
        guard let assembly = file.assembly else { failBatch(.corrupt, detail: "a chunk arrived before its manifest"); return }
        let part: Data
        do { part = try assembly.accept(transfer: transfer, index: index, data: data, mac: mac) }
        catch let failure as DeskClipboardAssembly.Failure { failBatch(.corrupt, detail: failure.detail); return }
        catch { failBatch(.corrupt, detail: "unreadable chunk"); return }
        self.batch?.current?.lastProgress = clock()
        let sink = file.sink, digest = assembly.manifest.digest, count = assembly.manifest.chunkCount
        // Written in order on the disk queue, and acknowledged once on disk, so
        // the window bounds what waits in memory.
        disk.async { [weak self] in
            let wrote: Bool
            do { try sink.append(part); wrote = true } catch { wrote = false }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.current?.id == transfer else { return }
                guard wrote else { self.failBatch(.writeFailed); return }
                self.batch?.current?.written += 1
                self.batch?.received += UInt64(part.count)
                self.batch?.current?.lastProgress = self.clock()
                let written = self.batch?.current?.written ?? 0
                self.send(.ack(transfer: transfer, next: written), to: peer)
                if written == count { self.verifyFile(transfer, digest: digest) }
            }
        }
    }

    private func verifyFile(_ transfer: UUID, digest: Data) {
        guard let file = batch?.current, file.id == transfer else { return }
        batch?.current?.finishing = true
        let sink = file.sink
        disk.async { [weak self] in
            let reason: DeskClipboardReason?
            do { try sink.verify(digest: digest); reason = nil }
            catch let failure as DeskClipboardReason { reason = failure }
            catch { reason = .writeFailed }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.current?.id == transfer else { return }
                if let reason { self.failBatch(reason); return }
                self.batch?.done.append(sink)
                self.batch?.current = nil
                self.batch?.index += 1
                self.nextFile()
            }
        }
    }

    /// Every file is here and verified. Mark them as downloaded, give each a
    /// name that does not exist yet, and put them on the pasteboard, unless
    /// something newer was copied here meanwhile. If any step fails, none of
    /// the copy stays.
    private func placeBatch() {
        guard let batch else { return }
        self.batch?.placing = true
        let sinks = batch.done, id = batch.id
        disk.async { [weak self] in
            var placed: [URL] = [], reason: DeskClipboardReason?
            for sink in sinks {
                do { placed.append(try sink.place()) }
                catch let failure as DeskClipboardReason { reason = failure; break }
                catch { reason = .writeFailed; break }
            }
            if reason != nil {
                sinks.forEach { $0.discard() }
                placed.forEach { unlink($0.path) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.id == id else { placed.forEach { unlink($0.path) }; return }
                if let reason {
                    self.batch = nil
                    self.decide(.failed(from: self.link.name(of: batch.peer), transfer: id, reason, detail: nil))
                    return
                }
                let items = placed.map { [(type: DeskClipboardMarker.fileURL, data: $0.dataRepresentation)] }
                self.pasteboard.replace(items, ifUnchanged: batch.expected) { [weak self] outcome in
                    guard let self, self.batch?.id == id else { return }
                    self.batch = nil
                    let from = self.link.name(of: batch.peer)
                    switch outcome {
                    case .success(let count):
                        self.copy = Copy(id: batch.copy, changeCount: count, at: batch.copyAt)
                        self.served = nil
                        self.decide(.received(from: from, transfer: id, size: DeskClipboardPolicy.sizeBucket(Int(clamping: batch.total))))
                    case .failure(let reason):
                        // Never the clipboard, so never left behind.
                        self.disk.async { placed.forEach { unlink($0.path) } }
                        self.decide(.discarded(transfer: id, reason))
                    }
                }
            }
        }
    }

    // MARK: Serving

    private func allow(_ table: inout [UUID: [Double]], _ peer: UUID, limit: Int, per window: Double) -> Bool {
        let now = clock()
        var times = (table[peer] ?? []).filter { now - $0 < window }
        defer { table[peer] = times }
        guard times.count < limit else { return false }
        times.append(now)
        return true
    }

    private func withhold(_ id: UUID, _ reason: DeskClipboardReason, age: UInt32? = nil, to peer: UUID) {
        send(.withheld(query: id, reason: reason, age: age), to: peer)
        decide(.withheld(to: link.name(of: peer), reason))
    }

    /// Questions waiting for the one pasteboard inspection in flight. Every
    /// Mac asking at the same moment gets the same, single look.
    private var questions: [(id: UUID, peer: UUID)] = []

    private func answer(_ id: UUID, to peer: UUID) {
        guard allow(&askTimes, peer, limit: 20, per: 10) else { withhold(id, .rateLimited, to: peer); return }
        guard permitted() else { withhold(id, .sharingOff, to: peer); return }
        questions.append((id, peer))
        guard questions.count == 1 else { return }
        pasteboard.inspect(limits: limits) { [weak self] inspection in
            guard let self else { return }
            let waiting = self.questions
            self.questions = []
            if let inspection { self.observe(inspection.changeCount) }
            for (id, peer) in waiting {
                guard self.permitted() else { self.withhold(id, .sharingOff, to: peer); continue }
                guard let inspection else { self.withhold(id, .readTimedOut, to: peer); continue }
                guard let copy = self.copy, let at = copy.at else { self.withhold(id, .noCopy, to: peer); continue }
                let age = UInt32(clamping: Int(max(0, (self.clock() - at) * 1000)))
                switch inspection.assessment {
                case .withheld(let reason): self.withhold(id, reason, age: age, to: peer)
                case .share, .files:
                    self.send(.offer(query: id, copy: copy.id, age: age), to: peer)
                    self.decide(.offered(to: self.link.name(of: peer)))
                }
            }
        }
    }

    private func refuse(_ transfer: UUID, _ reason: DeskClipboardReason, to peer: UUID) {
        send(.refuse(transfer: transfer, reason: reason), to: peer)
        decide(.refused(to: link.name(of: peer), transfer: transfer, reason))
    }

    /// One copy to each Mac at a time and one file to each Mac at a time; three
    /// transfers at most in all.
    private func busySending(to peer: UUID, file: Bool) -> Bool {
        outgoing.values.contains { $0.peer == peer && $0.file == file } || outgoing.count >= 3
    }

    private func serve(_ transfer: UUID, copy copyID: UUID, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&fetchTimes, peer, limit: 12, per: 60) else { refuse(transfer, .rateLimited, to: peer); return }
        guard permitted() else { refuse(transfer, .sharingOff, to: peer); return }
        guard outgoing[transfer] == nil, !busySending(to: peer, file: false) else { refuse(transfer, .busy, to: peer); return }
        guard let copy, copy.id == copyID, copy.at != nil, let format = formats[peer] else { refuse(transfer, .unknownCopy, to: peer); return }
        outgoing[transfer] = Outgoing(peer: peer, key: SymmetricKey(data: key), format: format, file: false, lastAck: clock())
        pasteboard.read(expecting: copy.changeCount, limits: limits, fileLimits: fileLimits) { [weak self] result in
            guard let self, let out = self.outgoing[transfer] else { return }
            let payload: Data
            switch result {
            case .failure(let reason):
                self.outgoing[transfer] = nil
                self.refuse(transfer, reason, to: peer); return
            case .success(.content(let content)): payload = content.encoded()
            case .success(.files(let files)):
                // Remember exactly what was examined: only these files, unchanged,
                // can be asked for one by one.
                self.served = (copyID, files)
                payload = DeskFileList(files: files.map { .init(name: $0.name, size: $0.size) }).encoded()
            }
            self.work.async { [weak self] in
                let parcel = DeskClipboardWire.seal(payload, transfer: transfer, copy: copyID, key: out.key, format: out.format)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.outgoing[transfer] != nil else { return }
                    self.outgoing[transfer]?.parcel = parcel
                    self.outgoing[transfer]?.manifest = parcel.manifest
                    self.outgoing[transfer]?.lastAck = self.clock()
                    self.send(.manifest(parcel.manifest), to: peer)
                    self.pump(transfer)
                }
            }
        }
    }

    private func serveFile(_ transfer: UUID, copy copyID: UUID, index: UInt32, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&fileFetchTimes, peer, limit: fileLimits.count + 20, per: 60) else { refuse(transfer, .rateLimited, to: peer); return }
        guard permitted() else { refuse(transfer, .sharingOff, to: peer); return }
        guard outgoing[transfer] == nil, !busySending(to: peer, file: true) else { refuse(transfer, .busy, to: peer); return }
        guard let copy, copy.id == copyID, let served, served.copy == copyID, served.files.indices.contains(Int(index)),
              let format = formats[peer] else { refuse(transfer, .unknownCopy, to: peer); return }
        let file = served.files[Int(index)]
        let sealKey = SymmetricKey(data: key)
        outgoing[transfer] = Outgoing(peer: peer, key: sealKey, format: format, file: true, lastAck: clock())
        // Open it only if it is still the same regular file, and read it through
        // once for its digest, all off the main thread.
        disk.async { [weak self] in
            let opened = file.open()
            var outcome: Result<(Int32, Data), DeskClipboardReason>
            switch opened {
            case .failure(let reason): outcome = .failure(reason)
            case .success(let fd):
                if let digest = DeskSourceFile.digest(fd, size: file.size), file.unchanged(fd) { outcome = .success((fd, digest)) }
                else { close(fd); outcome = .failure(.changed) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.outgoing[transfer] != nil else { if case .success(let (fd, _)) = outcome { self?.disk.async { close(fd) } }; return }
                switch outcome {
                case .failure(let reason):
                    self.outgoing[transfer] = nil
                    self.refuse(transfer, reason, to: peer)
                case .success(let (fd, digest)):
                    let manifest = DeskClipboardWire.fileManifest(transfer: transfer, copy: copyID, size: file.size, digest: digest, key: sealKey, format: format)
                    self.outgoing[transfer]?.descriptor = fd
                    self.outgoing[transfer]?.manifest = manifest
                    self.outgoing[transfer]?.lastAck = self.clock()
                    self.send(.manifest(manifest), to: peer)
                    self.pump(transfer)
                }
            }
        }
    }

    /// Send chunks while the receiver's window and the link's queue allow.
    /// The queue check is this side's own guarantee: whatever the other Mac
    /// acknowledges, the desk link is never pushed toward the size at which it
    /// would be closed, and pointer traffic keeps flowing beside the copy.
    private func pump(_ transfer: UUID) {
        guard var out = outgoing[transfer], let manifest = out.manifest else { return }
        while out.next < manifest.chunkCount && out.next < out.acked + Self.window && !out.reading {
            guard let queued = link.queuedBytes(to: out.peer) else { outgoing[transfer] = out; stopSending(transfer, .peerGone, tell: false); return }
            guard queued + Self.chunkWireBytes <= Self.paceLimit else {
                if !out.paced {
                    out.paced = true
                    after(0.01) { [weak self] in self?.outgoing[transfer]?.paced = false; self?.pump(transfer) }
                }
                break
            }
            if let parcel = out.parcel {
                send(parcel.chunk(out.next, key: out.key), to: out.peer)
                out.next += 1
            } else if let fd = out.descriptor {
                // One chunk read at a time, off the main thread, in order.
                out.reading = true
                let index = out.next, key = out.key, size = manifest.payloadLength, padded = manifest.paddedLength
                disk.async { [weak self] in
                    let data = DeskSourceFile.chunk(fd, index: index, size: size, padded: padded)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, var current = self.outgoing[transfer], current.reading else { return }
                        current.reading = false
                        guard let data else { self.outgoing[transfer] = current; self.stopSending(transfer, .changed, tell: true); return }
                        let message = DeskClipboardMessage.chunk(transfer: transfer, index: index, data: data,
                                                                 mac: DeskClipboardWire.chunkMAC(format: current.format, transfer: transfer, index: index,
                                                                                                 count: manifest.chunkCount, data: data, key: key))
                        self.send(message, to: current.peer)
                        current.next += 1
                        self.outgoing[transfer] = current
                        self.pump(transfer)
                    }
                }
            } else { break }
        }
        outgoing[transfer] = out
    }

    private func acknowledged(_ transfer: UUID, next: UInt32, by peer: UUID) {
        guard var out = outgoing[transfer], out.peer == peer, let manifest = out.manifest else { return }
        guard next <= out.next else { stopSending(transfer, .corrupt, tell: true); return }
        out.acked = max(out.acked, next); out.lastAck = clock()
        outgoing[transfer] = out
        if out.acked == manifest.chunkCount {
            finishSending(transfer)
            decide(.sent(to: link.name(of: peer), transfer: transfer, size: DeskClipboardPolicy.sizeBucket(Int(clamping: manifest.payloadLength))))
            return
        }
        pump(transfer)
    }

    /// Forget a transfer this Mac was sending, closing its file after any read
    /// still under way.
    @discardableResult private func finishSending(_ transfer: UUID) -> Outgoing? {
        guard let out = outgoing.removeValue(forKey: transfer) else { return nil }
        if let fd = out.descriptor { disk.async { close(fd) } }
        return out
    }

    private func stopSending(_ transfer: UUID, _ reason: DeskClipboardReason, tell: Bool) {
        guard let out = finishSending(transfer) else { return }
        if tell { send(.cancel(transfer: transfer, reason: reason), to: out.peer) }
        decide(.stoppedSending(to: link.name(of: out.peer), transfer: transfer, reason))
    }
}
