import AppKit

func runSettingsResetTests() throws {
    try runDeskInspectionTests()
    let fm = FileManager.default, domain = "local.scott.perch.reset-test." + UUID().uuidString
    let base = fm.temporaryDirectory.appendingPathComponent(domain)
    let defaults = UserDefaults(suiteName:domain)!
    defer { defaults.removePersistentDomain(forName:domain); try? fm.removeItem(at:base) }
    try fm.createDirectory(at:base.appendingPathComponent("requests"),withIntermediateDirectories:true)
    var config = SafetyConfiguration(); config.reverseWheel = true; config.keepAwake = true; config.targets = []
    try JSONEncoder().encode(config).write(to:base.appendingPathComponent("config.json"))
    defaults.set(true,forKey:"reverseWheel"); defaults.set("keep",forKey:"unrelated")
    defaults.set("mapping",forKey:MonitorInputController.preferenceKey)
    defaults.set("saved mappings",forKey:MonitorInputController.savedPlansKey)
    defaults.set("learned",forKey:KeyboardNavigationProfiles.key)
    defaults.set("confirmed",forKey:"monitor.confirmed.fixture")
    try Data().write(to:base.appendingPathComponent("requests/old.json"))
    try Data("helper fixture".utf8).write(to:base.appendingPathComponent("Perch Helper.app"))
    try SettingsReset.clear(.init(sections:["devices"]),defaults:defaults,domain:domain,base:base)
    guard defaults.object(forKey:MonitorInputController.preferenceKey) == nil,
          defaults.object(forKey:MonitorInputController.savedPlansKey) == nil,
          defaults.object(forKey:KeyboardNavigationProfiles.key) == nil,
          defaults.object(forKey:"monitor.confirmed.fixture") == nil,
          defaults.bool(forKey:"reverseWheel"), defaults.string(forKey:"unrelated") == "keep",
          try JSONDecoder().decode(SafetyConfiguration.self,from:Data(contentsOf:base.appendingPathComponent("config.json"))) == config else { throw AppError(message:"Selective reset changed unrelated preferences") }
    var monitor = MonitorInputPlan()
    monitor.display = "11111111-1111-1111-1111-111111111111"
    monitor.inputs = [.init(code:17,name:"HDMI"),.init(code:15,name:"DP")]
    monitor.shortcut.enabled = true; monitor.allowUnconfirmedCycle = true
    defaults.set(try JSONEncoder().encode([monitor.display:monitor]), forKey:MonitorInputController.savedPlansKey)
    try SettingsReset.clear(.init(sections:["preferences"]),defaults:defaults,domain:domain,base:base)
    let preserved = try JSONDecoder().decode([String:MonitorInputPlan].self, from: defaults.data(forKey:MonitorInputController.savedPlansKey)!)[monitor.display]!
    guard preserved.inputs == monitor.inputs && !preserved.shortcut.enabled && !preserved.allowUnconfirmedCycle else { throw AppError(message:"Preference reset lost saved monitor mappings or retained an old shortcut") }
    let partial = try JSONDecoder().decode(SafetyConfiguration.self,from:Data(contentsOf:base.appendingPathComponent("config.json")))
    guard !partial.reverseWheel && !partial.keepAwake else { throw AppError(message:"Preferences reset retained feature choices") }
    try SettingsReset.clear(.init(sections:Set(SettingsResetSelection.options.map { $0.0 })),defaults:defaults,domain:domain,base:base)
    guard (defaults.persistentDomain(forName:domain) ?? [:]).isEmpty,
          !fm.fileExists(atPath:base.appendingPathComponent("config.json").path),
          !fm.fileExists(atPath:base.appendingPathComponent("requests/old.json").path),
          fm.fileExists(atPath:base.appendingPathComponent("Perch Helper.app").path) else { throw AppError(message:"Full preference reset incomplete or touched installed helper") }
    guard LGFirmwareProfiles.entries.count == 162,
          LGFirmwareProfiles.family(identity:0x5124,extended:nil)?.name == "27UL850-RTK",
          LGFirmwareProfiles.inputs(identity:0x5124,extended:nil)?.inputs.contains(.init(code:209,name:"USB-C")) == true,
          LGFirmwareProfiles.family(identity:0x0124,extended:nil) == nil,
          LGFirmwareProfiles.family(identity:0xc000,extended:nil) == nil else { throw AppError(message:"Firmware-ID profile lookup failed") }
    for family in LGFirmwareProfiles.entries where family.inputProfile != nil {
        guard MonitorProfiles.entries.contains(where: { $0.name == family.inputProfile && $0.vendor == 7789 }) else { throw AppError(message:"Dangling firmware input profile") }
    }
    let identities = MonitorProfiles.entries.filter { $0.automatic != false }.map { "\($0.vendor):\($0.model ?? 0)" }
    guard Set(identities).count == identities.count else { throw AppError(message:"Ambiguous automatic monitor profile IDs") }
    guard PrivacyOnlyReset.arguments(global:false) == ["reset","All","local.scott.perch"],
          PrivacyOnlyReset.arguments(global:true) == ["reset","All"] else { throw AppError(message:"Privacy-only scope incorrect") }
    print("PASS: selective/full preference reset with disposable files/defaults; settings preserved by section; no services stopped or system settings changed; LG identity-to-input mapping")
}

