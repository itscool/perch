import Foundation
import Combine
import Network
import CryptoKit

/// Wire compatibility of the desk channel. Bump it whenever a message or a
/// signed payload changes so that an older build could not decode it or would
/// apply different validation to it. A hello without the field is version 1.
enum KVMDeskProtocol {
    static let version = 2
}
struct KVMHello: Codable {
    let card: KVMPeerCard
    let nonce: UUID
    let signature: Data
    let hosting: Bool
    let protocolVersion: Int
    static let domain = Data("Perch Desk hello v1\0".utf8)
    init(card: KVMPeerCard, nonce: UUID, signature: Data, hosting: Bool, protocolVersion: Int = KVMDeskProtocol.version) {
        self.card = card; self.nonce = nonce; self.signature = signature; self.hosting = hosting; self.protocolVersion = protocolVersion
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        card = try values.decode(KVMPeerCard.self, forKey: .card)
        nonce = try values.decode(UUID.self, forKey: .nonce)
        signature = try values.decode(Data.self, forKey: .signature)
        hosting = try values.decode(Bool.self, forKey: .hosting)
        protocolVersion = try values.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
    }
    static func bytes(_ card: KVMPeerCard, _ nonce: UUID, _ hosting: Bool) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return domain + (try encoder.encode(card)) + Data((nonce.uuidString + (hosting ? "host" : "join")).utf8)
    }
    func validate(certificate: Data?) throws {
        try card.validate()
        guard certificate == card.certificate,
              try Curve25519.Signing.PublicKey(rawRepresentation: card.signingKey).isValidSignature(signature, for: Self.bytes(card, nonce, hosting)) else { throw KVMError("The peer identity does not match its encrypted connection.") }
    }
}
enum KVMDeskMessage: Codable {
    case hello(KVMHello)
    case approve(String)
    case membership(KVMMembership)
    case revision(KVMSignedRevision)
    case receipt(String, UUID)
    case ping(UUID)
    case pong(UUID)
    case contact(UInt16)
    case contacts([UUID: String])
    case application(Data)
    /// The sender's current signed-history heads. The receiver answers with a
    /// receipt for each head it already holds and sends back only the revisions
    /// the sender lacks, instead of replaying the whole archive on every connect.
    case heads([String])
    /// Sent just before a deliberate close (reason, detail) so the other Mac
    /// records why instead of a generic "closed connection".
    case goodbye(String, String)
}

