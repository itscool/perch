import Foundation
import CryptoKit

extension DeskClipboardReason: Error {}
extension DeskClipboardRefusal: Error {}

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
    /// A copy of files and folders: where they are. They are examined by
    /// walking them, off the pasteboard's queue.
    case files([URL])
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
    /// What a copy is, as far as the pasteboard alone can say.
    enum Verdict: Equatable {
        case shareable(DeskClipboardDescriptor)
        case unshareable(DeskClipboardRefusal)
        /// Perch's own mark: a copy that came from another Mac.
        case received
        /// Files and folders: judged by walking them (`DeskSourceTree`).
        case files([URL])
    }
    struct Inspection: Equatable {
        let changeCount: Int
        let verdict: Verdict
    }
    let store: DeskPasteboardStore
    var timeout: Double
    private let queue = DispatchQueue(label: "Perch.desk.pasteboard", qos: .userInitiated)
    private var pending = 0
    private var stuck = false
    /// The last inspection, reused while the copy is unchanged. Touched only on
    /// the queue, so a copy is looked at once, however often it is asked about.
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

    /// The change count: the only thing read four times a second.
    func poll(_ done: @escaping (Int?) -> Void) { run({ $0.changeCount }, late: nil, done) }

    /// What a new copy is, at the least cost (Scott: Perch must not be a system
    /// hog). Its types decide almost everything, so a concealed copy is refused
    /// before any of its data is read. An image's data is never read here: it
    /// is announced by kind and count, without a size. Text is read one
    /// representation at a time, plain first, only until it is clearly more
    /// than small text. Files are only listed here.
    func inspect(limits: DeskClipboardLimits, _ done: @escaping (Inspection?) -> Void) {
        run({ [weak self] store in
            let count = store.changeCount
            if let cached = self?.inspected, cached.changeCount == count { return cached }
            let types = store.itemTypes()
            let verdict: Verdict
            switch DeskClipboardPolicy.assess(types, limits: limits) {
            case .withheld(.received): verdict = .received
            case .withheld(let reason): verdict = .unshareable(.init(reason))
            case .files: verdict = .files(Self.fileURLs(store, types: types))
            case .share(let plan):
                if plan.contains(where: { $0.contains { $0.isImage } }) {
                    verdict = .shareable(DeskClipboardDescriptor.describe(plan, textBytes: nil))
                } else {
                    verdict = Self.sizeText(store, plan: plan, limits: limits)
                }
            }
            let value = Inspection(changeCount: count, verdict: verdict)
            self?.inspected = value
            return value
        }, late: nil, done)
    }

    /// Text: plain first, then rich text and HTML, stopping as soon as the total
    /// passes the small-text line. Only then is its exact size known; past it,
    /// only that it is more.
    private static func sizeText(_ store: DeskPasteboardStore, plan: [[DeskClipboardType]], limits: DeskClipboardLimits) -> Verdict {
        var total = 0
        for (index, item) in plan.enumerated() {
            for type in item {
                let bytes = store.data(item: index, type: type.identifier)?.count ?? 0
                guard bytes <= limits.cap(type) else { return .unshareable(.init(.tooLarge, amount: UInt64(bytes), limit: UInt64(limits.cap(type)))) }
                total += bytes
                if total > DeskClipboardDescriptor.smallText { return .shareable(DeskClipboardDescriptor.describe(plan, textBytes: nil)) }
            }
        }
        return .shareable(DeskClipboardDescriptor.describe(plan, textBytes: total))
    }

    private static func fileURLs(_ store: DeskPasteboardStore, types: [[String]]) -> [URL] {
        types.indices.compactMap { index in
            store.data(item: index, type: DeskClipboardMarker.fileURL).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
        }
    }

    /// The file URLs the pasteboard holds now, and its change count.
    func files(_ done: @escaping ((changeCount: Int, urls: [URL])?) -> Void) {
        run({ store in (store.changeCount, Self.fileURLs(store, types: store.itemTypes())) }, late: nil, done)
    }

    /// The copy with this change count, or why it cannot be sent. The markers
    /// are checked again at the moment of reading, before any data is.
    func read(expecting changeCount: Int, limits: DeskClipboardLimits,
              _ done: @escaping (Result<DeskClipboardSnapshot, DeskClipboardRefusal>) -> Void) {
        run({ store in
            guard store.changeCount == changeCount else { return .failure(.init(.changed)) }
            let types = store.itemTypes()
            let result: Result<DeskClipboardSnapshot, DeskClipboardRefusal>
            switch DeskClipboardPolicy.assess(types, limits: limits) {
            case .withheld(let reason): return .failure(.init(reason))
            case .files: result = .success(.files(Self.fileURLs(store, types: types)))
            case .share(let plan):
                var items: [[DeskClipboardContent.Representation]] = [], total = 0
                for (index, types) in plan.enumerated() {
                    var item: [DeskClipboardContent.Representation] = []
                    for type in types {
                        guard let data = store.data(item: index, type: type.identifier), !data.isEmpty else { continue }
                        total += data.count
                        guard data.count <= limits.cap(type) else {
                            return .failure(.init(.tooLarge, amount: UInt64(data.count), limit: UInt64(limits.cap(type))))
                        }
                        guard total <= limits.total else { return .failure(.init(.tooLarge, amount: UInt64(total), limit: UInt64(limits.total))) }
                        item.append(.init(type: type, data: data))
                    }
                    if !item.isEmpty { items.append(item) }
                }
                guard !items.isEmpty else { return .failure(.init(.unsupported)) }
                result = .success(.content(DeskClipboardContent(items: items)))
            }
            // The copy must not have changed while it was being read.
            guard store.changeCount == changeCount else { return .failure(.init(.changed)) }
            return result
        }, late: .failure(.init(.readTimedOut)), done)
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
/// **Scott's design, September 27, 2026, confirmed November 2026.** When
/// something is copied on a Mac:
/// - A copy that is only text, 64 KB or less in all, goes onto every other
///   connected Mac's clipboard that has sharing on. The copying Mac announces
///   it and each of those Macs fetches it at once, silently.
/// - Anything else that can be brought over (more text, an image, files,
///   folders) is only announced: its kind, a size bucket, which Mac has it.
///   ⌃⌥⌘V brings it onto the clipboard of the Mac typing goes to, with a small
///   progress popup that closes itself. After that every ordinary paste works.
/// - A copy that cannot be brought over (private, too large, a link that leads
///   outside it) is invisible: never announced. Pressing ⌃⌥⌘V asks the other
///   Macs what their newest copy is, so the popup can say why it stays there.
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
/// **Scott's rules, each decided in one place:**
/// - Bring over acts for the Mac typing goes to: `bringOverTarget`.
/// - What is waiting clears when a newer copy is announced anywhere, when a copy
///   is made here, and when the Mac holding it leaves: `consider`, `observe`,
///   `peersChanged`. An unshareable copy is never announced, so it clears
///   nothing elsewhere; ⌃⌥⌘V finds it.
/// - Bring over with nothing newer anywhere does nothing: `settleBringOver`.
/// - Small text reaches only Macs with sharing on: `consider`.
/// - The shortcut is fixed: `DeskBringOverShortcut`.
final class DeskClipboard {
    struct Timings {
        /// How long ⌃⌥⌘V waits for the other Macs to say what they have.
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
        /// How often this Mac's clipboard's change count is checked.
        var tick = 0.25
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
    /// Every file read and write, in order, and the walks that judge files.
    let disk = DispatchQueue(label: "Perch.desk.files", qos: .userInitiated)
    private(set) var lastDecision: DeskClipboardDecision?
    private(set) var decisions: [DeskClipboardDecision] = []

    private var formats: [UUID: UInt8] = [:]
    /// Macs that greeted with no format in common with this one.
    private var incompatible: Set<UUID> = []
    private var helloSent: [UUID: Double] = [:]
    private var noted: [UUID: DeskClipboardReason] = [:]

    /// What a copy of this Mac's is, once judged.
    enum Verdict: Equatable {
        case shareable(DeskClipboardDescriptor)
        case unshareable(DeskClipboardRefusal)
        case received
    }
    /// What this Mac's clipboard holds. `at` is when it was copied, on this
    /// Mac's clock, nil for what was already there when Perch started (never
    /// announced). `verdict` is filled once it is judged.
    private struct Copy { let id: UUID; let changeCount: Int; let at: Double?; var verdict: Verdict? }
    private var copy: Copy?
    /// Callbacks waiting for the copy being judged. One look per copy.
    private var judging: (id: UUID, waiting: [(Verdict?) -> Void])?
    /// The copy last announced, so each is announced once.
    private var announced: UUID?
    /// The newest copy this Mac knows of on the desk: which Mac holds it (nil
    /// for this one) and when it was made, on this Mac's clock.
    private var newest: (peer: UUID?, at: Double)?

    /// Another Mac's copy, newer than anything here, not yet on this Mac.
    struct Waiting: Equatable {
        let peer: UUID, copy: UUID, at: Double
        let what: DeskClipboardDescriptor
    }
    private(set) var waiting: Waiting? { didSet { if waiting != oldValue { waitingChanged() } } }

    /// ⌃⌥⌘V asking the desk what its newest copy is.
    private struct Asking {
        let id: UUID
        var waiting: Set<UUID>
        var answers: [UUID: (copy: UUID?, at: Double, answer: DeskClipboardAnswer)]
    }
    private var asking: Asking?

    private enum Mode { case silent, bringOver }
    private struct Incoming {
        let id: UUID, peer: UUID, copy: UUID, copyAt: Double, key: SymmetricKey
        let mode: Mode
        /// Fetching the list of a copy's files: the popup's progress follows
        /// the files' own bytes, not this short list.
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

    /// What this Mac sends: a sealed copy held in memory, or a copy's files read
    /// from disk a chunk at a time.
    private struct Outgoing {
        let peer: UUID, key: SymmetricKey, format: UInt8
        let file: Bool
        var lastAck: Double
        var parcel: DeskClipboardWire.Parcel?
        var manifest: DeskClipboardManifest?
        var reader: DeskTreeReader?
        var reading = false
        var next: UInt32 = 0
        var acked: UInt32 = 0
        var paced = false
    }
    private var outgoing: [UUID: Outgoing] = [:]

    /// The files behind this Mac's newest copy, as examined when another Mac
    /// asked for their list, and the list as sent. Only these can be sent.
    private var served: (copy: UUID, tree: DeskSourceTree, list: Data)?

    /// Another Mac's copy of files on its way into the staging folder.
    private struct Batch {
        let id: UUID, peer: UUID, copy: UUID, copyAt: Double
        let expected: Int
        let folder: URL
        let plan: DeskTreePlan
        /// SHA-256 of the list checked here: the stream must say it follows it.
        let listDigest: Data
        let stream: UUID
        let key: SymmetricKey
        var writer: DeskTreeWriter?
        var assembly: DeskClipboardAssembly?
        var written: UInt32 = 0
        var verified = 0
        var received: UInt64 = 0
        let started: Double
        var lastProgress: Double
        /// Everything is here and being put in place. From here the copy
        /// finishes on its own terms: its pasteboard write already refuses if
        /// anything newer was copied, and then removes what it placed.
        var placing = false
        var cancelled = false
    }
    private var batch: Batch?

    private var fetchTimes: [UUID: [Double]] = [:]
    private var treeFetchTimes: [UUID: [Double]] = [:]
    private var bringTimes: [UUID: [Double]] = [:]
    private var askTimes: [UUID: [Double]] = [:]
    private var inbound: [UUID: (start: Double, count: Int)] = [:]
    private var timer: Timer?
    private var nextSweep: Double = 0

    init(link: DeskClipboardLink, pasteboard: DeskPasteboardAccess, staging: DeskFileStaging = DeskFileStaging(root: DeskFileStaging.standard)) {
        self.link = link; self.pasteboard = pasteboard; self.staging = staging
    }
    deinit { timer?.invalidate() }

    /// Whether a transfer is under way in either direction, for tests and status.
    var busy: Bool { incoming != nil || batch != nil || !outgoing.isEmpty || asking != nil }
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
        failBatch(.init(.cancelled))
        shown?.close()
        asking = nil
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
            if let batch, batch.peer == peer { failBatch(.init(.corrupt), detail: "unreadable message") }
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
        return entry.count <= 4000
    }

    private func handle(_ message: DeskClipboardMessage, from peer: UUID) {
        switch message {
        case .hello(let theirs, let reply): greeted(theirs, reply: reply, by: peer)
        case .copied(let copy, let age, let what): consider(copy, at: clock() - Double(age) / 1000, what: what, from: peer)
        case .bringOver:
            guard allow(&bringTimes, peer, limit: 10, per: 10) else { return }
            bringOverHere()
        case .ask(let query): answer(query, to: peer)
        case .newest(let query, let copy, let age, let answer):
            answered(query, by: peer, copy: copy, at: clock() - Double(age) / 1000, answer: answer)
        case .fetch(let transfer, let copy, let key): serve(transfer, copy: copy, key: key, to: peer)
        case .treeFetch(let transfer, let copy, let key): serveTree(transfer, copy: copy, key: key, to: peer)
        case .manifest(let manifest):
            if batch?.stream == manifest.transfer { streamManifestArrived(manifest, from: peer) } else { manifestArrived(manifest, from: peer) }
        case .chunk(let transfer, let index, let data, let mac):
            if batch?.stream == transfer { streamChunkArrived(transfer, index: index, data: data, mac: mac, from: peer) }
            else { chunkArrived(transfer, index: index, data: data, mac: mac, from: peer) }
        case .fileDigest(let transfer, let index, let digest, let mac): fileDigestArrived(transfer, index: index, digest: digest, mac: mac, from: peer)
        case .ack(let transfer, let next): acknowledged(transfer, next: next, by: peer)
        case .refuse(let transfer, let refusal):
            refused(transfer, refusal, by: peer)
        case .cancel(let transfer, let reason):
            refused(transfer, .init(reason), by: peer)
        }
    }

    /// The other Mac said no, or stopped: whichever transfer it was, by name.
    private func refused(_ transfer: UUID, _ refusal: DeskClipboardRefusal, by peer: UUID) {
        if let out = outgoing[transfer], out.peer == peer { stopSending(transfer, refusal.reason, tell: false) }
        else if let incoming, incoming.id == transfer, incoming.peer == peer {
            self.incoming = nil
            decide(.refusedBy(link.name(of: peer), transfer: transfer, refusal.reason))
            finished(incoming, .failure(refusal))
        } else if let batch, batch.stream == transfer, batch.peer == peer {
            failBatch(refusal, tell: false, refusedBy: true)
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
    /// longer waiting.
    func peersChanged() {
        let online = link.peers
        for peer in Set(formats.keys).union(helloSent.keys).union(noted.keys).union(incompatible) where !online.contains(peer) {
            formats[peer] = nil; helloSent[peer] = nil; noted[peer] = nil; incompatible.remove(peer)
        }
        if let incoming, !online.contains(incoming.peer) { fail(.peerGone, tell: false) }
        if let batch, !online.contains(batch.peer) { failBatch(.init(.peerGone), tell: false) }
        if let waiting, !online.contains(waiting.peer) { self.waiting = nil }
        for (id, out) in outgoing where !online.contains(out.peer) { stopSending(id, .peerGone, tell: false) }
        if var asking {
            asking.waiting = asking.waiting.intersection(online)
            self.asking = asking
            if asking.waiting.isEmpty { settleBringOver(asking.id) }
        }
        greet()
    }

    // MARK: This Mac's own copies

    private func observe(_ count: Int) {
        staging.clipboardChanged(to: count, now: clock())
        guard copy?.changeCount != count else { return }
        let first = copy == nil
        copy = Copy(id: UUID(), changeCount: count, at: first ? nil : clock(), verdict: nil)
        // Files examined for an older copy can no longer be sent.
        served = nil
        guard !first else { return }
        // A copy made here is the newest on the desk: nothing is waiting for
        // this Mac any more, and a fetch on its way here is dropped at once.
        newest = (nil, clock())
        waiting = nil
        if incoming != nil { fail(.newerHere) }
        if batch != nil { failBatch(.init(.newerHere)) }
        announceCopy()
    }

    /// Judge this Mac's newest copy once: from the pasteboard's types, then for
    /// files by walking them on the disk queue. Callbacks that arrive while it
    /// is being judged share the one look.
    private func judge(_ done: @escaping (Verdict?) -> Void) {
        guard let copy else { done(nil); return }
        if let verdict = copy.verdict { done(verdict); return }
        if let judging, judging.id == copy.id { self.judging?.waiting.append(done); return }
        judging = (copy.id, [done])
        let id = copy.id, fileLimits = self.fileLimits
        func settle(_ verdict: Verdict?) {
            guard let waiting = judging, waiting.id == id else { return }
            judging = nil
            if let verdict, self.copy?.id == id { self.copy?.verdict = verdict }
            for callback in waiting.waiting { callback(self.copy?.id == id ? verdict : nil) }
        }
        pasteboard.inspect(limits: limits) { [weak self] inspection in
            guard let self else { return }
            guard let inspection, self.copy?.id == id else { settle(nil); return }
            guard inspection.changeCount == self.copy?.changeCount else { settle(nil); self.observe(inspection.changeCount); return }
            switch inspection.verdict {
            case .received: settle(.received)
            case .shareable(let what): settle(.shareable(what))
            case .unshareable(let refusal): settle(.unshareable(refusal))
            case .files(let urls):
                // A walk of names and sizes only, bounded by the item and depth limits.
                self.disk.async { [weak self] in
                    let verdict: Verdict
                    switch DeskSourceTree.examine(urls, limits: fileLimits) {
                    case .success(let tree): verdict = .shareable(tree.list.descriptor)
                    case .failure(let refusal): verdict = .unshareable(refusal)
                    }
                    DispatchQueue.main.async { [weak self] in if self != nil { settle(verdict) } }
                }
            }
        }
    }

    /// Tell the other Macs about this Mac's newest copy, once, if it can be
    /// brought over. A copy that cannot is invisible: nothing about it leaves
    /// this Mac unless ⌃⌥⌘V asks. A copy Perch put here from another Mac is
    /// recognised by its mark and never announced, which is what stops a copy
    /// echoing back or being relayed onwards.
    private func announceCopy(to only: [UUID]? = nil) {
        guard let copy, let at = copy.at, permitted() else { return }
        guard only != nil || announced != copy.id else { return }
        let id = copy.id
        if only == nil { announced = id }
        judge { [weak self] verdict in
            guard let self, let verdict, self.copy?.id == id else {
                if only == nil, self?.announced == id { self?.announced = nil }
                return
            }
            switch verdict {
            case .received: return
            case .unshareable(let refusal):
                if only == nil { self.decide(.notAnnounced(refusal.reason)) }
            case .shareable(let what):
                let age = UInt32(clamping: Int(max(0, (self.clock() - at) * 1000)))
                let told = (only ?? Array(self.link.peers)).filter { self.send(.copied(copy: id, age: age, what: what), to: $0) }
                if !told.isEmpty { self.decide(.announced(to: told.map { self.link.name(of: $0) }.sorted())) }
            }
        }
    }

    /// Another Mac copied something that can be brought over. Newer than
    /// anything this Mac knows of, it replaces what is waiting here: small text
    /// comes straight onto this clipboard while sharing is on here; anything
    /// else waits for ⌃⌥⌘V.
    private func consider(_ copyID: UUID, at: Double, what: DeskClipboardDescriptor, from peer: UUID) {
        // The same copy announced again (after a reconnect, say) is recognised
        // by its identity, never by a time that network jitter can nudge.
        if copy?.id == copyID || (waiting?.copy == copyID && waiting?.peer == peer) { return }
        if let newest, at <= newest.at { return }
        newest = (peer, at)
        // Whatever was on its way here is older now.
        if incoming != nil { fail(.newerThere) }
        if batch != nil { failBatch(.init(.newerThere)) }
        waiting = Waiting(peer: peer, copy: copyID, at: at, what: what)
        if what.small, permitted() { fetch(copyID, at: at, from: peer, mode: .silent) }
        else { decide(.waiting(from: link.name(of: peer))) }
    }

    func tick() {
        greet()
        guard permitted() else {
            if incoming != nil { fail(.sharingOffHere) }
            failBatch(.init(.sharingOffHere))
            for id in Array(outgoing.keys) { stopSending(id, .sharingOffHere, tell: true) }
            return
        }
        // Cheap by rule: the change count, nothing more, four times a second.
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        // A copy made while sharing was off, or whose first look timed out, is
        // announced now.
        announceCopy()
        let now = clock()
        for (id, out) in outgoing where now - out.lastAck > timings.serveStall { stopSending(id, .timedOut, tell: true) }
        if now >= nextSweep { nextSweep = now + timings.sweep; sweep() }
    }

    // MARK: Bringing it over

    /// Bring over acts for the Mac typing goes to (the last one clicked),
    /// whichever Mac's keyboard pressed the keys; with sharing not running,
    /// that is this Mac.
    static func bringOverTarget(keyboard: UUID?, local: UUID) -> UUID { keyboard ?? local }

    /// ⌃⌥⌘V was pressed on this Mac's keyboard. `keyboard` is where typing goes.
    func bringOver(keyboard: UUID?) {
        let target = Self.bringOverTarget(keyboard: keyboard, local: link.localID)
        guard target != link.localID else { bringOverHere(); return }
        guard permitted() else { decide(.notBringing(.sharingOffHere)); return }
        if send(.bringOver, to: target) { decide(.askedToBringOver(on: link.name(of: target))) }
    }

    /// Bring the desk's newest copy onto this Mac's clipboard, with the popup.
    /// The other Macs are asked first, even with nothing waiting, so that a
    /// newest copy that cannot come is explained rather than silently skipped.
    func bringOverHere() {
        guard permitted() else { decide(.notBringing(.sharingOffHere)); return }
        // One at a time; a second press while one is coming is the same request.
        guard progress == nil, asking == nil, batch == nil else { return }
        let id = UUID()
        let asked = Set(link.peers.filter { send(.ask(query: id), to: $0) })
        guard !asked.isEmpty else {
            if let waiting { unreachable(waiting) } else { decide(.nothingWaiting) }
            return
        }
        asking = Asking(id: id, waiting: asked, answers: [:])
        after(timings.query) { [weak self] in self?.settleBringOver(id) }
    }

    private func answered(_ id: UUID, by peer: UUID, copy: UUID?, at: Double, answer: DeskClipboardAnswer) {
        guard var asking, asking.id == id, asking.waiting.remove(peer) != nil else { return }
        asking.answers[peer] = (copy, at, answer)
        self.asking = asking
        if asking.waiting.isEmpty { settleBringOver(id) }
    }

    /// The desk has answered ⌃⌥⌘V. The youngest copy wins, this Mac's own
    /// included: already here, nothing happens; it cannot come, the popup says
    /// why in one line; otherwise it comes, with the popup.
    private func settleBringOver(_ id: UUID) {
        guard let asking, asking.id == id else { return }
        self.asking = nil
        guard permitted() else { decide(.notBringing(.sharingOffHere)); return }
        // A received copy is never brought over from the Mac that received it:
        // its own Mac answers for it.
        let candidates = asking.answers.compactMap { peer, value -> (peer: UUID, copy: UUID, at: Double, answer: DeskClipboardAnswer)? in
            guard let copy = value.copy else { return nil }
            switch value.answer {
            case .shareable, .unshareable: return (peer, copy, value.at, value.answer)
            case .nothing, .received: return nil
            }
        }
        guard let best = candidates.max(by: { $0.at < $1.at }) else {
            if let waiting, asking.answers[waiting.peer] == nil { unreachable(waiting) } else { decide(.nothingWaiting) }
            return
        }
        let from = link.name(of: best.peer)
        if best.copy == copy?.id { decide(.newestHere); return }
        if let own = copy?.at, own >= best.at { decide(.newestHere); return }
        switch best.answer {
        case .unshareable(let refusal):
            waiting = nil
            show(DeskPasteProgress.explain(refusal, from: from))
            decide(.explained(from: from, refusal.reason))
        case .shareable(let what):
            if waiting?.copy != best.copy { waiting = Waiting(peer: best.peer, copy: best.copy, at: best.at, what: what) }
            newest = (best.peer, best.at)
            guard let waiting else { return }
            // Small text already on its way silently comes with the popup instead.
            if incoming != nil { fail(.cancelled) }
            let shown = DeskPasteProgress(title: DeskPasteProgress.title(waiting.what, from: from), clock: clock, after: after)
            shown.onCancel = { [weak self] in self?.cancelBringOver() }
            progress = shown
            presenter?.present(shown)
            decide(.bringing(from: from))
            fetch(waiting.copy, at: waiting.at, from: waiting.peer, mode: .bringOver)
        case .nothing, .received: decide(.nothingWaiting)
        }
    }

    /// What was waiting cannot be asked for: its Mac did not answer.
    private func unreachable(_ waiting: Waiting) {
        show(DeskPasteProgress.line(for: .init(.peerGone), from: link.name(of: waiting.peer)))
        decide(.notBringing(.peerGone))
    }

    /// The popup with one line, closing itself.
    private func show(_ sentence: String) {
        let shown = DeskPasteProgress(title: sentence, clock: clock, after: after)
        presenter?.present(shown)
        shown.inform()
    }

    /// The person pressed Cancel.
    private func cancelBringOver() {
        if let incoming, incoming.mode == .bringOver { fail(.cancelled) }
        else if batch != nil {
            batch?.cancelled = true
            failBatch(.init(.cancelled))
        }
    }

    /// Copies that will not arrive however often they are asked for stop
    /// waiting; one that failed for a passing reason stays, and bringing it
    /// over again retries.
    static func stopsWaiting(_ reason: DeskClipboardReason) -> Bool {
        [.tooLarge, .fileTooLarge, .tooMany, .tooDeep, .links, .linkOutside, .unreadable, .unsupported, .unsafeName,
         .concealed, .transient, .autoGenerated, .unknownCopy, .changed].contains(reason)
    }

    /// A fetch ended. Updates what is waiting and the popup.
    private func finished(_ copyID: UUID, peer: UUID, mode: Mode, _ outcome: Result<Void, DeskClipboardRefusal>) {
        switch outcome {
        case .success:
            if waiting?.copy == copyID { waiting = nil }
        case .failure(let refusal):
            if Self.stopsWaiting(refusal.reason), waiting?.copy == copyID { waiting = nil }
        }
        guard mode == .bringOver, let shown = progress else { return }
        progress = nil
        switch outcome {
        case .success: shown.finish()
        case .failure(let refusal): shown.fail(DeskPasteProgress.line(for: refusal, from: link.name(of: peer)))
        }
    }
    private func finished(_ incoming: Incoming, _ outcome: Result<Void, DeskClipboardRefusal>) {
        finished(incoming.copy, peer: incoming.peer, mode: incoming.mode, outcome)
    }

    // MARK: Fetching a copy (or the list of its files)

    /// The most a silent fetch may bring: small text and the few bytes around it.
    private static let silentPayload = DeskClipboardDescriptor.smallText + 1024

    private func fetch(_ copyID: UUID, at: Double, from peer: UUID, mode: Mode) {
        guard let expected = copy?.changeCount else { return }
        let transfer = UUID(), key = SymmetricKey(size: .bits256)
        let files = waiting?.copy == copyID && [.files, .folders].contains(waiting?.what.kind)
        incoming = Incoming(id: transfer, peer: peer, copy: copyID, copyAt: at, key: key, mode: mode, files: files, expected: expected,
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
        finished(incoming, .failure(.init(reason)))
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
            let result: Arrival
            do {
                switch try DeskClipboardPayload.decode(try assembly.finish(), limits: limits, fileLimits: fileLimits) {
                case .content(let content): result = .content(content)
                case .files(let list, let encoded):
                    // The one place a hostile list is refused, off the main thread.
                    switch DeskTreePlan.make(list, limits: fileLimits) {
                    case .success(let plan): result = .files(plan, listDigest: Data(SHA256.hash(data: encoded)))
                    case .failure(let refusal): result = .declined(refusal)
                    }
                }
            }
            catch DeskClipboardAssembly.Failure.declined(let reason) { result = .declined(.init(reason)) }
            catch let failure as DeskClipboardAssembly.Failure { result = .damaged(failure.detail) }
            catch let reason as DeskClipboardReason { result = .declined(.init(reason)) }
            catch { result = .damaged("does not follow the format") }
            DispatchQueue.main.async { [weak self] in self?.arrived(transfer, result) }
        }
    }

    /// What a completed fetch turned out to be, worked out off the main thread.
    private enum Arrival {
        case content(DeskClipboardContent)
        /// A checked list of files and folders, and the SHA-256 of the list as
        /// sent, which the stream of their contents must name.
        case files(DeskTreePlan, listDigest: Data)
        /// Whole and intact, but this Mac says no, by name.
        case declined(DeskClipboardRefusal)
        case damaged(String)
    }

    private func arrived(_ id: UUID, _ result: Arrival) {
        guard let incoming, incoming.id == id else { return }
        let from = link.name(of: incoming.peer)
        switch result {
        case .declined(let refusal):
            self.incoming = nil
            decide(.discarded(transfer: id, refusal.reason))
            finished(incoming, .failure(refusal))
        case .damaged(let detail): fail(.corrupt, detail: detail)
        case .content(let content):
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
                    self.copy = Copy(id: incoming.copy, changeCount: count, at: incoming.copyAt, verdict: .received)
                    self.served = nil
                    self.staging.clipboardChanged(to: count, now: self.clock())
                    self.decide(.received(from: from, transfer: id, size: DeskClipboardPolicy.sizeBucket(content.byteCount)))
                    self.finished(incoming, .success(()))
                case .failure(let reason):
                    self.decide(.discarded(transfer: id, reason))
                    self.finished(incoming, .failure(.init(reason)))
                }
            }
        case .files(let plan, let listDigest):
            guard incoming.mode == .bringOver else { fail(.corrupt, detail: "files arrived unasked"); return }
            beginBatch(plan, listDigest: listDigest, from: incoming)
        }
    }

    // MARK: Bringing a copy's files and folders

    /// The list has arrived and been checked, every name made safe. Check there
    /// is room, create the copy's folders in a staging folder of its own, then
    /// ask for the files' stream.
    private func beginBatch(_ plan: DeskTreePlan, listDigest: Data, from incoming: Incoming) {
        self.incoming = nil
        if let free = freeSpace(staging.root), free < plan.total + Self.spaceMargin {
            decide(.discarded(transfer: incoming.id, .noSpace)); finished(incoming, .failure(.init(.noSpace))); return
        }
        let stream = UUID(), key = SymmetricKey(size: .bits256)
        batch = Batch(id: incoming.id, peer: incoming.peer, copy: incoming.copy, copyAt: incoming.copyAt, expected: incoming.expected,
                      folder: staging.folder(incoming.id), plan: plan, listDigest: listDigest, stream: stream, key: key,
                      started: clock(), lastProgress: clock())
        let staging = self.staging, id = incoming.id, folder = staging.folder(incoming.id), copyID = incoming.copy, peer = incoming.peer
        disk.async { [weak self] in
            let made: Result<DeskTreeWriter, DeskClipboardReason>
            do { try staging.prepare(id); made = .success(try DeskTreeWriter(root: folder, plan: plan)) }
            catch let reason as DeskClipboardReason { made = .failure(reason) }
            catch { made = .failure(.writeFailed) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.id == id else { if case .success(let writer) = made { self?.disk.async { writer.close() } }; return }
                switch made {
                case .failure(let reason): self.failBatch(.init(reason), tell: false)
                case .success(let writer):
                    self.batch?.writer = writer
                    guard self.send(.treeFetch(transfer: stream, copy: copyID, key: key.withUnsafeBytes { Data($0) }), to: peer) else {
                        self.failBatch(.init(.peerGone), tell: false); return
                    }
                    self.watchBatch(id)
                }
            }
        }
    }

    private func watchBatch(_ id: UUID) {
        after(max(0.02, min(timings.reply, timings.stall) / 5)) { [weak self] in
            guard let self, let batch = self.batch, batch.id == id, !batch.placing else { return }
            let now = self.clock()
            if batch.assembly == nil, now - batch.started > self.timings.reply { self.failBatch(.init(.timedOut), detail: "no reply"); return }
            if batch.assembly != nil, now - batch.lastProgress > self.timings.stall { self.failBatch(.init(.timedOut), detail: "stalled"); return }
            self.watchBatch(id)
        }
    }

    /// End the copy on its way here and remove its staging folder, everything
    /// in it (rule 1 of `DeskFileStaging`).
    private func failBatch(_ refusal: DeskClipboardRefusal, detail: String? = nil, tell: Bool = true, refusedBy: Bool = false) {
        guard let batch, !batch.placing else { return }
        self.batch = nil
        let writer = batch.writer, staging = self.staging, id = batch.id
        disk.async { writer?.close(); staging.remove(id) }
        if tell { send(.cancel(transfer: batch.stream, reason: refusal.reason), to: batch.peer) }
        let from = link.name(of: batch.peer)
        decide(refusedBy ? .refusedBy(from, transfer: batch.stream, refusal.reason) : .failed(from: from, transfer: batch.stream, refusal.reason, detail: detail))
        finished(batch.copy, peer: batch.peer, mode: .bringOver, .failure(refusal))
    }

    private func streamManifestArrived(_ manifest: DeskClipboardManifest, from peer: UUID) {
        guard let batch, batch.peer == peer, batch.assembly == nil, batch.writer != nil, let format = formats[peer] else { return }
        do {
            let assembly = try DeskClipboardAssembly(manifest, transfer: batch.stream, copy: batch.copy, key: batch.key, format: format,
                                                     maximumPayload: Int(clamping: fileLimits.total), streaming: true)
            // The stream must be of exactly the list this Mac checked.
            guard manifest.payloadLength == batch.plan.total, DeskClipboardWire.validMAC(manifest.digest, batch.listDigest) else {
                failBatch(.init(.corrupt), detail: "the files are not the ones listed"); return
            }
            self.batch?.assembly = assembly
            self.batch?.lastProgress = clock()
            send(.ack(transfer: batch.stream, next: 0), to: peer)
        } catch let failure as DeskClipboardAssembly.Failure {
            failBatch(.init(.corrupt), detail: "manifest " + failure.detail)
        } catch { failBatch(.init(.corrupt), detail: "manifest unreadable") }
    }

    private func streamChunkArrived(_ transfer: UUID, index: UInt32, data: Data, mac: Data, from peer: UUID) {
        guard let batch, batch.peer == peer, !batch.placing, let writer = batch.writer else { return }
        guard let assembly = batch.assembly else { failBatch(.init(.corrupt), detail: "a chunk arrived before its manifest"); return }
        let part: Data
        do { part = try assembly.accept(transfer: transfer, index: index, data: data, mac: mac) }
        catch let failure as DeskClipboardAssembly.Failure { failBatch(.init(.corrupt), detail: failure.detail); return }
        catch { failBatch(.init(.corrupt), detail: "unreadable chunk"); return }
        self.batch?.lastProgress = clock()
        let id = batch.id
        // Written in order on the disk queue, and acknowledged once on disk, so
        // the window bounds what waits in memory.
        disk.async { [weak self] in
            let failure: DeskClipboardReason?
            do { try writer.append(part); failure = nil }
            catch let reason as DeskClipboardReason { failure = reason }
            catch { failure = .writeFailed }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.id == id else { return }
                if let failure { self.failBatch(.init(failure)); return }
                self.batch?.written += 1
                self.batch?.received += UInt64(part.count)
                self.batch?.lastProgress = self.clock()
                if let batch = self.batch, batch.plan.total > 0 { self.progress?.advance(to: Double(batch.received) / Double(batch.plan.total)) }
                self.send(.ack(transfer: transfer, next: self.batch?.written ?? 0), to: peer)
                self.placeIfComplete()
            }
        }
    }

    private func fileDigestArrived(_ transfer: UUID, index: UInt32, digest: Data, mac: Data, from peer: UUID) {
        guard let batch, batch.peer == peer, batch.stream == transfer, !batch.placing, let writer = batch.writer,
              let format = formats[peer], Int(index) < batch.plan.files.count else { return }
        guard DeskClipboardWire.validMAC(DeskClipboardWire.fileDigestMAC(format: format, transfer: transfer, index: index, digest: digest, key: batch.key), mac) else {
            failBatch(.init(.corrupt), detail: "a file's digest failed authentication"); return
        }
        let id = batch.id
        disk.async { [weak self] in
            let failure: DeskClipboardReason?
            do { try writer.verify(Int(index), digest: digest); failure = nil }
            catch let reason as DeskClipboardReason { failure = reason }
            catch { failure = .writeFailed }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.batch?.id == id else { return }
                if let failure { self.failBatch(.init(failure), detail: failure == .corrupt ? "a file is not what was sent" : nil); return }
                self.batch?.verified += 1
                self.placeIfComplete()
            }
        }
    }

    /// Every chunk is on disk and every file checked: create the links, last,
    /// and put the copy's top-level items on the clipboard as files, unless
    /// something newer was copied here meanwhile or the person pressed Cancel.
    /// If any step fails, none of the copy stays.
    private func placeIfComplete() {
        guard let batch, !batch.placing, let writer = batch.writer, let assembly = batch.assembly,
              batch.written == assembly.manifest.chunkCount, batch.verified == batch.plan.files.count else { return }
        self.batch?.placing = true
        let id = batch.id, staging = self.staging
        disk.async { [weak self] in
            let placed: Result<[URL], DeskClipboardReason>
            do { placed = .success(try writer.finish()) }
            catch let reason as DeskClipboardReason { placed = .failure(reason) }
            catch { placed = .failure(.writeFailed) }
            writer.close()
            if case .failure = placed { staging.remove(id) }
            DispatchQueue.main.async { [weak self] in
                guard let self, let current = self.batch, current.id == id else { staging.remove(id); return }
                let urls: [URL]
                switch placed {
                case .failure(let reason):
                    self.batch = nil
                    self.decide(.failed(from: self.link.name(of: batch.peer), transfer: batch.stream, reason, detail: nil))
                    self.finished(batch.copy, peer: batch.peer, mode: .bringOver, .failure(.init(reason)))
                    return
                case .success(let made): urls = made
                }
                if current.cancelled {
                    self.batch = nil
                    self.disk.async { staging.remove(id) }
                    self.decide(.failed(from: self.link.name(of: batch.peer), transfer: batch.stream, .cancelled, detail: nil))
                    self.finished(batch.copy, peer: batch.peer, mode: .bringOver, .failure(.init(.cancelled)))
                    return
                }
                let items = urls.map { [(type: DeskClipboardMarker.fileURL, data: $0.dataRepresentation)] }
                self.pasteboard.replace(items, marker: batch.copy, ifUnchanged: batch.expected) { [weak self] outcome in
                    guard let self, self.batch?.id == id else { return }
                    self.batch = nil
                    let from = self.link.name(of: batch.peer)
                    switch outcome {
                    case .success(let count):
                        self.copy = Copy(id: batch.copy, changeCount: count, at: batch.copyAt, verdict: .received)
                        self.served = nil
                        self.staging.placed(id, changeCount: count, now: self.clock())
                        self.decide(.received(from: from, transfer: batch.stream, size: DeskClipboardPolicy.sizeBucket(Int(clamping: batch.plan.total))))
                        self.finished(batch.copy, peer: batch.peer, mode: .bringOver, .success(()))
                    case .failure(let reason):
                        // Never on the clipboard, so never kept.
                        self.disk.async { staging.remove(id) }
                        self.decide(.discarded(transfer: batch.stream, reason))
                        self.finished(batch.copy, peer: batch.peer, mode: .bringOver, .failure(.init(reason)))
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

    /// Another Mac's ⌃⌥⌘V asks what this Mac's newest copy is. The answer
    /// carries why a copy cannot come: the only time an unshareable copy's
    /// existence leaves this Mac, and only to a Mac of the same desk asking.
    private func answer(_ query: UUID, to peer: UUID) {
        guard allow(&askTimes, peer, limit: 20, per: 10) else { return }
        func reply(_ copy: UUID?, _ at: Double?, _ answer: DeskClipboardAnswer) {
            let age = at.map { UInt32(clamping: Int(max(0, (clock() - $0) * 1000))) } ?? 0
            send(.newest(query: query, copy: copy, age: age, answer: answer), to: peer)
        }
        // A Mac with sharing off takes no part, and says nothing of its copies.
        guard permitted(), let copy, let at = copy.at else { reply(nil, nil, .nothing); return }
        let id = copy.id
        judge { [weak self] verdict in
            guard let self, self.copy?.id == id else { reply(nil, nil, .nothing); return }
            switch verdict {
            case .shareable(let what)?: reply(id, at, .shareable(what))
            case .unshareable(let refusal)?: reply(id, at, .unshareable(refusal))
            case .received?: reply(id, at, .received)
            case nil: reply(id, at, .unshareable(.init(.readTimedOut)))
            }
        }
    }

    private func refuse(_ transfer: UUID, _ refusal: DeskClipboardRefusal, to peer: UUID) {
        send(.refuse(transfer: transfer, refusal: refusal), to: peer)
        decide(.refused(to: link.name(of: peer), transfer: transfer, refusal.reason))
    }

    /// One copy to each Mac at a time and one stream of files to each Mac at a
    /// time; three transfers at most in all. A Mac asks for one copy or stream
    /// at a time, so a new request from it replaces whatever it asked for
    /// before: that one was abandoned (it lost this Mac for a moment, or gave
    /// up), and waiting for its stall timer would refuse the new one as busy.
    private func busySending(to peer: UUID, file: Bool) -> Bool {
        for (id, out) in outgoing where out.peer == peer && out.file == file { stopSending(id, .cancelled, tell: false) }
        return outgoing.count >= 3
    }

    /// Only this Mac's own newest copy is ever sent, and only when it can be:
    /// never one that came from another Mac.
    private func serve(_ transfer: UUID, copy copyID: UUID, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&fetchTimes, peer, limit: 60, per: 60) else { refuse(transfer, .init(.rateLimited), to: peer); return }
        guard permitted() else { refuse(transfer, .init(.sharingOff), to: peer); return }
        guard outgoing[transfer] == nil, !busySending(to: peer, file: false) else { refuse(transfer, .init(.busy), to: peer); return }
        guard let copy, copy.id == copyID, copy.verdict != .received, copy.at != nil, let format = formats[peer] else {
            refuse(transfer, .init(.unknownCopy), to: peer); return
        }
        outgoing[transfer] = Outgoing(peer: peer, key: SymmetricKey(data: key), format: format, file: false, lastAck: clock())
        let fileLimits = self.fileLimits
        pasteboard.read(expecting: copy.changeCount, limits: limits) { [weak self] result in
            guard let self, self.outgoing[transfer] != nil else { return }
            switch result {
            case .failure(let refusal):
                self.outgoing[transfer] = nil
                self.refuse(transfer, refusal, to: peer)
            case .success(.content(let content)): self.seal(content.encoded(), transfer: transfer, copy: copyID, to: peer)
            case .success(.files(let urls)):
                // Walked again now, so what is sent is what is there now.
                self.disk.async { [weak self] in
                    let result = DeskSourceTree.examine(urls, limits: fileLimits).map { ($0, $0.list.encoded()) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.outgoing[transfer] != nil else { return }
                        switch result {
                        case .failure(let refusal):
                            self.outgoing[transfer] = nil
                            self.refuse(transfer, refusal, to: peer)
                        case .success(let (tree, list)):
                            // Remember exactly what was examined and listed:
                            // only these files, unchanged, can be streamed.
                            self.served = (copyID, tree, list)
                            self.seal(list, transfer: transfer, copy: copyID, to: peer)
                        }
                    }
                }
            }
        }
    }

    private func seal(_ payload: Data, transfer: UUID, copy copyID: UUID, to peer: UUID) {
        guard let out = outgoing[transfer] else { return }
        work.async { [weak self] in
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

    /// The stream of a listed copy's files, read from disk as it goes.
    private func serveTree(_ transfer: UUID, copy copyID: UUID, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&treeFetchTimes, peer, limit: 30, per: 60) else { refuse(transfer, .init(.rateLimited), to: peer); return }
        guard permitted() else { refuse(transfer, .init(.sharingOff), to: peer); return }
        guard outgoing[transfer] == nil, !busySending(to: peer, file: true) else { refuse(transfer, .init(.busy), to: peer); return }
        guard let copy, copy.id == copyID, copy.verdict != .received, let served, served.copy == copyID, let format = formats[peer] else {
            refuse(transfer, .init(.unknownCopy), to: peer); return
        }
        let sealKey = SymmetricKey(data: key)
        let manifest = DeskClipboardWire.treeManifest(transfer: transfer, copy: copyID, total: served.tree.total, list: served.list, key: sealKey, format: format)
        outgoing[transfer] = Outgoing(peer: peer, key: sealKey, format: format, file: true, lastAck: clock(), manifest: manifest,
                                      reader: DeskTreeReader(served.tree, padded: manifest.paddedLength))
        send(.manifest(manifest), to: peer)
        pump(transfer)
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
            } else if let reader = out.reader {
                // One chunk read at a time, off the main thread, in order.
                out.reading = true
                let index = out.next, key = out.key
                disk.async { [weak self] in
                    let produced = reader.next()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, var current = self.outgoing[transfer], current.reading else { return }
                        current.reading = false
                        switch produced {
                        case .failure(let reason):
                            self.outgoing[transfer] = current
                            self.stopSending(transfer, reason, tell: true)
                        case .success(let next):
                            self.send(.chunk(transfer: transfer, index: index, data: next.data,
                                             mac: DeskClipboardWire.chunkMAC(format: current.format, transfer: transfer, index: index,
                                                                             count: manifest.chunkCount, data: next.data, key: key)), to: current.peer)
                            for done in next.digests {
                                self.send(.fileDigest(transfer: transfer, index: done.index, digest: done.digest,
                                                      mac: DeskClipboardWire.fileDigestMAC(format: current.format, transfer: transfer, index: done.index,
                                                                                           digest: done.digest, key: key)), to: current.peer)
                            }
                            current.next += 1
                            self.outgoing[transfer] = current
                            self.pump(transfer)
                        }
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

    /// Forget a transfer this Mac was sending, closing its files after any read
    /// still under way.
    @discardableResult private func finishSending(_ transfer: UUID) -> Outgoing? {
        guard let out = outgoing.removeValue(forKey: transfer) else { return nil }
        if let reader = out.reader { disk.async { reader.close() } }
        return out
    }

    private func stopSending(_ transfer: UUID, _ reason: DeskClipboardReason, tell: Bool) {
        guard let out = finishSending(transfer) else { return }
        if tell { send(.cancel(transfer: transfer, reason: reason), to: out.peer) }
        decide(.stoppedSending(to: link.name(of: out.peer), transfer: transfer, reason))
    }
}
