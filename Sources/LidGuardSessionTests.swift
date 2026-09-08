import Foundation

private final class LidSessionFixture {
    var clock: Double = 100
    var requests: [(LidGuardSession.Request, (Data?) -> Void)] = []
    var timers: [(Double, () -> Void)] = []
    var invalidations = 0
    var published: LidGuardStatus?
    var changing = false
    var active = false
    lazy var session = LidGuardSession(send: { [unowned self] request, reply in
        requests.append((request, reply))
    }, schedule: { [unowned self] delay, action in timers.append((delay, action)) },
    invalidate: { [unowned self] in invalidations += 1 },
    publish: { [unowned self] status, changing in published = status; self.changing = changing },
    activity: { [unowned self] in active = $0 }, now: { [unowned self] in clock })
    func response(armed: Bool, token: String?, error: String? = nil) throws -> Data {
        try JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: armed, detail: armed ? "Lid session requested." : "Off", error: error), token: token))
    }
    func fire(_ delay: Double) {
        let index = timers.firstIndex { $0.0 == delay }!
        timers.remove(at: index).1()
    }
}

func runLidGuardSessionTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let token = UUID().uuidString
    let f = LidSessionFixture()
    var completions = 0
    f.session.change(true) { if case .success = $0 { completions += 1 } }
    try check(f.changing && f.requests.last?.0 == .change(true), "Enable did not enter the pending state")
    f.requests[0].1(try f.response(armed: true, token: token))
    try check(completions == 1 && !f.changing && f.active, "Enable did not retain its valid session")
    f.fire(3)
    try check(completions == 1 && f.active, "Late enable timeout undid a successful request")
    f.session.refresh()
    try check(f.requests.last?.0 == .renew(token), "Active session did not renew")
    let delayed = f.requests.last!.1
    f.clock = 102; f.fire(2)
    try check(f.published == nil && f.active && f.invalidations == 1, "Timeout did not expose unknown status while preserving bounded recovery")
    f.clock = 102.25; f.fire(0.25)
    try check(f.requests.last?.0 == .renew(token), "Reply timeout discarded the token or tried to enable a new session")
    f.requests.last!.1(try f.response(armed: true, token: token))
    delayed(nil)
    delayed(try f.response(armed: false, token: nil))
    try check(f.published?.armed == true && f.invalidations == 1, "Late reply/error overwrote recovered status")

    f.session.refresh()
    let beforeDisable = f.requests.last!.1
    f.session.change(false) { if case .success = $0 { completions += 1 } }
    try check(f.requests.last?.0 == .change(false), "Disable was blocked by a pending renewal")
    f.requests.last!.1(try f.response(armed: false, token: nil))
    beforeDisable(try f.response(armed: true, token: token))
    f.session.refresh()
    try check(!f.active && f.requests.last?.0 == .status && completions == 2, "Old renewal resurrected a disabled session")

    let expiry = LidSessionFixture()
    expiry.session.change(true) { _ in }
    expiry.requests.last!.1(try expiry.response(armed: true, token: token))
    expiry.session.refresh()
    expiry.requests.last!.1(Data("invalid reply".utf8))
    expiry.clock = 102; expiry.fire(0.25)
    try check(expiry.requests.last?.0 == .renew(token), "Malformed reply prevented bounded retry")
    expiry.requests.last!.1(nil)
    expiry.clock = 105; expiry.fire(0.25)
    try check(expiry.requests.last?.0 == .status && !expiry.active, "Recovery extended the five-second lease or kept responsiveness active indefinitely")
    try check(expiry.requests.filter { $0.0 == .change(true) }.count == 1, "Recovery silently re-enabled an expired session")

    let stopped = LidSessionFixture()
    stopped.session.change(true) { _ in }
    stopped.requests.last!.1(try stopped.response(armed: true, token: token))
    stopped.session.refresh()
    stopped.requests.last!.1(try stopped.response(armed: false, token: nil, error: "Sleep interrupted the session"))
    stopped.session.refresh()
    try check(stopped.requests.last?.0 == .status && !stopped.active, "Helper stop did not discard renewal authority")

    let changed = LidSessionFixture()
    changed.session.change(true) { _ in }
    changed.requests.last!.1(try changed.response(armed: true, token: token))
    changed.session.refresh()
    changed.requests.last!.1(try changed.response(armed: true, token: UUID().uuidString))
    try check(changed.published == nil && !changed.active, "A different session was silently adopted")

    let invalid = LidSessionFixture()
    var failures = 0
    invalid.session.change(true) { if case .failure = $0 { failures += 1 } }
    invalid.requests.last!.1(try invalid.response(armed: true, token: "invalid"))
    invalid.fire(3)
    try check(failures == 1 && !invalid.active && !invalid.changing, "Invalid session token or duplicate completion was accepted")
    // Exercise the actual queue/timer adapter while the UI thread is blocked.
    // Inject the entire transport so no production helper can be contacted.
    let renewed = DispatchSemaphore(value: 0)
    let queueLock = NSLock()
    var renewals = 0
    var sentOnMain = false
    var client: LidGuardClient? = LidGuardClient(transport: { request, reply in
        queueLock.withLock { sentOnMain = sentOnMain || Thread.isMainThread }
        let armed: Bool
        switch request {
        case .change(let enabled): armed = enabled
        case .renew:
            armed = true
            let count = queueLock.withLock { renewals += 1; return renewals }
            if count >= 2 { renewed.signal() }
        case .status: armed = false
        }
        reply(try? JSONEncoder().encode(LidGuardReply(status: .init(updatedAt: LidGuardClock.now, armed: armed, detail: "Injected helper"), token: armed ? token : nil)))
    })
    client!.change(true) { _ in }
    client!.start()
    let heartbeatContinued = renewed.wait(timeout: .now() + 4) == .success
    client = nil
    try check(heartbeatContinued && queueLock.withLock { !sentOnMain }, "Lid renewal still depends on the blocked UI thread")
    print("PASS: lid session timeout recovery, bounded renewal authority, malformed and late replies, explicit disable, helper stop, token mismatch, exactly-once completion; injected transport and time only")
}
