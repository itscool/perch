import AppKit
import Carbon

/// Compile with the full isolated fixture. Execution belongs to an announced desktop session.
func runSettingsReviewFixTests() throws {
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    let app = AppDelegate(); app.installSettingsNavigation()
    defer { host.pickerTestDriver = nil; host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); host.pages = [] }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func buttons(_ view: NSView) -> [NSButton] { view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) } }

    var granted = false
    let access = KeyboardAccessPage(readAccess: { granted }, recheck: {}, openSettings: {})
    access.show()
    let drag = access.view.subviews.first { $0 is PermissionDragItem }!
    try check(!drag.isHidden && !host.interactionBusy, "Missing access has no usable repair route")
    granted = true; access.refresh()
    try check(drag.isHidden && access.status.stringValue.contains("ready"), "Ready permission still asks for setup")
    buttons(access.view).first { $0.title == "Review permission setup…" }!.performClick(nil)
    try check(!drag.isHidden, "Ready grant cannot be reviewed voluntarily")
    buttons(access.view).first { $0.title == "Hide permission instructions" }!.performClick(nil)
    granted = false; access.refresh()
    try check(!drag.isHidden, "Lost access did not restore recovery")
    host.navigate(to: host.sidebar.destinations.first { $0.id == "desk-input" }!)
    try check(host.pages.count == 1 && host.pages.last?.title == "Keyboard & mouse sharing" && host.back.isHidden && !host.interactionBusy, "Input settings is not a stable sidebar destination")
    host.navigate(to: host.sidebar.destinations.first { $0.id == "desk-preferences" }!)
    try check(host.pages.count == 1 && host.pages.last?.title == "Desk settings" && host.back.isHidden, "Desk preferences retained sheet navigation")

    let presetShortcut = KVMShortcut(key: "F8")
    let emergency = PanicShortcut(key: UInt32(kVK_F8), modifiers: UInt32(controlKey | optionKey | cmdKey), enabled: true)
    try check(presetShortcut.matches(emergency), "Current Desk shortcut collision was missed")
    var changedModifiers = emergency; changedModifiers.modifiers |= UInt32(shiftKey)
    var disabledEmergency = emergency; disabledEmergency.enabled = false
    try check(!presetShortcut.matches(changedModifiers) && !presetShortcut.matches(disabledEmergency), "Shortcut validation rejected a distinct or disabled shortcut")
    var config = SafetyConfiguration(); config.shortcut.enabled = true
    var reported: SafetyStatus? = nil
    let agents = AgentSettingsPage(load: { config }, save: { config = $0 }, conflicts: { _ in false }, readStatus: { reported })
    agents.show()
    try check(agents.status.stringValue.contains("Waiting"), "Saved shortcut was called ready without registration")
    reported = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: nil, inputActive: false, keepAwakeActive: false, trackedCount: 0, targets: [], message: "Fixture", testResultID: nil, testUntil: nil, error: nil, registeredShortcut: config.shortcut)
    host.pages.last?.refresh?()
    try check(agents.status.stringValue.contains("Registered and ready"), "Confirmed matching registration is not shown")
    reported?.shortcutActive = false
    reported?.registeredShortcut = PanicShortcut(key: UInt32(kVK_F9), enabled: true)
    reported?.error = "Replacement unavailable; previous shortcut remains active."
    host.pages.last?.refresh?()
    try check(agents.status.stringValue.contains("Not registered") && agents.status.stringValue.contains("previous shortcut"), "Failed replacement was reported ready or hid working fallback")

    var navigationConfig = SafetyConfiguration()
    navigationConfig.navigation = NavigationPreferences(homeEnd: true, pageUpDown: true)
    var profileReads = 0, navigationWrites = 0
    app.setNavigation(homeEnd: true, load: { navigationConfig }, save: { navigationConfig = $0; navigationWrites += 1 }, readProfiles: { profileReads += 1; throw AppError(message: "Damaged layout store") })
    try check(navigationWrites == 1 && profileReads == 0 && navigationConfig.navigation?.homeEnd == false && navigationConfig.navigation?.pageUpDown == true, "Turning one behavior off read corrupt layouts or disabled the other behavior")
    app.setNavigation(homeEnd: false, load: { navigationConfig }, save: { navigationConfig = $0; navigationWrites += 1 }, readProfiles: { profileReads += 1; throw AppError(message: "Damaged layout store") })
    try check(navigationWrites == 2 && profileReads == 0 && navigationConfig.navigation?.enabled == false, "Turning all navigation off depends on layout recovery")
    app.setNavigation(homeEnd: true, load: { navigationConfig }, save: { navigationConfig = $0; navigationWrites += 1 }, readProfiles: { profileReads += 1; throw AppError(message: "Damaged layout store") })
    try check(navigationWrites == 2 && profileReads == 1 && navigationConfig.navigation?.enabled == false, "Enabling ignored a failed profile read")

    // Add/remove has an independent failure path; failed removal must keep both the row and error.
    var preferences = NavigationPreferences(); preferences.customApps = ["example.app": "Example app"]
    preferences.excludedApps.append("example.app")
    var fail = false
    func showExceptions() {
        app.showNavigationExceptions(load: { preferences }, save: { id, excluded in
            preferences.excludedApps.removeAll { $0 == id }; if excluded { preferences.excludedApps.append(id) }
        }, editApp: { id, name in
            if fail { throw AppError(message: "Fixture storage unavailable") }
            preferences.customApps?[id] = name
            preferences.excludedApps.removeAll { $0 == id }; if name != nil { preferences.excludedApps.append(id) }
        })
    }
    showExceptions()
    buttons(host.pages.last!.view).first { $0.title == "Example app" }!.performClick(nil)
    showExceptions()
    try check(buttons(host.pages.last!.view).contains { $0.title == "Example app" && $0.state == .off }, "Disabled custom exception vanished on reopen")
    fail = true
    buttons(host.pages.last!.view).first { $0.title == "Remove" }!.performClick(nil)
    try check(preferences.customApps?["example.app"] != nil && host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Not removed") }, "Failed removal discarded the row or its error")
    fail = false
    buttons(host.pages.last!.view).first { $0.title == "Remove" }!.performClick(nil)
    try check(preferences.customApps?["example.app"] == nil && !buttons(host.pages.last!.view).contains { $0.title == "Example app" }, "Successful custom removal did not refresh the list")
    print("PASS: permission ready/review/revoked flow, stable Desk destinations, actual shortcut readiness and custom exception recovery")
}
