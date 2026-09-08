import AppKit

func runKeyboardRegistrationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func identity(vendor: Int = 1234, product: Int = 123, version: Int = 1, name: String = "Unknown keyboard", transport: String = "USB", usages: [UInt32] = NavigationLearning.usages.sorted()) -> NavigationKeyboardIdentity {
        .init(vendor: vendor, product: product, version: version, name: name, transport: transport, usages: usages)
    }
    let unknown = identity()
    let unregistered = KeyboardRegistrationStatus.assess(unknown, saved: [])
    try check(unregistered.needsSetup, "An unknown model bypassed registration because its descriptor advertised navigation keys")
    let monitor = KeyboardModeMonitor(); monitor.registrations = [unregistered]
    try check(!NavigationPreferences().enabled && monitor.warning && monitor.attentionHint.contains("setup needed"), "Unknown keyboard warning depended on an optional feature being enabled")
    let mx = identity(vendor: 0x046D, product: 0xB35B, name: "MX Keys", transport: "Bluetooth")
    try check(!BundledNavigationProfiles.entries.isEmpty && !KeyboardRegistrationStatus.assess(mx, saved: []).needsSetup, "Bundled MX Keys profile missing or not recognized")
    for unrelated in [identity(name: "MX Keys"), identity(vendor: 0x046D, product: 0xB35B, name: "MX Keys", transport: "USB"), identity(vendor: 0x046D, product: 0xB35B, name: "Another model", transport: "Bluetooth")] {
        try check(KeyboardRegistrationStatus.assess(unrelated, saved: []).needsSetup, "Bundled profile matched an unrelated device or receiver transport")
    }

    let suite = "Perch.KeyboardRegistration.Tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let learned = NavigationKeyboardProfile(identity: unknown, keys: [0x68, 0x69, 0x6A, 0x6B])
    try KeyboardNavigationProfiles.save(learned, defaults: defaults)
    let records = try KeyboardNavigationProfiles.read(defaults: defaults)
    try check(records == [learned], "Profile did not survive decoding")
    let recognized = KeyboardRegistrationStatus.assess(identity(), saved: records)
    try check(!recognized.needsSetup && recognized.profile?.hasHomeEnd == true && recognized.profile?.hasPageKeys == true, "Saved identity did not survive reconnect without a registry ID")
    monitor.registrations = [recognized]
    try check(!monitor.warning && monitor.attentionHint.isEmpty, "Successful registration retained setup warning")
    monitor.registrations = []
    try check(!monitor.warning, "Disconnected unknown keyboard retained setup warning")
    for changed in [identity(product: 124), identity(version: 2), identity(transport: "Bluetooth"), identity(usages: [0x68, 0x69])] {
        try check(KeyboardRegistrationStatus.assess(changed, saved: records).needsSetup, "Profile crossed a model, firmware, transport or layout boundary")
    }
    for keys: [UInt32?] in [[0x68,0x68,0x6A,0x6B],[0x04,0x69,0x6A,0x6B],[0x68]] {
        try check(!NavigationKeyboardProfile(identity: unknown, keys: keys).valid, "Invalid or typing-key profile accepted")
    }
    let absent = NavigationKeyboardProfile(identity: unknown, keys: [nil,nil,nil,nil])
    try KeyboardNavigationProfiles.save(absent, defaults: defaults)
    let withoutKeys = KeyboardRegistrationStatus.assess(unknown, saved: try KeyboardNavigationProfiles.read(defaults: defaults))
    try check(!withoutKeys.needsSetup && withoutKeys.profile?.hasHomeEnd == false && withoutKeys.profile?.hasPageKeys == false, "Absent keys either blocked registration or enabled unsupported features")
    for entry in BundledNavigationProfiles.entries {
        let id = NavigationKeyboardIdentity(vendor:entry.vendor,product:entry.product,version:1,name:entry.deviceNames[0],transport:entry.transports[0],usages:entry.keys.compactMap { $0 }.sorted())
        try check(entry.matches(id), "Bundled profile rejected its documented descriptor: \(entry.name)")
        let receiver = NavigationKeyboardIdentity(vendor:entry.vendor,product:0xc548,version:1,name:id.name,transport:"USB",usages:id.usages)
        try check(!entry.matches(receiver), "Receiver inherited a keyboard profile")
    }
    try check(BundledNavigationProfiles.entries.count >= 28, "Expanded keyboard profiles absent")
    let override = NavigationKeyboardProfile(identity: mx, keys: [nil,nil,nil,nil])
    try check(KeyboardRegistrationStatus.assess(mx, saved: [override]).profile == override, "Bundled profile overrode user's learned layout")
    try KeyboardNavigationProfiles.reset(unknown, defaults: defaults)
    try check(try KeyboardNavigationProfiles.read(defaults: defaults).isEmpty, "Reset retained selected layout")
    defaults.set(Data("broken".utf8), forKey: KeyboardNavigationProfiles.key)
    do { _ = try KeyboardNavigationProfiles.read(defaults: defaults); throw AppError(message: "Corrupt profile storage was silently accepted") }
    catch let error as AppError { try check(error.message != "Corrupt profile storage was silently accepted", error.message) }
    try KeyboardNavigationProfiles.reset(nil, defaults: defaults)

    var now: TimeInterval = 1
    let session = NavigationProbeSession(now: { now })
    let source = MockNavigationProbeSource()
    session.start(deviceID: 42, source: source, guided: true)
    try check(session.state.currentKey == .home, "Guided setup did not start with Home")
    source.value?(99,7,0x68,1); source.value?(42,7,4,1); source.value?(42,12,0x68,1)
    try check(!session.state.keys[0].pressed, "Guided setup captured another device or text/consumer input")
    source.value?(42,7,0x68,1); session.skipCurrent()
    try check(session.state.keys[0].held && !session.state.keys[0].absent, "Held key was skipped")
    source.value?(42,7,0x69,0)
    try check(session.state.currentKey == .home, "An unrelated release completed the key")
    source.value?(42,7,0x68,0)
    try check(session.state.currentKey == .end, "Guided setup did not advance after release")
    source.value?(42,7,0x68,1); source.value?(42,7,0x68,0)
    try check(session.state.currentKey == .end && session.state.notice != nil, "Duplicate key silently assigned twice")
    source.value?(42,7,0x69,1); source.value?(42,7,0x69,0)
    session.skipCurrent(); session.skipCurrent()
    try check(session.state.learnedKeys == [0x68,0x69,nil,nil] && source.stops == 1, "Guided result or cleanup failed")
    let next = MockNavigationProbeSource()
    session.start(deviceID: 42, source: next, guided: true)
    now = 62; session.skipCurrent()
    try check(session.state.phase == .incomplete && next.stops == 1 && session.state.learnedKeys == nil, "Late skip bypassed setup timeout")
    session.markAllAbsent(deviceID: 42)
    try check(session.state.learnedKeys == [nil,nil,nil,nil], "Declaring absent keys requires an input subscription")
    print("PASS: bundled MX Keys; unknown models always need setup; scoped persistent profiles; overrides, absent keys, corrupt data; guided learning excludes typing; matched release, duplicates, cancellation and timeout; isolated preferences/mock input")
}

