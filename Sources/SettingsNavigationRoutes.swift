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
        func item(_ id: String, _ title: String, _ pages: [String], _ selector: Selector, depth: Int = 0, setupStage: Bool = false) -> SettingsDestination {
            SettingsDestination(id: id, title: title, pageTitles: pages, depth: depth, setupStage: setupStage, open: { [weak self] in _ = self?.perform(selector) })
        }
        SettingsWindow.shared.sidebar.readSetupStatus = { [weak self] in
            guard let self else { return [:] }
            let snapshot = self.setupSnapshot()
            let helper = snapshot.checks.first { $0.id == "helpers" }?.state
            let tracking = snapshot.checks.first { $0.id == "events" }?.state
            let inputReady = InputReadiness.assess(input: snapshot.input, config: snapshot.config)
            func status(_ state: SetupCheck.State?) -> SettingsSetupStatus {
                switch state { case .ready: .ready; case .attention, .unverified: .attention; case .optional: .optional; default: .checking }
            }
            return [
                "maintenance": status(helper),
                "keyboard-access": NavigationProbeHID.hasAccess ? .ready : .attention,
                "input-access": inputReady.ready ? .ready : snapshot.input?.fresh != true ? .checking : .attention,
                "sharing-access": AXIsProcessTrusted() && CGPreflightPostEventAccess() && CGPreflightListenEventAccess() ? .ready : .attention,
                "lid-setup": snapshot.lidHelperUpdatePending ? .attention : snapshot.lidHelperInstalled ? .ready : snapshot.lidWanted ? .attention : .optional,
                "events": status(tracking)
            ]
        }
        SettingsWindow.shared.configureNavigation([
            item("overview", "Setup", ["Setup & status"], #selector(setupOverview)),
            item("maintenance", "Background helpers", ["Background helpers"], #selector(presentBackgroundSetup), depth: 1, setupStage: true),
            item("keyboard-access", "Keyboard access", ["Keyboard access"], #selector(presentKeyboardAccessStage), depth: 1, setupStage: true),
            item("input-access", "Scrolling & navigation", ["Scrolling & navigation access"], #selector(presentInputAccessStage), depth: 1, setupStage: true),
            item("sharing-access", "Shared input access", ["Shared input access"], #selector(presentSharingAccessStage), depth: 1, setupStage: true),
            item("lid-setup", "Lid protection", ["Lid protection setup"], #selector(presentLidSetupStage), depth: 1, setupStage: true),
            item("events", "Agent tracking", ["Process event collection"], #selector(presentEventSetupStage), depth: 1, setupStage: true),
            item("keyboard", "Keyboards", ["Keyboards", "Set up navigation keys"], #selector(keyboardSettings)),
            item("exceptions", "App exceptions", ["Navigation app exceptions"], #selector(navigationExceptions), depth: 1),
            item("desk", "Desk", ["Desk"], #selector(deskSettings)),
            item("desk-input", "Input options", ["Input options"], #selector(deskInputPreferences), depth: 1),
            item("lid-activity", "Lid activity", ["Lid activity"], #selector(lidActivity)),
            item("agents", "Agent Kill Switch", ["Agent Kill Switch"], #selector(configurePanic)),
            item("agent-choices", "Agents & panic actions", ["Agents & panic actions"], #selector(editSafetyConfiguration), depth: 1),
            item("custom-agents", "Add or remove agents", ["Add or remove agents"], #selector(manageAgents), depth: 1),
            item("recognition", "Recognition", ["Agent recognition"], #selector(agentRecognition), depth: 1),
            item("targets", "Target preview", ["Preview panic targets"], #selector(safetyReport), depth: 1),
            item("security", "Security", ["Security"], #selector(securitySettings)),
            item("app", "App settings", ["App settings"], #selector(appSettings)),
            item("hotkeys", "Hotkeys", ["Hotkeys"], #selector(hotkeySettings), depth: 1),
            item("appearance", "Menu Appearance", ["Menu Appearance"], #selector(appearanceSettings), depth: 1),
            item("updates", "Updates", ["Updates"], #selector(updateSettings), depth: 1),
            item("reset", "Reset Settings", ["Reset Settings"], #selector(resetHub))
        ])
        SettingsWindow.shared.configureResetNavigation(Dictionary(uniqueKeysWithValues: SettingsResetScope.allCases.map { scope in
            (scope, SettingsDestination(id: "reset", title: scope.title, pageTitles: [scope.title], open: { [weak self] in self?.presentResetScope(scope) }))
        }))
    }
}
