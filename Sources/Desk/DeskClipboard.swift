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
        /// What the copy is, when it may be offered.
        let what: DeskClipboardDescriptor?
    }
    let store: DeskPasteboardStore
    var timeout: Double
    private let queue = DispatchQueue(label: "Perch.desk.pasteboard", qos: .userInitiated)
    private var pending = 0
    private var stuck = false
    /// The last inspection, reused while the copy is unchanged. Touched only on
    /// the queue, so sizing a text copy reads its data once, not on every click.
    private var inspected: Inspection?
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

    /// What the newest copy is. Its types decide everything except whether
    /// text is small, which needs the size of its text, read here once per copy.
    /// A concealed copy is refused from its types; none of its data is read.
    func inspect(limits: DeskClipboardLimits, _ done: @escaping (Inspection?) -> Void) {
        run({ [weak self] store in
            let count = store.changeCount
            if let cached = self?.inspected, cached.changeCount == count { return cached }
            let types = store.itemTypes()
            let assessment = DeskClipboardPolicy.assess(types, limits: limits)
            let what: DeskClipboardDescriptor?
            switch assessment {
            case .withheld: what = nil
            case .files:
                // Their number and total size, from the file system alone.
                let urls = types.indices.compactMap { index in
                    store.data(item: index, type: DeskClipboardMarker.fileURL).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                }
                let bytes = urls.reduce(0) { total, url in
                    var info = stat()
                    return total + (lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG ? Int(info.st_size) : 0)
                }
                what = .init(kind: .files, count: max(1, urls.count), small: false, size: DeskClipboardPolicy.sizeIndex(bytes))
            case .share(let plan):
                // The size of what would be sent: the text, and the one image
                // representation. Read once per copy; the answer is kept.
                var total = 0
                for (index, item) in plan.enumerated() {
                    for type in item { total += store.data(item: index, type: type.identifier)?.count ?? 0 }
                }
                what = DeskClipboardDescriptor.describe(plan, bytes: total)
            }
            let value = Inspection(changeCount: count, assessment: assessment, what: what)
            self?.inspected = value
            return value
        }, late: nil, done)
    }

    /// The file URLs the pasteboard holds now, and its change count.
    func files(_ done: @escaping ((changeCount: Int, urls: [URL])?) -> Void) {
        run({ store in
            let urls = store.itemTypes().indices.compactMap { index in
                store.data(item: index, type: DeskClipboardMarker.fileURL).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            }
            return (store.changeCount, urls)
        }, late: nil, done)
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

    /// Put another Mac's copy on the pasteboard, only if nothing was copied
    /// here since the fetch began (something newer made here always wins), and
    /// with Perch's mark holding the copy's identity, so it is recognised as
    /// received and never announced or sent on again.
    func write(_ content: DeskClipboardContent, marker: UUID, ifUnchanged expected: Int, _ done: @escaping (Result<Int, DeskClipboardReason>) -> Void) {
        replace(content.items.map { item in item.map { (type: $0.type.identifier, data: $0.data) } }, marker: marker, ifUnchanged: expected, done)
    }

    /// Replace the pasteboard with these items (staged files as file URLs, for
    /// example) on the same terms.
    func replace(_ items: [[(type: String, data: Data)]], marker: UUID, ifUnchanged expected: Int, _ done: @escaping (Result<Int, DeskClipboardReason>) -> Void) {
        let mark = (type: DeskClipboardMarker.received, data: Data(marker.uuidString.utf8))
        run({ store in
            guard store.changeCount == expected else { return .failure(.newerHere) }
            return .success(store.replace(with: items.map { $0 + [mark] }))
        }, late: .failure(.writeFailed), done)
    }
}

