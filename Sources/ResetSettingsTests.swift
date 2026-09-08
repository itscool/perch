import Foundation

func runSettingsResetTests() throws {
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
