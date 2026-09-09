import Foundation

private final class KeyboardRefreshFixture {
    let lock = NSLock()
    let gate = DispatchSemaphore(value: 0)
    var requests: [KeyboardModeMonitor.Scan] = []
    var standard = true
    var count: Int { lock.withLock { requests.count } }
    func scan(_ request: KeyboardModeMonitor.Scan) -> KeyboardModeMonitor.Result {
        let number = lock.withLock { requests.append(request); return requests.count }
        if number == 2 { _ = gate.wait(timeout: .now() + 5) }
        return lock.withLock {
            if let desired = request.builtIn { standard = desired }
            return .init(standard: standard, results: [.init(name: "Fixture keyboard", detail: "Confirmed", verified: true, standard: standard)],
                         registrations: request.scanNavigation ? [] : nil)
        }
    }
}

func runKeyboardRefreshTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func wait(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try check(condition(), "Keyboard refresh fixture timed out")
    }
    let fixture = KeyboardRefreshFixture()
    defer { fixture.gate.signal() }
    let monitor = KeyboardModeMonitor(scan: fixture.scan)
    monitor.started = true // Injected scans only; no device observer or real HID I/O.
    monitor.queue(navigationChanged: true)
    try check(monitor.blocksFunctionKeyChanges, "Unknown initial keyboard state appeared usable")
    try wait { fixture.count == 1 && !monitor.working }
    try check(!monitor.blocksFunctionKeyChanges && monitor.results.first?.standard == true, "Initial confirmed keyboard result remained blocked")
    var changes = 0
    monitor.onChange = { changes += 1 }
    monitor.readForPresentation()
    try check(!monitor.blocksFunctionKeyChanges && changes == 0, "Routine debounce disabled or republished unchanged controls")
    try wait { fixture.count == 2 }
    try check(!monitor.blocksFunctionKeyChanges && monitor.results.first?.standard == true && changes == 0, "In-flight routine read hid confirmed state")
    monitor.setBuiltIn(false)
    try check(monitor.blocksFunctionKeyChanges && changes > 0, "Actual queued change was not distinguished from a routine read")
    let until = Date().addingTimeInterval(0.5)
    while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    try check(fixture.count == 2, "Keyboard write raced an unfinished read")
    fixture.gate.signal()
    try wait { fixture.count == 3 && !monitor.working }
    try check(!monitor.blocksFunctionKeyChanges && monitor.results.first?.standard == false, "Queued setting was lost or never published its confirmed result")
    let requests = fixture.lock.withLock { fixture.requests }
    try check(requests[1].readOnly && requests[1].builtIn == nil && requests[2].builtIn == false && !requests[2].readOnly, "Routine read and user write crossed transaction boundaries")
    monitor.queue(navigationChanged: true, readOnly: true)
    try check(monitor.blocksFunctionKeyChanges && monitor.registrationPending, "Device invalidation retained stale actionable readiness")
    try wait { !monitor.working }
    print("PASS: routine keyboard reads retain confirmed controls; clicks queue behind reads; initial/device-invalidated state blocks; mock hardware only")
}
