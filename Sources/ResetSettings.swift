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
    static func clear(_ selection: SettingsResetSelection, defaults: UserDefaults, domain: String, base: URL, preserving: Set<String> = []) throws {
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
            for key in (defaults.persistentDomain(forName:domain) ?? [:]).keys where selection.removes(key) && !preserving.contains(key) { defaults.removeObject(forKey:key) }
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

enum SettingsResetScope: CaseIterable, Hashable {
    case settings, keyboardLayouts, appearance, perchPrivacy, sleep, allAppsPrivacy
    var area: ResetArea? {
        switch self {
        case .settings: return .preferences
        case .keyboardLayouts: return .layouts
        case .appearance: return .appearance
        case .perchPrivacy: return .privacy
        case .sleep: return .sleep
        case .allAppsPrivacy: return nil
        }
    }
    var title: String { self == .allAppsPrivacy ? "Reset all apps’ privacy permissions?" : "Reset Settings" }

}

extension AppDelegate {
    func openReset(_ scope: SettingsResetScope, returningToCurrentPage: Bool = true) {
        if menuOpen { withMenuClosed { [weak self] in self?.openReset(scope, returningToCurrentPage: returningToCurrentPage) }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.openReset(scope, returningToCurrentPage: returningToCurrentPage) }; return }
        if !host.hasSidebar { installSettingsNavigation() }
        host.navigateToReset(scope, returningToCurrentPage: returningToCurrentPage)
    }
    func presentResetScope(_ scope: SettingsResetScope) {
        if scope == .allAppsPrivacy {
            if SettingsWindow.shared.pages.isEmpty { resetHub() }
            privacyOnlyReset(global: true)
        } else { presentResetChecklist(highlight: scope.area) }
    }
    @objc func openResets() {
        if menuOpen { withMenuClosed { [weak self] in self?.openResets() }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.openResets() }; return }
        if !host.hasSidebar { installSettingsNavigation() }
        host.navigateToResets()
    }
    @objc func resetHub() { presentResetChecklist() }
    func presentResetChecklist(highlight: ResetArea? = nil, operation: ResetBatchOperation = .shared,
                               readLayouts: @escaping () throws -> [NavigationKeyboardProfile] = { try KeyboardNavigationProfiles.read() }) {
        let page = ResetChecklistPage(highlight: highlight, operation: operation, readLayouts: readLayouts,
            allApps: { [weak self] in self?.privacyOnlyReset(global: true) })
        page.show()
    }
}
