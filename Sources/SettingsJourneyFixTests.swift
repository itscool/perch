import AppKit

private final class JourneyMonitorBackend: MonitorCommandBackend {
    func run(_ arguments: [String]) throws -> Data { throw AppError(message: "Unexpected hardware request in journey fixture") }
}

func runSettingsJourneyFixTests() throws {
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    defer { host.modalTestDriver = nil; host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); host.pages = [] }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func flush() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
    func button(_ title: String) -> NSButton? {
        let result = host.pages.last?.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == title }
        if result == nil { fputs("Fixture missing button: " + title + " on " + (host.pages.last?.title ?? "no page") + "\n", stderr) }
        return result
    }
    let app = AppDelegate(); app.buildMenu(); app.configureSettings()
    var callbacks: [(Result<String, Error>) -> Void] = [], scopes: [Bool] = []
    let reset = PrivacyResetOperation { scope, complete in scopes.append(scope); callbacks.append(complete) }
    app.privacyOnlyReset(global: false, operation: reset)
    button("Reset Perch’s privacy permissions")!.performClick(nil)
    try check(scopes == [false] && reset.runningScope == false && !host.detail.stringValue.contains("Back cancels"), "Reset start or running copy is incorrect")
    host.goBack(); app.privacyOnlyReset(global: true, operation: reset)
    try check(button("Reset all apps’ privacy permissions")?.isEnabled == false, "A second reset can overlap the first")
    host.goBack()
    callbacks[0](.failure(AppError(message: "Fixture partial failure")))
    app.privacyOnlyReset(global: false, operation: reset)
    try check(button("Retry privacy reset")?.isEnabled == true, "Failure was lost on leaving/reopening")
    button("Retry privacy reset")!.performClick(nil)
    callbacks[0](.success("Stale completion"))
    try check(reset.runningScope == false, "An old completion ended a new reset")
    host.goBack(); callbacks[1](.success("✓ Fixture reset completed"))
    app.privacyOnlyReset(global: false, operation: reset); flush()
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "✓ Fixture reset completed" }, "Completed reset disappeared on return")
    try check(button("Start another reset…") != nil && host.heading.stringValue == "Privacy reset completed", "Success did not transition to a result")
    button("Start another reset…")!.performClick(nil)
    try check(scopes.count == 2 && button("Reset Perch’s privacy permissions") != nil, "Starting another proposal immediately repeated the reset")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-privacy-result.png")
    host.goBack()

    for titles in [["OK"], ["Apply Updates", "Cancel"], ["Cancel", "Terminate agents"], ["Check setup & status", "Back"], ["Do something"]] {
        let alert = NSAlert(); alert.messageText = "Fixture alert"
        titles.forEach { alert.addButton(withTitle: $0) }
        var correct = false
        host.modalTestDriver = { _ in
            let controls = host.container.subviews.first!.subviews.compactMap { $0 as? NSButton }
            let expected = titles.enumerated().filter { !["OK", "Cancel", "Back"].contains($0.element) }
            correct = controls.map(\.title) == expected.map(\.element) && controls.map(\.tag) == expected.map { 1000 + $0.offset }
            return host.cancelCode
        }
        let response = host.run(alert)
        try check(correct, "Shared alert duplicated navigation or changed action indices")
        if titles == ["Do something"] { try check(response == .abort, "Closing an action-only alert approved its action") }
    }
    host.modalTestDriver = nil

    app.keyboardSettings(); app.keyboardDetails()
    let route = host.pages.map(\.title)
    var keyboardChanges = 0
    app.keyboardActionTestDriver = { _, _ in keyboardChanges += 1 }
    // Enable only injected controls here; this tests navigation, not live device availability.
    for title in ["F1–F12 directly", "Swap Control and Command"] {
        for index in 0..<2 {
            let control = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter { $0.title == title }[index]
            control.isEnabled = true; control.performClick(nil)
            try check(host.pages.map(\.title) == route, "Keyboard detail change pushed another page")
        }
    }
    try check(keyboardChanges == 4, "Not all four keyboard detail actions reached their injected writer")
    host.goBack(); host.goBack()

    let suite = "perch-journey-fixture." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let display = MonitorDescriptor(id: "11111111-1111-1111-1111-111111111111", displayID: 99, name: "Fixture display", vendor: 7789, model: 30470, ddcAvailable: true)
    let controller = MonitorInputController(displays: [display], backend: JourneyMonitorBackend(), defaults: defaults)
    controller.plan.display = display.id
    controller.plan.inputs = [.init(code: 17, name: "HDMI"), .init(code: 15, name: "DisplayPort")]
    var group = MonitorGroup(); group.destinations = (1...3).map { .init(name: "Computer \($0)", inputs: [:]) }
    let editor = MonitorGroupEditor(controller, group: group); editor.show()
    host.contentScroll.contentView.scroll(to: .zero)
    let add = button("Add destination")!; add.performClick(nil)
    try check(editor.draft.destinations.count == 4, "Add destination did not retain its draft")
    let field = host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Destination name, for example Mac mini" && $0.stringValue.isEmpty }!
    try check(!field.visibleRect.isEmpty, "New destination was not revealed after rebuilding the editor")
    field.stringValue = "New Mac"
    host.contentScroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
    let offset = host.container.bounds.height - host.contentScroll.contentSize.height - host.contentScroll.contentView.bounds.minY
    let include = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "group.member." + display.id }!
    include.performClick(nil)
    let newOffset = host.container.bounds.height - host.contentScroll.contentSize.height - host.contentScroll.contentView.bounds.minY
    try check(abs(newOffset - offset) < 2 && editor.draft.destinations.last?.name == "New Mac", "Including a display lost position or unsaved destination text")
    host.goBack()

    let monitorPage = MonitorInputPage(controller); monitorPage.show()
    var tokens: [MonitorProbeCancellation] = [], probes: [(MonitorProbeResult) -> Void] = []
    monitorPage.probeTestDriver = { token, complete in tokens.append(token); probes.append(complete) }
    button("Identify this Mac’s input…")!.performClick(nil)
    button("Find this Mac automatically")!.performClick(nil)
    button("Stop test")!.performClick(nil)
    try check(tokens[0].cancelled, "Stop did not cancel the active probe")
    probes[0](.init(lines: ["Stopped fixture"], cancelled: true))
    button("Retry automatic identification")!.performClick(nil)
    try check(tokens.count == 2 && !tokens[1].cancelled && tokens[0] !== tokens[1], "Retry reused a cancelled probe")
    probes[1](.init(lines: ["Ambiguous fixture"]))
    try check(button("Retry automatic identification")?.isEnabled == true && button("Save as this Mac’s input")?.isEnabled == false, "Ambiguous result cannot retry or can be saved as identified")
    button("Retry automatic identification")!.performClick(nil)
    let input = controller.plan.inputs[0]
    probes[2](.init(lines: ["Suggested fixture"], suggested: input, showing: input))
    button("Save as this Mac’s input")!.performClick(nil)
    try check(controller.plan.macInput == 17 && !controller.plan.allowUnconfirmedCycle && host.pages.last?.title == "Monitor inputs", "Confirmed mapping changed an unrelated cycling preference or failed to return")
    try check(monitorPage.status.stringValue.contains("Saved: this Mac uses HDMI") && button("Change this Mac’s input…") != nil, "Saved mapping did not become a durable ready state")
    host.goBack(); let reopened = MonitorInputPage(controller); reopened.show()
    try check(reopened.status.stringValue.contains("Saved: this Mac uses HDMI") && reopened.currentStatus.stringValue.lowercased().contains("unknown"), "Saved mapping was lost or mistaken for current input evidence")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-monitor-mapping-ready.png")
    host.goBack()

    app.awakeItem.state = .off; app.lidItem.state = .off; app.applyLidSleepPresentation(); app.menu.update()
    try check(!app.lidItem.isEnabled, "Native menu validation re-enabled a disabled lid row")
    app.awakeItem.state = .mixed; app.lidItem.state = .mixed; app.applyLidSleepPresentation(); app.menu.update()
    try check(!app.lidItem.isEnabled && !app.awakeItem.isEnabled, "Native validation re-enabled unknown sleep controls")
    app.trackpadItem.state = .off; app.wheelItem.state = .on
    app.refreshScrolling(input: .init(trusted: true, active: false), checking: false)
    app.menu.update()
    try check(app.trackpadItem.action == #selector(AppDelegate.toggleTrackpad) && app.wheelItem.isEnabled && app.menuTitleSources[app.wheelItem]?.string.contains("not running") == true, "Scrolling used guardian readiness or hid inactive input")
    app.refreshScrolling(input: nil, checking: true); app.menu.update()
    try check(!app.trackpadItem.isEnabled && app.wheelItem.isEnabled && app.wheelItem.action == #selector(AppDelegate.toggleWheel), "Pending input allows a new choice or prevents turning off a saved one")
    app.refreshSafety(status: nil, config: SafetyConfiguration(), checking: true)
    app.menu.update()
    try check(!app.safetyResumeItem.isHidden && !app.safetyResumeItem.isEnabled, "Cold helper check prematurely hid or enabled Resume")
    try check(app.currentProtectionIssue == nil && app.menuTitleSources[app.safetyItem]?.string.contains("Checking") == true, "Cold helper read was reported offline")
    app.refreshSafety(status: nil, config: SafetyConfiguration(), checking: false)
    try check(app.currentProtectionIssue != nil && app.menuTitleSources[app.safetyItem]?.string.contains("offline") == true, "Failed helper read remained checking")
    print("PASS: privacy leave/result/retry and cross-scope exclusion; shared alert exits/action indices; four keyboard detail routes; group scroll/draft preservation; monitor stop/retry/fresh token and saved mapping; native sleep and scrolling validation; cold/failed helper presentation. All mutations injected.")
}
