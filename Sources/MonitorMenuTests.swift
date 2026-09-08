import AppKit

/// Delayed metadata replies reproduce first-paint and disconnect races without
/// querying a real display, sending DDC, or changing live preferences.
private final class MonitorMenuBackend: MonitorCommandBackend {
    let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reply: Result<Data, Error> = .success(Data("[]".utf8))
    private var recorded: [[String]] = []
    var commands: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
    func respond(_ displays: [MonitorDescriptor]?) throws {
        let value: Result<Data, Error> = try displays.map { .success(try JSONEncoder().encode($0)) }
            ?? .failure(AppError(message: "Fixture metadata unavailable"))
        lock.lock(); reply = value; lock.unlock()
    }
    func run(_ arguments: [String]) throws -> Data {
        lock.lock(); recorded.append(arguments); let result = reply; lock.unlock()
        guard arguments == ["list"] else { throw AppError(message: "Menu attempted a non-metadata command") }
        guard gate.wait(timeout: .now() + 5) == .success else { throw AppError(message: "Fixture reply timed out") }
        return try result.get()
    }
}

func runMonitorMenuTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func wait(in mode: RunLoop.Mode = .default, _ ready: () -> Bool) throws {
        let end = Date().addingTimeInterval(3)
        while !ready() && Date() < end { RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.005)) }
        try check(ready(), "Monitor menu fixture did not finish")
    }
    let suite = "local.perch.monitor-menu-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let display = MonitorDescriptor(id: UUID().uuidString, displayID: 99, name: "Fixture", vendor: 1, model: 1, ddcAvailable: true)
    let backend = MonitorMenuBackend()
    let monitor = MonitorInputController(backend: backend, defaults: defaults)
    monitor.plan.display = display.id
    monitor.plan.inputs = [.init(code: 17, name: "HDMI"), .init(code: 15, name: "DisplayPort")]
    let app = AppDelegate(monitorInputs: monitor)
    app.checkedStartupInputAccess = true
    app.buildMenu()
    defer { app.menuDidClose(app.menu); monitor.onChange = nil }
    let item = app.monitorInputItem!, row = item.view as! MenuRowView
    var publishedEnabled: [Bool] = []
    monitor.onChange = { [weak app] in
        app?.refreshMonitorInputItem()
        publishedEnabled.append(app?.monitorInputItem.isEnabled == true)
    }
    func blocked() throws {
        app.menu.update() // Include AppKit's automatic validation, not just isEnabled.
        try check(!item.isEnabled && !app.validateMenuItem(item) && !row.isAccessibilityEnabled() && !row.accessibilityPerformPress(), "Unchecked monitor control became actionable")
        try check(row.displayedText().string.contains("Checking monitors…"), "Pending availability is unexplained")
    }
    func finish(in mode: RunLoop.Mode = .default) throws { backend.gate.signal(); try wait(in: mode) { !monitor.busy && !monitor.checkingDisplays } }

    try blocked() // Before startup has had time to check anything.
    try backend.respond([display])
    app.menuWillOpen(app.menu)
    try blocked()
    monitor.refresh() // Reopening during discovery shares the in-flight request.
    try wait { backend.commands.count == 1 }
    try finish(in: .eventTracking)
    try check(backend.commands.count == 1 && item.isEnabled && item.action == #selector(AppDelegate.cycleMonitorInput), "Confirmed metadata did not enable the cycle or discovery was duplicated")

    // Reopening checks again before the first visible frame, including on a Mac
    // where the saved monitor is no longer connected.
    app.menuDidClose(app.menu)
    try backend.respond([])
    app.menuWillOpen(app.menu)
    try blocked(); try finish()
    try check(item.isEnabled && item.action == #selector(AppDelegate.monitorInputSettings) && !monitor.canCycle, "Missing monitor did not retain a truthful Settings route")

    // An old successful reply must never override a newer disconnect signal.
    try backend.respond([display]); monitor.refresh()
    try wait { backend.commands.count == 3 }
    monitor.screensChanged()
    publishedEnabled = []
    try backend.respond([]); backend.gate.signal()
    try wait { backend.commands.count == 4 }
    try check(!publishedEnabled.contains(true), "A superseded reply briefly re-enabled monitor controls")
    try blocked(); try finish()
    try check(monitor.displays.isEmpty && !monitor.canCycle, "Stale topology survived the newer check")

    // Debounce itself is unsafe to treat as ready, even before any job is busy.
    try backend.respond([display]); monitor.refresh(); try finish()
    monitor.screensChanged()
    try check(!monitor.busy && !monitor.canCycle, "Screen-change debounce retained stale cycle readiness")
    try blocked()
    monitor.refresh(); try finish() // Menu open bypasses the debounce delay.

    // Failure clears previously discovered DDC routes and points to recovery.
    try backend.respond(nil); monitor.refresh(); try finish()
    try check(monitor.displays.isEmpty && !monitor.canCycle && monitor.warning && item.action == #selector(AppDelegate.monitorInputSettings), "Failed discovery retained stale monitor readiness")

    // A menu opened during another operation queues discovery without publishing
    // an enabled state between that operation and the metadata request.
    let operation = DispatchSemaphore(value: 0)
    defer { operation.signal() }
    monitor.perform({ _ = operation.wait(timeout: .now() + 3) }) { _ in }
    try backend.respond([display]); monitor.refresh(); publishedEnabled = []
    let beforeQueued = backend.commands.count
    operation.signal()
    try wait { backend.commands.count == beforeQueued + 1 }
    try check(!publishedEnabled.contains(true), "Queued metadata check published a usable gap")
    try blocked(); try finish()
    try check(!monitor.warning && item.action == #selector(AppDelegate.cycleMonitorInput), "Recovered discovery left cycling stuck behind the old error")

    // Groups use the same readiness gate and keep missing members in Settings.
    var group = MonitorGroup()
    group.members = [.init(display: display.id, name: display.name)]
    group.destinations = [.init(name: "Laptop", inputs: [display.id: 17]), .init(name: "Desktop", inputs: [display.id: 15])]
    try monitor.groups.save(.init(groups: [group], activeID: group.id))
    try check(monitor.groups.canCycle && item.action == #selector(AppDelegate.cycleMonitorInput), "Ready group was not available")
    try backend.respond([]); monitor.refresh(); try blocked(); try finish()
    try check(!monitor.groups.canCycle && item.action == #selector(AppDelegate.monitorGroupSettings), "Missing group member remained cycle-ready")

    // A saved USB/LAN control route remains usable when video is on another Mac.
    var route = monitor.plan; route.controlConnection = .init(kind: "msi-usb", endpoint: "fixture:serial:1")
    try monitor.save(route)
    try check(monitor.canCycle && monitor.groups.canCycle, "Inactive video incorrectly removed the independent control route")
    try check(backend.commands.allSatisfy { $0 == ["list"] }, "Opening or validating a menu attempted an input read/write")
    print("PASS: monitor menu first paint, native/accessible validation, re-entry, discovery coalescing, disconnect debounce, stale replies, failure, queued checks, group availability and inactive-video routes; mock metadata only")
}
