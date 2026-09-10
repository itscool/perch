import AppKit

extension AppDelegate {
    func installSettingsNavigation() {
        func item(_ id: String, _ title: String, _ pages: [String], _ selector: Selector, depth: Int = 0) -> SettingsDestination {
            SettingsDestination(id: id, title: title, pageTitles: pages, depth: depth, open: { [weak self] in _ = self?.perform(selector) })
        }
        SettingsWindow.shared.configureNavigation([
            item("overview", "Setup & status", ["Setup & status"], #selector(setupOverview)),
            item("keyboard", "Keyboards", ["Keyboard settings"], #selector(keyboardSettings)),
            item("navigation", "Navigation keys", ["Navigation keys"], #selector(navigationSettings), depth: 1),
            item("layouts", "Keyboard layouts", ["Set up navigation keys"], #selector(testNavigationKeys), depth: 1),
            item("exceptions", "App exceptions", ["Navigation app exceptions"], #selector(navigationExceptions), depth: 1),
            item("keyboard-access", "Keyboard access", ["Keyboard access"], #selector(keyboardAccessRecovery), depth: 1),
            item("keyboard-details", "Keyboard details", ["Keyboard details"], #selector(keyboardDetails), depth: 1),
            item("scrolling", "Scrolling", ["Scrolling"], #selector(scrollingSettings)),
            item("displays", "Displays", ["Displays"], #selector(displaySettings)),
            item("desk", "Desk", ["Desk"], #selector(deskSettings), depth: 1),
            item("awake", "Keep awake", ["Keep awake"], #selector(keepAwakeSettings)),
            item("lid-activity", "Lid activity", ["Lid activity"], #selector(lidActivity), depth: 1),
            item("agents", "Agent Kill Switch", ["Agent Kill Switch"], #selector(configurePanic)),
            item("agent-choices", "Agents & shortcut", ["Agents, shortcut & panic actions"], #selector(editSafetyConfiguration), depth: 1),
            item("custom-agents", "Add or remove agents", ["Add or remove agents"], #selector(manageAgents), depth: 1),
            item("recognition", "Recognition", ["Agent recognition"], #selector(agentRecognition), depth: 1),
            item("events", "Process event collection", ["Process event collection"], #selector(processEventSetup), depth: 1),
            item("targets", "Target preview", ["Preview panic targets"], #selector(safetyReport), depth: 1),
            item("app", "App settings", ["App settings"], #selector(appSettings)),
            item("appearance", "Menu Appearance", ["Menu Appearance"], #selector(appearanceSettings), depth: 1),
            item("updates", "Updates", ["Updates"], #selector(updateSettings), depth: 1),
            item("maintenance", "Maintenance", ["Maintenance"], #selector(advancedSafetySettings)),
            item("input-access", "Input access", ["Input controls"], #selector(inputPermissionsFromSettings), depth: 1),
            item("reset", "Reset Perch settings", ["Reset settings"], #selector(resetSettingsPage), depth: 1)
        ])
    }
}
