import AppKit
import ServiceManagement

struct SettingsResetSelection {
    var sections: Set<String>
    var all: Bool { sections == Set(Self.options.map { $0.0 }) }
    static let options = [
        ("input", "Scroll reversal and navigation choices"),
        ("keyboard", "Keyboard layouts and remembered Fn/modifier choices"),
        ("monitor", "Monitor inputs, shortcut and confirmations"),
        ("safety", "Agent choices, panic shortcut, catalog and history"),
        ("awake", "Perch’s keep-awake preference"),
        ("display", "CPU display preferences"),
        ("login", "Start at login")
    ]
    func removes(_ key: String) -> Bool {
        if all { return true }
        if sections.contains("awake") && key == SleepMasterChange.lidPreferenceKey { return true }
        if sections.contains("input") && ["reverseTrackpad", "reverseWheel", "swapModifiers"].contains(key) { return true }
        if sections.contains("keyboard") && (key == KeyboardNavigationProfiles.key || key.hasPrefix("modifierSwap.") || key == NativeFunctionKeys.externalIntentKey) { return true }
        if sections.contains("monitor") && (key == MonitorInputController.preferenceKey || key.hasPrefix("monitor.confirmed.")) { return true }
        if sections.contains("safety") && key == "panicShortcut" { return true }
        return sections.contains("display") && key == CPUDisplaySettings.key
    }
    func configuration(_ original: SafetyConfiguration) -> SafetyConfiguration {
        var c = original
        if sections.contains("input") { c.reverseTrackpad = false; c.reverseWheel = false; c.swapModifiers = false; c.navigation = nil }
        if sections.contains("keyboard") { c.navigationProfiles = nil }
        if sections.contains("awake") { c.keepAwake = false }
        if sections.contains("safety") { c.targets = AgentTarget.defaults; c.shortcut = PanicShortcut(); c.resetAgentPermissions = true; c.resetAllPermissions = true }
        return c
    }
}

/// All mutations are reachable only through the explicit Settings confirmation.
/// Tests use a disposable defaults suite/directory and never stop real services.
enum SettingsReset {
    static func clear(_ selection: SettingsResetSelection, defaults: UserDefaults, domain: String, base: URL) throws {
        guard !selection.sections.isEmpty, selection.sections.isSubset(of: Set(SettingsResetSelection.options.map { $0.0 })) else { throw AppError(message:"Choose settings to reset.") }
        let fm = FileManager.default
        let configURL = base.appendingPathComponent("config.json")
        if !selection.all && fm.fileExists(atPath:configURL.path) {
            let config = try JSONDecoder().decode(SafetyConfiguration.self,from:Data(contentsOf:configURL))
            try JSONEncoder().encode(selection.configuration(config)).write(to:configURL,options:.atomic)
        }
        var names: [String] = selection.all ? ["config.json"] : []
        if selection.sections.contains("safety") { names += ["agents.json","state.json","events.jsonl","events-previous.jsonl","Safety report.txt","shortcut-test-lease.json"] }
        for name in names {
            let path = base.appendingPathComponent(name)
            if fm.fileExists(atPath:path.path) { try fm.removeItem(at:path) }
        }
        // Clear queued old panic/test requests on every reset, after helpers stop.
        let requests = base.appendingPathComponent("requests")
        if fm.fileExists(atPath:requests.path) {
            for url in try fm.contentsOfDirectory(at:requests,includingPropertiesForKeys:nil) where url.pathExtension == "json" {
                try fm.removeItem(at:url)
            }
        }
        if selection.all { defaults.removePersistentDomain(forName:domain) }
        else {
            for key in (defaults.persistentDomain(forName:domain) ?? [:]).keys where selection.removes(key) { defaults.removeObject(forKey:key) }
        }
        guard defaults.synchronize() else { throw AppError(message:"Could not finish writing the preference reset. Perch remains open.") }
    }
    static func stopHelpers() throws {
        // Refuse to discard a lockdown that still owns disabled launch jobs.
        if FileManager.default.fileExists(atPath:SafetyFiles.state.path) {
            let state = try SafetyFiles.read(SafetyState.self,from:SafetyFiles.state)
            guard !state.locked && state.disabledJobs.isEmpty else { throw AppError(message:"Resume Agent Kill Switch first, then reset settings. This preserves the record of blocked launch jobs.") }
        }
        for label in [GuardianInstall.label, "local.scott.perch.input"] {
            let service = "gui/\(getuid())/" + label
            if SafetyCommand.run("/bin/launchctl",["print",service]) == "ok" {
                let result = SafetyCommand.run("/bin/launchctl",["bootout",service])
                guard result == "ok" else { throw AppError(message:"Could not stop \(label): \(result). No preferences have been erased.") }
            }
            guard SafetyCommand.run("/bin/launchctl",["print",service]) != "ok" else { throw AppError(message:"A Perch helper is still running; reset stopped.") }
        }
        for label in [GuardianInstall.label, "local.scott.perch.input"] {
            let path = GuardianInstall.plist.deletingLastPathComponent().appendingPathComponent(label + ".plist")
            if FileManager.default.fileExists(atPath:path.path) { try FileManager.default.removeItem(at:path) }
        }
    }
}

