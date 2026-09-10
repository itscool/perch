import Foundation
import Network
import Security
import CryptoKit

/// All callbacks and trust changes run on main. Transport authentication is
/// certificate pinning; unpaired TLS connections carry only the approval flow.
final class KVMPeerTransport {
    struct Nearby: Identifiable { let id: String; let name: String; let endpoint: NWEndpoint }
    final class Link {
        let id = UUID()
        let connection: NWConnection
        var certificate: Data?
        var framer = KVMMessageFramer()
        var queuedBytes = 0
        var ready = false
        init(_ connection: NWConnection) { self.connection = connection }
    }
    let identity: KVMPeerIdentity
    var permitted: (Data) -> Bool = { _ in false }
    var received: ((Link, Data) -> Void)?
    var connected: ((Link) -> Void)?
    var disconnected: ((Link) -> Void)?
    var discovered: (([Nearby]) -> Void)?
    var problem: ((String) -> Void)?
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
        if !localOnly { listener.service = .init(name: identity.saved.id.uuidString, type: serviceType, txtRecord: NWTXTRecord(["name": name])) }
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.stateUpdateHandler = { [weak self] state in if case .failed(let error) = state { self?.problem?("Desk networking could not start: " + error.localizedDescription) } }
        listener.start(queue: .main)
        guard !localOnly else { return }
        let discoveryParameters = NWParameters.tcp; discoveryParameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: discoveryParameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.nearby = results.compactMap { result -> Nearby? in
                guard case .service(let id, _, _, _) = result.endpoint, id != self.identity.saved.id.uuidString else { return nil }
                var label = "Perch " + String(id.prefix(8))
                if case .bonjour(let txt) = result.metadata, let value = txt["name"] { label = String(value.prefix(100)) }
                return Nearby(id: id, name: label, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            self.discovered?(self.nearby)
        }
        browser.stateUpdateHandler = { [weak self] state in if case .waiting(let error) = state { self?.problem?("Nearby discovery is unavailable. Check Local Network access in System Settings, or connect by address. " + error.localizedDescription) } }
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
            guard let self, let link else { return }
            switch state {
            case .ready:
                guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { self.close(link); return }
                var certificates: [Data] = []
                sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
                    certificates.append(SecCertificateCopyData(sec_certificate_copy_ref(certificate).takeRetainedValue()) as Data)
                }
                guard let certificate = certificates.first, self.permitted(certificate) else { self.problem?("Peer certificate unavailable or no longer approved."); self.close(link); return }
                link.certificate = certificate; link.ready = true; self.connected?(link); self.read(link)
            case .waiting(let error): self.problem?("Desk connection is waiting: " + error.localizedDescription)
            case .failed(let error): self.problem?("Desk connection failed: " + error.localizedDescription); self.close(link)
            case .cancelled: self.close(link)
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak link] in if let link, !link.ready { self?.close(link) } }
        return link
    }
    func send(_ data: Data, to link: Link) {
        do {
            let frame = try KVMMessageFramer.encode(data)
            guard links[link.id] != nil, link.queuedBytes + frame.count <= 2 * 1024 * 1024 else { close(link); return }
            link.queuedBytes += frame.count
            link.connection.send(content: frame, completion: .contentProcessed { [weak self, weak link] error in
                guard let link else { return }; link.queuedBytes -= frame.count
                if error != nil { self?.close(link) }
            })
        } catch { close(link) }
    }
    private func read(_ link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak link] data, _, done, error in
            guard let self, let link, self.links[link.id] != nil else { return }
            do { if let data { for frame in try link.framer.append(data) { self.received?(link, frame) } } }
            catch { self.close(link); return }
            if done || error != nil { self.close(link) } else { self.read(link) }
        }
    }
    func close(_ link: Link) {
        guard links.removeValue(forKey: link.id) != nil else { return }
        link.connection.stateUpdateHandler = nil; link.connection.cancel(); disconnected?(link)
    }
    func stop() { browser?.cancel(); browser = nil; listener?.cancel(); listener = nil; Array(links.values).forEach(close) }
}
