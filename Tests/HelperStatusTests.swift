import Foundation

func runHelperStatusTests() throws {
    struct Payload: Codable { let timestamp: Date; let number: Int }
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    func until(_ predicate: () -> Bool, seconds: Double = 3) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return predicate()
    }
    let server = HelperStatusServer()
    server.publish(Payload(timestamp: Date().addingTimeInterval(-10), number: 1)); server.start()
    let client = HelperStatusClient<Payload>(endpoint: server.listener.endpoint)
    defer { client.onChange = nil; client.stop(); server.stop() }
    var publications = 0, shown: Int?
    client.onChange = {
        client.withCachedValue { publications += 1; shown = client.value?.number }
    }
    try check(client.initiallyChecking, "Cold status cache was not checking")
    try check(until { client.value?.number == 1 }, "XPC status did not arrive")
    try check(until { shown == 1 } && !client.initiallyChecking, "Reply did not publish its state to the UI")
    let beforeIdle = publications
    _ = until({ false }, seconds: 0.2)
    try check(publications == beforeIdle, "Rendering a reply started a self-sustaining request loop")
    try check(Date().timeIntervalSince(client.value!.timestamp) > 9, "XPC reply refreshed stale helper timestamp")
    server.publish(Payload(timestamp: Date(), number: 2))
    try check(until { client.value?.number == 2 }, "New in-memory status was not delivered")
    let buildLock = NSLock(); var built = 0
    server.publishSnapshot {
        buildLock.lock(); built += 1; buildLock.unlock()
        return Payload(timestamp: Date().addingTimeInterval(-10), number: 3)
    }
    buildLock.lock(); let beforeRead = built; buildLock.unlock()
    try check(beforeRead == 0, "Status details were built before a reader requested them")
    try check(until { client.value?.number == 3 }, "Lazy status was not delivered")
    _ = until({ _ = client.value; return false }, seconds: 0.2)
    buildLock.lock(); let afterRead = built; buildLock.unlock()
    try check(afterRead == 1, "Unchanged lazy snapshot was rebuilt on every request")
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<10_000 { _ = client.value }
    let ns = DispatchTime.now().uptimeNanoseconds - start
    try check(ns < 500_000_000, "Cached XPC getters blocked")
    // A wrong signing requirement must reject the connection, never return data.
    let mismatch = NSXPCConnection(listenerEndpoint: server.listener.endpoint)
    mismatch.remoteObjectInterface = NSXPCInterface(with: HelperStatusProtocol.self)
    mismatch.setCodeSigningRequirement("identifier \"local.scott.perch.invalid-test-identity\"")
    mismatch.resume()
    let resultLock = NSLock(); var rejected = false, received = false
    let proxy = mismatch.remoteObjectProxyWithErrorHandler { _ in resultLock.lock(); rejected = true; resultLock.unlock() } as? HelperStatusProtocol
    proxy?.readStatus { data in resultLock.lock(); received = data != nil; resultLock.unlock() }
    try check(until { resultLock.lock(); defer { resultLock.unlock() }; return rejected }, "Incorrect peer identity was not rejected")
    resultLock.lock(); let accepted = received; resultLock.unlock()
    mismatch.invalidate()
    try check(!accepted, "Unexpected peer returned trusted status")
    server.stop()
    _ = until({ _ = client.value; return false }, seconds: 0.2)
    // A disconnected service may retain its last snapshot but cannot renew it.
    try check(client.value == nil || client.value?.number == 3, "Disconnected client fabricated status")
    print("PASS: authenticated asynchronous XPC, snapshot updates, unchanged stale timestamp, mismatched identity rejection and bounded cached reads (\(ns / 10_000) ns/getter)")
}

// Persistent read-only diagnostic client, avoiding one subprocess per sample.
func runStatusStream() {
    struct Snapshot: Encodable {
        var guardian: SafetyStatus?
        var input: InputHelperStatus?
        var observerPID = getpid()
    }
    func emit() {
        let snapshot = Snapshot(guardian: HelperStatusIPC.guardianClient.value, input: HelperStatusIPC.inputClient.value)
        if let data = try? JSONEncoder().encode(snapshot) { print(String(decoding: data, as: UTF8.self)); fflush(stdout) }
    }
    emit()
    let timer = Timer(timeInterval: 1, repeats: true) { _ in emit() }
    RunLoop.main.add(timer, forMode: .default)
    RunLoop.main.run()
}
