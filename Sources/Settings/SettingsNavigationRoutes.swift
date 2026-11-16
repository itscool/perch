import AppKit

extension AppDelegate {
    /// Every prerequisite/repair entry chooses its one Setup destination. The
    /// destination owns the overview and stage; feature pages never embed it.
    func openSetupStage(_ id: String) {
        if menuOpen { withMenuClosed { [weak self] in self?.openSetupStage(id) }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.openSetupStage(id) }; return }
        if !host.hasSidebar { installSettingsNavigation() }
        host.navigateToSetupStage(id)
    }
    func installSettingsNavigation() {
        // The same states the Setup page shows: one source for both.
        SettingsWindow.shared.sidebar.readSetupStatus = { [weak self] in
            guard let self else { return [:] }
            return self.setupSnapshot().sidebar.mapValues { state in
                switch state { case .ready: .ready; case .attention: .attention; case .optional: .optional; case .checking: .checking }
            }
        }
        SettingsWindow.shared.configureNavigation(settingsDestinations())
        SettingsWindow.shared.configureResetNavigation(Dictionary(uniqueKeysWithValues: SettingsResetScope.allCases.map { scope in
            (scope, SettingsDestination(id: "reset", title: scope.title, pageTitles: [scope.title], open: { [weak self] in self?.presentResetScope(scope) }))
        }))
    }
    /// The sidebar's rows, in order. Built without a window, so a headless test
    /// can compare them with the Setup page's rows.
    func settingsDestinations() -> [SettingsDestination] {
        func item(_ id: String, _ title: String, _ pages: [String], _ selector: Selector, depth: Int = 0, setupStage: Bool = false, flagsAttention: Bool = false) -> SettingsDestination {
            SettingsDestination(id: id, title: title, pageTitles: pages, depth: depth, setupStage: setupStage, flagsAttention: flagsAttention, open: { [weak self] in _ = self?.perform(selector) })
        }
        return [
            item("overview", "Setup", ["Setup & status"], #selector(setupOverview)),
            item("maintenance", "Background helpers", ["Background helpers"], #selector(presentBackgroundSetup), depth: 1, setupStage: true),
            item("keyboard-access", "Keyboard access", ["Keyboard access"], #selector(presentKeyboardAccessStage), depth: 1, setupStage: true),
            item("input-access", "Scrolling & navigation", ["Scrolling & navigation access"], #selector(presentInputAccessStage), depth: 1, setupStage: true),
            item("sharing-access", "Shared input access", ["Shared input access"], #selector(presentSharingAccessStage), depth: 1, setupStage: true),
            item("lid-setup", "Lid protection", ["Lid protection setup"], #selector(presentLidSetupStage), depth: 1, setupStage: true),
            item("keyboard", "Keyboards", ["Keyboards", "Set up navigation keys"], #selector(keyboardSettings), flagsAttention: true),
            item("exceptions", "App exceptions", ["Navigation app exceptions"], #selector(navigationExceptions), depth: 1),
            item("desk", "Desk", ["Desk"], #selector(deskSettings), flagsAttention: true),
            item("desk-input", "Input options", ["Input options"], #selector(deskInputPreferences), depth: 1),
            item("logs", "Logs", ["Logs"], #selector(logsSettings)),
            item("lid-activity", "Lid activity", ["Lid activity"], #selector(lidActivity), depth: 1),
            item("cpu-logs", "CPU logs", ["CPU logs"], #selector(cpuLogs), depth: 1),
            item("desk-connection-logs", "Desk connection activity", ["Desk connection activity"], #selector(deskConnectionLogs), depth: 1),
            item("app", "App settings", ["App settings"], #selector(appSettings)),
            item("hotkeys", "Hotkeys", ["Hotkeys"], #selector(hotkeySettings), depth: 1),
            item("appearance", "Menu Appearance", ["Menu Appearance"], #selector(appearanceSettings), depth: 1),
            item("updates", "Updates", ["Updates"], #selector(updateSettings), depth: 1),
            item("reset", "Reset Settings", ["Reset Settings"], #selector(resetHub))
        ]
    }
}