extension AppDelegate {
    @objc func resetSettingsPage() {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:340))
        var boxes: [(String,NSButton)] = []
        for (i,option) in SettingsResetSelection.options.enumerated() {
            let box = NSButton(checkboxWithTitle:option.1,target:nil,action:nil)
            box.frame = NSRect(x:0,y:300-i*35,width:572,height:28); box.state = .on
            boxes.append((option.0,box)); page.addSubview(box)
        }
        let next = SettingsActionButton(title:"Review reset & quit…") { [weak self] in
            let selection = SettingsResetSelection(sections:Set(boxes.filter { $0.1.state == .on }.map { $0.0 }))
            guard !selection.sections.isEmpty else { return }
            self?.confirmSettingsReset(selection)
        }
        next.frame = NSRect(x:260,y:5,width:312,height:32); page.addSubview(next)
        SettingsWindow.shared.show(.init(title:"Reset settings",detail:"Select everything for a fresh Perch, or only the sections to forget. Reset stops Perch’s input and protection helpers and quits. Reopening starts them again. macOS permissions, lid-sleep settings, audio, and keyboard firmware/system settings are unchanged; their current state will be queried again. The collector installation remains installed.",view:page))
    }
    func confirmSettingsReset(_ selection: SettingsResetSelection) {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:180))
        let status = NSTextField(wrappingLabelWithString:"This removes the selected saved choices. Perch’s emergency shortcut and input controls stop until you reopen Perch. A Perch keep-awake assertion is released when its helper stops. Back cancels.")
        status.frame = NSRect(x:0,y:60,width:572,height:110); status.textColor = StatusColors.warning
        let action = SettingsActionButton(title:selection.all ? "Reset all settings and quit" : "Reset selected settings and quit") { [weak self] in
            guard let self, !SettingsWindow.shared.testing else { return }
            do {
                try SettingsReset.stopHelpers()
                if selection.sections.contains("login"), SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
                try SettingsReset.clear(selection,defaults:.standard,domain:Bundle.main.bundleIdentifier ?? "local.scott.perch",base:SafetyFiles.base)
                NSApp.terminate(nil)
            } catch {
                status.stringValue = error.localizedDescription + " Some helpers may be stopped; reopen Perch to restore them."
                self.refresh()
            }
        }
        action.frame = NSRect(x:170,y:5,width:402,height:32)
        page.addSubview(status); page.addSubview(action)
        let names = SettingsResetSelection.options.filter { selection.sections.contains($0.0) }.map { $0.1 }.joined(separator:", ")
        SettingsWindow.shared.show(.init(title:selection.all ? "Reset all settings?" : "Reset selected settings?",detail:names,view:page))
    }
}
