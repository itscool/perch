import Foundation
import Network
import Security
import CryptoKit

enum KVMCloseReason: String, Codable {
    case local = "Local close", shutdown = "Perch stopped", duplicate = "Redundant connection replaced"
    case pairingClosed = "Pairing closed", pairingExpired = "Pairing expired", revoked = "Membership changed"
    case timeout = "Connection timed out", heartbeat = "Peer stopped replying"
    case network = "Network failure", remote = "Other computer closed connection"
    case cancelled = "Connection cancelled externally", identity = "Identity rejected"
    case protocolFailure = "Invalid message", backpressure = "Send queue exceeded limit"
    var unexpected: Bool { [.timeout, .heartbeat, .network, .remote, .cancelled, .identity, .protocolFailure, .backpressure].contains(self) }
}
struct KVMConnectionEvent: Codable, Identifiable {
    let id: UUID
    let time: Date
    let peer: UUID?
    let peerName: String
    let detail: String
    let unexpected: Bool
    let duration: Double?
    static func retained(_ values: [Self], now: Date = Date()) -> [Self] {
        Array(values.filter { $0.time <= now && now.timeIntervalSince($0.time) <= 86400 }.suffix(1024))
    }
}

/// All callbacks and trust changes run on main. Transport authentication is
/// certificate pinning; unpaired TLS connections carry only the approval flow.
final class KVMPeerTransport {
    struct Nearby: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
        var pairingRole: String?
        var deskName: String?
        static func make(id: String, endpoint: NWEndpoint, txt: NWTXTRecord?) -> Self {
            let name = txt?["name"].map { String($0.prefix(100)) }.flatMap { $0.isEmpty ? nil : $0 }
            return Self(id: id, name: name ?? "Unnamed Mac", endpoint: endpoint,
                        pairingRole: txt?["pairing"], deskName: txt?["desk"].map { String($0.prefix(100)) })
        }
    }
    final class Link {
        let id = UUID()
        let connection: NWConnection
        var certificate: Data?
        var framer = KVMMessageFramer()
        var queuedBytes = 0
        var ready = false
        let created = ProcessInfo.processInfo.systemUptime
        var readyAt: Double?
        var closeReason = KVMCloseReason.local
        var failureCode: String?
        init(_ connection: NWConnection) { self.connection = connection }
    }
    let identity: KVMPeerIdentity
    var permitted: (Data) -> Bool = { _ in false }
    var received: ((Link, Data) -> Void)?
    var connected: ((Link) -> Void)?
    var disconnected: ((Link) -> Void)?
    var discovered: (([Nearby]) -> Void)?
    var listenerProblem: ((String?) -> Void)?
    var discoveryProblem: ((String?) -> Void)?
    var connectionProblem: ((Link, String?) -> Void)?
    private var advertisedName = "Perch"
    private var advertising = false
    private var pairingRole = "closed"
    private var deskName = ""
    func advertisePairing(hosting: Bool?, desk: String) {
        pairingRole = hosting.map { $0 ? "invite" : "join" } ?? "closed"
        deskName = desk
        updateAdvertisement()
    }
    private func updateAdvertisement() {
        guard advertising else { return }
        listener?.service = .init(name: identity.saved.id.uuidString, type: serviceType,
                                  txtRecord: NWTXTRecord(["name": advertisedName, "pairing": pairingRole, "desk": deskName]))
    }
    var listener: NWListener?
    var browser: NWBrowser?
    private(set) var links: [UUID: Link] = [:]
    var nearby: [Nearby] = []
    private let serviceType = "_perch-desk._tcp"
    init(identity: KVMPeerIdentity) { self.identity = identity }
    func parameters(certificate: @escaping (Data) -> Void) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity.tls)
        sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        sec_protocol_options_set_tls_resumption_enabled(tls.securityProtocolOptions, false)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
            let data = SecCertificateCopyData(leaf) as Data
            guard data.count <= 8192, self?.permitted(data) == true else { complete(false); return }
            certificate(data); complete(true)
        }, .main)
        let result = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        result.includePeerToPeer = true
        return result
    }
    func start(name: String, localOnly: Bool = false, port: NWEndpoint.Port = .any) throws {
        guard listener == nil else { return }
        // TLS metadata is read again from each accepted connection. A listener's
        // verify callback must not share a mutable peer certificate between links.
        let params = parameters(certificate: { _ in })
        if localOnly { params.includePeerToPeer = false; params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port) }
        let listener = try localOnly ? NWListener(using: params) : NWListener(using: params, on: port)
        self.listener = listener
        advertisedName = name; advertising = !localOnly; updateAdvertisement()
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error), .waiting(let error): self?.listenerProblem?("This Mac cannot accept Desk connections: " + error.localizedDescription)
            case .ready: self?.listenerProblem?(nil)
            default: break
            }
        }
        listener.start(queue: .main)
        guard !localOnly else { return }
        let discoveryParameters = NWParameters.tcp; discoveryParameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: discoveryParameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.nearby = results.compactMap { result -> Nearby? in
                guard case .service(let id, _, _, _) = result.endpoint, id != self.identity.saved.id.uuidString else { return nil }
                let txt: NWTXTRecord?
                if case .bonjour(let record) = result.metadata { txt = record } else { txt = nil }
                return Nearby.make(id: id, endpoint: result.endpoint, txt: txt)
            }.sorted { $0.name < $1.name }
            self.discovered?(self.nearby)
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .waiting(let error), .failed(let error):
                self?.discoveryProblem?("Finding nearby Macs is unavailable. Existing Desk connections may still work. Check Local Network access in System Settings, or connect by address. " + error.localizedDescription)
            case .ready: self?.discoveryProblem?(nil)
            default: break
            }
        }
        browser.start(queue: .main)
    }
    @discardableResult func connect(_ endpoint: NWEndpoint) -> Link {
        let params = parameters(certificate: { _ in })
        if case .hostPort(let host, _) = endpoint, host == NWEndpoint.Host("127.0.0.1") { params.includePeerToPeer = false }
        let connection = NWConnection(to: endpoint, using: params)
        return accept(connection)
    }
    @discardableResult private func accept(_ connection: NWConnection) -> Link {
        let link = Link(connection)
        guard links.count < 32 else { connection.cancel(); return link }
        links[link.id] = link
        connection.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link, self.links[link.id] != nil else { return }
            switch state {
            case .ready:
                guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { self.close(link, reason: .identity); return }
                var certificates: [Data] = []
                sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
                    certificates.append(SecCertificateCopyData(sec_certificate_copy_ref(certificate).takeRetainedValue()) as Data)
                }
                guard let certificate = certificates.first, self.permitted(certificate) else { self.connectionProblem?(link, "The computer’s identity is unavailable or no longer approved."); self.close(link, reason: .identity); return }
                link.certificate = certificate; link.ready = true; link.readyAt = ProcessInfo.processInfo.systemUptime; self.connectionProblem?(link, nil); self.connected?(link); self.read(link)
            case .waiting(let error): self.connectionProblem?(link, "Waiting to connect: " + error.localizedDescription)
            case .failed(let error): link.failureCode = String(describing: error); self.connectionProblem?(link, "Could not connect: " + error.localizedDescription); self.close(link, reason: .network)
            case .cancelled: self.close(link, reason: .cancelled)
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak link] in if let self, let link, self.links[link.id] != nil, !link.ready { self.connectionProblem?(link, "The connection timed out. Check that Add a computer is open on both Macs, then try again."); self.close(link, reason: .timeout) } }
        return link
    }
    func send(_ data: Data, to link: Link) {
        do {
            let frame = try KVMMessageFramer.encode(data)
            guard links[link.id] != nil, link.queuedBytes + frame.count <= 2 * 1024 * 1024 else { close(link, reason: .backpressure); return }
            link.queuedBytes += frame.count
            link.connection.send(content: frame, completion: .contentProcessed { [weak self, weak link] error in
                guard let link else { return }; link.queuedBytes -= frame.count
                if let error { link.failureCode = String(describing: error); self?.close(link, reason: .network) }
            })
        } catch { close(link, reason: .protocolFailure) }
    }
    private func read(_ link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak link] data, _, done, error in
            guard let self, let link, self.links[link.id] != nil else { return }
            do { if let data { for frame in try link.framer.append(data) { self.received?(link, frame) } } }
            catch { self.close(link, reason: .protocolFailure); return }
            if let error { link.failureCode = String(describing: error); self.close(link, reason: .network) }
            else if done { self.close(link, reason: .remote) } else { self.read(link) }
        }
    }
    func close(_ link: Link, reason: KVMCloseReason = .local) {
        guard links.removeValue(forKey: link.id) != nil else { return }
        link.closeReason = reason
        link.connection.stateUpdateHandler = nil; link.connection.cancel(); disconnected?(link)
    }
    func stop() { browser?.stateUpdateHandler = nil; browser?.cancel(); browser = nil; listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil; advertising = false; Array(links.values).forEach { close($0, reason: .shutdown) }; listenerProblem?(nil); discoveryProblem?(nil) }
}
