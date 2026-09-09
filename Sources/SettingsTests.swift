import AppKit

func runSettingsTests() throws {
    try DesktopTestSession.check()
    try runDialogOwnershipTests()
    try runShortcutDialogBackTests()
    try runSleepPresentationTests()
    try runSettingsJourneyFixTests()
    try runLidSettingTests()
    try runStatusColorTests()
    try runReleaseUITests()
    try runNavigationProbeUITests()
    try runKeyboardRegistrationUITests()
    try runMonitorInputUITests()
    try runMonitorDraftTests()
    try runReviewFixTests()
    try runPresentationHandoffTests()
    try runSetupOverviewTests()
    try runLidActivityUITests()
    let host = SettingsWindow.shared
    host.testing = true
    let app = AppDelegate()
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: message) } }
    try check(host.window.isFloatingPanel && host.window.level == .floating && !host.window.hidesOnDeactivate, "Setup window can disappear behind other apps")
    app.configureSettings()
    let identity = host.window.windowNumber
    try check(host.pages.count == 1, "Settings root missing")
    app.appSettings()
    let cpuBox = host.pages.last?.view.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == CPUDisplaySettings.key }
    try check(cpuBox != nil && (cpuBox?.state == .on) == CPUDisplaySettings.enabled(), "CPU checkbox missing or disagrees with preference")
    host.goBack()
    try render("/private/tmp/perch-settings-root-preview.png")
    app.configurePanic()
    try check(host.pages.count == 2 && host.window.windowNumber == identity, "Agent Kill Switch changed windows")
    EventCollectorSetup.shared.show(fromSettings: true)
    try check(host.pages.count == 3 && EventCollectorSetup.shared.primary.window === host.window, "Collector controls are outside shared window")
    // Render the real view hierarchy into an explicit test background.
    func render(_ path: String) throws {
        guard let view = host.window.contentView else { throw AppError(message: "Settings content missing") }
        try renderReleaseView(view, path: path)
    }
    try render("/private/tmp/perch-settings-preview.png")
    host.goBack()
    try check(host.pages.count == 2 && host.pages.last?.title == "Agent Kill Switch" && EventCollectorSetup.shared.timer == nil, "Collector Back/lifecycle failed")
    host.goBack()
    try check(host.pages.count == 1 && host.pages.last?.title == "Perch settings", "Settings Back failed")
    app.inputPermissionsFromSettings()
    try check(app.permissionSetup?.status.window === host.window && host.pages.count == 2, "Input setup changed windows")
    try render("/private/tmp/perch-input-preview.png")
    host.goBack()
    try check(host.pages.count == 1 && app.permissionSetup?.timer == nil, "Input Back did not return to parent")
    app.keyboardSettings()
    try check(host.pages.count == 2 && host.pages.last?.title == "Keyboard settings", "Keyboard settings broke navigation")
    let swaps = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter { $0.title.contains("Swap Control") }
    try check(swaps.count == 2, "Keyboard settings must offer clearly scoped built-in and external controls")
    try render("/private/tmp/perch-keyboard-preview.png")
    host.goBack()
    app.resetSettingsPage()
    try check(host.pages.count == 2 && host.window.windowNumber == identity, "Reset opened a different window")
    try render("/private/tmp/perch-reset-preview.png")
    app.confirmSettingsReset(.init(sections:["devices"]))
    try check(host.pages.count == 3 && host.pages.last?.title == "Reset selected settings?", "Selective reset confirmation missing")
    try render("/private/tmp/perch-reset-confirm-preview.png")
    host.goBack(); host.goBack()
    try check(host.pages.count == 1, "Reset Back failed to return to Settings")
    app.privacyOnlyReset(global:false)
    try check(host.pages.last?.title == "Reset Perch’s privacy permissions?", "Perch privacy scope missing")
    host.goBack()
    app.privacyOnlyReset(global:true)
    try check(host.pages.last?.title == "Reset all apps’ privacy permissions?", "Global privacy scope missing")
    try render("/private/tmp/perch-privacy-only-preview.png")
    host.goBack()
    app.systemResetPage()
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.filter { $0.title.hasPrefix("Remove the lid") || $0.title == "Unmute system audio" }.allSatisfy { $0.state == .off }, "System reset preselected destructive choices")
    host.goBack()
    app.configurePanic(); app.advancedSafetySettings()
    try check(host.pages.count == 3 && host.window.windowNumber == identity, "Advanced navigation changed windows")
    try render("/private/tmp/perch-advanced-preview.png")
    // The test panel stays offscreen and may already be closed. Exercise the
    // close delegate explicitly; AppKit does not resend close for a closed panel.
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    try check(host.pages.isEmpty, "Closing settings retained navigation stack")
    print("PASS: one-window Settings → Agent Kill Switch → Collector and Back; Input Back returns to root; Advanced navigation; timers stop on leaving")
}
