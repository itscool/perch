import AppKit

private final class ReleaseBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill(); bounds.fill()
        }
    }
}

/// Render app-owned views without desktop capture or changes to the user's theme.
func renderReleaseView(_ content: NSView, path: String, prepare: ((NSAppearance) -> Void)? = nil) throws {
    let wrapper = ReleaseBackground(frame: content.bounds)
    let window = NSWindow(contentRect: wrapper.bounds, styleMask: [], backing: .buffered, defer: false)
    window.contentView = wrapper
    let children = content.subviews
    for child in children { wrapper.addSubview(child) }
    defer { for child in children { content.addSubview(child) } }
    for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let appearance = NSAppearance(named: name)!
        window.appearance = appearance; wrapper.appearance = appearance
        prepare?(appearance)
        wrapper.layoutSubtreeIfNeeded()
        guard let bitmap = wrapper.bitmapImageRepForCachingDisplay(in: wrapper.bounds) else {
            throw AppError(message: "Could not render release view")
        }
        appearance.performAsCurrentDrawingAppearance { wrapper.cacheDisplay(in: wrapper.bounds, to: bitmap) }
        let destination = path.replacingOccurrences(of: ".png", with: "-\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: destination))
    }
}

private final class ReleaseTrackingMenu: NSMenu {
    var dismissals = 0
    override func cancelTracking() { dismissals += 1; super.cancelTracking() }
}

private final class ReleaseToggleTarget: NSObject, NSMenuItemValidation {
    var allowed = true
    var presses = 0
    @objc func toggle(_ item: NSMenuItem) { presses += 1; item.state = item.state == .on ? .off : .on }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { allowed }
}