/// Copy on one Mac of the desk, paste on another.
///
/// **Scott's design, September 27, 2026.** When something is copied on a Mac:
/// - A copy that is only text, 64 KB or less in all, goes onto every other
///   connected Mac's clipboard. The copying Mac announces it and each other Mac
///   with sharing on fetches it at once, silently, so the content only ever
///   reaches a Mac whose own consent is on.
/// - Anything else (more text, any image, any file) is only announced: its kind,
///   a size bucket, which Mac has it. ⌃⌥⌘V brings it over onto the clipboard of
///   the Mac typing goes to, with a small progress popup that closes itself.
///   After that every ordinary paste works: keyboard, menu or right-click.
/// - A copy Perch put on a clipboard carries Perch's mark and is never announced
///   or sent on again, so nothing echoes between Macs.
///
/// **Nothing waits for the network on the main thread, and nothing is ever
/// promised on the pasteboard.** Perch's desk connections and its input event
/// tap both run on the main run loop; a pasteboard promise is answered on that
/// same thread while the pasting app waits, so one that waited for the network
/// would deadlock and freeze the shared pointer. Copies are written as ordinary
/// data once they are here and verified, so every paste reads what is already
/// on this Mac. Pasteboard reads and writes happen off the main thread with
/// deadlines (`DeskPasteboardAccess`); so do compression, digests, decoding and
/// all file work. Only small bounded steps run on main.
///
/// **An older Perch is never sent anything but a hello.** Desk application
/// messages are routed by their tag; a Perch without clipboard support routes
/// this tag nowhere and ignores it (checked against the 2.0.297 sources). Every
/// other clipboard message waits until that Mac has answered with a format both
/// speak; `send` enforces that in one place.
///
/// **Defaults pending Scott's confirmation**, each decided in one place:
/// - (a) Bring over acts for the Mac typing goes to: `bringOverTarget`.
/// - (b) What is waiting clears when a newer copy appears anywhere, and when the
///   Mac holding it leaves: `consider` and `peersChanged`.
/// - (c) Bring over with nothing waiting does nothing: `bringOverHere`.
/// - (d) Small text reaches only Macs with sharing on: `consider`.
/// - (e) The shortcut and its conflicts: `DeskBringOverShortcut`.
final class DeskClipboard {
    struct Timings {
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
        /// How often this Mac's clipboard is checked for a new copy.
        var tick = 0.25
        /// Reading a file through once to take its digest before sending it:
        /// allowed this long per gigabyte, on top of `reply`.
        var digestPerGigabyte = 10.0
        /// How often staged files are checked against `DeskFileStaging`'s rule.
        var sweep = 30.0
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
    /// Space left free on this Mac beyond the files being staged.
    static let spaceMargin: UInt64 = 64 * 1024 * 1024

    let link: DeskClipboardLink
    let pasteboard: DeskPasteboardAccess
    let staging: DeskFileStaging
    var limits = DeskClipboardLimits()
    var fileLimits = DeskFileLimits()
    var timings = Timings()
    /// Whether this Mac takes part now: keyboard and mouse sharing is on here,
    /// and ready (not locked, access granted).
    var permitted: () -> Bool = { false }
    /// Draws the bring-over popup. Nil draws nothing.
    var presenter: DeskPastePresenting?
    /// What is waiting changed; the menu bar's status follows it.
    var waitingChanged: () -> Void = {}
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var after: (Double, @escaping () -> Void) -> Void = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    /// Free space on the volume files are staged on.
    var freeSpace: (URL) -> UInt64? = { directory in
        let probe = FileManager.default.fileExists(atPath: directory.path) ? directory : FileManager.default.homeDirectoryForCurrentUser
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
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

    /// What this Mac's clipboard holds. `at` is when it was copied, on this
    /// Mac's clock, nil for what was already there when Perch started (never
    /// announced). `received` marks a copy that came from another Mac.
    private struct Copy { let id: UUID; let changeCount: Int; let at: Double?; var received: Bool }
    private var copy: Copy?
    /// The copy last announced, or judged not to be, so each is decided once.
    private var announced: UUID?
    private var announcing: UUID?
    /// The newest copy this Mac knows of on the desk: which Mac holds it (nil
    /// for this one) and when it was made, on this Mac's clock.
    private var newest: (peer: UUID?, at: Double)?

    /// Another Mac's copy, newer than anything here, not yet on this Mac.
    struct Waiting: Equatable {
        let peer: UUID, copy: UUID, at: Double
        let what: DeskClipboardDescriptor
    }
    private(set) var waiting: Waiting? { didSet { if waiting != oldValue { waitingChanged() } } }

    private enum Mode { case silent, bringOver }
    private struct Incoming {
        let id: UUID, peer: UUID, copy: UUID, copyAt: Double, key: SymmetricKey
        let mode: Mode
        /// Fetching the names of files: the popup's progress follows the
        /// files' own bytes, not this short list.
        var files = false
        /// This Mac's change count when the fetch began.
        let expected: Int
        let started: Double
        var lastProgress: Double
        var assembly: DeskClipboardAssembly?
        var finishing = false
    }
    private var incoming: Incoming?
    /// The popup of the bring-over in flight.
    private var progress: DeskPasteProgress?

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

    /// Another Mac's copy of files on its way into the staging folder.
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
        let expected: Int
        let folder: URL
        let files: [DeskFileList.Entry]
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
        var cancelled = false
    }
    private var batch: FileBatch?