/// Portable runtime: durable signed edits, TLS peers and owner-signed membership.
/// The owner authorizes membership only; paired members synchronize directly.
final class KVMDeskNode: ObservableObject {
    struct Pairing: Identifiable {
        let id: UUID
        let card: KVMPeerCard
        let comparison: String
        var approvedHere = false
        var approvedThere = false
    }
    @Published private(set) var group: KVMGroup
    @Published private(set) var online: Set<UUID> = []
    @Published private(set) var nearby: [KVMPeerTransport.Nearby] = []
    @Published private(set) var completedPairing: UUID?
    @Published private(set) var pairings: [Pairing] = []
    @Published private(set) var conflicts: [KVMGroup] = []
    @Published private(set) var recoveredDraft: KVMGroup?
    @Published var problem: String?
    @Published private(set) var listenerProblem: String?
    @Published private(set) var discoveryProblem: String?
    @Published private(set) var pairingProblem: String?
    @Published private(set) var peerProblems: [UUID: String] = [:]
    @Published private(set) var pairingConnection: UUID?
    @Published private(set) var connectionEvents: [KVMConnectionEvent] = []
    @Published private(set) var connectionLogProblem: String?
    /// Desk protocol version each member last announced.
    @Published private(set) var peerVersions: [UUID: Int] = [:]
    private var connectionLogURL: URL { storage.deletingPathExtension().appendingPathExtension("connections.json") }
    private let connectionLogQueue = DispatchQueue(label: "Perch.desk.connection-log", qos: .utility)
    private func recordConnection(_ event: KVMConnectionEvent) {
        connectionEvents = KVMConnectionEvent.retained(connectionEvents + [event])
        let events = connectionEvents, url = connectionLogURL
        // Serial snapshots preserve event order without disk I/O on the network/UI executor.
        connectionLogQueue.async { [weak self] in
            let problem: String?
            do { try SecureFile.writeAtomically(events, to: url, protection: true); problem = nil }
            catch { problem = "Connection activity could not be saved. " + error.localizedDescription }
            DispatchQueue.main.async { [weak self] in self?.connectionLogProblem = problem }
        }
    }
    /// Write the activity log before the process exits; the asynchronous
    /// writer would otherwise lose the final "Perch stopped" entries.
    private func flushConnectionLog() {
        let events = connectionEvents, url = connectionLogURL
        connectionLogQueue.sync { try? SecureFile.writeAtomically(events, to: url, protection: true) }
    }
    var networkProblem: String? {
        listenerProblem ?? membership.peers.filter { !online.contains($0.id) }.compactMap { peer in
            peerProblems[peer.id].map { "\(peer.name): \($0)" }
        }.first
    }
    var displayProblem: String? { problem ?? networkProblem }
    var inviting: Bool { hostingPairing }
    var localName: String { group.computers.first { $0.id == localID }?.name ?? "This Mac" }
    func canSelect(_ nearby: KVMPeerTransport.Nearby) -> Bool {
        guard pairingOpen, pairingConnection == nil, pairings.isEmpty else { return false }
        // Discovery is an advisory hint only. Signed hellos and both approvals establish trust.
        guard let role = nearby.pairingRole else { return true }
        return role == (hostingPairing ? "join" : "invite")
    }
    @Published private(set) var pendingPeers: Set<UUID> = []
    @Published private(set) var pairingUntil: Date?
    let identity: KVMPeerIdentity
    let transport: KVMPeerTransport
    let storage: URL
    private(set) var archive: KVMDeskArchive
    private(set) var membership: KVMMembershipPayload
    private(set) var graph: KVMSyncGraph
    var application: ((UUID, Data) -> Void)?
    var peersChanged: (() -> Void)?
    private var hellos: [UUID: KVMHello] = [:]
    private var localNonces: [UUID: UUID] = [:]
    private var peerLinks: [UUID: UUID] = [:]
    private var expectedPeers: [UUID: UUID] = [:]
    /// A peer may have one pending route attempt. The old implementation used
    /// this timestamp as a retry cooldown, which allowed a still-live attempt
    /// to be duplicated after 12 seconds.
    private var connecting: [UUID: Date] = [:]
    private var reconnectAfter: [UUID: Date] = [:]
    private var failedAttempts: [UUID: Int] = [:]
    private var lastHeard: [UUID: Date] = [:]
    /// Liveness per link, not per peer: a message on a fresh route must not
    /// keep a dead route alive.
    private var lastHeardLink: [UUID: Date] = [:]
    /// When the route to a peer was lost. Only the member with the smaller ID
    /// dials immediately; the other waits so both Macs do not open at once.
    private var routeLostAt: [UUID: Date] = [:]
    private var lastDialUsedDiscovery: [UUID: Bool] = [:]
    /// Peers a wired dial has already been started for, and the cable it was
    /// started over. Together they are `KVMPeerPath`'s "one move per cable
    /// event": the record is forgotten only when that cable goes away or a
    /// different one replaces it, never merely because discovery reported the
    /// same peer again.
    private var triedWire: Set<UUID> = []
    private var peerWire: [UUID: String] = [:]
    private var hostingPairing = false
    private var directContacts: [UUID: String] = [:]
    private var lastEdit = Date()
    var canCheckpoint: () -> Bool = { true }
    /// Test hook: the version this node announces in its hello.
    var announcedProtocolVersion = KVMDeskProtocol.version
    private var timer: Timer?
    private var syncing: Set<UUID> = []
    private var syncAgain: Set<UUID> = []
    private var historyQueues: [UUID: [KVMSignedRevision]] = [:]
    private var historyOffsets: [UUID: Int] = [:]
    var localID: UUID { identity.saved.id }
    var ownerID: UUID { membership.authority }
    var isMember: Bool { membership.peers.contains { $0.id == localID } }
    var isOwner: Bool { localID == ownerID }
    var ownerName: String { group.computers.first { $0.id == ownerID }?.name ?? "Desk owner" }
    var revision: String? { graph.heads.count == 1 ? graph.heads.first : nil }
    var canEdit: Bool { membership.peers.contains { $0.id == localID } && conflicts.isEmpty && recoveredDraft == nil }
    var pairingOpen: Bool { (pairingUntil ?? .distantPast) > Date() }
    var hasOtherMembers: Bool { membership.peers.count > 1 }
    init(identity: KVMPeerIdentity, name: String, storage: URL) throws {
        self.identity = identity; self.storage = storage; transport = KVMPeerTransport(identity: identity)
        let activity = storage.deletingPathExtension().appendingPathExtension("connections.json")
        if let size = try? activity.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
           let data = try? Data(contentsOf: activity), let saved = try? JSONDecoder().decode([KVMConnectionEvent].self, from: data),
           saved.count <= 1024, saved.allSatisfy({ $0.peerName.utf8.count <= 400 && $0.detail.utf8.count <= 1000 }) {
            connectionEvents = KVMConnectionEvent.retained(saved)
        }
        if FileManager.default.fileExists(atPath: storage.path) {
            archive = try KVMDeskArchive.read(storage)
        } else {
            let card = identity.card(name: name)
            let group = KVMGroup(name: "My desk", computers: [.init(id: card.id, name: name)])
            let signed = try KVMMembership.sign(group: group, peers: [card], authority: card.id, key: identity.signing, generation: 1, previousHeads: [])
            archive = KVMDeskArchive(authorityKey: card.signingKey, membership: signed, history: [])
            try archive.write(storage)
        }
        (membership, graph) = try archive.verified()
        guard membership.peers.first(where: { $0.id == identity.saved.id }).map({ $0.signingKey == identity.signing.publicKey.rawRepresentation && $0.certificate == identity.saved.certificate }) ?? true else { throw KVMError("This Mac’s identity does not match the saved desk. Its original setup is preserved.") }
        group = try graph.current ?? membership.graph().current!
        recoveredDraft = archive.recoveredDraft
        online = [identity.saved.id]
        refreshPresentation()
        transport.permitted = { [weak self] certificate in
            guard let self else { return false }
            return self.membership.peers.contains { $0.certificate == certificate && $0.id != self.localID } || self.pairingOpen && self.pairings.count < 1
        }
        transport.connected = { [weak self] link in self?.linkReady(link) }
        transport.received = { [weak self] link, bytes in self?.receive(bytes, link: link) }
        transport.disconnected = { [weak self] link in self?.linkLost(link) }
        transport.goodbye = { reason in
            try? JSONEncoder().encode(KVMDeskMessage.goodbye(reason.rawValue, reason == .incompatible ? "\(KVMDeskProtocol.version)" : ""))
        }
        transport.discovered = { [weak self] nearby in self?.nearby = nearby; self?.wireUpdate(); self?.reconnect() }
        transport.listenerProblem = { [weak self] in self?.listenerProblem = $0 }
        transport.discoveryProblem = { [weak self] in self?.discoveryProblem = $0 }
        transport.connectionProblem = { [weak self] link, message in self?.connectionStatus(link, message: message) }
        transport.pathChanged = { [weak self] available in
            guard available else { return }
            // A newly usable path is a trigger to retry missing peers, not a
            // reason to tear down an authenticated route.
            self?.reconnect()
        }
    }
    func start(localOnly: Bool = false, port: NWEndpoint.Port = .init(rawValue: 53031)!) throws {
        guard isMember else { problem = "This Mac was removed from the desk. Start a new desk to join again."; return }
        try transport.start(name: group.computers.first { $0.id == localID }?.name ?? "Perch", localOnly: localOnly, port: port)
        for peer in membership.peers where peer.id != localID { routeLostAt[peer.id] = Date() }
        let timer = MainTimer.every(5) { [weak self] in self?.tick() }
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil; transport.stop(); flushConnectionLog() }
    func archiveRemovedDesk() throws {
        guard !isMember else { throw KVMError("This Mac still belongs to the desk.") }
        let saved = try KVMDeskArchive.read(storage)
        guard try !saved.verified().0.peers.contains(where: { $0.id == localID }) else { throw KVMError("Desk membership changed. Open Desk again.") }
        stop()
        try FileManager.default.moveItem(at: storage, to: storage.deletingLastPathComponent().appendingPathComponent("removed-desk-" + UUID().uuidString + ".json"))
    }
    func openPairing(hosting: Bool) {
        guard isMember else { problem = "Start a new desk before joining again."; return }
        guard isOwner || !hasOtherMembers else { problem = "Add computers from \(ownerName), which approves membership for this desk."; return }
        guard membership.peers.count < 16 else { problem = "This desk already has 16 computers. Remove one before adding another."; return }
        guard hosting || !hasOtherMembers else { problem = "This Mac already belongs to a desk."; return }
        hostingPairing = hosting
        completedPairing = nil; pairingProblem = nil
        pairingUntil = Date().addingTimeInterval(120); problem = nil
        transport.advertisePairing(hosting: hosting, desk: group.name)
    }
    func closePairing() {
        pairingUntil = nil
        transport.advertisePairing(hosting: nil, desk: group.name)
        let pending = pairingConnection; pairingConnection = nil; pairingProblem = nil
        if let pending, let link = transport.links[pending] { transport.close(link, reason: .pairingClosed) }
        for pairing in pairings { if let link = transport.links[pairing.id] { transport.close(link, reason: .pairingClosed) } }
        pairings = []
    }
    func connect(_ endpoint: NWEndpoint, expected: UUID? = nil, wire: NWInterface? = nil) {
        if expected == nil {
            guard pairingOpen, pairingConnection == nil, pairings.isEmpty else { return }
            pairingProblem = nil
        } else if let expected {
            // Never create a second route while the first one is still
            // negotiating. A successful peer link also suppresses attempts.
            // An explicit endpoint request may probe a redundant route, but
            // automatic reconnect never calls this while an authenticated
            // route exists. The in-flight guard still prevents duplicate
            // automatic attempts.
            guard connecting[expected] == nil else { return }
            connecting[expected] = Date()
        }
        // Members dial over infrastructure; peer-to-peer stays available for
        // pairing and as a fallback when ordinary attempts keep failing.
        let peerToPeer = expected == nil || pairingOpen || (expected.flatMap { failedAttempts[$0] } ?? 0) >= 3
        let link = transport.connect(endpoint, peerToPeer: peerToPeer, wire: wire)
        guard transport.links[link.id] != nil else {
            // Refused at the link cap: nothing will report this attempt as lost.
            if let expected { connecting[expected] = nil }
            return
        }
        if let expected { expectedPeers[link.id] = expected }
        else { pairingConnection = link.id }
    }
    func connect(address: String) throws {
        guard pairingOpen else { throw KVMError("Choose Add computer on both Macs first.") }
        guard let endpoint = Self.endpoint(address) else { throw KVMError("Enter the other Mac’s address and Desk port, such as mac.local:53031 or [IPv6 address]:53031.") }
        guard pairingConnection == nil, pairings.isEmpty else { return }
        connect(endpoint)
        if let id = pairingConnection { directContacts[id] = address }
    }
    static func endpoint(_ address: String) -> NWEndpoint? {
        guard address.utf8.count <= 300, let url = URLComponents(string: "perch://" + address), url.user == nil, url.password == nil, url.path.isEmpty, url.query == nil, url.fragment == nil,
              let host = url.host, !host.isEmpty, let port = url.port, (1...65535).contains(port) else { return nil }
        let trimmed = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        return .hostPort(host: .init(trimmed), port: .init(rawValue: UInt16(port))!)
    }