func runKeyboardRegistrationUITests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let app = AppDelegate(); app.buildMenu()
    let host = SettingsWindow.shared; host.testing = true
    app.keyboardModes.registrations = [.init(name: "Unknown keyboard", profile: nil, detail: "⚠ Unrecognized navigation layout · set up this keyboard")]
    app.refreshKeyboardAttention()
    try check(!app.keyboardSetupItem.isHidden && app.keyboardSetupItem.action == #selector(AppDelegate.keyboardSettings) && app.menuTitleSources[app.safetySettingsItem]?.string.contains("Keyboard setup needed") == true, "Unknown keyboard has no direct menu/settings route")
    app.configureSettings()
    let root = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title.contains("Keyboards…") }
    try check(root != nil, "Root Settings does not offer the keyboard task")
    app.keyboardSettings(); app.keyboardDetails()
    let scroll = host.pages.last!.view.subviews.compactMap { $0 as? NSScrollView }.first!
    let firstEntry = scroll.documentView!.subviews.compactMap { $0 as? NSTextField }.first!
    try check(firstEntry.stringValue.contains("Unknown keyboard") && scroll.contentView.bounds.contains(firstEntry.frame), "Keyboard needing attention started outside the visible list")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-keyboard-registration.png")
    host.goBack(); host.goBack()
    try check(host.pages.last?.title == "Perch settings", "Keyboard setup Back failed")
    app.currentProtectionIssue = .init(severity: .critical, title: "Emergency shortcut unavailable", detail: "test", route: "shortcut")
    app.label(app.safetySettingsItem, "Settings…", hint: "⛔ Emergency shortcut unavailable", hintColor: StatusColors.critical)
    app.refreshKeyboardAttention()
    try check(app.menuTitleSources[app.safetySettingsItem]?.string.contains("Emergency shortcut") == true, "Keyboard notice obscured a critical protection issue")
    app.currentProtectionIssue = nil; app.keyboardModes.registrations = []
    app.refreshKeyboardAttention()
    try check(app.keyboardSetupItem.isHidden && app.safetySettingsItem.title == "Settings…", "Resolved or disconnected keyboard left a stale warning")
    app.nativeKeyboards = []
    app.refreshKeyboardAttention()
    try check(app.externalKeyboardSection.title.contains("None connected") && [app.externalSwapItem!,app.externalFnItem!,app.homeEndItem!,app.pageKeysItem!].allSatisfy { $0.isHidden }, "Disconnected keyboard left controls visible")
    let identity = NavigationKeyboardIdentity(vendor:1234, product:123, version:1, name:"Test keyboard", transport:"USB", usages:NavigationLearning.usages.sorted())
    let profile = NavigationKeyboardProfile(identity:identity, keys:[0x68,0x69,nil,nil])
    app.keyboardModes.registrations = [.init(name:"Test keyboard",profile:profile,detail:"Recognized")]
    app.refreshKeyboardAttention()
    try check(app.externalKeyboardSection.title.contains("Test keyboard") && !app.externalSwapItem.isHidden && !app.externalFnItem.isHidden && !app.homeEndItem.isHidden && app.pageKeysItem.isHidden, "Reconnect did not restore supported controls")
    app.keyboardModes.registrations.append(.init(name:"Second keyboard",profile:profile,detail:"Recognized"))
    app.refreshKeyboardAttention()
    try check(app.externalKeyboardSection.title.contains("2 keyboards"), "Multiple keyboard count missing")
    try check(perchStatusImage(awake:true)?.isTemplate == true && perchStatusImage(awake:false) != nil, "Bird status image unavailable")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    print("PASS: unknown keyboard routes to Settings while optional controls are off; warning clears; critical protection priority; shared window and theme rendering")
}