    private var fetchTimes: [UUID: [Double]] = [:]
    private var fileFetchTimes: [UUID: [Double]] = [:]
    private var bringTimes: [UUID: [Double]] = [:]
    private var inbound: [UUID: (start: Double, count: Int)] = [:]
    private var timer: Timer?
    private var nextSweep: Double = 0

    init(link: DeskClipboardLink, pasteboard: DeskPasteboardAccess, staging: DeskFileStaging = DeskFileStaging(root: DeskFileStaging.standard)) {
        self.link = link; self.pasteboard = pasteboard; self.staging = staging
    }
    deinit { timer?.invalidate() }

    /// Whether a transfer is under way in either direction, for tests and status.
    var busy: Bool { incoming != nil || batch != nil || !outgoing.isEmpty }
    /// How far the bring-over in flight has come, 0 to 1.
    var bringOverProgress: Double? { progress?.fraction }

    func start() {
        guard timer == nil else { return }
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        // A staged copy the clipboard still lists is kept; the rest go now.
        pasteboard.files { [weak self] found in
            guard let self else { return }
            if let found { self.staging.adopt(found.urls, changeCount: found.changeCount) }
            self.sweep()
        }
        nextSweep = clock() + timings.sweep
        timer = MainTimer.every(timings.tick) { [weak self] in self?.tick() }
        greet()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let shown = progress
        if incoming != nil { fail(.cancelled) }
        failBatch(.cancelled)
        shown?.close()
        for id in Array(outgoing.keys) { stopSending(id, .cancelled, tell: true) }
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
        case .copied(let copy, let age, let what): consider(copy, at: clock() - Double(age) / 1000, what: what, from: peer)
        case .bringOver:
            guard allow(&bringTimes, peer, limit: 10, per: 10) else { return }
            bringOverHere()
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
                finished(incoming, .failure(reason))
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
                // A Mac that has just arrived learns of this Mac's newest copy.
                announceCopy(to: [peer])
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
    private func greet() {
        let now = clock()
        for peer in link.peers where formats[peer] == nil && !incompatible.contains(peer) {
            if let sent = helloSent[peer], now - sent < timings.hello { continue }
            helloSent[peer] = now
            send(.hello(formats: DeskClipboardWire.formats, reply: false), to: peer)
        }
    }

    /// The desk's online Macs changed. A Mac that left may come back running a
    /// different Perch, so what it said is forgotten, and what it held is no
    /// longer waiting (default (b)).
    func peersChanged() {
        let online = link.peers
        for peer in Set(formats.keys).union(helloSent.keys).union(noted.keys).union(incompatible) where !online.contains(peer) {
            formats[peer] = nil; helloSent[peer] = nil; noted[peer] = nil; incompatible.remove(peer)
        }
        if let incoming, !online.contains(incoming.peer) { fail(.peerGone, tell: false) }
        if let batch, !online.contains(batch.peer) { failBatch(.peerGone, tell: false) }
        if let waiting, !online.contains(waiting.peer) { self.waiting = nil }
        for (id, out) in outgoing where !online.contains(out.peer) { stopSending(id, .peerGone, tell: false) }
        greet()
    }

    // MARK: This Mac's own copies

    private func observe(_ count: Int) {
        staging.clipboardChanged(to: count, now: clock())
        guard copy?.changeCount != count else { return }
        let first = copy == nil
        copy = Copy(id: UUID(), changeCount: count, at: first ? nil : clock(), received: false)
        // Files examined for an older copy can no longer be sent.
        served = nil
        guard !first else { return }
        // A copy made here is the newest on the desk: nothing is waiting for
        // this Mac any more, and a fetch on its way here is dropped at once.
        newest = (nil, clock())
        waiting = nil
        if incoming != nil { fail(.newerHere) }
        if batch != nil { failBatch(.newerHere) }
        announceCopy()
    }

    /// Tell the other Macs about this Mac's newest copy, once. A copy Perch put
    /// here from another Mac is recognised by its mark and never announced:
    /// that is what stops a copy echoing back or being relayed onwards. A copy
    /// marked concealed, transient or generated leaves no trace on other Macs.
    private func announceCopy(to only: [UUID]? = nil) {
        guard let copy, !copy.received, let at = copy.at, permitted() else { return }
        guard only != nil || (announced != copy.id && announcing != copy.id) else { return }
        let id = copy.id
        if only == nil { announcing = id }
        pasteboard.inspect(limits: limits) { [weak self] inspection in
            guard let self else { return }
            if only == nil, self.announcing == id { self.announcing = nil }
            guard let inspection, let current = self.copy, current.id == id else { return }
            guard inspection.changeCount == current.changeCount else { self.observe(inspection.changeCount); return }
            if only == nil { self.announced = id }
            switch inspection.assessment {
            case .withheld(.received):
                self.copy?.received = true
                return
            case .withheld(let reason) where [.concealed, .transient, .autoGenerated].contains(reason):
                self.decide(.notAnnounced(reason))
                return
            default: break
            }
            let age = UInt32(clamping: Int(max(0, (self.clock() - at) * 1000)))
            let told = (only ?? Array(self.link.peers)).filter { self.send(.copied(copy: id, age: age, what: inspection.what), to: $0) }
            if !told.isEmpty { self.decide(.announced(to: told.map { self.link.name(of: $0) }.sorted())) }
        }
    }

    /// Another Mac copied something. Newer than anything this Mac knows of, it
    /// replaces what is waiting here (default (b)): small text comes straight
    /// onto this clipboard while sharing is on here (default (d)); anything else
    /// waits for ⌃⌥⌘V; a copy that cannot be brought over just clears it.
    private func consider(_ copyID: UUID, at: Double, what: DeskClipboardDescriptor?, from peer: UUID) {
        // The same copy announced again (after a reconnect, say) is recognised
        // by its identity, never by a time that network jitter can nudge.
        if copy?.id == copyID || (waiting?.copy == copyID && waiting?.peer == peer) { return }
        if let newest, at <= newest.at { return }
        newest = (peer, at)
        // Whatever was on its way here is older now.
        if incoming != nil { fail(.newerThere) }
        if batch != nil { failBatch(.newerThere) }
        guard let what else { waiting = nil; decide(.newerElsewhere(from: link.name(of: peer))); return }
        waiting = Waiting(peer: peer, copy: copyID, at: at, what: what)
        if what.small, permitted() { fetch(copyID, at: at, from: peer, mode: .silent) }
        else { decide(.waiting(from: link.name(of: peer))) }
    }

    func tick() {
        greet()
        guard permitted() else {
            if incoming != nil { fail(.sharingOffHere) }
            failBatch(.sharingOffHere)
            for id in Array(outgoing.keys) { stopSending(id, .sharingOffHere, tell: true) }
            return
        }
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        // A copy made while sharing was off, or whose first look timed out, is
        // announced now.
        announceCopy()
        let now = clock()
        for (id, out) in outgoing where now - out.lastAck > timings.serveStall { stopSending(id, .timedOut, tell: true) }
        if now >= nextSweep { nextSweep = now + timings.sweep; sweep() }
    }

    // MARK: Bringing it over

    /// Default (a): bring over acts for the Mac typing goes to (the last one
    /// clicked), whichever Mac's keyboard pressed the keys; with sharing not
    /// running, that is this Mac.
    static func bringOverTarget(keyboard: UUID?, local: UUID) -> UUID { keyboard ?? local }

    /// ⌃⌥⌘V was pressed on this Mac's keyboard. `keyboard` is where typing goes.
    func bringOver(keyboard: UUID?) {
        let target = Self.bringOverTarget(keyboard: keyboard, local: link.localID)
        guard target != link.localID else { bringOverHere(); return }
        guard permitted() else { decide(.notBringing(.sharingOffHere)); return }
        if send(.bringOver, to: target) { decide(.askedToBringOver(on: link.name(of: target))) }
    }

    /// Bring what is waiting onto this Mac's clipboard, with the popup.
    func bringOverHere() {
        guard permitted() else { decide(.notBringing(.sharingOffHere)); return }
        // Default (c): nothing waiting, nothing happens.
        guard let waiting else { decide(.nothingWaiting); return }
        // One at a time; a second press while one is coming is the same request.
        guard progress == nil else { return }
        guard link.peers.contains(waiting.peer), formats[waiting.peer] != nil else {
            self.waiting = nil; decide(.notBringing(.peerGone)); return
        }
        // Small text already on its way silently is brought over with the popup instead.
        if incoming != nil { fail(.cancelled) }
        let from = link.name(of: waiting.peer)
        let shown = DeskPasteProgress(title: DeskPasteProgress.title(waiting.what, from: from), clock: clock, after: after)
        shown.onCancel = { [weak self] in self?.cancelBringOver() }
        progress = shown
        presenter?.present(shown)
        decide(.bringing(from: from))
        fetch(waiting.copy, at: waiting.at, from: waiting.peer, mode: .bringOver)
    }

    /// The person pressed Cancel.
    private func cancelBringOver() {
        if let incoming, incoming.mode == .bringOver { fail(.cancelled) }
        else if batch != nil {
            batch?.cancelled = true
            failBatch(.cancelled)
        }
    }

    /// Copies that will not arrive however often they are asked for stop
    /// waiting; one that failed for a passing reason stays, and bringing it
    /// over again retries.
    static func stopsWaiting(_ reason: DeskClipboardReason) -> Bool {
        [.tooLarge, .folders, .links, .unreadable, .unsupported, .unsafeName, .concealed, .transient, .autoGenerated, .unknownCopy, .changed].contains(reason)
    }

    /// A fetch ended. Updates what is waiting and the popup.
    private func finished(_ incoming: Incoming, _ outcome: Result<Void, DeskClipboardReason>) {
        switch outcome {
        case .success:
            if waiting?.copy == incoming.copy { waiting = nil }
        case .failure(let reason):
            if Self.stopsWaiting(reason), waiting?.copy == incoming.copy { waiting = nil }
        }
        guard incoming.mode == .bringOver, let shown = progress else { return }
        progress = nil
        switch outcome {
        case .success: shown.finish()
        case .failure(let reason): shown.fail(DeskPasteProgress.line(for: reason, from: link.name(of: incoming.peer)))
        }
    }

    // MARK: Fetching a copy (or the names of its files)

    /// The most a silent fetch may bring: small text and the few bytes around it.
    private static let silentPayload = DeskClipboardDescriptor.smallText + 1024

    private func fetch(_ copyID: UUID, at: Double, from peer: UUID, mode: Mode) {
        guard let expected = copy?.changeCount else { return }
        let transfer = UUID(), key = SymmetricKey(size: .bits256)
        incoming = Incoming(id: transfer, peer: peer, copy: copyID, copyAt: at, key: key, mode: mode,
                            files: waiting?.copy == copyID && waiting?.what.kind == .files, expected: expected,
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
        finished(incoming, .failure(reason))
    }

    private func manifestArrived(_ manifest: DeskClipboardManifest, from peer: UUID) {
        guard let incoming, incoming.peer == peer, incoming.id == manifest.transfer, incoming.assembly == nil,
              let format = formats[peer] else { return }
        do {
            // Unasked, only small text comes, whatever the other Mac says it sends.
            let most = incoming.mode == .silent ? Self.silentPayload : limits.total
            let assembly = try DeskClipboardAssembly(manifest, transfer: incoming.id, copy: incoming.copy, key: incoming.key,
                                                     format: format, maximumPayload: most)
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
        if incoming.mode == .bringOver, !incoming.files { progress?.advance(to: assembly.fraction) }
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
            DispatchQueue.main.async { [weak self] in self?.arrived(transfer, result) }
        }
    }

    private func arrived(_ id: UUID, _ result: Result<DeskClipboardPayload, DeskClipboardAssembly.Failure>) {
        guard let incoming, incoming.id == id else { return }
        let from = link.name(of: incoming.peer)
        switch result {
        case .failure(.declined(let reason)):
            // Everything arrived intact; this Mac says no, by name.
            self.incoming = nil
            decide(.discarded(transfer: id, reason))
            finished(incoming, .failure(reason))
        case .failure(let failure): fail(.corrupt, detail: failure.detail)
        case .success(.content(let content)):
            if incoming.mode == .silent {
                let text = content.items.allSatisfy { $0.allSatisfy { !$0.type.isImage } }
                guard text, content.byteCount <= DeskClipboardDescriptor.smallText else {
                    fail(.corrupt, detail: "more than small text arrived unasked"); return
                }
            }
            pasteboard.write(content, marker: incoming.copy, ifUnchanged: incoming.expected) { [weak self] outcome in
                guard let self, self.incoming?.id == id else { return }
                self.incoming = nil
                switch outcome {
                case .success(let count):
                    self.copy = Copy(id: incoming.copy, changeCount: count, at: incoming.copyAt, received: true)
                    self.served = nil
                    self.staging.clipboardChanged(to: count, now: self.clock())
                    self.decide(.received(from: from, transfer: id, size: DeskClipboardPolicy.sizeBucket(content.byteCount)))
                    self.finished(incoming, .success(()))
                case .failure(let reason):
                    self.decide(.discarded(transfer: id, reason))
                    self.finished(incoming, .failure(reason))
                }
            }
        case .success(.files(let list)):
            guard incoming.mode == .bringOver else { fail(.corrupt, detail: "files arrived unasked"); return }
            beginBatch(list, from: incoming)
        }
    }

    // MARK: Bringing a copy's files

    /// The names have arrived. Make each safe, check there is room, then bring
    /// the files one by one into a staging folder of their own.
    private func beginBatch(_ list: DeskFileList, from incoming: Incoming) {
        self.incoming = nil
        // A name that cannot be made safe refuses the whole copy rather than
        // inventing one.
        let safe = list.files.map { entry in DeskFileNames.sanitize(entry.name).map { DeskFileList.Entry(name: $0, size: entry.size) } }
        guard safe.allSatisfy({ $0 != nil }) else {
            decide(.discarded(transfer: incoming.id, .unsafeName)); finished(incoming, .failure(.unsafeName)); return
        }
        if let free = freeSpace(staging.root), free < list.total + Self.spaceMargin {
            decide(.discarded(transfer: incoming.id, .noSpace)); finished(incoming, .failure(.noSpace)); return
        }
        batch = FileBatch(id: incoming.id, peer: incoming.peer, copy: incoming.copy, copyAt: incoming.copyAt, expected: incoming.expected,
                          folder: staging.folder(incoming.id), files: safe.compactMap { $0 })
        let staging = self.staging, id = incoming.id
        disk.async { [weak self] in
            let ready: Bool
            do { try staging.prepare(id); ready = true } catch { ready = false }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.id == id else { return }
                guard ready else { self.failBatch(.writeFailed, tell: false); return }
                self.nextFile()
            }
        }
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

    /// Stand-in for the fetch a batch replaced, so `finished` treats both alike.
    private func asIncoming(_ batch: FileBatch) -> Incoming {
        Incoming(id: batch.id, peer: batch.peer, copy: batch.copy, copyAt: batch.copyAt, key: SymmetricKey(size: .bits256),
                 mode: .bringOver, files: true, expected: batch.expected, started: 0, lastProgress: 0)
    }

    /// End the copy on its way here and remove its staging folder, partial and
    /// verified files alike (rule 1 of `DeskFileStaging`).
    private func failBatch(_ reason: DeskClipboardReason, detail: String? = nil, tell: Bool = true, refusedBy: Bool = false) {
        guard let batch, !batch.placing else { return }
        self.batch = nil
        let sinks = batch.done + (batch.current.map { [$0.sink] } ?? []), staging = self.staging, id = batch.id
        disk.async { sinks.forEach { $0.discard() }; staging.remove(id) }
        if tell, let current = batch.current { send(.cancel(transfer: current.id, reason: reason), to: batch.peer) }
        let from = link.name(of: batch.peer), transfer = batch.current?.id ?? batch.id
        decide(refusedBy ? .refusedBy(from, transfer: transfer, reason) : .failed(from: from, transfer: transfer, reason, detail: detail))
        finished(asIncoming(batch), .failure(reason))
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
                if let batch = self.batch, batch.total > 0 { self.progress?.advance(to: Double(batch.received) / Double(batch.total)) }
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

    /// Every file is here and verified. Mark them as downloaded, give each its
    /// name in the staging folder, and put them on the clipboard as files,
    /// unless something newer was copied here meanwhile or the person pressed
    /// Cancel. If any step fails, none of the copy stays.
    private func placeBatch() {
        guard let batch else { return }
        self.batch?.placing = true
        let sinks = batch.done, id = batch.id, staging = self.staging
        disk.async { [weak self] in
            var placed: [URL] = [], reason: DeskClipboardReason?
            for sink in sinks {
                do { placed.append(try sink.place()) }
                catch let failure as DeskClipboardReason { reason = failure; break }
                catch { reason = .writeFailed; break }
            }
            if reason != nil { sinks.forEach { $0.discard() }; staging.remove(id) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let current = self.batch, current.id == id else { staging.remove(id); return }
                let failure = reason ?? (current.cancelled ? .cancelled : nil)
                if let failure {
                    self.batch = nil
                    if reason == nil { self.disk.async { staging.remove(id) } }
                    self.decide(.failed(from: self.link.name(of: batch.peer), transfer: id, failure, detail: nil))
                    self.finished(self.asIncoming(batch), .failure(failure))
                    return
                }
                let items = placed.map { [(type: DeskClipboardMarker.fileURL, data: $0.dataRepresentation)] }
                self.pasteboard.replace(items, marker: batch.copy, ifUnchanged: batch.expected) { [weak self] outcome in
                    guard let self, self.batch?.id == id else { return }
                    self.batch = nil
                    let from = self.link.name(of: batch.peer)
                    switch outcome {
                    case .success(let count):
                        self.copy = Copy(id: batch.copy, changeCount: count, at: batch.copyAt, received: true)
                        self.served = nil
                        self.staging.placed(id, changeCount: count, now: self.clock())
                        self.decide(.received(from: from, transfer: id, size: DeskClipboardPolicy.sizeBucket(Int(clamping: batch.total))))
                        self.finished(self.asIncoming(batch), .success(()))
                    case .failure(let reason):
                        // Never on the clipboard, so never kept.
                        self.disk.async { staging.remove(id) }
                        self.decide(.discarded(transfer: id, reason))
                        self.finished(self.asIncoming(batch), .failure(reason))
                    }
                }
            }
        }
    }

    /// Apply `DeskFileStaging`'s rule now: list the staging folder off the main
    /// thread and remove what may go.
    func sweep() {
        let staging = self.staging, onClipboard = staging.onClipboard?.id, active = batch?.id, leftAt = staging.leftAt, now = clock()
        disk.async { [weak self] in
            let gone = DeskFileStaging.removable(present: staging.present(), onClipboard: onClipboard, active: active, leftAt: leftAt, now: now)
            gone.forEach { staging.remove($0) }
            DispatchQueue.main.async { [weak self] in
                guard !gone.isEmpty else { return }
                staging.forget(gone)
                self?.decide(.cleaned(gone.count))
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

    private func refuse(_ transfer: UUID, _ reason: DeskClipboardReason, to peer: UUID) {
        send(.refuse(transfer: transfer, reason: reason), to: peer)
        decide(.refused(to: link.name(of: peer), transfer: transfer, reason))
    }

    /// One copy to each Mac at a time and one file to each Mac at a time; three
    /// transfers at most in all. A Mac asks for one copy or file at a time, so a
    /// new request from it replaces whatever it asked for before: that one was
    /// abandoned (it lost this Mac for a moment, or gave up), and waiting for
    /// its stall timer would refuse the new one as busy.
    private func busySending(to peer: UUID, file: Bool) -> Bool {
        for (id, out) in outgoing where out.peer == peer && out.file == file { stopSending(id, .cancelled, tell: false) }
        return outgoing.count >= 3
    }

    /// Only this Mac's own newest copy is ever sent, and only the one announced:
    /// never one that came from another Mac.
    private func serve(_ transfer: UUID, copy copyID: UUID, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&fetchTimes, peer, limit: 60, per: 60) else { refuse(transfer, .rateLimited, to: peer); return }
        guard permitted() else { refuse(transfer, .sharingOff, to: peer); return }
        guard outgoing[transfer] == nil, !busySending(to: peer, file: false) else { refuse(transfer, .busy, to: peer); return }
        guard let copy, copy.id == copyID, !copy.received, copy.at != nil, let format = formats[peer] else { refuse(transfer, .unknownCopy, to: peer); return }
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
        guard let copy, copy.id == copyID, !copy.received, let served, served.copy == copyID, served.files.indices.contains(Int(index)),
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