    func approve(_ id: UUID) {
        guard pairingOpen, let i = pairings.firstIndex(where: { $0.id == id }), let link = transport.links[id] else { return }
        pairings[i].approvedHere = true
        send(.approve(pairings[i].comparison), to: link)
        finishPairing(id)
    }
    func reject(_ id: UUID) { if let link = transport.links[id] { transport.close(link, reason: .pairingClosed) } }
    private func linkReady(_ link: KVMPeerTransport.Link) {
        do {
            let nonce = UUID(); localNonces[link.id] = nonce
            let card = identity.card(name: group.computers.first { $0.id == localID }?.name ?? "This Mac")
            let hello = KVMHello(card: card, nonce: nonce, signature: try identity.signing.signature(for: KVMHello.bytes(card, nonce, hostingPairing)), hosting: hostingPairing, protocolVersion: announcedProtocolVersion)
            send(.hello(hello), to: link)
            // Pairing approval may remain open for its two-minute window, but
            // the application hello itself must arrive promptly. The previous
            // 125-second timer kept a TLS-ready, otherwise unusable route
            // around long enough to block reconnects and produced the
            // recurring ~116-second disconnects seen in the activity log.
            // Once a hello has arrived, either trust() or the pairing state
            // owns the connection lifetime; closePairing handles the latter.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak link] in
                guard let self, let link,
                      self.transport.links[link.id] != nil,
                      self.hellos[link.id] == nil,
                      self.peerLinks.values.contains(link.id) == false else { return }
                self.transport.close(link, reason: .timeout)
            }
        } catch { transport.close(link, reason: .protocolFailure) }
    }
    private func receive(_ bytes: Data, link: KVMPeerTransport.Link) {
        let trusted = peerLinks.values.contains(link.id)
        let message: KVMDeskMessage
        do {
            guard trusted || bytes.count <= 24 * 1024 || pairings.contains(where: { $0.id == link.id && $0.approvedHere && $0.approvedThere }) else { throw KVMError("Unpaired Desk message exceeded its limit.") }
            message = try JSONDecoder().decode(KVMDeskMessage.self, from: bytes)
        } catch { fail(link, error); return }
        if case .goodbye(let reason, let detail) = message {
            // The peer cancels next; its stated reason replaces our generic one.
            link.remoteReason = KVMCloseReason(rawValue: reason) ?? .remote
            link.remoteDetail = String(detail.prefix(200))
            if link.remoteReason == .incompatible, let peer = hellos[link.id]?.card.id ?? expectedPeers[link.id] {
                noteIncompatible(peer, remoteVersion: Int(detail), name: hellos[link.id]?.card.name)
            }
            if link.remoteReason == .protocolFailure, detail.contains("not been approved"),
               let peer = hellos[link.id]?.card.id ?? expectedPeers[link.id], let name = membership.peers.first(where: { $0.id == peer })?.name {
                // The other Mac reset its desk: it no longer knows this one.
                // Dialling it again will never help; only removing and
                // re-adding it can, and only the owner can do that.
                peerProblems[peer] = isOwner ? "\(name) no longer lists this Mac in its desk. Remove \(name) from this desk, then add it again."
                                             : "\(name) no longer lists this Mac in its desk. On \(name), remove this Mac from the desk and add it again."
                failedAttempts[peer] = 7; reconnectAfter[peer] = Date().addingTimeInterval(KVMReconnectPolicy.delay(failures: 7))
            }
            return
        }
        do {
            if case .hello(let hello) = message {
                guard hellos[link.id] == nil else { throw KVMError("Repeated peer introduction.") }
                try hello.validate(certificate: link.certificate)
                guard hello.card.id != localID, expectedPeers[link.id] == nil || expectedPeers[link.id] == hello.card.id else { throw KVMError("A different computer answered this connection.") }
                hellos[link.id] = hello
                guard hello.protocolVersion == KVMDeskProtocol.version else {
                    noteIncompatible(hello.card.id, remoteVersion: hello.protocolVersion, name: hello.card.name)
                    transport.close(link, reason: .incompatible); return
                }
                if membership.peers.contains(where: { $0.id == hello.card.id && $0.signingKey == hello.card.signingKey && $0.certificate == hello.card.certificate }) { trust(link) }
                else {
                    guard pairingOpen, pairings.isEmpty, let nonce = localNonces[link.id] else { throw KVMError("This computer has not been approved for the desk.") }
                    guard hello.hosting != hostingPairing else { throw KVMError("Both Macs chose the same action. Invite from the desk you want to keep, and choose Join another desk on the other Mac.") }
                    let pieces = [identity.saved.certificate.base64EncodedString() + nonce.uuidString, hello.card.certificate.base64EncodedString() + hello.nonce.uuidString].sorted()
                    let hash = SHA256.hash(data: Data(pieces.joined(separator: "|").utf8)).prefix(8).map { String(format: "%02X", $0) }
                    let comparison = stride(from: 0, to: 8, by: 2).map { hash[$0] + hash[$0+1] }.joined(separator: " ")
                    pairingProblem = nil
                    pairings.append(.init(id: link.id, card: hello.card, comparison: comparison))
                }
                return
            }
            guard let hello = hellos[link.id] else { throw KVMError("The peer must identify itself first.") }
            if case .approve(let comparison) = message {
                guard pairingOpen, let i = pairings.firstIndex(where: { $0.id == link.id }), pairings[i].comparison == comparison else { throw KVMError("The pairing comparison does not match.") }
                pairings[i].approvedThere = true; finishPairing(link.id); return
            }
            if case .membership(let signed) = message {
                if trusted { try acceptMembership(signed, key: archive.authorityKey) }
                else {
                    guard let pairing = pairings.first(where: { $0.id == link.id }), pairing.approvedHere, pairing.approvedThere, !hasOtherMembers else { throw KVMError("This desk has not been approved.") }
                    let value = try signed.verified(authorityKey: hello.card.signingKey)
                    guard value.authority == hello.card.id, value.peers.contains(identity.card(name: value.peers.first { $0.id == localID }?.name ?? "")) else { throw KVMError("The invitation does not include this Mac’s identity.") }
                    try installMembership(signed, value: value, key: hello.card.signingKey, joining: true)
                }
                if !trusted, membership.peers.contains(where: { $0.id == hello.card.id }) { trust(link) }
                return
            }
            guard trusted, membership.peers.contains(where: { $0.id == hello.card.id }) else { throw KVMError("This computer is not an authorized member.") }
            lastHeard[hello.card.id] = Date(); lastHeardLink[link.id] = Date()
            // A change this Mac cannot apply (a revision that fails validation
            // here, a full disk, an unknown receipt) is reported, not treated
            // as a broken connection: closing the link only replays the same
            // rejection after every reconnect.
            do { try handle(message, from: hello.card.id, link: link) }
            catch { problem = error.localizedDescription }
        } catch { fail(link, error) }
    }
    private func fail(_ link: KVMPeerTransport.Link, _ error: Error) {
        if peerLinks.values.contains(link.id) { problem = error.localizedDescription }
        else { connectionStatus(link, message: error.localizedDescription) }
        link.failureCode = String(error.localizedDescription.prefix(160))
        transport.close(link, reason: .protocolFailure)
    }
    private func handle(_ message: KVMDeskMessage, from peer: UUID, link: KVMPeerTransport.Link) throws {
        switch message {
        case .revision(let revision):
            if graph.revisions[revision.id] == nil {
                let payload = try JSONDecoder().decode(KVMRevisionPayload.self, from: revision.payload)
                guard payload.epoch == graph.roster.epoch else { return }
                var next = graph; try next.receive(revision); try save(next)
                announce(revision, except: link.id)
            }
            send(.receipt(revision.id, graph.roster.epoch), to: link)
        case .receipt(let id, let epoch):
            guard epoch == graph.roster.epoch, graph.revisions[id] != nil else { return }
            try graph.acknowledge(id, from: peer, epoch: epoch); refreshPresentation()
        case .heads(let theirs):
            guard theirs.count <= 16, theirs.allSatisfy({ $0.count == 64 }) else { return }
            for head in theirs where graph.revisions[head] != nil { send(.receipt(head, graph.roster.epoch), to: link) }
            queueHistory(try graph.missing(from: theirs), to: link)
        case .ping(let nonce): send(.pong(nonce), to: link)
        case .pong: break
        case .contact(let port):
            if port > 0, case .hostPort(let host, _) = link.connection.currentPath?.remoteEndpoint {
                let text = String(describing: host)
                // Link-local and interface-scoped addresses only work over the
                // interface that produced them (AWDL sessions change them
                // constantly), so they are useless as a saved fallback.
                if !text.lowercased().hasPrefix("fe80:"), !text.contains("%"), !text.lowercased().hasPrefix("169.254.") {
                    let address = (text.contains(":") ? "[" + text + "]" : text) + ":\(port)"
                    if Self.endpoint(address) != nil, archive.addresses[peer] != address { archive.addresses[peer] = address; try archive.write(storage) }
                }
            }
            send(.contacts(archive.addresses), to: link)
        case .contacts(let addresses):
            guard addresses.count <= 16, addresses.allSatisfy({ Self.endpoint($0.value) != nil }) else { return }
            var changed = false
            for (id, address) in addresses where membership.peers.contains(where: { $0.id == id }) && archive.addresses[id] == nil { archive.addresses[id] = address; changed = true }
            if changed { try archive.write(storage) }
            reconnect()
        case .application(let data): application?(peer, data)
        case .hello, .approve, .membership, .goodbye: break
        }
    }
    private func noteIncompatible(_ peer: UUID, remoteVersion: Int?, name: String?) {
        let peerName = name ?? membership.peers.first { $0.id == peer }?.name ?? "The other Mac"
        // Without a version from the peer, it refused us, so it is the newer one.
        let older = remoteVersion.map { $0 < KVMDeskProtocol.version } ?? false
        let text = older ? "\(peerName) runs an older Perch. Update Perch there to this Mac’s version."
                         : "\(peerName) runs a newer Perch. Update Perch on this Mac."
        if let version = remoteVersion { peerVersions[peer] = version }
        if membership.peers.contains(where: { $0.id == peer }) {
            peerProblems[peer] = text
            failedAttempts[peer] = 7; reconnectAfter[peer] = Date().addingTimeInterval(KVMReconnectPolicy.delay(failures: 7))
        } else { pairingProblem = text }
    }
    private func finishPairing(_ id: UUID) {
        guard let pairing = pairings.first(where: { $0.id == id }), pairing.approvedHere, pairing.approvedThere, let link = transport.links[id] else { return }
        // Only the explicitly inviting owner grants membership, after both approvals.
        guard isOwner, hostingPairing else { return }
        do {
            guard canEdit, membership.peers.count < 16 else { throw KVMError("Resolve desk changes or free a member slot before adding a computer.") }
            var group = self.group
            // A Mac that reset its desk and is being added again keeps its
            // identity; replace its old card instead of failing on the duplicate.
            group.computers.removeAll { $0.id == pairing.card.id }
            group.computers.append(.init(id: pairing.card.id, name: pairing.card.name))
            let signed = try KVMMembership.sign(group: group, peers: membership.peers.filter { $0.id != pairing.card.id } + [pairing.card], authority: localID, key: identity.signing,
                                                generation: membership.generation + 1, previousHeads: graph.heads.sorted())
            let value = try signed.verified(authorityKey: archive.authorityKey)
            try installMembership(signed, value: value, key: archive.authorityKey)
            send(.membership(signed), to: link); trust(link)
        } catch { problem = error.localizedDescription }
    }
    private func trust(_ link: KVMPeerTransport.Link) {
        guard let hello = hellos[link.id] else { return }
        let peer = hello.card.id
        if let oldID = peerLinks[peer], oldID != link.id, let old = transport.links[oldID] {
            // Two routes exist. When both became ready at almost the same time
            // the Macs dialled each other simultaneously, and a symmetric
            // tie-break picks the same survivor on both sides. Otherwise the
            // peer dialled again because its side of the old route is gone,
            // so the new route wins regardless of nonce order. A route over the
            // cable between the two Macs outranks a wireless one in that
            // tie-break; see `KVMPeerPath.keepsArrivingRoute`.
            let simultaneous = abs((old.readyAt ?? old.created) - (link.readyAt ?? link.created)) < 2
            func order(_ id: UUID) -> String { [localNonces[id]?.uuidString ?? "", hellos[id]?.nonce.uuidString ?? ""].sorted().joined() }
            guard KVMPeerPath.keepsArrivingRoute(arrivingIsWired: link.wired, workingIsWired: old.wired,
                                                 simultaneous: simultaneous,
                                                 arrivingWinsTieBreak: order(oldID) >= order(link.id)) else {
                transport.close(link, reason: .duplicate); return
            }
            peerLinks[peer] = link.id
            transport.close(old, reason: .duplicate)
        }
        if peerLinks[peer] != link.id {
            recordConnection(.init(id: UUID(), time: Date(), peer: peer, peerName: String(hello.card.name.prefix(100)), detail: "Authenticated connection ready", unexpected: false, duration: nil))
        }
        peerLinks[peer] = link.id
        if expectedPeers[link.id] == peer { connecting[peer] = nil }
        // Any other attempt still dialling this peer is redundant now.
        for (id, expected) in expectedPeers where expected == peer && id != link.id {
            if let other = transport.links[id], !other.ready { transport.close(other, reason: .local) }
        }
        reconnectAfter[peer] = nil; routeLostAt[peer] = nil
        peerVersions[peer] = hello.protocolVersion
        if pairings.contains(where: { $0.id == link.id }) {
            // Clear operation state before publishing completion: the sheet may close synchronously.
            pairings.removeAll { $0.id == link.id }; pairingConnection = nil; pairingProblem = nil
            pairingUntil = nil; transport.advertisePairing(hosting: nil, desk: group.name)
            completedPairing = peer
        }
        peerProblems[peer] = nil
        pairings.removeAll { $0.id == link.id }; lastHeard[peer] = Date(); lastHeardLink[link.id] = Date()
        online.insert(peer)
        if let address = directContacts.removeValue(forKey: link.id) { archive.addresses[peer] = address; do { try archive.write(storage) } catch { problem = error.localizedDescription } }
        refreshPresentation(); peersChanged?(); sync(link)
        if let port = transport.listener?.port?.rawValue, port > 0 { send(.contact(port), to: link) }
        // The other moment a cable event can be acted on: a route has just come
        // up, and it may be the wireless one. The cable is often discovered
        // before this Mac has anything to move onto it — the other Mac waking
        // is both a new record in discovery and, a moment later, a connection.
        // `wireUpdate` is idempotent, so arriving here changes nothing once the
        // desk is already on the cable or has already spent its one attempt.
        wireUpdate()
    }
    private func connectionStatus(_ link: KVMPeerTransport.Link, message: String?) {
        if let peer = expectedPeers[link.id] ?? hellos[link.id]?.card.id,
           membership.peers.contains(where: { $0.id == peer }) {
            // A failed redundant route must not overwrite the working authenticated route.
            if online.contains(peer), peerLinks[peer] != link.id { return }
            peerProblems[peer] = message
        } else if pairingOpen, pairingConnection == link.id || pairings.contains(where: { $0.id == link.id }) {
            pairingProblem = message
        }
    }
    private func linkLost(_ link: KVMPeerTransport.Link) {
        let peer = expectedPeers[link.id] ?? hellos[link.id]?.card.id
        let name = peer.flatMap { id in membership.peers.first { $0.id == id }?.name } ?? "Unpaired computer"
        let isWorkingRoute = peer.map { peerLinks[$0] == link.id } ?? false
        var detail = link.closeReason.rawValue
        if link.closeReason == .remote, let remote = link.remoteReason {
            detail += " · " + remote.rawValue + ((link.remoteDetail?.isEmpty == false) ? " · " + link.remoteDetail! : "")
        } else if let code = link.failureCode { detail += " · " + String(code.prefix(160)) }
        let announcedExpected = link.remoteReason.map { !$0.unexpected } ?? false
        recordConnection(.init(id: UUID(), time: Date(), peer: peer, peerName: String(name.prefix(100)), detail: detail,
                               unexpected: link.closeReason.unexpected && !announcedExpected && (isWorkingRoute || link.readyAt == nil),
                               duration: max(0, ProcessInfo.processInfo.systemUptime - (link.readyAt ?? link.created))))
        if pairingOpen, pairingConnection == link.id || pairings.contains(where: { $0.id == link.id }) {
            if pairingProblem == nil { pairingProblem = "The other Mac disconnected before setup finished. Select it again to retry." }
        }
        if pairingConnection == link.id { pairingConnection = nil }
        directContacts[link.id] = nil
        if let peer = hellos[link.id]?.card.id, peerLinks[peer] == link.id {
            // Keep the offline peer visible until the authenticated route is
            // restored. Connection activity is useful diagnostics, but it is
            // not itself a live status indicator; without this entry the Desk
            // UI silently dropped an unexpected disconnect while reconnect
            // backoff was in progress.
            if link.remoteReason == .incompatible || link.closeReason == .incompatible ||
               (link.remoteReason == .protocolFailure && link.remoteDetail?.contains("not been approved") == true) {
                // The goodbye handler already named the problem and the fix.
            } else if link.closeReason.unexpected && !announcedExpected {
                peerProblems[peer] = "Connection lost (\(link.remoteReason?.rawValue ?? link.closeReason.rawValue)). Reconnecting automatically."
            } else { peerProblems[peer] = nil }
            peerLinks[peer] = nil; online.remove(peer); lastHeard[peer] = nil; peersChanged?()
        }
        // This attempt is over whether or not another route exists; a stale
        // marker would block every later automatic dial to the peer.
        if let peer, expectedPeers[link.id] == peer { connecting[peer] = nil }
        if let peer, peerLinks[peer] == nil {
            // A route that died within seconds of authenticating is a repeating
            // failure, not a one-off: keep backing off. Long-lived routes reset
            // the count once they have survived (see tick).
            let quickDeath = link.readyAt.map { ProcessInfo.processInfo.systemUptime - $0 < 5 } ?? true
            let failures = quickDeath ? min((failedAttempts[peer] ?? 0) + 1, 7) : 1
            failedAttempts[peer] = failures
            if link.closeReason != .incompatible, link.remoteReason != .incompatible {
                reconnectAfter[peer] = Date().addingTimeInterval(KVMReconnectPolicy.delay(failures: failures))
            }
            routeLostAt[peer] = Date()
        }
        pairings.removeAll { $0.id == link.id }; hellos[link.id] = nil; localNonces[link.id] = nil; expectedPeers[link.id] = nil
        lastHeardLink[link.id] = nil
        syncing.remove(link.id); syncAgain.remove(link.id); historyQueues[link.id] = nil; historyOffsets[link.id] = nil
        refreshPresentation()
    }
    private func acceptMembership(_ signed: KVMMembership, key: Data) throws {
        if signed == archive.membership { return }
        let value = try signed.verified(authorityKey: key)
        let root = try value.graph()
        guard root.roster.group == graph.roster.group, value.authority == membership.authority else { throw KVMError("The peer sent a different desk.") }
        guard value.generation > membership.generation else { return }
        try installMembership(signed, value: value, key: key)
    }
    private func installMembership(_ signed: KVMMembership, value: KVMMembershipPayload, key: Data, joining: Bool = false) throws {
        let nextGraph = try value.graph()
        let changedLocally = !joining && Set(value.previousHeads) != graph.heads
        let draft = recoveredDraft ?? (changedLocally || joining && !group.monitors.isEmpty ? group : nil)
        var next = KVMDeskArchive(authorityKey: key, membership: signed, history: try nextGraph.history(), recoveredDraft: draft)
        next.addresses = archive.addresses.filter { pair in value.peers.contains { $0.id == pair.key } }
        try next.write(storage)
        archive = next; membership = value; graph = nextGraph; recoveredDraft = draft
        if !value.peers.contains(where: { $0.id == localID }) { problem = "This Mac was removed from the desk. Its saved setup is preserved."; closePairing(); transport.stop() }
        for link in Array(transport.links.values) {
            if let peer = hellos[link.id]?.card, peerLinks[peer.id] != nil, !value.peers.contains(where: { $0.id == peer.id && $0.certificate == peer.certificate }) { transport.close(link, reason: .revoked) }
        }
        refreshPresentation(); broadcastSync(); peersChanged?()
    }
    func removePeer(_ peer: UUID) throws {
        guard isOwner, peer != localID, canEdit else { throw KVMError("Remove other members from \(ownerName). Resolve desk changes first.") }
        var group = self.group; try group.removeComputer(peer)
        let signed = try KVMMembership.sign(group: group, peers: membership.peers.filter { $0.id != peer }, authority: localID,
                                            key: identity.signing, generation: membership.generation + 1, previousHeads: graph.heads.sorted())
        if let link = peerLinks[peer].flatMap({ transport.links[$0] }) { send(.membership(signed), to: link) }
        try installMembership(signed, value: signed.verified(authorityKey: archive.authorityKey), key: archive.authorityKey)
    }
    func edit(_ next: KVMGroup) throws {
        guard canEdit else { throw KVMError("Review the competing or recovered changes before editing this desk.") }
        guard next != group else { return }
        var graph = self.graph; let revision = try graph.edit(next, author: localID, key: identity.signing)
        try save(graph); announce(revision)
    }
    func resolve(_ chosen: KVMGroup) throws {
        var next = chosen
        next.id = group.id; next.computers = group.computers
        for i in next.connections.indices where !next.computers.contains(where: { $0.id == next.connections[i].computer }) { next.connections[i].computer = nil; next.connections[i].localDisplay = nil }
        _ = try next.validated()
        var graph = self.graph; let revision = try graph.edit(next, author: localID, key: identity.signing, resolving: graph.heads)
        try save(graph, clearingDraft: true); announce(revision)
    }
    private func save(_ nextGraph: KVMSyncGraph, clearingDraft: Bool = false) throws {
        var next = archive; next.history = try nextGraph.history(); if clearingDraft { next.recoveredDraft = nil }
        try next.write(storage); archive = next; graph = nextGraph; recoveredDraft = next.recoveredDraft; lastEdit = Date(); refreshPresentation()
    }
    private func refreshPresentation() {
        if let current = graph.current, current != group { group = current }
        let nextConflicts = graph.hasConflict ? graph.heads.sorted().compactMap { graph.revisions[$0].flatMap { try? $0.verified(roster: graph.roster).group } } : []
        if conflicts != nextConflicts { conflicts = nextConflicts }
        let nextPending = revision.map { graph.awaitingAcknowledgement(of: $0).subtracting([localID]) } ?? []
        if pendingPeers != nextPending { pendingPeers = nextPending }
    }
    /// Application messages use the same trusted, live peer link as monitor
    /// switching.  Callers need the result so a stale membership entry cannot
    /// make a remote action look as though it succeeded.
    @discardableResult func sendApplication(_ data: Data, peer: UUID) -> Bool {
        guard let link = peerLinks[peer].flatMap({ transport.links[$0] }) else { return false }
        send(.application(data), to: link)
        return true
    }
    func hasApplicationLink(to peer: UUID) -> Bool {
        peer == localID || peerLinks[peer].flatMap { transport.links[$0] } != nil
    }
    private func send(_ message: KVMDeskMessage, to link: KVMPeerTransport.Link) {
        do { transport.send(try JSONEncoder().encode(message), to: link) } catch { problem = error.localizedDescription }
    }
    private func broadcastSync() { for id in peerLinks.values { if let link = transport.links[id] { sync(link) } } }
    /// Exchange membership and heads; the peer requests nothing and receives
    /// only what it lacks (see `.heads` handling).
    private func sync(_ link: KVMPeerTransport.Link) {
        send(.membership(archive.membership), to: link)
        send(.heads(graph.heads.sorted()), to: link)
    }
    /// Send one new revision to every trusted route except the one it came from.
    private func announce(_ revision: KVMSignedRevision, except: UUID? = nil) {
        for id in peerLinks.values where id != except { if let link = transport.links[id] { send(.revision(revision), to: link) } }
    }
    private func queueHistory(_ revisions: [KVMSignedRevision], to link: KVMPeerTransport.Link) {
        guard !revisions.isEmpty else { return }
        historyQueues[link.id] = revisions; historyOffsets[link.id] = 0
        if !syncing.contains(link.id) { syncing.insert(link.id); pumpHistory(link) }
    }
    private func pumpHistory(_ link: KVMPeerTransport.Link) {
        guard transport.links[link.id] != nil, let queue = historyQueues[link.id], let offset = historyOffsets[link.id] else { syncing.remove(link.id); return }
        if offset >= queue.count {
            syncing.remove(link.id); historyQueues[link.id] = nil; historyOffsets[link.id] = nil; return
        }
        // Bound outstanding writes; retry only while this authenticated link lives.
        if link.queuedBytes < 512 * 1024 { send(.revision(queue[offset]), to: link); historyOffsets[link.id] = offset + 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { [weak self, weak link] in if let link { self?.pumpHistory(link) } }
    }
    /// Retry only missing trusted links; healthy connections and membership stay intact.
    func retryConnections() {
        for peer in membership.peers where peer.id != localID && peerLinks[peer.id] == nil {
            // An explicit retry cancels only a still-negotiating route. It
            // leaves authenticated links untouched and clears the backoff.
            let pending = expectedPeers.compactMap { id, expected in expected == peer.id ? id : nil }
            for id in pending { if let link = transport.links[id], !link.ready { transport.close(link, reason: .local) } }
            connecting[peer.id] = nil; reconnectAfter[peer.id] = nil; failedAttempts[peer.id] = nil; routeLostAt[peer.id] = nil
        }
        reconnect()
    }
    private func reconnect() {
        let now = Date()
        for peer in membership.peers where peer.id != localID && peerLinks[peer.id] == nil && connecting[peer.id] == nil && now >= (reconnectAfter[peer.id] ?? .distantPast) {
            // While both Macs can reach each other only one of them dials, so a
            // lost route does not produce two simultaneous connections that
            // then have to be reconciled. The other waits 15 seconds.
            let primaryDialer = localID.uuidString < peer.id.uuidString
            if !primaryDialer, now.timeIntervalSince(routeLostAt[peer.id] ?? .distantPast) < 15 { continue }
            let entry = nearby.first { $0.id == peer.id.uuidString }
            // A wire beats wireless: when the peer is discovered on a cable,
            // the first attempt goes over that cable, before the ordinary
            // alternation below. One attempt only, so a cable that does not
            // carry this peer costs a single dial rather than all of them.
            if KVMPeerPath.dialsOverWire(wireFound: entry?.wire != nil, loopback: transport.localOnly,
                                         triedWire: triedWire.contains(peer.id)),
               let endpoint = entry?.endpoint, let wire = entry?.wire {
                triedWire.insert(peer.id)
                connect(endpoint, expected: peer.id, wire: wire)
                continue
            }
            let discovered = entry?.endpoint
            let saved = archive.addresses[peer.id].flatMap(Self.endpoint)
            let useDiscovery: Bool
            switch (discovered, saved) {
            case (nil, nil): continue
            case (.some, nil): useDiscovery = true
            case (nil, .some): useDiscovery = false
            // Alternate between the advertised service and the saved address:
            // a stale Bonjour record must not block a reachable peer.
            default: useDiscovery = !(lastDialUsedDiscovery[peer.id] ?? false)
            }
            lastDialUsedDiscovery[peer.id] = useDiscovery
            guard let endpoint = useDiscovery ? discovered : saved else { continue }
            connect(endpoint, expected: peer.id)
        }
    }
    /// Discovery has republished the nearby Macs. When a cable to a member has
    /// appeared while the desk is running over Wi-Fi, move onto it — once.
    /// Nothing is closed here: this adds a second connection, and the working
    /// one is given up only in `trust`, once the wired route has authenticated.
    private func wireUpdate() {
        for peer in membership.peers where peer.id != localID {
            let entry = nearby.first { $0.id == peer.id.uuidString }
            let wire = entry?.wire
            if !KVMPeerPath.remembersWiredTry(triedWire.contains(peer.id), wire: wire?.name, lastWire: peerWire[peer.id]) {
                triedWire.remove(peer.id)
            }
            peerWire[peer.id] = wire?.name
            // Only the Mac that dials first moves, the same way only one of them
            // redials a lost route, so a cable event adds one connection between
            // the two Macs rather than one from each.
            guard localID.uuidString < peer.id.uuidString else { continue }
            let link = peerLinks[peer.id].flatMap { transport.links[$0] }
            guard KVMPeerPath.movesToWire(wireFound: wire != nil, loopback: transport.localOnly,
                                          connected: link?.ready == true, linkIsWired: link?.wired == true,
                                          triedWire: triedWire.contains(peer.id),
                                          dialInFlight: connecting[peer.id] != nil),
                  let endpoint = entry?.endpoint, let wire else { continue }
            triedWire.insert(peer.id)
            connect(endpoint, expected: peer.id, wire: wire)
        }
    }
    private func tick() {
        if pairingUntil != nil && !pairingOpen { closePairing() }
        for (peer, id) in peerLinks {
            guard let link = transport.links[id] else { continue }
            if Date().timeIntervalSince(lastHeardLink[id] ?? .distantPast) > 20 { transport.close(link, reason: .heartbeat) }
            else {
                send(.ping(UUID()), to: link)
                if let ready = link.readyAt, ProcessInfo.processInfo.systemUptime - ready > 30 { failedAttempts[peer] = nil }
            }
        }
        reconnect()
        // A checkpoint restarts history under a new generation. Peers that are
        // offline but have acknowledged the current head rebase on reconnect;
        // waiting for every member to be online at once never happened on a
        // desk whose Macs sleep independently.
        if isOwner, canEdit, canCheckpoint(), graph.revisions.count >= 128, Date().timeIntervalSince(lastEdit) > 30,
           pendingPeers.isEmpty {
            do {
                let signed = try KVMMembership.sign(group: group, peers: membership.peers, authority: localID, key: identity.signing, generation: membership.generation + 1, previousHeads: graph.heads.sorted())
                try installMembership(signed, value: signed.verified(authorityKey: archive.authorityKey), key: archive.authorityKey)
                lastEdit = Date()
            } catch { problem = error.localizedDescription }
        }
    }
}
