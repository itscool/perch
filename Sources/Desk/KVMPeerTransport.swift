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
    case incompatible = "Incompatible Perch version"
    var unexpected: Bool { [.timeout, .heartbeat, .network, .remote, .cancelled, .identity, .protocolFailure, .backpressure, .incompatible].contains(self) }
    /// Reasons worth announcing to the other Mac before cancelling. The rest
    /// describe a peer that cannot be reached anyway.
    var announced: Bool { ![.timeout, .heartbeat, .network, .remote, .cancelled, .backpressure].contains(self) }
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

/// Which way Perch reaches another Mac: over a cable between the two, or over
/// Wi-Fi.
///
/// Measured on Scott's two Macs, both on 2.0.296, same peer, same port, forty
/// TCP handshakes each. Over Wi-Fi a handshake took a median of 16.7 ms, 69.8 ms
/// at the ninety-fifth percentile and 101.4 ms at worst. Over the Thunderbolt
/// cable already joining those two Macs the same handshake took 0.9 ms, 1.2 ms
/// and 1.3 ms. Perch's own pointer travel over Wi-Fi measured 67 to 73 ms at the
/// ninety-fifth percentile and 86 to 112 ms at worst, which the Wi-Fi handshakes
/// reproduce. The lag and the jitter people feel as the pointer crosses to the
/// other Mac's screen is the wireless link, not Perch's code.
///
/// The cable was plugged in the whole time. Perch handed Bonjour's service
/// endpoint to Network.framework and let it pick the route, and a Thunderbolt
/// bridge carries no route to the internet, so it lost to Wi-Fi every time —
/// even though macOS itself ranks Thunderbolt Bridge above Wi-Fi.
///
/// The rule is deliberately blunt. The subtle version of a rule like this is
/// what produced the pointer that traded itself between Macs.
///
/// 1. A wire beats wireless. When the other Mac is discovered on a wired
///    interface, dial it over that interface. With no wire, dial as before.
/// 2. A working link is never dropped for one that might not arrive. Nothing
///    here closes a connection. A wired attempt is an extra dial alongside the
///    link in use, and it can only take over once it is connected and its
///    signed hello has been checked.
/// 3. One move per cable event. A desk already running over Wi-Fi moves onto a
///    newly plugged cable exactly once. Discovery republishes a peer whenever
///    anything about it changes, so the same cable is reported over and over;
///    a rule that acted on each report would dial in a loop.
/// 4. There is no setting. Using the cable you plugged in is not a preference.
enum KVMPeerPath {
    /// Whether this dial should be pinned to the wire the peer was found on.
    ///
    /// `triedWire` is the single attempt rule 3 allows. A cable that is plugged
    /// in but does not carry this peer — one Mac wired to a switch, the other
    /// only on Wi-Fi — must cost one attempt, not every attempt, or the desk
    /// would spend its whole reconnect budget on a route that cannot work.
    ///
    /// Loopback is excluded outright: there is no wire between a process and
    /// itself, and requiring one would hang the desk's own network fixtures.
    static func dialsOverWire(wireFound: Bool, loopback: Bool, triedWire: Bool) -> Bool {
        guard wireFound, !loopback else { return false }
        return !triedWire
    }

    /// Whether to add one wired dial for a peer the desk already reaches over
    /// Wi-Fi, because a cable to it has just appeared.
    ///
    /// This closes nothing (rule 2). It asks for a second connection beside the
    /// working one: if it arrives and authenticates, the ordinary duplicate-route
    /// rule retires the wireless one, and if it never arrives the desk carries
    /// on over Wi-Fi having lost nothing.
    static func movesToWire(wireFound: Bool, loopback: Bool, connected: Bool, linkIsWired: Bool,
                            triedWire: Bool, dialInFlight: Bool) -> Bool {
        guard connected, !linkIsWired, !dialInFlight else { return false }
        return dialsOverWire(wireFound: wireFound, loopback: loopback, triedWire: triedWire)
    }

    /// Whether the record of that one wired attempt survives this report of the
    /// peer's interfaces.
    ///
    /// Rule 3 lives here. macOS republishes a discovered Mac many times over,
    /// and every one of those reports names the same cable; only the cable
    /// going away, or a different one taking its place, is a new cable event
    /// and earns another attempt. Forgetting on any other report is what would
    /// turn discovery into a dialling loop.
    static func remembersWiredTry(_ tried: Bool, wire: String?, lastWire: String?) -> Bool {
        guard let wire, wire == lastWire else { return false }
        return tried
    }