func runReleaseUITests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true
    defer { host.modalTestDriver = nil; host.window.close() }
    var config = SafetyConfiguration(); config.reverseWheel = true
    var state = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: true, inputActive: true, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
    let setup = PermissionSetup()
    setup.refresh(state: state, config: config)
    try check(setup.status.stringValue.hasPrefix("✓"), "Ready input is not confirmed")
    state.inputActive = false; setup.refresh(state: state, config: config)
    try check(setup.status.stringValue.hasPrefix("⚠") && ProtectionIssue.assess(state, config: config)?.route == "repair", "Granted but inactive input appeared ready")
    config.reverseWheel = false; config.reverseTrackpad = false; config.swapModifiers = false
    try check(InputReadiness.assess(state, config: config).ready, "Disabled input incorrectly needs an active tap")
    config.reverseWheel = true
    state.inputTrusted = false; setup.refresh(state: state, config: config)
    try check(setup.status.stringValue.contains("Accessibility access") && setup.status.stringValue.hasPrefix("⚠"), "Missing permission is not explicit")
    state.inputTrusted = nil; setup.refresh(state: state, config: config)
    try check(setup.status.stringValue.contains("has not been determined"), "Missing helper was misreported as denied permission")
    state.inputTrusted = true; state.timestamp = Date().addingTimeInterval(-10)
    setup.refresh(state: state, config: config)
    try check(setup.status.stringValue.hasPrefix("⚠"), "Stale input stayed green")

    // Drive the actual shortcut dialogs with isolated status/requests. No OS key
    // injection, production test lease, target signals, or privacy reset occurs.
    let flowApp = AppDelegate()
    flowApp.configureSettings(); flowApp.configurePanic()
    let pageCount = host.pages.count
    for scenario in ["cancel", "success", "timeout"] {
        var fake = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: false, inputTrusted: true, inputActive: true, keepAwakeActive: false, trackedCount: 0, targets: [], message: "", error: nil)
        var actions: [String] = []
        var messages: [String] = []
        var sawReady = false
        host.modalTestDriver = { alert in
            messages.append(alert.messageText)
            if alert.messageText == "Test shortcut" && scenario == "cancel" { return .alertFirstButtonReturn }
            let duration: TimeInterval = alert.messageText == "Test shortcut" && scenario == "timeout" ? 10.4 : 0.35
            if alert.messageText == "Test shortcut" && scenario == "success" { fake.testResultID = UUID().uuidString }
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.025))
                sawReady = sawReady || alert.informativeText.hasPrefix("Press ")
            }
            if alert.messageText == "Test shortcut" {
                return NSApplication.ModalResponse(rawValue: scenario == "success" ? 2101 : 2102)
            }
            return .alertFirstButtonReturn
        }
        flowApp.runShortcutTest(readStatus: { fake.timestamp = Date(); return fake }, send: { action in
            actions.append(action)
            if action == "test" { fake.testUntil = scenario == "cancel" ? nil : Date().addingTimeInterval(30) }
            if action == "finish-test" { fake.testUntil = nil }
        }, keepAlive: {})
        try check(actions == ["test", "finish-test"] && fake.testUntil == nil && !fake.shortcutActive, "Shortcut test did not restore the original disabled state")
        try check(host.pages.count == pageCount && host.pages.last?.title == "Agent Kill Switch", "Shortcut test did not return to Agent Kill Switch")
        try check(messages.contains("Ending shortcut test…"), "Shortcut test skipped cleanup confirmation")
        if scenario == "success" { try check(messages.contains("Shortcut worked"), "Shortcut success was not reported") }
        if scenario == "timeout" { try check(sawReady && messages.contains("No shortcut received"), "Ready/countdown/timeout result missing") }
    }
    host.modalTestDriver = nil
    host.window.close()
    print("PASS: shortcut preparation cancel, success, 10-second timeout, harmless cleanup, return to Agent Kill Switch; isolated helper transport")

    // Exercise the production toggle action route with a harmless local target.
    let target = ReleaseToggleTarget()
    let toggle = NSMenuItem(title: "Test toggle", action: #selector(ReleaseToggleTarget.toggle(_:)), keyEquivalent: "")
    toggle.target = target
    let row = MenuRowView(item: toggle, kind: .toggle)
    try check(row.accessibilityPerformPress() && toggle.state == .on && target.presses == 1, "Toggle action/state failed")
    target.allowed = false
    try check(!row.accessibilityPerformPress() && target.presses == 1, "Disabled toggle remained actionable")


    target.allowed = true
    toggle.state = .mixed
    try check(row.accessibilityValue() as? Int == 2, "Mixed toggle lost its accessible state")
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    row.keyDown(with: key) // Delivered only to this test view, never posted globally.
    try check(target.presses == 2 && toggle.state == .on, "Keyboard toggle route differs from mouse/Accessibility")
    let commandItem = NSMenuItem(title: "Test command", action: #selector(ReleaseToggleTarget.toggle(_:)), keyEquivalent: "")
    commandItem.target = target
    let command = MenuRowView(item: commandItem, kind: .command)
    try check(command.activate() && !command.activate() && target.presses == 2, "Command dispatched before dismissal or accepted twice")
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    try check(target.presses == 3, "Command didn't dispatch once after dismissal")
    commandItem.isEnabled = false
    try check(!command.accessibilityPerformPress(), "Disabled command remained actionable")
    let information = MenuRowView(item: commandItem, kind: .information)
    try check(!information.accessibilityPerformPress() && information.isAccessibilityEnabled(), "Information is actionable or falsely dimmed")

    let authorizationMenu = ReleaseTrackingMenu()
    let authorizationItem = NSMenuItem(title: "Test authorization toggle", action: #selector(ReleaseToggleTarget.toggle(_:)), keyEquivalent: "")
    authorizationItem.target = target
    authorizationMenu.addItem(authorizationItem)
    let authorizationRow = MenuRowView(item: authorizationItem, kind: .toggle)
    authorizationRow.opensAnotherInterface = { true }
    let beforePrompt = target.presses
    try check(authorizationRow.activate() && authorizationMenu.dismissals == 1 && target.presses == beforePrompt, "Authorization started inside menu tracking")
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    try check(target.presses == beforePrompt + 1, "Deferred authorization action didn't run")
    authorizationRow.opensAnotherInterface = { false }
    try check(authorizationRow.activate() && authorizationMenu.dismissals == 1 && target.presses == beforePrompt + 2, "Ordinary toggle unnecessarily dismissed the menu")

    // Read-only native menu refresh; no helper installation or setting changes.
    let app = AppDelegate(); app.checkedStartupInputAccess = true; app.buildMenu()
    let warm = Date().addingTimeInterval(2)
    while Date() < warm { _ = GuardianInstall.status; RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    app.menuWillOpen(app.menu)
    let until = Date().addingTimeInterval(2.5)
    let keepModeAlive = Timer(timeInterval: 0.05, repeats: true) { _ in }
    RunLoop.main.add(keepModeAlive, forMode: .eventTracking)
    while Date() < until { RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05)) }
    keepModeAlive.invalidate()
    let cpu = (app.systemItems[1].view as? MenuRowView)?.text.string ?? ""
    try check(!cpu.contains("--%") && cpu.contains("%"), "CPU did not update while tracking an open menu")
    let lid = (app.lidItem.view as? MenuRowView)?.text.string ?? ""
    try check(app.lidItem.state == .on && app.lidItem.isEnabled ? lid.contains("⚠ Keep ventilated") : (lid.contains("Currently sleeps on lid close") || lid.contains("Applies when Keep awake is on")), "Lid wording disagrees with current state")
    try check(app.menu.items.firstIndex(of: app.loginItem)! < app.menu.items.firstIndex(of: app.safetySettingsItem)!, "Settings not beneath Start at login")
    try check((app.safetyItem.view as? MenuRowView)?.kind == .command && (app.lidItem.view as? MenuRowView)?.kind == .toggle, "Command/toggle menu behavior changed")
    try check(app.swapItem.title.contains("keys"), "Key-swap label regressed")
    try check((app.lidItem.view as! MenuRowView).opensAnotherInterface(), "Lid authorization toggle must close the menu first")
    app.lidItem.state = .on; app.applyLidSleepPresentation()
    try check(app.awakeItem.isEnabled && app.awakeItem.state == .on && app.lidItem.isEnabled, "Lid override did not activate master")
    app.lidItem.state = .off; app.awakeItem.state = .off; app.applyLidSleepPresentation()
    try check(app.awakeItem.isEnabled && !app.lidItem.isEnabled && (app.lidItem.view as! MenuRowView).text.string.contains("Applies when Keep awake is on"), "Master off did not explain disabled lid preference")
    app.refresh()
    let headings = app.menu.items.filter { ($0.view as? MenuRowView)?.kind == .section }.map { $0.title }
    try check(headings.contains("Scrolling") && headings.contains("Built-in keyboard") && headings.contains { $0.hasPrefix("External keyboard") } && !headings.contains("Input"), "Keyboard groups were not split")
    let titles = app.menu.items.map { $0.title }
    try check(headings.contains("Sleep") && headings.contains("Display") && !headings.contains("Power & Display"), "Sleep and Display sections not separated")
    try check(titles.firstIndex(of:"Sleep")! < titles.firstIndex(of:"Keep awake")! && titles.firstIndex(of:"Including with lid closed")! < titles.firstIndex(of:"Display")! && titles.firstIndex(of:"Display")! < titles.firstIndex(of:"Turn display off")!, "Display action is outside Display section")
    try check(!titles.contains("Monitor input settings…"), "Monitor settings duplicated in menu")
    // Use fixture firmware modes; safe UI tests never change physical keyboard modes.
    app.keyboardModes.results = [.init(name: "Test external keyboard", detail: "✓ Firmware mode read", verified: true, standard: false)]
    app.keyboardModes.busy = true // Routine refresh is not a settings transaction.
    app.refreshFunctionKeyItem(true)
    try check(app.externalFnItem.isEnabled, "Routine keyboard refresh disabled known external Fn controls")
    try check(app.fnItem.isEnabled == app.nativeKeyboards.contains { $0.builtIn }, "Routine refresh disabled built-in Fn controls")
    app.keyboardModes.busy = false
    try check(app.fnItem.state == .on && app.externalFnItem.state == .off, "Fn checkboxes reflect the same value")
    app.keyboardModes.results = [.init(name: "Test external keyboard", detail: "✓ Firmware mode read", verified: true, standard: true)]
    app.refreshFunctionKeyItem(false)
    try check(app.fnItem.state == .off && app.externalFnItem.state == .on, "External Fn state changed with built-in Fn state")

    let visibleItems = app.menu.items.filter { !$0.isHidden }
    let menuWidth = max(430, visibleItems.compactMap { $0.view?.frame.width }.max() ?? 430)
    let renderedMenu = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth + 16, height: CGFloat(visibleItems.count * 26 + 16)))
    for (index, item) in visibleItems.enumerated() {
        let frame = NSRect(x: 8, y: renderedMenu.frame.height - CGFloat((index + 1) * 26), width: menuWidth, height: 24)
        if let production = item.view as? MenuRowView {
            // Draw the actual production class with its real text/kind/state.
            let row = MenuRowView(item: item, kind: production.kind, text: production.text)
            row.frame = frame; renderedMenu.addSubview(row)
        } else if item.isSeparatorItem {
            let line = NSBox(frame: NSRect(x: 14, y: frame.midY, width: menuWidth - 12, height: 1))
            line.boxType = .separator; renderedMenu.addSubview(line)
        } else { throw AppError(message: "A menu row escaped the unified renderer") }
    }
    try renderReleaseView(renderedMenu, path: "/private/tmp/perch-release-menu.png")
    app.menuDidClose(app.menu)
    let requests = app.systemMonitor.processCPU.requests
    app.refreshSystem()
    app.systemMonitor.processCPU.refresh(now: ProcessInfo.processInfo.systemUptime + 100)
    try check(!app.menuOpen && app.systemMonitor.processCPU.requests == requests, "Closed menu continued sampling")
    print("PASS: real menu refresh in tracking mode, lid wording, Settings placement, toggle/disabled actions, ready/denied/missing/stale/inactive input, light/dark app-owned view renders")
}
