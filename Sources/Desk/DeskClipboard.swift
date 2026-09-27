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
    func read(expecting changeCount: Int, limits: DeskClipboardLimits, _ done: @escaping (Result<DeskClipboardContent, DeskClipboardReason>) -> Void) {
        run({ store in
            guard store.changeCount == changeCount else { return .failure(.changed) }
            switch DeskClipboardPolicy.assess(store.itemTypes(), limits: limits) {
            case .withheld(let reason): return .failure(reason)
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
                // The copy must not have changed while it was being read.
                guard store.changeCount == changeCount else { return .failure(.changed) }
                guard !items.isEmpty else { return .failure(.unsupported) }
                return .success(DeskClipboardContent(items: items))
            }
        }, late: .failure(.readTimedOut), done)
    }

    /// Put a copy on the pasteboard only if nothing was copied here since the
    /// fetch began: something newer made on this Mac always wins.
    func write(_ content: DeskClipboardContent, ifUnchanged expected: Int, _ done: @escaping (Result<Int, DeskClipboardReason>) -> Void) {
        run({ store in
            guard store.changeCount == expected else { return .failure(.newerHere) }
            return .success(store.replace(with: content.items.map { item in item.map { (type: $0.type.identifier, data: $0.data) } }))
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
/// input event tap both run on the main run loop. A pasteboard promise (a data
/// provider) is answered synchronously on the main thread while the pasting app
/// waits; one that waited there for network data arriving on that same main
/// thread would deadlock, and would freeze the shared pointer for everyone while
/// it did. So Stage 1 never promises anything. The copy is fetched when the
/// keyboard arrives (a click moves the keyboard, so this is still on demand,
/// never on every copy) and written as ordinary data once it is complete and
/// verified. A paste only ever reads data already on this Mac: before the fetch
/// finishes it pastes what was there before, and a slow or dead peer costs a
/// timeout here, never a hang there. Pasteboard reads and writes happen off the
/// main thread with deadlines (`DeskPasteboardAccess`); so do compression, the
/// content digest and decoding. Only small bounded steps run on main.
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
        /// A whole transfer.
        var total = 120.0
        /// Serving side: between acknowledgements.
        var serveStall = 10.0
        /// How often a Mac that has not answered is greeted again.
        var hello = 30.0
        var tick = 0.5
    }
    /// Chunks in flight beyond the last acknowledgement.
    static let window: UInt32 = 8
    /// One chunk as the link carries it: the 64 KB envelope, base64 inside the
    /// desk message, plus framing. Rounded up.
    static let chunkWireBytes = 90 * 1024
    /// Stay far below the send queue size at which the desk closes a link.
    static let paceLimit = 1024 * 1024

    let link: DeskClipboardLink
    let pasteboard: DeskPasteboardAccess
    var limits = DeskClipboardLimits()
    var timings = Timings()
    /// Whether this Mac takes part now: keyboard and mouse sharing is on here,
    /// and ready (not locked, access granted).
    var permitted: () -> Bool = { false }
    /// Which Mac typing goes to while sharing is active; nil when it is not.
    var keyboardComputer: () -> UUID? = { nil }
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var after: (Double, @escaping () -> Void) -> Void = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    /// Heavy, pure work: sealing, digests, decompression, decoding.
    var work = DispatchQueue(label: "Perch.desk.clipboard", qos: .userInitiated)
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

    private struct Outgoing {
        let peer: UUID, key: SymmetricKey
        var lastAck: Double
        var parcel: DeskClipboardWire.Parcel?
        var next: UInt32 = 0
        var acked: UInt32 = 0
        var paced = false
    }
    private var outgoing: [UUID: Outgoing] = [:]

    private var askTimes: [UUID: [Double]] = [:]
    private var fetchTimes: [UUID: [Double]] = [:]
    private var inbound: [UUID: (start: Double, count: Int)] = [:]
    private var timer: Timer?

    init(link: DeskClipboardLink, pasteboard: DeskPasteboardAccess) {
        self.link = link; self.pasteboard = pasteboard
    }
    deinit { timer?.invalidate() }

    /// Whether a transfer is under way in either direction, for tests and status.
    var busy: Bool { incoming != nil || !outgoing.isEmpty || query != nil }
    /// How much of the copy on its way here has arrived, 0 to 1, while one is.
    var progress: Double? { incoming.map { $0.assembly?.fraction ?? 0 } }

    func start() {
        guard timer == nil else { return }
        pasteboard.poll { [weak self] count in if let count { self?.observe(count) } }
        timer = MainTimer.every(timings.tick) { [weak self] in self?.tick() }
        announce()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if incoming != nil { fail(.cancelled) }
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
        case .manifest(let manifest): manifestArrived(manifest, from: peer)
        case .chunk(let transfer, let index, let data, let mac): chunkArrived(transfer, index: index, data: data, mac: mac, from: peer)
        case .ack(let transfer, let next): acknowledged(transfer, next: next, by: peer)
        case .refuse(let transfer, let reason):
            guard let incoming, incoming.id == transfer, incoming.peer == peer else { return }
            self.incoming = nil
            decide(.refusedBy(link.name(of: peer), transfer: transfer, reason))
        case .cancel(let transfer, let reason):
            if let out = outgoing[transfer], out.peer == peer { stopSending(transfer, reason, tell: false) }
            else if let incoming, incoming.id == transfer, incoming.peer == peer {
                self.incoming = nil
                decide(.refusedBy(link.name(of: peer), transfer: transfer, reason))
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
        // Something was copied here while a fetch was on its way: this Mac's
        // own newer copy wins, and the fetch is dropped at once.
        if !first, incoming != nil { fail(.newerHere) }
    }

    func tick() {
        announce()
        guard permitted() else {
            if incoming != nil { fail(.sharingOffHere) }
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
        guard query == nil, incoming == nil else { return }
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

    // MARK: Fetching

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
        do { try assembly.accept(transfer: transfer, index: index, data: data, mac: mac) }
        catch let failure as DeskClipboardAssembly.Failure { fail(.corrupt, detail: failure.detail); return }
        catch { fail(.corrupt, detail: "unreadable chunk"); return }
        self.incoming?.lastProgress = clock()
        send(.ack(transfer: transfer, next: assembly.next), to: peer)
        guard assembly.complete else { return }
        self.incoming?.finishing = true
        let limits = self.limits
        work.async { [weak self] in
            let result: Result<DeskClipboardContent, DeskClipboardAssembly.Failure>
            do { result = .success(try DeskClipboardContent.decode(try assembly.finish(), limits: limits)) }
            catch let failure as DeskClipboardAssembly.Failure { result = .failure(failure) }
            catch { result = .failure(.content("does not follow the format")) }
            DispatchQueue.main.async { [weak self] in self?.finished(transfer, result) }
        }
    }

    private func finished(_ id: UUID, _ result: Result<DeskClipboardContent, DeskClipboardAssembly.Failure>) {
        guard let incoming, incoming.id == id else { return }
        switch result {
        case .failure(let failure): fail(.corrupt, detail: failure.detail)
        case .success(let content):
            pasteboard.write(content, ifUnchanged: incoming.expected) { [weak self] outcome in
                guard let self, self.incoming?.id == id else { return }
                self.incoming = nil
                switch outcome {
                case .success(let count):
                    self.copy = Copy(id: incoming.copy, changeCount: count, at: incoming.copyAt)
                    self.decide(.received(from: self.link.name(of: incoming.peer), transfer: id, size: DeskClipboardPolicy.sizeBucket(content.byteCount)))
                case .failure(let reason): self.decide(.discarded(transfer: id, reason))
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
                case .share:
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

    private func serve(_ transfer: UUID, copy copyID: UUID, key: Data, to peer: UUID) {
        guard key.count == 32 else { return }
        guard allow(&fetchTimes, peer, limit: 12, per: 60) else { refuse(transfer, .rateLimited, to: peer); return }
        guard permitted() else { refuse(transfer, .sharingOff, to: peer); return }
        guard outgoing[transfer] == nil, !outgoing.values.contains(where: { $0.peer == peer }), outgoing.count < 2 else { refuse(transfer, .busy, to: peer); return }
        guard let copy, copy.id == copyID, copy.at != nil else { refuse(transfer, .unknownCopy, to: peer); return }
        outgoing[transfer] = Outgoing(peer: peer, key: SymmetricKey(data: key), lastAck: clock())
        pasteboard.read(expecting: copy.changeCount, limits: limits) { [weak self] result in
            guard let self, let out = self.outgoing[transfer] else { return }
            switch result {
            case .failure(let reason):
                self.outgoing[transfer] = nil
                self.refuse(transfer, reason, to: peer)
            case .success(let content):
                guard let format = self.formats[peer] else { self.stopSending(transfer, .notSupported, tell: false); return }
                self.work.async { [weak self] in
                    let parcel = DeskClipboardWire.seal(content.encoded(), transfer: transfer, copy: copyID, key: out.key, format: format)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.outgoing[transfer] != nil else { return }
                        self.outgoing[transfer]?.parcel = parcel
                        self.outgoing[transfer]?.lastAck = self.clock()
                        self.send(.manifest(parcel.manifest), to: peer)
                        self.pump(transfer)
                    }
                }
            }
        }
    }

    /// Send chunks while the receiver's window and the link's queue allow.
    /// The queue check is this side's own guarantee: whatever the other Mac
    /// acknowledges, the desk link is never pushed toward the size at which it
    /// would be closed, and pointer traffic keeps flowing beside the copy.
    private func pump(_ transfer: UUID) {
        guard var out = outgoing[transfer], let parcel = out.parcel else { return }
        while out.next < parcel.manifest.chunkCount && out.next < out.acked + Self.window {
            guard let queued = link.queuedBytes(to: out.peer) else { outgoing[transfer] = out; stopSending(transfer, .peerGone, tell: false); return }
            guard queued + Self.chunkWireBytes <= Self.paceLimit else {
                if !out.paced {
                    out.paced = true
                    after(0.01) { [weak self] in self?.outgoing[transfer]?.paced = false; self?.pump(transfer) }
                }
                break
            }
            send(parcel.chunk(out.next, key: out.key), to: out.peer)
            out.next += 1
        }
        outgoing[transfer] = out
    }

    private func acknowledged(_ transfer: UUID, next: UInt32, by peer: UUID) {
        guard var out = outgoing[transfer], out.peer == peer, let parcel = out.parcel else { return }
        guard next <= out.next else { stopSending(transfer, .corrupt, tell: true); return }
        out.acked = max(out.acked, next); out.lastAck = clock()
        outgoing[transfer] = out
        if out.acked == parcel.manifest.chunkCount {
            outgoing[transfer] = nil
            decide(.sent(to: link.name(of: peer), transfer: transfer, size: DeskClipboardPolicy.sizeBucket(Int(parcel.manifest.payloadLength))))
            return
        }
        pump(transfer)
    }

    private func stopSending(_ transfer: UUID, _ reason: DeskClipboardReason, tell: Bool) {
        guard let out = outgoing.removeValue(forKey: transfer) else { return }
        if tell { send(.cancel(transfer: transfer, reason: reason), to: out.peer) }
        decide(.stoppedSending(to: link.name(of: out.peer), transfer: transfer, reason))
    }
}
