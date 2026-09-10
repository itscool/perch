import AppKit

// Exercise route handlers with native panels and injected completion only.
// No OS authorization, file import, permission request or external app launch.
func runPresentationHandoffTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func flush() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    defer {
        host.pickerTestDriver = nil; host.modalTestDriver = nil; host.externalAppTestDriver = nil
        host.returnedToApp(); host.window.orderOut(nil); host.pages = []
    }
    let app = AppDelegate(monitorInputs: MonitorInputController(displays: []))
    app.configureSettings(); app.configurePanic()
    let original = host.pages.last!.view, depth = host.pages.count
    var notices = 0, pickerTitles: [String] = [], pickerChecks = true
    host.pickerTestDriver = { panel in
        pickerTitles.append(panel.title)
        pickerChecks = pickerChecks && host.interactionBusy && host.picking && !host.back.isEnabled
        host.afterInteraction { notices += 1 }
        host.goBack()
        pickerChecks = pickerChecks && host.pages.count == depth && !host.windowShouldClose(host.window)
        let other = NSAlert(); other.addButton(withTitle: "Apply")
        pickerChecks = pickerChecks && host.run(other) == .abort && host.open(NSOpenPanel()) == .cancel && notices == pickerTitles.count - 1
        return .cancel
    }
    for action in [{ app.addTarget(app: true) }, { app.addTarget(app: false) }, { app.importAgentCatalog() }] {
        let expectedNotices = notices + 1
        action()
        let deadline = Date().addingTimeInterval(2)
        while notices < expectedNotices && Date() < deadline { flush() }
        try check(notices == expectedNotices, "Picker completion did not deliver its queued notice")
        try check(!host.interactionBusy && host.back.isEnabled && host.pages.last?.view === original, "Picker cancellation changed the originating page or left it busy")
    }
    try check(pickerChecks && pickerTitles == ["Choose an agent app", "Choose an agent executable", "Import agent catalog"] && notices == 3, "A picker route lost interaction ownership or a queued notice: checks=\(pickerChecks), titles=\(pickerTitles), notices=\(notices)")
    host.pickerTestDriver = { _ in .OK }
    try check(host.open(NSOpenPanel()) == .OK && !host.interactionBusy, "Picker success left ownership stuck")

    // A modal result/confirmation also owns the shared host. A queued page must
    // not replace its controls; it may appear after the response is consumed.
    var alertChecks = false
    let deferred = SettingsWindow.Page(title: "Deferred fixture", detail: "", view: NSView())
    host.modalTestDriver = { _ in
        host.afterInteraction { notices += 1 }
        host.show(deferred)
        alertChecks = host.modal && host.interactionBusy && host.pages.last?.view === original && host.open(NSOpenPanel()) == .cancel
        return .alertFirstButtonReturn
    }
    let alert = NSAlert(); alert.messageText = "Fixture confirmation"; alert.addButton(withTitle: "Continue")
    try check(host.run(alert) == .alertFirstButtonReturn && alertChecks && !host.interactionBusy, "Modal alert did not serialize competing presentation")
    host.modalTestDriver = nil; flush()
    try check(host.pages.last?.view === deferred.view && notices == 4, "Deferred page/notice was dropped")
    host.window.orderOut(nil)
    try check(host.run(NSAlert()) == .abort && !host.interactionBusy, "Standalone alert fallback leaked ownership")
    app.configureSettings(); app.configurePanic()

    var opens = 0
    host.externalAppTestDriver = { opens += 1; return true }
    try DesktopTestSession.check()
    host.window.orderFront(nil)
    let priorLevel = host.window.level, priorFloating = host.window.isFloatingPanel
    let permission = PermissionSetup(helperApp: { SafetyFiles.helperApp })
    let routes: [() -> Void] = [permission.openSettings, permission.revealHelper, EventCollectorSetup.shared.openPrivacySettings, EventCollectorSetup.shared.showFile]
    for route in routes {
        let before = opens, oldNotices = notices
        route()
        try check(opens == before + 1 && host.externalHandoff && host.interactionBusy && host.window.isVisible && !host.window.isFloatingPanel && host.window.level == .normal, "External route covered its destination or lost drag instructions")
        host.afterInteraction { notices += 1 }; flush()
        try check(notices == oldNotices, "External open acceptance was treated as user return")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        flush()
        try check(!host.interactionBusy && host.window.level == priorLevel && host.window.isFloatingPanel == priorFloating && notices == oldNotices + 1, "Returning from external route did not restore ownership")
    }
    for needsPermission in [false, true] {
        app.keyboardModes.results = [.init(name: "Fixture", detail: "Fixture", verified: !needsPermission, needsAccess: needsPermission)]
        app.keyboardDetails()
        let title = needsPermission ? "Open macOS Input Monitoring" : "Open macOS Keyboard Settings"
        guard let button = host.pages.last?.view.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else { throw AppError(message: "Missing keyboard handoff route") }
        let before = opens; button.performClick(nil)
        try check(opens == before + 1 && host.externalHandoff, "Keyboard route bypassed the shared handoff")
        host.returnedToApp(); flush()
    }
    let navigation = NavigationProbePage(enumerate: { [] }, hasAccess: { false }, readProfiles: { [] })
    navigation.show()
    guard let button = navigation.view.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Open Input Monitoring" }) else { throw AppError(message: "Missing navigation handoff route") }
    let before = opens; button.performClick(nil)
    try check(opens == before + 1 && host.externalHandoff, "Navigation route bypassed the shared handoff")
    host.returnedToApp(); flush()
    // Missing activation notifications must not strand a status-menu return.
    permission.openSettings()
    app.configureSettings()
    try check(!host.externalHandoff && !host.interactionBusy && host.pages.last?.title == "Setup & status", "Explicit Settings menu return stayed blocked")
    permission.openSettings()
    host.window.userReturned?()
    try check(!host.interactionBusy, "Click/key return did not release external handoff")
    let restoreAuthorization = host.beginAuthorization()
    host.window.userReturned?()
    app.configureSettings()
    try check(host.authorizing && host.interactionBusy, "Ordinary navigation released a real authorization owner")
    restoreAuthorization()

    host.externalAppTestDriver = { false }
    permission.openSettings()
    try check(!host.interactionBusy && host.window.level == priorLevel, "Failed external open stranded Settings")
    host.externalAppTestDriver = { true }
    permission.openSettings()
    let endAuthorization = host.beginAuthorization()
    try check(!host.externalHandoff && host.authorizing && !host.window.isVisible, "Authorization retained an external handoff owner")
    endAuthorization()
    try check(!host.interactionBusy && host.window.isFloatingPanel == priorFloating, "Authorization after external return lost window state")
    print("PASS: all three picker entry routes; modal overlap refusal; queued page/result ownership; Accessibility, Full Disk Access, Finder, keyboard and navigation handoffs, retained drag UI, failed open and return; injected OS operations only")
}
