import AppKit
import ServiceManagement

struct SettingsResetSelection {
    var sections: Set<String>
    var all: Bool { sections == Set(Self.options.map { $0.0 }) }
    static let options = [
        ("devices", "Learned navigation layouts on this Mac"),
        ("preferences", "Local Perch preferences — keyboard modes, feature choices and agents")
    ]
    func removes(_ key: String) -> Bool {
        if all { return true }
        let deviceKey = key == KeyboardNavigationProfiles.key || key == MonitorInputController.preferenceKey || key == MonitorInputController.savedPlansKey || key == MonitorGroupController.preferenceKey || key.hasPrefix("monitor.confirmed.")
        if sections.contains("devices") && deviceKey { return true }
        return sections.contains("preferences") && !deviceKey
    }
    func configuration(_ original: SafetyConfiguration) -> SafetyConfiguration {
        var c = sections.contains("preferences") ? SafetyConfiguration() : original
        if sections.contains("preferences") { c.reverseTrackpad = false; c.reverseWheel = false; c.swapModifiers = false }
        c.navigationProfiles = sections.contains("devices") ? nil : original.navigationProfiles
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
        if selection.sections.contains("preferences") { names += ["agents.json","state.json","events.jsonl","events-previous.jsonl","Safety report.txt","shortcut-test-lease.json"] }
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
        if selection.sections.contains("preferences"), !selection.sections.contains("devices"),
           let data = defaults.data(forKey:MonitorInputController.preferenceKey),
           var plan = try? JSONDecoder().decode(MonitorInputPlan.self,from:data) {
            plan.shortcut = MonitorInputPlan().shortcut
            plan.allowUnconfirmedCycle = false
            defaults.set(try JSONEncoder().encode(plan),forKey:MonitorInputController.preferenceKey)
        }
        if selection.sections.contains("preferences"), !selection.sections.contains("devices"),
           let data = defaults.data(forKey: MonitorInputController.savedPlansKey),
           var plans = try? JSONDecoder().decode([String: MonitorInputPlan].self, from: data) {
            for key in Array(plans.keys) {
                plans[key]?.shortcut = MonitorInputPlan().shortcut
                plans[key]?.allowUnconfirmedCycle = false
            }
            defaults.set(try JSONEncoder().encode(plans), forKey: MonitorInputController.savedPlansKey)
        }
        if selection.sections.contains("preferences"), !selection.sections.contains("devices"),
           let data = defaults.data(forKey: MonitorGroupController.preferenceKey),
           var settings = try? JSONDecoder().decode(MonitorGroupSettings.self, from: data) {
            settings.activeID = nil
            for i in settings.groups.indices { settings.groups[i].shortcut.enabled = false }
            defaults.set(try JSONEncoder().encode(settings), forKey: MonitorGroupController.preferenceKey)
        }
        guard defaults.synchronize() else { throw AppError(message:"Could not finish writing the preference reset. Perch remains open.") }
    }
    static func stopHelpers() throws {
        // Refuse to discard a lockdown that still owns disabled launch jobs.
        if FileManager.default.fileExists(atPath:SafetyFiles.state.path) {
            let state = try SafetyFiles.read(SafetyState.self,from:SafetyFiles.state)
            guard !state.locked && state.disabledJobs.isEmpty else { throw AppError(message:"Resume Agent Kill Switch first, then reset settings. This preserves the record of blocked launch jobs.") }
        }
        try LidGuardInstall.cleanup()
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
    @objc func openResets() {
        if menuOpen { withMenuClosed { [weak self] in self?.openResets() }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.openResets() }; return }
        if !host.hasSidebar { installSettingsNavigation() }
        host.navigateToResets()
    }
    @objc func resetHub() {
        let page = SettingsTaskPage(title: "Resets", detail: "Choose what you want to reset. Each option explains its scope before you make changes.", height: 558)
        page.status.stringValue = "Nothing changes when you open a reset option. Setup is available whenever you need to restore access afterward."
        page.add("Saved Perch settings…", detail: "Choose local preferences or learned layouts to forget. Perch quits after the reset; shared Desk setup is kept.") { [weak self] in self?.resetSettingsPage() }
        page.add("Keyboard layouts…", detail: "Forget one or all learned navigation layouts without quitting. Disconnected keyboards are included; Fn and modifier choices stay as they are.") { [weak self] in self?.presentKeyboardLayoutReset() }
        page.add("Menu appearance…", detail: "Restore Perch’s original appearance for both rainbow sections and System. Other preferences are kept.") { [weak self] in self?.presentAppearanceReset() }
        page.add("Perch privacy permissions…", detail: "Forget macOS permission decisions for Perch and its helpers. Other apps and your saved Perch choices are excluded.") { [weak self] in self?.privacyOnlyReset(global: false) }
        page.add("Sleep & audio…", detail: "Choose to end Perch’s sleep protection or unmute system audio. Other apps’ sleep assertions and unowned overrides are kept.") { [weak self] in self?.systemResetPage() }
        page.add("All apps’ privacy permissions…", detail: "Broader reset: forget permission decisions for every app in your macOS account. Apps may ask for access again; this does not stop agents.") { [weak self] in self?.privacyOnlyReset(global: true) }
        page.show()
    }
    func presentKeyboardLayoutReset(read: @escaping () throws -> [NavigationKeyboardProfile] = { try KeyboardNavigationProfiles.read() }, reset: ((NavigationKeyboardIdentity?) throws -> Void)? = nil) {
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 210))
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 160, width: 572, height: 30))
        picker.setAccessibilityLabel("Keyboard layout to reset")
        let status = SettingsStatusField(wrappingLabelWithString: "")
        status.frame = NSRect(x: 0, y: 57, width: 572, height: 92)
        var profiles: [NavigationKeyboardProfile] = []
        let reload = {
            picker.removeAllItems(); picker.addItems(withTitles: ["Choose a layout…", "All saved navigation layouts"])
            do {
                profiles = try read()
                for profile in profiles {
                    let id = profile.identity
                    picker.addItem(withTitle: "\(id.name) · \(id.transport) · \(id.vendor):\(id.product) v\(id.version)")
                }
                status.stringValue = profiles.isEmpty ? "No learned layouts are saved. Bundled layouts remain available." : "Choose a saved keyboard, even if disconnected, or all layouts. Bundled defaults remain available."
                status.textColor = .secondaryLabelColor
            } catch {
                profiles = []; status.stringValue = error.localizedDescription + " You can reset all saved layouts to remove unreadable data."
                status.textColor = StatusColors.warning
            }
        }
        reload()
        weak var actionReference: NSButton?
        let action = SettingsActionButton(title: "Reset selected layout…") {
            let index = picker.indexOfSelectedItem
            guard index > 0, index == 1 || profiles.indices.contains(index - 2) else { return }
            let identity = index == 1 ? nil : profiles[index - 2].identity
            let alert = NSAlert()
            alert.messageText = identity == nil ? "Reset all saved navigation layouts?" : "Reset this navigation layout?"
            alert.informativeText = (identity.map { "\($0.name) · \($0.transport). " } ?? "All learned keyboard layouts on this Mac. ") + "Bundled defaults remain available. Fn, modifier and permission settings are kept."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Reset layout" + (identity == nil ? "s" : ""))
            SettingsWindow.shared.present(alert) { response in
                guard response == .alertSecondButtonReturn, !SettingsWindow.shared.testing || reset != nil else { return }
                do {
                    try (reset ?? { try KeyboardNavigationProfiles.reset($0) })(identity)
                    reload(); actionReference?.isEnabled = false
                    status.stringValue = "Layout reset completed. Bundled defaults remain available; you can learn a replacement in Keyboard layouts."
                    status.textColor = StatusColors.success
                } catch { status.stringValue = error.localizedDescription; status.textColor = StatusColors.warning }
            }
        }
        action.frame = NSRect(x: 0, y: 10, width: 572, height: 32)
        actionReference = action; action.isEnabled = false
        let refresh = { action.isEnabled = picker.indexOfSelectedItem > 0 }
        // Native popup changes dispatch immediately; completion also clears selection.
        let target = SettingsActionButton(title: "", action: refresh)
        picker.target = target; picker.action = #selector(SettingsActionButton.invoke)
        [picker, status, action].forEach { page.addSubview($0) }
        SettingsWindow.shared.show(.init(title: "Reset keyboard layouts", detail: "Resetting a learned layout changes only Perch’s saved navigation key mapping. Choose the scope, then confirm.", view: page, refresh: { _ = target; refresh() }))
    }
    func presentAppearanceReset(store: MenuAppearanceStore = .shared) {
        let page = SettingsTaskPage(title: "Reset menu appearance", detail: "Restore the original menu style for rainbow sections and System. Other settings and permissions are kept.", height: 170)
        page.status.stringValue = "Your current appearance is kept until you select Restore original appearance."
        page.add("Restore original appearance", detail: "Replaces both appearance sections immediately. You can customize them again in Menu Appearance.") { [weak page] in
            guard !SettingsWindow.shared.testing || store !== MenuAppearanceStore.shared else { return }
            store.save(MenuAppearance(), restoring: true)
            page?.status.stringValue = store.problem ?? "Original appearance restored."
            page?.status.textColor = store.problem == nil ? StatusColors.success : StatusColors.warning
        }
        page.show()
    }
    @objc func resetSettingsPage() {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:160))
        weak var reviewButton: NSButton?
        var boxes: [(String,NSButton)] = []
        for (i,option) in SettingsResetSelection.options.enumerated() {
            let box = SettingsActionButton(title:option.1) { [weak page] in
                reviewButton?.isEnabled = page?.subviews.compactMap { $0 as? NSButton }.contains { $0.state == .on } == true
            }
            box.setButtonType(.switch)
            box.frame = NSRect(x:0,y:120-i*35,width:572,height:28); box.state = .off
            boxes.append((option.0,box)); page.addSubview(box)
        }
        let next = SettingsActionButton(title:"Review reset & quit…") { [weak self] in
            let selection = SettingsResetSelection(sections:Set(boxes.filter { $0.1.state == .on }.map { $0.0 }))
            guard !selection.sections.isEmpty else { return }
            self?.confirmSettingsReset(selection)
        }
        reviewButton = next; next.isEnabled = false
        next.frame = NSRect(x:260,y:5,width:312,height:32); page.addSubview(next)
        SettingsWindow.shared.show(.init(title:"Reset settings",detail:"Choose what to forget, then review before resetting and quitting. Resetting learned layouts restores bundled layout defaults. This resets only the local choices selected above. Shared Desk computers, screen arrangements, connections and preset shortcuts are retained. Privacy and system permissions are not reset.",view:page))
    }
    func confirmSettingsReset(_ selection: SettingsResetSelection) {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:180))
        let status = NSTextField(wrappingLabelWithString:"This removes the selected saved choices. Learned layouts, if selected, return to bundled defaults. Perch’s emergency shortcut and input controls stop until you reopen Perch. A Perch keep-awake assertion is released when its helper stops. Back cancels.")
        status.frame = NSRect(x:0,y:60,width:572,height:110); status.textColor = StatusColors.warning
        let action = SettingsActionButton(title:selection.all ? "Reset local settings and quit" : "Reset selected settings and quit") { [weak self] in
            guard let self, !SettingsWindow.shared.testing else { return }
            do {
                try SettingsReset.stopHelpers()
                if selection.sections.contains("preferences"), SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
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
        SettingsWindow.shared.show(.init(title:selection.all ? "Reset local settings?" : "Reset selected settings?",detail:names + "\nShared Desk setup and membership are kept on this and the other computers.",view:page))
    }
}