func runResetNavigationTests() throws {
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    let app = AppDelegate(); app.installSettingsNavigation()
    defer { host.modalTestDriver = nil; host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); host.pages = [] }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: "Resets: " + message) } }
    func buttons() -> [NSButton] { host.pages.last!.view.subviews.compactMap { $0 as? NSButton } }
    for enter in [app.lidProtectionSetup, app.advancedSafetySettings, app.appSettings] {
        enter()
        guard let link = buttons().first(where: { $0.title == "Resets…" }) else { throw AppError(message: "Recovery page has no named Resets route") }
        link.performClick(nil)
        try check(host.pages.count == 1 && host.pages.last?.title == "Resets" && host.back.isHidden &&
                  host.sidebar.destinations[host.sidebar.table.selectedRow].id == "reset", "contextual reset failed to choose its canonical sidebar home")
    }
    let root = host.pages.last!.view
    for title in ["Saved Perch settings…", "Keyboard layouts…", "Menu appearance…", "Perch privacy permissions…", "Sleep & audio…", "All apps’ privacy permissions…"] {
        buttons().first { $0.title == title }!.performClick(nil)
        try check(host.pages.count == 2 && host.sidebar.destinations[host.sidebar.table.selectedRow].id == "reset" && !host.interactionBusy,
                  "scope lost Resets ownership: " + title)
        if title == "Saved Perch settings…" || title == "Sleep & audio…" {
            try check(buttons().allSatisfy { $0.state == .off }, "navigation preselected a destructive scope")
        }
        host.goBack()
        try check(host.pages.count == 1 && host.pages.last?.view === root, "Back discarded reset choices or returned to a feature")
    }
    let keyboard = NavigationKeyboardIdentity(vendor: 1234, product: 123, version: 1, name: "Disconnected fixture", transport: "USB", usages: NavigationLearning.usages.sorted())
    var profiles = [NavigationKeyboardProfile(identity: keyboard, keys: [0x68, 0x69, nil, nil])]
    var writes: [NavigationKeyboardIdentity?] = []
    var failRead = false, failWrite = false
    app.presentKeyboardLayoutReset(read: {
        if failRead { throw AppError(message: "Unreadable fixture") }
        return profiles
    }, reset: { identity in
        if failWrite { throw AppError(message: "Fixture write failed") }
        writes.append(identity); profiles.removeAll { identity == nil || $0.identity == identity }
    })
    let popup = host.pages.last!.view.subviews.compactMap { $0 as? NSPopUpButton }.first!
    let reset = buttons().first { $0.title == "Reset selected layout…" }!
    try check(!reset.isEnabled && popup.numberOfItems == 3 && writes.isEmpty, "opening layout reset selected or erased data")
    popup.selectItem(at: 2); popup.sendAction(popup.action, to: popup.target)
    try check(reset.isEnabled, "choosing disconnected layout did not enable its reset")
    host.modalTestDriver = { _ in .alertFirstButtonReturn }
    reset.performClick(nil)
    try check(writes.isEmpty && profiles.count == 1 && !host.interactionBusy, "Cancel changed layouts or trapped navigation")
    host.modalTestDriver = { _ in .alertSecondButtonReturn }
    failWrite = true; reset.performClick(nil)
    try check(writes.isEmpty && popup.indexOfSelectedItem == 2 && reset.isEnabled, "failed reset lost selection/retry")
    failWrite = false; reset.performClick(nil)
    try check(writes.count == 1 && writes[0] == keyboard && profiles.isEmpty && popup.indexOfSelectedItem == 0 && !reset.isEnabled,
              "successful targeted reset affected wrong scope or retained stale action")
    host.goBack()
    failRead = true
    app.presentKeyboardLayoutReset(read: { throw AppError(message: "Unreadable fixture") }, reset: { identity in writes.append(identity) })
    let unreadable = host.pages.last!.view.subviews.compactMap { $0 as? NSPopUpButton }.first!
    unreadable.selectItem(at: 1); unreadable.sendAction(unreadable.action, to: unreadable.target)
    buttons().first { $0.title == "Reset selected layout…" }!.performClick(nil)
    try check(writes.count == 2 && writes.last! == nil, "unreadable layouts cannot be explicitly cleared")
    host.goBack()
    let domain = "perch.appearance-reset-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = MenuAppearanceStore(defaults: defaults)
    var custom = MenuAppearance(); custom.sections.thickness = 5; custom.system.greyBackground = true
    store.save(custom); defaults.set("kept", forKey: "unrelated")
    app.presentAppearanceReset(store: store)
    try check(store.value == custom, "opening appearance reset changed styling")
    buttons().first { $0.title == "Restore original appearance" }!.performClick(nil)
    try check(store.value == MenuAppearance() && defaults.string(forKey: "unrelated") == "kept", "appearance reset omitted System or touched other choices")
    print("PASS: canonical Resets from setup/features; six scopes and Back; disconnected/unreadable layouts, Cancel/failure/retry and exact writes; scoped appearance defaults")
}
