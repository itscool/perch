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
    buttons(access.view).first { $0.title == "Show permission instructions" }!.performClick(nil)
    try check(!drag.isHidden, "Ready grant cannot be reviewed voluntarily")
    buttons(access.view).first { $0.title == "Hide permission instructions" }!.performClick(nil)
    granted = false; access.refresh()
    try check(!drag.isHidden, "Lost access did not restore recovery")
    host.navigate(to: host.sidebar.destinations.first { $0.id == "desk-input" }!)
    try check(host.pages.count == 1 && host.pages.last?.title == "Input options" && host.back.isHidden && !host.interactionBusy, "Input settings is not a stable sidebar destination")
    host.navigate(to: host.sidebar.destinations.first { $0.id == "hotkeys" }!)
    try check(host.pages.count == 1 && host.pages.last?.title == "Hotkeys" && host.back.isHidden, "Desk preferences retained sheet navigation")

    // Every entry shares a canonical Setup stage and a single retained overview.
    let stages: [(String, () -> Void)] = [
        ("keyboard-access", app.keyboardAccessRecovery), ("input-access", app.inputPermissionsFromSettings),
        ("sharing-access", app.sharingAccessSetup), ("lid-setup", app.lidProtectionSetup),
        ("maintenance", app.advancedSafetySettings), ("events", app.processEventSetup)
    ]
    let stageIDs = Set(stages.map { $0.0 })
    let destinations = host.sidebar.destinations
    try check(Set(destinations.filter(\.setupStage).map(\.id)) == stageIDs,
              "Prerequisite stages are missing or duplicated outside Setup")
    try check(destinations.prefix(1 + stages.count).dropFirst().allSatisfy { $0.setupStage && $0.depth == 1 },
              "Setup stages are scattered among feature destinations")
    for (id, enter) in stages {
        host.navigate(to: host.sidebar.destinations.first { $0.id == "keyboard" }!)
        enter()
        let stage = host.pages.last!.view, overview = host.pages.first!.view
        try check(host.pages.count == 2 && host.pages.first?.title == "Setup & status" &&
                  host.sidebar.destinations[host.sidebar.table.selectedRow].id == id &&
                  host.back.title == "Back to setup" && !host.interactionBusy,
                  "Feature repair failed to select its one Setup stage: " + id)
        enter()
        try check(host.pages.count == 2 && host.pages.last?.view === stage, "Repeated repair rebuilt or stacked its stage: " + id)
        let other = id == "keyboard-access" ? "input-access" : "keyboard-access"
        host.navigate(to: host.sidebar.destinations.first { $0.id == other }!)
        try check(host.pages.count == 2 && host.pages.first?.view === overview,
                  "Switching Setup stages discarded the existing checklist")
        host.goBack()
        try check(host.pages.count == 1 && host.pages.first?.view === overview && host.back.isHidden,
                  "Setup Back lost the original checklist")
    }
    app.advancedSafetySettings()
    try check(!host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.contains { ["Repair background helpers…", "Open macOS Login Items…", "Protect background helper files…", "Perch privacy reset…"].contains($0.title) }, "Background setup retains maintenance chores or duplicate reset/security controls")
    try check(!host.sidebar.destinations.contains { $0.id == "security" || $0.title == "Security" } && host.sidebar.destinations.contains { $0.id == "reset" && $0.title == "Reset Settings" }, "Retired Security page remains in navigation or Reset Settings is missing")
    for enter in [app.keyboardSettings, app.keyboardDetails, app.testNavigationKeys] {
        enter()
        try check(!host.pages.last!.view.subviews.contains { $0 is PermissionDragItem },
                  "Feature page still embeds permission instructions")
        host.goBack()
    }
    app.keepAwakeSettings()
    try check(host.pages.last?.title == "Lid activity", "Retired Keep awake route did not reach Lid activity")
    try check(!buttons(host.pages.last!.view).contains { ["Keep awake", "Including with the lid closed", "Start five-minute countdown", "Hotkeys…"].contains($0.title) }, "Lid activity duplicates menu or hotkey controls")
    app.lidProtectionSetup()
    try check(host.pages.last?.title == "Lid protection setup", "Lid repair missed Setup")
    try check(!host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "Background helpers in Setup…" }, "Lid setup duplicated the Background helpers Setup item")
    var sharingGrant = false
    app.presentSharingAccess(readAccessibility: { sharingGrant }, readMonitoring: { sharingGrant })
    let sharingView = host.pages.last!.view
    sharingGrant = true; host.pages.last?.refresh?()
    try check(sharingView.subviews.compactMap { $0 as? SettingsStatusField }.first?.stringValue.contains("Access is ready") == true,
              "Sharing access did not transition to ready without enabling sharing")
    try check(sharingView.subviews.filter { $0 is PermissionDragItem }.allSatisfy(\.isHidden),
              "Ready sharing access still asks the user to grant access")
    sharingGrant = false; host.pages.last?.refresh?()
    try check(sharingView.subviews.compactMap { $0 as? SettingsStatusField }.first?.stringValue.contains("needs attention") == true,
              "Revoked shared-input access retained Ready")
    app.configureSettings()

    let presetShortcut = KVMShortcut(key: "F8")
    let emergency = Shortcut(key: UInt32(kVK_F8))
    try check(presetShortcut.matches(emergency), "Current Desk shortcut collision was missed")
    var changedModifiers = emergency; changedModifiers.modifiers.insert(.shift)
    var disabledEmergency = emergency; disabledEmergency.enabled = false
    try check(!presetShortcut.matches(changedModifiers) && !presetShortcut.matches(disabledEmergency), "Shortcut validation rejected a distinct or disabled shortcut")
    var config = SafetyConfiguration(); config.shortcut.enabled = true
    var reported: SafetyStatus? = nil
    let agents = AgentSettingsPage(mode: .shortcut, load: { config }, save: { config = $0 }, conflicts: { _ in false }, readStatus: { reported })
    agents.show()
    try check(agents.status.stringValue.contains("Waiting"), "Saved shortcut was called ready without registration")
    reported = SafetyStatus(locked: false, pendingLaunchJobs: 0, shortcutActive: true, inputTrusted: nil, inputActive: false, keepAwakeActive: false, trackedCount: 0, targets: [], message: "Fixture", testResultID: nil, testUntil: nil, error: nil, registeredShortcut: config.shortcut)
    host.pages.last?.refresh?()
    try check(agents.status.stringValue.contains("Registered and ready"), "Confirmed matching registration is not shown")
    reported?.shortcutActive = false
    reported?.registeredShortcut = Shortcut(key: UInt32(kVK_F9))
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
