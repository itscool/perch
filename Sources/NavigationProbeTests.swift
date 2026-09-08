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
    let app = AppDelegate(); app.configureSettings()
    let identity = host.window.windowNumber
    let knownIdentity = NavigationKeyboardIdentity(vendor: 1133, product: 45915, version: 19, name: "MX Keys", transport: "Bluetooth Low Energy", usages: [74,75,77,78])
    let knownKeyboard = NavigationProbeKeyboard(id: 420, name: knownIdentity.name, transport: knownIdentity.transport, identity: knownIdentity)
    let known = NavigationProbePage(enumerate: { [knownKeyboard] }, hasAccess: { false },
        saveProfile: { _ in throw AppError(message: "Recognized keyboard unexpectedly saved a learned layout") }, readProfiles: { [] })
    known.show()
    try check(known.instruction.stringValue == "Layout ready — no setup needed." && known.rows.allSatisfy { $0.stringValue.contains("— recognized") }, "Known layout still presents unidentified-key setup")
    try check(!known.permission.stringValue.contains("⚠") && known.permission.stringValue.contains("different layout") && known.timer == nil, "Known layout requires input access or starts listening")
    host.goBack()
    let learnedIdentity = NavigationKeyboardIdentity(vendor: 1234, product: 123, version: 1, name: "Mock keyboard", transport: "USB", usages: NavigationLearning.usages.sorted())
    let keyboard = NavigationProbeKeyboard(id: 42, name: learnedIdentity.name, transport: learnedIdentity.transport, identity: learnedIdentity)
    let previous = NavigationKeyboardProfile(identity: learnedIdentity, keys: [0x68,0x69,0x6A,0x6B])
    var profiles = [previous], saves = 0, failSave = false, now: TimeInterval = 100
    let page = NavigationProbePage(enumerate: { [keyboard] }, hasAccess: { true }, saveProfile: { profile in
        saves += 1
        if failSave { throw AppError(message: "Storage unavailable.") }
        profiles = [profile]
    }, readProfiles: { profiles }, now: { now })
    page.show()
    func visibleButtons() -> [NSButton] { page.view.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden } }
    try check(host.pages.count == 2 && host.window.windowNumber == identity && page.timer == nil, "Opening navigation test changed window or began listening")
    let source = MockNavigationProbeSource()
    page.setupIdentity = learnedIdentity
    page.session.start(deviceID: 42, source: source, guided: true)
    try check(page.timer != nil && host.back.title == "Back", "Active test lacks timeout or shared Back")
    try check(visibleButtons().filter { $0.isEnabled }.map { $0.title } == ["I don’t have Home"], "Active learning has ambiguous acceptance/cancellation controls")
    source.pressAndRelease(.home)
    try check(page.rows[0].stringValue.hasPrefix("✓") && saves == 0 && profiles == [previous], "Partial learning changed the saved layout")
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        host.window.appearance = NSAppearance(named: appearance)
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-navigation-test-\(suffix).png")
    }
    source.pressAndRelease(.end); source.pressAndRelease(.pageUp)
    source.value?(42, 7, NavigationKey.pageDown.rawValue, 1)
    try check(saves == 0, "Final press saved before its release")
    source.value?(42, 7, NavigationKey.pageDown.rawValue, 0)
    try check(page.timer == nil && source.stops == 1 && saves == 1 && profiles[0].keys == [74,77,75,78], "Completed layout did not save automatically once and stop input")
    try check(page.status.stringValue.contains("saved automatically") && visibleButtons().isEmpty && host.back.title == "Back", "Completed setup has an extra accept/cancel button or unclear save status")
    try check(host.detail.stringValue.contains("Mock keyboard") && host.detail.stringValue.contains("is saved") && !host.detail.stringValue.contains("Press and release"), "Completed setup retains instructions to keep learning")
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        host.window.appearance = NSAppearance(named: appearance)
        try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-navigation-saved-\(suffix).png")
    }
    page.session.tick()
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: host.window)
    host.goBack()
    try check(saves == 1 && profiles[0].keys == [74,77,75,78], "Refresh or Back resaved or discarded a completed layout")
    let reopened = NavigationProbePage(enumerate: { [keyboard] }, hasAccess: { false }, saveProfile: { _ in saves += 1 }, readProfiles: { profiles })
    reopened.show()
    try check(reopened.rows.allSatisfy { $0.stringValue.contains("recognized") } && saves == 1, "Reopening forgot the automatically saved layout")
    host.goBack()

    page.show()
    let restarted = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: restarted, guided: true)
    restarted.pressAndRelease(.home)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: host.window)
    try check(restarted.stops == 1 && page.timer == nil && saves == 1, "Focus loss retained input or saved an unfinished replacement")
    let timeout = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: timeout, guided: true)
    timeout.pressAndRelease(.home); now += 61; page.session.tick()
    try check(timeout.stops == 1 && saves == 1 && profiles[0].keys == [74,77,75,78] && page.session.state.phase == .incomplete && page.status.stringValue.contains("kept"), "Timeout saved a partial layout or lost recovery guidance")
    let interrupted = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: interrupted, guided: true)
    interrupted.pressAndRelease(.home); host.goBack()
    try check(host.pages.count == 1 && page.timer == nil && interrupted.stops == 1 && saves == 1, "Back did not stop unfinished setup without saving")

    page.show(); failSave = true
    let failed = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: failed, guided: true)
    for usage: UInt32 in [0x68,0x69,0x6A,0x6B] { failed.value?(42,7,usage,1); failed.value?(42,7,usage,0) }
    try check(saves == 2 && profiles[0].keys == [74,77,75,78] && page.status.stringValue.contains("previous layout is still in use"), "Failed autosave discarded the old layout or claimed success")
    try check(visibleButtons().map { $0.title } == ["Retry saving"], "Failed save has ambiguous recovery controls")
    page.session.tick()
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: host.window)
    try check(saves == 2, "Failed autosave retried on every refresh")
    failSave = false
    visibleButtons().first!.performClick(nil)
    try check(saves == 3 && profiles[0].keys == [0x68,0x69,0x6A,0x6B] && visibleButtons().isEmpty && page.status.stringValue.contains("saved automatically"), "Retry did not recover the completed layout")
    host.goBack()

    page.show()
    let absent = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: absent, guided: true)
    for index in 0..<4 {
        visibleButtons().first { $0.title.hasPrefix("I don’t have") }!.performClick(nil)
        try check(saves == (index == 3 ? 4 : 3), "Absent-key setup saved before all four answers")
    }
    try check(profiles[0].keys == [nil,nil,nil,nil] && page.timer == nil && absent.stops == 1, "All-absent layout did not save and stop")
    host.goBack()
    page.show()
    let closing = MockNavigationProbeSource()
    page.session.start(deviceID: 42, source: closing, guided: true)
    closing.pressAndRelease(.home)
    host.window.appearance = nil
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    try check(closing.stops == 1 && page.timer == nil && saves == 4, "Window close saved an unfinished layout")

    app.configureSettings()
    var preferences = NavigationPreferences(), exceptionSaves = 0, rejectException = false
    preferences.homeEnd = true; preferences.excludedApps = ["test.app", "preserved.app"]
    app.showNavigationExceptions(load: { preferences }, save: { id, excluded in
        exceptionSaves += 1
        if rejectException { throw AppError(message: "Storage unavailable.") }
        preferences.excludedApps.removeAll { $0 == id }
        if excluded { preferences.excludedApps.append(id) }
    })
    let exceptionsView = host.pages.last!.view
    let exceptionScroll = exceptionsView.subviews.compactMap { $0 as? NSScrollView }.first!
    let checkbox = exceptionScroll.documentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "test.app" }!
    checkbox.performClick(nil)
    try check(exceptionSaves == 1 && !preferences.excludedApps.contains("test.app") && preferences.excludedApps.contains("preserved.app") && preferences.homeEnd, "Exception checkbox did not save its own choice immediately")
    try check(exceptionsView.subviews.compactMap { $0 as? NSButton }.isEmpty && host.back.title == "Back", "Exception page retains a separate Save/Cancel action")
    rejectException = true; checkbox.performClick(nil)
    try check(exceptionSaves == 2 && checkbox.state == .off && !preferences.excludedApps.contains("test.app"), "Failed exception save left an unsaved checkmark")
    try check(exceptionsView.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Not saved") }, "Failed exception save lacks inline recovery")
    host.goBack()
    try check(exceptionSaves == 2, "Back tried to save app exceptions again")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    print("PASS: navigation setup autosaves exactly once after the final release/absence; Back-only completion; previous layout survives partial setup, timeout, focus loss and close; save failure/retry and reopen; light/dark fixture renders")
}
