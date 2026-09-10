import Foundation
import Combine
import Network
import CryptoKit

struct KVMHello: Codable {
    let card: KVMPeerCard
    let nonce: UUID
    let signature: Data
    let hosting: Bool
    static let domain = Data("Perch Desk hello v1\0".utf8)
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
    private var connecting: [UUID: Date] = [:]
    private var lastHeard: [UUID: Date] = [:]
    private var hostingPairing = false
    private var directContacts: [UUID: String] = [:]
    private var lastEdit = Date()
    var canCheckpoint: () -> Bool = { true }
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
        transport.discovered = { [weak self] nearby in self?.nearby = nearby; self?.reconnect() }
        transport.problem = { [weak self] in self?.problem = $0 }
    }
    func start(localOnly: Bool = false, port: NWEndpoint.Port = .init(rawValue: 53031)!) throws {
        guard isMember else { problem = "This Mac was removed from the desk. Start a new desk to join again."; return }
        try transport.start(name: group.computers.first { $0.id == localID }?.name ?? "Perch", localOnly: localOnly, port: port)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil; transport.stop() }
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
        pairingUntil = Date().addingTimeInterval(120); problem = nil
    }
    func closePairing() {
        pairingUntil = nil
        for pairing in pairings { if let link = transport.links[pairing.id] { transport.close(link) } }
        pairings = []
    }
    func connect(_ endpoint: NWEndpoint, expected: UUID? = nil) {
        let link = transport.connect(endpoint)
        if let expected { expectedPeers[link.id] = expected; connecting[expected] = Date() }
    }
    func connect(address: String) throws {
        guard pairingOpen else { throw KVMError("Choose Add computer on both Macs first.") }
        guard let endpoint = Self.endpoint(address) else { throw KVMError("Enter the other Mac’s address and Desk port, such as mac.local:53031 or [IPv6 address]:53031.") }
        let link = transport.connect(endpoint); directContacts[link.id] = address
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
    func reject(_ id: UUID) { if let link = transport.links[id] { transport.close(link) } }
    private func linkReady(_ link: KVMPeerTransport.Link) {
        do {
            let nonce = UUID(); localNonces[link.id] = nonce
            let card = identity.card(name: group.computers.first { $0.id == localID }?.name ?? "This Mac")
            let hello = KVMHello(card: card, nonce: nonce, signature: try identity.signing.signature(for: KVMHello.bytes(card, nonce, hostingPairing)), hosting: hostingPairing)
            send(.hello(hello), to: link)
            DispatchQueue.main.asyncAfter(deadline: .now() + 125) { [weak self, weak link] in
                guard let self, let link, self.peerLinks.values.contains(link.id) == false else { return }; self.transport.close(link)
            }
        } catch { transport.close(link) }
    }
    private func receive(_ bytes: Data, link: KVMPeerTransport.Link) {
        do {
            let trusted = peerLinks.values.contains(link.id)
            guard trusted || bytes.count <= 24 * 1024 || pairings.contains(where: { $0.id == link.id && $0.approvedHere && $0.approvedThere }) else { throw KVMError("Unpaired Desk message exceeded its limit.") }
            let message = try JSONDecoder().decode(KVMDeskMessage.self, from: bytes)
            if case .hello(let hello) = message {
                guard hellos[link.id] == nil else { throw KVMError("Repeated peer introduction.") }
                try hello.validate(certificate: link.certificate)
                guard hello.card.id != localID, expectedPeers[link.id] == nil || expectedPeers[link.id] == hello.card.id else { throw KVMError("A different computer answered this connection.") }
                hellos[link.id] = hello
                if membership.peers.contains(where: { $0.id == hello.card.id && $0.signingKey == hello.card.signingKey && $0.certificate == hello.card.certificate }) { trust(link) }
                else {
                    guard pairingOpen, hello.hosting != hostingPairing, pairings.isEmpty, let nonce = localNonces[link.id] else { throw KVMError("This computer has not been approved for the desk.") }
                    let pieces = [identity.saved.certificate.base64EncodedString() + nonce.uuidString, hello.card.certificate.base64EncodedString() + hello.nonce.uuidString].sorted()
                    let hash = SHA256.hash(data: Data(pieces.joined(separator: "|").utf8)).prefix(8).map { String(format: "%02X", $0) }
                    let comparison = stride(from: 0, to: 8, by: 2).map { hash[$0] + hash[$0+1] }.joined(separator: " ")
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
            lastHeard[hello.card.id] = Date()
            switch message {
            case .revision(let revision):
                let payload = try JSONDecoder().decode(KVMRevisionPayload.self, from: revision.payload)
                guard payload.epoch == graph.roster.epoch else { return }
                if graph.revisions[revision.id] == nil { var next = graph; try next.receive(revision); try save(next); broadcastSync() }
                send(.receipt(revision.id, graph.roster.epoch), to: link)
            case .receipt(let id, let epoch):
                guard epoch == graph.roster.epoch else { return }
                try graph.acknowledge(id, from: hello.card.id, epoch: epoch); refreshPresentation()
            case .ping(let nonce): send(.pong(nonce), to: link)
            case .pong: break
            case .contact(let port):
                if port > 0, case .hostPort(let host, _) = link.connection.currentPath?.remoteEndpoint {
                    let text = String(describing: host)
                    let address = (text.contains(":") ? "[" + text + "]" : text) + ":\(port)"
                    if Self.endpoint(address) != nil { archive.addresses[hello.card.id] = address; try archive.write(storage) }
                }
                send(.contacts(archive.addresses), to: link)
            case .contacts(let addresses):
                guard addresses.count <= 16, addresses.allSatisfy({ Self.endpoint($0.value) != nil }) else { return }
                for (id, address) in addresses where membership.peers.contains(where: { $0.id == id }) && archive.addresses[id] == nil { archive.addresses[id] = address }
                try archive.write(storage); reconnect()
            case .application(let data): application?(hello.card.id, data)
            default: throw KVMError("Unexpected Desk message.")
            }
        } catch { problem = error.localizedDescription; transport.close(link) }
    }
    private func finishPairing(_ id: UUID) {
        guard let pairing = pairings.first(where: { $0.id == id }), pairing.approvedHere, pairing.approvedThere, let link = transport.links[id] else { return }
        // The established desk wins; two new desks deterministically choose an
        // owner. The hello does not grant membership before both approvals.
        guard isOwner, hostingPairing else { return }
        do {
            guard canEdit, membership.peers.count < 16 else { throw KVMError("Resolve desk changes or free a member slot before adding a computer.") }
            var group = self.group; group.computers.append(.init(id: pairing.card.id, name: pairing.card.name))
            let signed = try KVMMembership.sign(group: group, peers: membership.peers + [pairing.card], authority: localID, key: identity.signing,
                                                generation: membership.generation + 1, previousHeads: graph.heads.sorted())
            let value = try signed.verified(authorityKey: archive.authorityKey)
            try installMembership(signed, value: value, key: archive.authorityKey)
            send(.membership(signed), to: link); trust(link)
        } catch { problem = error.localizedDescription }
    }
    private func trust(_ link: KVMPeerTransport.Link) {
        guard let hello = hellos[link.id] else { return }
        if let oldID = peerLinks[hello.card.id], oldID != link.id, let old = transport.links[oldID] {
            func order(_ id: UUID) -> String { [localNonces[id]?.uuidString ?? "", hellos[id]?.nonce.uuidString ?? ""].sorted().joined() }
            if order(oldID) < order(link.id) { transport.close(link); return }
            transport.close(old)
        }
        peerLinks[hello.card.id] = link.id; connecting[hello.card.id] = nil
        if pairings.contains(where: { $0.id == link.id }) { completedPairing = hello.card.id; pairingUntil = nil }
        pairings.removeAll { $0.id == link.id }; lastHeard[hello.card.id] = Date()
        online.insert(hello.card.id)
        if let address = directContacts.removeValue(forKey: link.id) { archive.addresses[hello.card.id] = address; do { try archive.write(storage) } catch { problem = error.localizedDescription } }
        refreshPresentation(); peersChanged?(); sync(link)
        if let port = transport.listener?.port?.rawValue, port > 0 { send(.contact(port), to: link) }
    }
    private func linkLost(_ link: KVMPeerTransport.Link) {
        if let peer = hellos[link.id]?.card.id, peerLinks[peer] == link.id {
            peerLinks[peer] = nil; online.remove(peer); lastHeard[peer] = nil; peersChanged?()
        }
        pairings.removeAll { $0.id == link.id }; hellos[link.id] = nil; localNonces[link.id] = nil; expectedPeers[link.id] = nil
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
            if let peer = hellos[link.id]?.card, peerLinks[peer.id] != nil, !value.peers.contains(where: { $0.id == peer.id && $0.certificate == peer.certificate }) { transport.close(link) }
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
        var graph = self.graph; _ = try graph.edit(next, author: localID, key: identity.signing)
        try save(graph); broadcastSync()
    }
    func resolve(_ chosen: KVMGroup) throws {
        var next = chosen
        next.id = group.id; next.computers = group.computers
        for i in next.connections.indices where !next.computers.contains(where: { $0.id == next.connections[i].computer }) { next.connections[i].computer = nil; next.connections[i].localDisplay = nil }
        _ = try next.validated()
        var graph = self.graph; _ = try graph.edit(next, author: localID, key: identity.signing, resolving: graph.heads)
        try save(graph, clearingDraft: true); broadcastSync()
    }
    private func save(_ nextGraph: KVMSyncGraph, clearingDraft: Bool = false) throws {
        var next = archive; next.history = try nextGraph.history(); if clearingDraft { next.recoveredDraft = nil }
        try next.write(storage); archive = next; graph = nextGraph; recoveredDraft = next.recoveredDraft; lastEdit = Date(); refreshPresentation()
    }
    private func refreshPresentation() {
        if let current = graph.current { group = current }
        conflicts = graph.hasConflict ? graph.heads.sorted().compactMap { graph.revisions[$0].flatMap { try? $0.verified(roster: graph.roster).group } } : []
        if let revision { pendingPeers = graph.awaitingAcknowledgement(of: revision).subtracting([localID]) } else { pendingPeers = [] }
    }
    func sendApplication(_ data: Data, peer: UUID) {
        guard let link = peerLinks[peer].flatMap({ transport.links[$0] }) else { return }
        send(.application(data), to: link)
    }
    private func send(_ message: KVMDeskMessage, to link: KVMPeerTransport.Link) {
        do { transport.send(try JSONEncoder().encode(message), to: link) } catch { problem = error.localizedDescription }
    }
    private func broadcastSync() { for id in peerLinks.values { if let link = transport.links[id] { sync(link) } } }
    private func sync(_ link: KVMPeerTransport.Link) {
        guard !syncing.contains(link.id) else { syncAgain.insert(link.id); return }
        syncing.insert(link.id); historyQueues[link.id] = (try? graph.history()) ?? []; historyOffsets[link.id] = 0
        send(.membership(archive.membership), to: link); pumpHistory(link)
    }
    private func pumpHistory(_ link: KVMPeerTransport.Link) {
        guard transport.links[link.id] != nil, let queue = historyQueues[link.id], let offset = historyOffsets[link.id] else { return }
        if offset >= queue.count {
            syncing.remove(link.id); historyQueues[link.id] = nil; historyOffsets[link.id] = nil
            if syncAgain.remove(link.id) != nil { sync(link) }; return
        }
        // Bound outstanding writes; retry only while this authenticated link lives.
        if link.queuedBytes < 512 * 1024 { send(.revision(queue[offset]), to: link); historyOffsets[link.id] = offset + 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { [weak self, weak link] in if let link { self?.pumpHistory(link) } }
    }
    private func reconnect() {
        for peer in membership.peers where peer.id != localID && peerLinks[peer.id] == nil && Date().timeIntervalSince(connecting[peer.id] ?? .distantPast) > 12 {
            if let nearby = nearby.first(where: { $0.id == peer.id.uuidString }) { connect(nearby.endpoint, expected: peer.id) }
            else if let address = archive.addresses[peer.id], let endpoint = Self.endpoint(address) { connect(endpoint, expected: peer.id) }
        }
    }
    private func tick() {
        if pairingUntil != nil && !pairingOpen { closePairing() }
        for (peer, id) in peerLinks {
            guard let link = transport.links[id] else { continue }
            if Date().timeIntervalSince(lastHeard[peer] ?? .distantPast) > 20 { transport.close(link) }
            else { send(.ping(UUID()), to: link) }
        }
        reconnect()
        if isOwner, canEdit, canCheckpoint(), graph.revisions.count >= 256, Date().timeIntervalSince(lastEdit) > 30,
           pendingPeers.isEmpty, online == Set(membership.peers.map(\.id)) {
            do {
                let signed = try KVMMembership.sign(group: group, peers: membership.peers, authority: localID, key: identity.signing, generation: membership.generation + 1, previousHeads: graph.heads.sorted())
                try installMembership(signed, value: signed.verified(authorityKey: archive.authorityKey), key: archive.authorityKey)
                lastEdit = Date()
            } catch { problem = error.localizedDescription }
        }
    }
}
