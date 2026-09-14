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
    let host = SettingsWindow.shared; host.testing = true; host.pages = []
    let app = AppDelegate(); app.installSettingsNavigation()
    defer { host.modalTestDriver = nil; host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); host.pages = [] }
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: "Reset checklist: " + message) } }
    func allButtons(_ view: NSView) -> [NSButton] { view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? allButtons($0) } }
    for (enter, label, area, parentName) in [
        (app.lidProtectionSetup, "Sleep reset options…", ResetArea.sleep, "Lid protection")
    ] {
        enter(); let parent = host.pages.last!.view, overview = host.pages.first!.view
        allButtons(parent).first { $0.title == label }!.performClick(nil)
        let checklist = host.pages.last!.view
        try check(host.pages.last?.title == "Reset Settings" && host.pages.count == 3 && host.back.title == "Back to " + parentName && host.sidebar.destinations[host.sidebar.table.selectedRow].id == "reset", "deep link lost reset ownership or return")
        try check(allButtons(checklist).filter { $0.identifier?.rawValue.hasPrefix("reset.area.") == true }.allSatisfy { $0.state == .off }, "repair link selected a destructive action")
        let row = checklist.subviews.first { $0.identifier?.rawValue == "reset.row." + area.rawValue }
        try check(row?.layer?.borderWidth == 1, "repair row was not highlighted")
        host.goBack()
        try check(host.pages.last?.view === parent && host.pages.first?.view === overview, "Back lost original setup page/checklist")
    }
    app.openResets()
    let keyboard = NavigationKeyboardIdentity(vendor: 1234, product: 123, version: 1, name: "Offline keyboard", transport: "USB", usages: NavigationLearning.usages.sorted())
    let profiles = [NavigationKeyboardProfile(identity: keyboard, keys: [0x68,0x69,nil,nil])]
    var calls: [ResetArea] = [], quits = 0
    var callback: ((Result<String, Error>) -> Void)?
    let operation = ResetBatchOperation(execute: { area, plan, finish in
        calls.append(area)
        if area == .layouts { precondition(plan.keyboard == keyboard) }
        if area == .privacy { callback = finish; return }
        finish(.success("Fixture completed"))
    }, quit: { quits += 1 })
    let page = ResetChecklistPage(highlight: .layouts, operation: operation, readLayouts: { profiles }, allApps: {})
    page.show()
    try check(page.boxes.count == 6 && page.boxes.values.allSatisfy { $0.state == .off }, "new checklist is preselected")
    page.boxes[.layouts]!.performClick(nil)
    try check(page.proposedPlan == nil && !page.keyboardPicker.isHidden, "layout reset omitted inline target selection")
    page.keyboardPicker.selectItem(at: 2); page.keyboardPicker.callback?()
    page.boxes[.appearance]!.performClick(nil)
    page.boxes[.privacy]!.performClick(nil)
    page.boxes[.preferences]!.performClick(nil)
    try check(page.proposedPlan?.keyboard == keyboard && page.proposedPlan?.summary.contains("quits") == true, "summary omitted keyboard scope or quit")
    let reset = allButtons(page.view).first { $0.identifier?.rawValue == "reset.selected" }!
    host.modalTestDriver = { alert in
        precondition(alert.informativeText.contains("Offline keyboard") && !alert.informativeText.contains("All apps"))
        return .alertFirstButtonReturn
    }
    reset.performClick(nil)
    try check(calls.isEmpty && !host.interactionBusy && page.boxes[.layouts]?.state == .on, "Cancel executed reset or erased proposal")
    host.modalTestDriver = { _ in .alertSecondButtonReturn }
    reset.performClick(nil)
    try check(operation.running && calls == [.layouts,.appearance,.privacy] && quits == 0, "batch quit early or ran wrong scope/order")
    page.refresh(); try check(!reset.isEnabled, "running batch can be started twice")
    // Leaving does not cancel the operation; its failure/result remains available.
    app.openSetupStage("maintenance")
    callback?(.failure(AppError(message: "Fixture privacy failure")))
    try check(!operation.running && operation.failedPlan?.areas == [.privacy,.preferences] && quits == 0, "failure lost retry scope or reset preferences/quit prematurely")
    operation.start(operation.failedPlan!, retry: true)
    let stale = callback
    callback?(.success("Fixture privacy complete")); stale?(.failure(AppError(message: "Duplicate callback")))
    try check(calls == [.layouts,.appearance,.privacy,.privacy,.preferences] && quits == 1 && operation.failedPlan == nil, "retry repeated successes, accepted duplicate completion, or failed to quit once")
    page.refresh()
    try check(page.status.stringValue.contains("completed"), "results vanished after leaving")
    app.openReset(.allAppsPrivacy, returningToCurrentPage: false)
    try check(host.pages.map(\.title) == ["Reset Settings", "Reset all apps’ privacy permissions?"], "global privacy was combined into checklist")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification)); app.openResets()
    try check(host.pages.count == 1 && host.back.isHidden, "reopened resets retained a stale contextual return")

    // Broad preferences cannot silently erase unchecked appearance or navigation.
    let domain = "perch.checklist-reset." + UUID().uuidString
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let isolated = UserDefaults(suiteName: domain)!
    defer { isolated.removePersistentDomain(forName: domain) }
    isolated.set("appearance-kept", forKey: MenuAppearanceStore.key); isolated.set(Data([1,2]), forKey: KeyboardNavigationProfiles.key); isolated.set(true, forKey: "reverseWheel")
    try SettingsReset.clear(.init(sections: ["preferences"]), defaults: isolated, domain: domain, base: base, preserving: [MenuAppearanceStore.key])
    try check(isolated.string(forKey: MenuAppearanceStore.key) == "appearance-kept" && isolated.data(forKey: KeyboardNavigationProfiles.key) == Data([1,2]) && !isolated.bool(forKey: "reverseWheel"), "unchecked appearance/layouts changed during preference reset")
    print("PASS: flat reset checklist, exact unchecked highlights and contextual Back, inline disconnected layout scope, confirmation/Cancel, asynchronous partial results, retry only failed areas, quit ordering and independent reset areas; injected writes only")
}