    /// Which of two authenticated routes to the same Mac the desk keeps.
    ///
    /// This is the only place a working link is given up, and it is reached
    /// only once the arriving route is connected and its signed hello has been
    /// checked. That is rule 2: a wired dial in flight is not yet a route, and
    /// one that never connects simply dies with the desk still running.
    static func keepsArrivingRoute(arrivingIsWired: Bool, workingIsWired: Bool,
                                   simultaneous: Bool, arrivingWinsTieBreak: Bool) -> Bool {
        // Routes that did not become ready together mean the peer dialled again
        // because its side of the working one is gone, so the arriving route
        // wins whatever each runs over. Holding on to a wire the other Mac has
        // already given up on would leave it dialling a route this Mac has not
        // yet noticed is dead.
        guard simultaneous else { return true }
        // Both Macs see the same pair of connections, and a connection runs over
        // the same kind of interface at both ends, so preferring the wire picks
        // the same survivor on both and neither is left dialling alone.
        if arrivingIsWired != workingIsWired { return arrivingIsWired }
        return arrivingWinsTieBreak
    }
}

/// All callbacks and trust changes run on main. Transport authentication is
/// certificate pinning; unpaired TLS connections carry only the approval flow.
final class KVMPeerTransport {
    struct Nearby: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
        /// The wired interface this Mac was found on, when the two are cabled
        /// together. Discovery answers "are these Macs wired to each other",
        /// which a path monitor cannot: a Thunderbolt bridge carries no route
        /// to anywhere else, so macOS reports no wired path at all. See
        /// `KVMPeerPath`.
        let wire: NWInterface?
        var pairingRole: String?
        var deskName: String?
        static func make(id: String, endpoint: NWEndpoint, txt: NWTXTRecord?, wire: NWInterface? = nil) -> Self {
            let name = txt?["name"].map { String($0.prefix(100)) }.flatMap { $0.isEmpty ? nil : $0 }
            return Self(id: id, name: name ?? "Unnamed Mac", endpoint: endpoint, wire: wire,
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
        /// Whether this connection runs over a cable between the two Macs.
        var wired = false
        let created = ProcessInfo.processInfo.systemUptime
        var readyAt: Double?
        var closeReason = KVMCloseReason.local
        var failureCode: String?
        /// Why the other Mac said it was closing, when it said so.
        var remoteReason: KVMCloseReason?
        var remoteDetail: String?
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
    /// Updated when macOS reports a different usable network path. This is
    /// diagnostic only; existing connections are allowed to migrate or fail
    /// normally and the desk node decides when to reconnect.
    /// Whether any usable network path exists; peers are only dialed when one does.
    var pathChanged: ((Bool) -> Void)?
    /// Bytes to send just before a deliberate close, so the peer can record the reason.
    var goodbye: ((KVMCloseReason) -> Data?)?
    private var advertisedName = "Perch"
    private var advertising = false
    private var pairingRole = "closed"
    private var deskName = ""
    private var discoveryPeerToPeer = false
    func advertisePairing(hosting: Bool?, desk: String) {
        pairingRole = hosting.map { $0 ? "invite" : "join" } ?? "closed"
        deskName = desk
        updateAdvertisement()
        // Peer-to-peer (AWDL) discovery is only needed while a Mac is being
        // added. Members on the same network reconnect over infrastructure,
        // which keeps Wi-Fi off the AWDL time-slice and avoids the extra
        // Local Network policy evaluations that restarted every desk flow.
        let wanted = hosting != nil
        if advertising, wanted != discoveryPeerToPeer { startDiscovery(peerToPeer: wanted) }
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
    private var pathMonitor: NWPathMonitor?
    /// A Perch started for loopback testing. It has no wire and must never be
    /// pinned to one; see `KVMPeerPath`.
    private(set) var localOnly = false
    private let serviceType = "_perch-desk._tcp"
    init(identity: KVMPeerIdentity) { self.identity = identity }
    func parameters(certificate: @escaping (Data) -> Void, peerToPeer: Bool = true) -> NWParameters {
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
        let tcp = NWProtocolTCP.Options()
        // A dead route must not wait for the 20-second application heartbeat:
        // TCP keepalive notices a vanished peer in about ten seconds, and a
        // dial that cannot complete gives up before the app's own timer.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 8
        // Pointer movement is a stream of tiny packets. Nagle holds them back to
        // fill a segment, which showed up as 40 to 90 ms stalls in the movement
        // gaps; send each one as it happens and ask the network for interactive
        // treatment, which matters most over Wi-Fi.
        tcp.noDelay = true
        let result = NWParameters(tls: tls, tcp: tcp)
        result.serviceClass = .responsiveData
        result.includePeerToPeer = peerToPeer
        return result
    }
    func start(name: String, localOnly: Bool = false, port: NWEndpoint.Port = .any) throws {
        guard listener == nil else { return }
        self.localOnly = localOnly
        // TLS metadata is read again from each accepted connection. A listener's
        // verify callback must not share a mutable peer certificate between links.
        let params = parameters(certificate: { _ in })
        if localOnly { params.includePeerToPeer = false; params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port) }
        let listener = try localOnly ? NWListener(using: params) : NWListener(using: params, on: port)
        self.listener = listener
        startPathMonitor()
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
        startDiscovery(peerToPeer: pairingRole != "closed")
    }
    private func startDiscovery(peerToPeer: Bool) {
        browser?.stateUpdateHandler = nil; browser?.browseResultsChangedHandler = nil; browser?.cancel()
        discoveryPeerToPeer = peerToPeer
        let discoveryParameters = NWParameters.tcp; discoveryParameters.includePeerToPeer = peerToPeer
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: discoveryParameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.nearby = results.compactMap { result -> Nearby? in
                guard case .service(let id, _, _, _) = result.endpoint, id != self.identity.saved.id.uuidString else { return nil }
                let txt: NWTXTRecord?
                if case .bonjour(let record) = result.metadata { txt = record } else { txt = nil }
                return Nearby.make(id: id, endpoint: result.endpoint, txt: txt,
                                   wire: result.interfaces.first { $0.type == .wiredEthernet })
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
    /// `wire` pins the dial to the interface the peer was discovered on, which
    /// is how `KVMPeerPath`'s first rule reaches Network.framework. Left to
    /// itself it picks Wi-Fi over a Thunderbolt bridge, because the bridge has
    /// no route to the internet to recommend it.
    @discardableResult func connect(_ endpoint: NWEndpoint, peerToPeer: Bool = true, wire: NWInterface? = nil) -> Link {
        var loopback = false
        if case .hostPort(let host, _) = endpoint, host == NWEndpoint.Host("127.0.0.1") { loopback = true }
        // Belt and braces for the loopback fixtures: a connection to this same
        // process, or from a Perch started for local-only testing, is never put
        // on a physical interface whatever the caller asked for.
        let wire = loopback || localOnly ? nil : wire
        // Peer-to-peer is Wi-Fi by definition, so a wired dial never offers it.
        let params = parameters(certificate: { _ in }, peerToPeer: wire == nil && peerToPeer)
        if loopback { params.includePeerToPeer = false }
        if let wire { params.requiredInterface = wire }
        let connection = NWConnection(to: endpoint, using: params)
        return accept(connection, wired: wire != nil)
    }
    @discardableResult private func accept(_ connection: NWConnection, wired: Bool = false) -> Link {
        let link = Link(connection)
        link.wired = wired
        // Handshakes that never finish must not crowd out members: they have
        // their own small cap inside the overall limit.
        guard links.count < 32, links.values.filter({ !$0.ready }).count < 8 else { connection.cancel(); return link }
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
                link.wired = link.wired || connection.currentPath?.usesInterfaceType(.wiredEthernet) == true
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
        link.connection.stateUpdateHandler = nil
        let connection = link.connection
        if link.ready, reason.announced, let data = goodbye?(reason), let frame = try? KVMMessageFramer.encode(data) {
            // Tell the peer why, then cancel once the frame has left (or after a
            // bounded wait). The local state is already closed either way.
            connection.send(content: frame, completion: .contentProcessed { _ in connection.cancel() })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { connection.cancel() }
        } else { connection.cancel() }
        disconnected?(link)
    }
    func stop() {
        browser?.stateUpdateHandler = nil; browser?.cancel(); browser = nil
        listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        pathMonitor?.cancel(); pathMonitor = nil
        advertising = false
        Array(links.values).forEach { close($0, reason: .shutdown) }
        listenerProblem?(nil); discoveryProblem?(nil)
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in self?.pathChanged?(path.status == .satisfied) }
        }
        monitor.start(queue: .main)
    }
}
