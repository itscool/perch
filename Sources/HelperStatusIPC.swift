import Foundation
import Security
import Darwin

@objc protocol HelperStatusProtocol {
    func readStatus(_ reply: @escaping (Data?) -> Void)
}

enum HelperStatusIPC {
    static let guardian = "local.scott.perch.guardian.status"
    static let input = "local.scott.perch.input.status"
    static let maximumBytes = 1_048_576
    static let requirement: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()
    static let guardianClient = HelperStatusClient<SafetyStatus>(service: guardian)
    static let inputClient = HelperStatusClient<InputHelperStatus>(service: input)
}

// Read-only service. Updates stay in memory; JSON is encoded only when a client
// requests a newer snapshot. The timestamp comes from the helper's main loop,
// never from the XPC callback, so a wedged main loop cannot appear healthy.
final class HelperStatusServer: NSObject, NSXPCListenerDelegate, HelperStatusProtocol {
    let listener: NSXPCListener
    private let lock = NSLock()
    private var encode: (() -> Data?)?
    private var encoded: Data?
    private var connections: [ObjectIdentifier: NSXPCConnection] = [:]
    init(service: String? = nil) {
        listener = service.map(NSXPCListener.init(machServiceName:)) ?? .anonymous()
        super.init()
        listener.delegate = self
    }
    func start() { listener.resume() }
    func publish<T: Encodable>(_ status: T) {
        publishSnapshot { status }
    }
    // Capture immutable values from the helper loop. Construction, formatting
    // and encoding run only for an authenticated reader, never on idle ticks.
    func publishSnapshot<T: Encodable>(_ makeStatus: @escaping () -> T) {
        lock.lock(); defer { lock.unlock() }
        encode = { try? JSONEncoder().encode(makeStatus()) }
        encoded = nil
    }
    func readStatus(_ reply: @escaping (Data?) -> Void) {
        lock.lock()
        if encoded == nil { encoded = encode?() }
        let result = encoded.flatMap { $0.count <= HelperStatusIPC.maximumBytes ? $0 : nil }
        lock.unlock()
        reply(result)
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid(), let requirement = HelperStatusIPC.requirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperStatusProtocol.self)
        connection.exportedObject = self
        let id = ObjectIdentifier(connection)
        lock.lock()
        guard connections.count < 16 else { lock.unlock(); return false }
        connections[id] = connection
        lock.unlock()
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.connections.removeValue(forKey: id); self.lock.unlock()
        }
        connection.resume()
        return true
    }
    func stop() {
        listener.invalidate()
        lock.lock(); let active = Array(connections.values); connections.removeAll(); lock.unlock()
        for connection in active { connection.invalidate() }
    }
}

// Getters return immediately. One pending request at a time, with no polling
// thread or timeout timer; existing UI refreshes trigger reads and reconnects.
final class HelperStatusClient<Status: Decodable> {
    private let makeConnection: () -> NSXPCConnection
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var cached: Status?
    private var pending = false
    private var generation: UInt64 = 0
    private var lastRequest: UInt64 = 0
    init(service: String) { makeConnection = { NSXPCConnection(machServiceName: service) } }
    init(endpoint: NSXPCListenerEndpoint) { makeConnection = { NSXPCConnection(listenerEndpoint: endpoint) } }
    var value: Status? { refresh(); lock.lock(); defer { lock.unlock() }; return cached }
    func refresh() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        guard now &- lastRequest >= 80_000_000 else { lock.unlock(); return }
        if pending && now &- lastRequest < 1_000_000_000 { lock.unlock(); return }
        if pending {
            let old = connection; connection = nil; pending = false; generation &+= 1
            lock.unlock(); old?.invalidate(); refresh(); return
        }
        if connection == nil {
            guard let requirement = HelperStatusIPC.requirement else { lock.unlock(); return }
            let new = makeConnection()
            new.setCodeSigningRequirement(requirement)
            new.remoteObjectInterface = NSXPCInterface(with: HelperStatusProtocol.self)
            generation &+= 1
            let current = generation
            new.interruptionHandler = { [weak self] in self?.failed(current) }
            new.invalidationHandler = { [weak self] in self?.failed(current) }
            connection = new
            new.resume()
        }
        let current = generation, remote = connection!
        pending = true; lastRequest = now
        lock.unlock()
        let proxy = remote.remoteObjectProxyWithErrorHandler { [weak self] _ in self?.failed(current) } as? HelperStatusProtocol
        guard let proxy else { failed(current); return }
        proxy.readStatus { [weak self] data in
            let status = data.flatMap { $0.count <= HelperStatusIPC.maximumBytes ? try? JSONDecoder().decode(Status.self, from: $0) : nil }
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.generation == current else { return }
            self.cached = status; self.pending = false
        }
    }
    private func failed(_ current: UInt64) {
        lock.lock()
        guard generation == current else { lock.unlock(); return }
        let old = connection; connection = nil; pending = false; generation &+= 1
        // A recent snapshot may remain useful during a brief restart. Its
        // original timestamp still expires; failures never refresh it.
        lock.unlock(); old?.invalidate()
    }
    func stop() {
        lock.lock(); let old = connection; connection = nil; pending = false; cached = nil; generation &+= 1; lock.unlock()
        old?.invalidate()
    }
    deinit { stop() }
}
