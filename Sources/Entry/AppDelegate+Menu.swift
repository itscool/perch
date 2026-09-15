import AppKit
import ServiceManagement

/// The status item and its menu: construction, labels, refresh, validation
/// and the shared error/action plumbing every menu command uses.
extension AppDelegate {
    // Kept separate from helper installation so the real menu can be checked safely.
    func buildMenu() {
        menu.delegate = self
        section("System")
        for title in ["Mac", "CPU", "GPU", "Memory", "Thermal"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.view = MenuRowView(item: item, kind: .information)
            label(item, title, hint: "--", hintColor: StatusColors.information)
            menu.addItem(item); systemItems.append(item)
        }
        setupSafetyMenu()
        section("Displays")
        let displayItem = add("Turn display off", #selector(turnDisplayOff), help: ControlHelp.display)
        label(displayItem, "Turn display off", hint: "Move mouse to wake")
        do {
        shareInputItem = add("Share on this Mac", #selector(toggleDeskSharing), help: "Allow approved Desk computers to send keyboard and mouse input to this Mac. Enabled by default; an active preset with a remote screen starts control automatically.")
            for i in 0..<3 { let item = add("Preset \(i+1)", #selector(useDeskPreset(_:)), help: "Switch monitor inputs to this Desk preset. Keyboard and mouse stay on their current computer."); item.tag = i; deskPresetItems.append(item) }
            refreshDeskMenu()
        }
        audioSection = section("Audio")
        audioItem = add("Mute audio", #selector(toggleAudio), help: ControlHelp.audio)
        section("Scrolling")
        trackpadItem = add("Reverse trackpad scroll", #selector(toggleTrackpad), help: ControlHelp.trackpad)
        wheelItem = add("Reverse mouse wheel", #selector(toggleWheel), help: ControlHelp.wheel)
        section("Built-in keyboard")
        swapItem = add("Swap Control ↔ Command keys", #selector(toggleModifiers), help: ControlHelp.builtInModifiers)
        fnItem = add("Use F1–F12 directly", #selector(toggleFunctionKeys), help: ControlHelp.builtInFn)
        externalKeyboardSection = section("External keyboards")
        externalSwapItem = add("Swap Control ↔ Command keys", #selector(toggleExternalModifiers), help: ControlHelp.externalModifiers)
        keypadItem = add("Use Num Lock for keypad navigation", #selector(toggleKeypadNavigation), help: "Num Lock/Clear switches each external keypad between numbers and navigation keys. Starts in number mode after restart or wake. Decimal punctuation is unchanged in number mode; hardware LEDs may not reflect Perch’s mode.")
        externalFnItem = add("Use F1–F12 directly", #selector(toggleExternalFunctionKeys), help: ControlHelp.externalFn)
        homeEndItem = add("Home/End move to line edges", #selector(toggleHomeEnd), help: ControlHelp.homeEnd)
        pageKeysItem = add("Page Up/Down move the cursor", #selector(togglePageKeys), help: ControlHelp.pageKeys)
        keyboardSetupItem = add("Set up keyboard…", #selector(keyboardSettings), help: ControlHelp.keyboardSetup)
        keyboardSetupItem.isHidden = true
        section("Sleep")
        awakeItem = add("Keep awake", #selector(toggleAwake), help: ControlHelp.awake)
        lidItem = add("Including with lid closed", #selector(toggleLid), help: ControlHelp.lid)
        idleLockItem = add("Prevent idle lock", #selector(toggleIdleLock), help: ControlHelp.idleLock)
        section("Perch")
        let installed = NSMenuItem(title: "Installed Perch", action: nil, keyEquivalent: "")
        installed.view = MenuRowView(item: installed, kind: .information)
        installed.isHidden = true; menu.addItem(installed); replacementInfoItem = installed
        loginItem = add("Start at login", #selector(toggleLogin), help: ControlHelp.login)
        safetySettingsItem = add("Settings…", #selector(configureSettings), help: ControlHelp.settings)
        _ = add("About Perch", #selector(about), help: ControlHelp.about)
        replacementRestartItem = add("Restart Perch", #selector(restartForReplacement), help: "Close and reopen the installed Perch, keeping your saved choices and an active lid session’s existing timeout. The app and handoff are verified before quitting.")
        replacementRestartItem?.isHidden = true
        let quit = add("Quit Perch", #selector(quit), help: ControlHelp.quit)
        quit.keyEquivalent = "q"
        label(quit, "Quit Perch")
        for item in [awakeItem, lidItem, idleLockItem, audioItem, trackpadItem, wheelItem, swapItem, externalSwapItem, fnItem, externalFnItem, keypadItem, homeEndItem, pageKeysItem, loginItem, shareInputItem].compactMap({ $0 }) {
            item.view = MenuRowView(item: item, kind: .toggle, text: menuTitleSources[item])
        }
        (lidItem.view as? MenuRowView)?.opensAnotherInterface = { true }
        (awakeItem.view as? MenuRowView)?.opensAnotherInterface = { [weak self] in
            self?.lidItem.state != .off || UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
        }
        (loginItem.view as? MenuRowView)?.opensAnotherInterface = { SMAppService.mainApp.status == .requiresApproval }
        MenuAppearanceStore.shared.changed = { [weak self] in self?.styleMenuSections(); self?.menu.items.forEach { $0.view?.needsDisplay = true } }
        styleMenuSections()
        systemMonitor.processCPU.onUpdate = { [weak self] in
            guard let self, self.menuOpen, self.systemItems.count > 1 else { return }
            self.showSystemReading(self.systemItems[1], self.systemMonitor.cpuReading)
        }
    }
    func add(_ title: String, _ action: Selector, help: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.menuHelp = help
        item.view = MenuRowView(item: item, kind: .command)
        menu.addItem(item)
        return item
    }
    @discardableResult func section(_ title: String) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: title)
        item.view = MenuRowView(item: item, kind: .section)
        menu.addItem(item)
        return item
    }

    func label(_ item: NSMenuItem, _ title: String, hint: String = "", hintColor: NSColor = .secondaryLabelColor, hintWeight: NSFont.Weight = .regular) {
        let text = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        if !hint.isEmpty {
            text.append(NSAttributedString(string: "  \u{2002}" + hint, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: hintWeight), .foregroundColor: hintColor]))
        }
        if item.title != title { item.title = title }
        setMenuTitle(item, text)
    }
    func menuWillOpen(_ menu: NSMenu) {
        refreshAppReplacement(showNotice: false)
        appReplacement.check()
        menuOpen = true; menuGeneration &+= 1
        beginMenuKeyboardHandling()
        let generation = menuGeneration
        refreshMenuAppearance()
        nativeKeyboards = NativeModifierKeys.keyboards()
        keyboardModes.readForPresentation() // Read only; never reapply a saved hardware choice.
        refresh()
        // One quick second interval, then the existing menu refresh cadence.
        for item in menu.items { (item.view as? MenuRowView)?.holdsMenuWidth = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.menuOpen, self.menuGeneration == generation else { return }
            self.refreshSystem()
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false; menuGeneration &+= 1; systemMonitor.menuClosed()
        for item in menu.items { (item.view as? MenuRowView)?.holdsMenuWidth = false }
        endMenuKeyboardHandling()
        DispatchQueue.main.async { [weak self] in self?.refreshAppReplacement() }
    }
    func showSystemReading(_ item: NSMenuItem, _ reading: SystemReading) {
        let color: NSColor
        switch reading.level {
        case .critical: color = StatusColors.critical
        case .warning: color = StatusColors.warning
        case .unavailable: color = .secondaryLabelColor
        case .information: color = StatusColors.information
        }
        label(item, reading.title, hint: reading.detail, hintColor: color)
        item.menuHelp = reading.help
    }
    func refreshSystem() {
        guard menuOpen else { return }
        for (item, reading) in zip(systemItems, systemMonitor.read()) { showSystemReading(item, reading) }
    }
    func refresh() {
        refreshSystem()
        refreshAppReplacement()
        let settings = SafetyConfiguration.load()
        inputs.reverseTrackpad = settings.reverseTrackpad
        inputs.reverseWheel = settings.reverseWheel
        inputs.navigation.preferences = settings.navigation ?? NavigationPreferences()
        inputs.swapModifiers = false // Modifier swaps now run in macOS, per keyboard.
        for (item, enabled) in [(trackpadItem!, inputs.reverseTrackpad), (wheelItem!, inputs.reverseWheel)] {
            item.state = enabled ? .on : .off
        }
        refreshKeypadNavigation()
        refreshScrolling(input: HelperStatusIPC.inputClient.value)
        refreshModifierItems()
        if !checkedStartupInputAccess, Date() >= inputStartupGraceEnds,
           let protection = GuardianInstall.status, protection.fresh, protection.inputTrusted != nil {
            checkedStartupInputAccess = true
            if inputs.wanted && protection.inputTrusted == false {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputs.wanted, GuardianInstall.status?.inputTrusted == false, !SettingsWindow.shared.window.isVisible, !SettingsWindow.shared.interactionBusy else { return }
                    self.showInputAccessPrompt()
                }
            }
        }
        refreshSafety()
        refreshNavigationItems()
        refreshDeskMenu(); refreshDeskSharingMenu()
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        label(loginItem, "Start at login", hint: loginStatus == .requiresApproval ? "Needs approval" : "Menu app")
        loginItem.menuHelp = ControlHelp.adding(loginStatus == .requiresApproval ? "Select to open macOS Login Items and approve Perch." : nil, to: ControlHelp.login)
        do { let standard = try FunctionKeys.standard(); refreshFunctionKeyItem(standard); keyboardModes.observeStandard(standard) }
        catch { fnItem.state = .mixed; label(fnItem, "Use F1–F12 directly", hint: "Unavailable"); fnItem.menuHelp = ControlHelp.adding("The current setting could not be read. Review Settings → Keyboards before changing it.", to: ControlHelp.builtInFn) }
        observedSleep = try? SleepStatus.read()
        observedLidDisabled = try? unownedSleepOverride()
        LidGuardClient.shared.refresh()
        applyLidSleepPresentation()
        refreshIdleLock()
        do {
            let muted = try AudioStatus.muted()
            audioItem.state = muted ? .on : .off
            label(audioItem, "Mute audio")
            audioItem.menuHelp = ControlHelp.audio
        } catch { label(audioItem, "Mute audio", hint: "Unavailable"); audioItem.state = .mixed; audioItem.menuHelp = ControlHelp.adding("The current mute setting could not be read. Check the selected output in macOS Sound settings.", to: ControlHelp.audio) }
        if menuOpen {
            let title = AudioStatus.heading(volume:AudioStatus.volume(),muted:audioItem.state == .mixed ? nil : audioItem.state == .on)
            (audioSection.view as? MenuRowView)?.text = NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.secondaryLabelColor])
        }
        if let button = status?.button {
            let critical = currentProtectionIssue?.severity == .critical
            if lastStatusCritical != critical {
                lastStatusCritical = critical
                status.length = critical ? 46 : NSStatusItem.squareLength
                button.attributedTitle = NSAttributedString(string: critical ? " ⚠" : "", attributes: [.foregroundColor: StatusColors.critical, .font: NSFont.systemFont(ofSize: 14, weight: .bold)])
                button.imagePosition = .imageLeading
            }
            button.toolTip = currentProtectionIssue.map { $0.title + ": " + $0.detail } ?? "Perch — your Mac, ready for AI work"
        }
        styleMenuSections()
        settingsRefresh?()
        let symbol = awakeItem.state == .on ? "awake-bird" : "bird"
        if lastStatusSymbol != symbol {
            lastStatusSymbol = symbol
            status?.button?.image = perchStatusImage(awake: symbol == "awake-bird")
        }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // App-owned confirmations use the ordinary event loop now. Preserve
        // their exclusive action scope without a native modal window.
        // Quit is never taken away: while a Settings alert is open it waits for
        // that alert, and a Quit with nothing on proceeds immediately.
        if item.action == #selector(quit) { return true }
        if SettingsWindow.shared.modal { return false }
        if item === replacementRestartItem { return appReplacement.state.available != nil && !RestartSettingsSnapshot.current.busy }
        if item === shareInputItem { return true }
        if deskPresetItems.contains(item) { return DeskCoordinator.shared.runtime.map { $0.switching.readiness($0.node.group.presets[item.tag].id) == nil } ?? false }
        if item === awakeItem || item === lidItem || item === safetyResumeItem { return item.isEnabled }
        if item === fnItem { return !keyboardModes.blocksFunctionKeyChanges && fnItem.state != .mixed && nativeKeyboards.contains { $0.builtIn } }
        if item === externalFnItem { return !keyboardModes.blocksFunctionKeyChanges && (item.action == #selector(keyboardDetails) || keyboardModes.results.contains { $0.standard != nil }) }
        if item === trackpadItem || item === wheelItem || item === homeEndItem || item === pageKeysItem { return item.isEnabled }
        return true
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { showError(error) }
        refresh()
    }
    func withMenuClosed(_ action: @escaping () -> Void) {
        if menuOpen {
            SettingsWindow.shared.returnedToApp()
            menu.cancelTracking()
            // Permission prompts must start after AppKit's tracking loop unwinds.
            DispatchQueue.main.async(execute: action)
        } else { action() }
    }
    func showError(_ error: Error) {
        withMenuClosed {
            SettingsWindow.shared.afterInteraction {
                let host = SettingsWindow.shared
                if let page = host.pages.last {
                    host.feedback = error.localizedDescription
                    host.display(page)
                } else {
                    let page = SettingsTaskPage(title: "Setting needs attention", detail: error.localizedDescription, height: 160)
                    page.add("Review setup", detail: "See the feature that needs attention and complete its setup.") { [weak self] in self?.configureSettings() }
                    page.show()
                }
            }
        }
    }
    @objc func about() {
        // Informational windows do not acquire the settings interaction scope.
        // AppKit retains and reuses its independent, modeless About panel.
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Perch",
            .applicationVersion: PerchVersion.current,
            .version: "",
            .credits: NSAttributedString(string: "Many computers. One place to land.\n\nShared monitor presets and keyboard/mouse control.\nKeyboard and scrolling preferences, keep-awake controls,\nlocal workload monitoring and agent safeguards.",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
