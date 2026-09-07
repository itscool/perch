import AppKit

final class MockNavigationProbeSource: NavigationProbeSource {
    var starts = 0, stops = 0
    var throwOnStart = false
    var value: ((UInt64, UInt32, UInt32, Int) -> Void)?
    var failed: ((String) -> Void)?
    func start(value: @escaping (UInt64, UInt32, UInt32, Int) -> Void, failed: @escaping (String) -> Void) throws {
        starts += 1; self.value = value; self.failed = failed
        if throwOnStart { throw AppError(message: "Mock access denied") }
    }
    // Retain mock callbacks intentionally to simulate late delivery after stop.
    func stop() { stops += 1 }
    func pressAndRelease(_ key: NavigationKey, id: UInt64 = 42) {
        value?(id, 7, key.rawValue, 1); value?(id, 7, key.rawValue, 0)
    }
}

func runNavigationProbeTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    for transport in ["USB", "Bluetooth", "Bluetooth Low Energy"] {
        try check(!NavigationDeviceScope.isExternal(builtIn: true, transport: transport), "Built-in keyboard entered external test")
        try check(NavigationDeviceScope.isExternal(builtIn: false, transport: transport), "Explicit external transport rejected")
    }
    for transport in ["", "Virtual", "SPI", "Unknown"] {
        try check(!NavigationDeviceScope.isExternal(builtIn: nil, transport: transport), "Unidentified device entered external test")
    }
    var now: TimeInterval = 100
    let session = NavigationProbeSession(now: { now })
    let first = MockNavigationProbeSource()
    try check(first.starts == 0 && session.state.phase == .idle, "Diagnostic started without user action")
    session.start(deviceID: 42, source: first)
    first.value?(99, 7, NavigationKey.home.rawValue, 1)
    first.value?(42, 12, NavigationKey.home.rawValue, 1)
    first.value?(42, 7, 0x04, 1) // ordinary typing
    first.value?(42, 7, NavigationKey.home.rawValue, 0) // release without press
    first.value?(42, 7, NavigationKey.home.rawValue, 2) // invalid value
    try check(session.state.keys.allSatisfy { !$0.pressed }, "Other device, typing, or invalid report entered diagnostic")
    first.value?(42, 7, NavigationKey.home.rawValue, 1)
    first.value?(42, 7, NavigationKey.home.rawValue, 1)
    try check(session.state.keys[0].held && !session.state.keys[0].complete, "A repeat counted as release")
    first.value?(42, 7, NavigationKey.home.rawValue, 0)
    for key in NavigationKey.allCases where key != .home { first.pressAndRelease(key) }
    try check(session.state.phase == .complete && first.stops == 1, "Successful test retained input subscription")
    session.tick(); session.stop("done")
    try check(first.stops == 1, "Source closed more than once")

    let second = MockNavigationProbeSource()
    session.start(deviceID: 42, source: second)
    first.pressAndRelease(.home); first.failed?("stale disconnect")
    try check(session.state.listening && !session.state.keys[0].pressed, "Old callback corrupted restarted test")
    now = 130
    second.pressAndRelease(.home)
    try check(session.state.phase == .incomplete && second.stops == 1, "Late event bypassed timeout")
    let third = MockNavigationProbeSource()
    session.start(deviceID: 42, source: third)
    now = 161; session.tick()
    try check(session.state.phase == .incomplete && third.stops == 1, "Idle timeout retained input subscription")

    for reason in ["Cancelled", "Focus lost", "Input Monitoring revoked", "Page closed"] {
        let source = MockNavigationProbeSource()
        session.start(deviceID: 42, source: source); session.stop(reason)
        source.pressAndRelease(.home)
        try check(session.state.phase == .stopped(reason) && source.stops == 1 && !session.state.keys[0].pressed, "Stop or late callback failed: \(reason)")
    }
    let disconnected = MockNavigationProbeSource()
    session.start(deviceID: 42, source: disconnected); disconnected.failed?("Disconnected")
    try check(disconnected.stops == 1 && session.state.phase == .stopped("Disconnected"), "Disconnect retained subscription")
    let denied = MockNavigationProbeSource(); denied.throwOnStart = true
    session.start(deviceID: 42, source: denied)
    try check(denied.stops == 1 && !session.state.listening, "Failed open retained subscription")
    let invalid = MockNavigationProbeSource()
    session.start(deviceID: 0, source: invalid)
    try check(invalid.starts == 0 && !session.state.listening, "Unknown device identity opened input")
    let destroyed = MockNavigationProbeSource()
    var temporary: NavigationProbeSession? = NavigationProbeSession()
    temporary?.start(deviceID: 42, source: destroyed); temporary = nil
    try check(destroyed.stops == 1, "Session destruction retained subscription")
    print("PASS: external navigation diagnostic device isolation; no typing; press/release; bounded state; stale callbacks; timeout, cancel, disconnect and cleanup; mock sources only")
}

func runNavigationProbeUITests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true
    AppDelegate().configureSettings()
    let identity = host.window.windowNumber
    let page = NavigationProbePage(enumerate: { [] }, hasAccess: { true })
    page.show()
    try check(host.pages.count == 2 && host.window.windowNumber == identity && page.timer == nil, "Opening navigation test changed window or began listening")
    let source = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: source)
    try check(page.timer != nil, "Active test lacks timeout timer")
    source.pressAndRelease(.home)
    try check(page.rows[0].stringValue.hasPrefix("✓"), "Received navigation key lacks explicit confirmation")
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        host.window.appearance = NSAppearance(named: appearance)
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-navigation-test-\(suffix).png")
    }
    for key in NavigationKey.allCases where key != .home { source.pressAndRelease(key) }
    try check(page.timer == nil && source.stops == 1 && page.status.stringValue.contains("Test stopped"), "Successful test lacks visible result or retained timer")
    let restarted = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: restarted)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: host.window)
    try check(restarted.stops == 1 && page.timer == nil, "Leaving test window retained subscription")
    let final = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: final)
    host.goBack()
    try check(host.pages.count == 1 && page.timer == nil && final.stops == 1, "Back did not stop test or return to Settings")
    host.window.appearance = nil
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    print("PASS: navigation diagnostic stays in Settings, starts only explicitly, shows receipt, stops on success/focus loss/Back; light/dark rendered with synthetic input")
}
