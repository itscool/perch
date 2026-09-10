import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import IOKit.pwr_mgt

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func script(_ source: String) throws -> NSAppleEventDescriptor {
    var restoreAuthorization: (() -> Void)?
    if source.contains("with administrator privileges") {
        _ = NSApplication.shared
        restoreAuthorization = SettingsWindow.shared.beginAuthorization()
    }
    defer { restoreAuthorization?() }
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { throw AppError(message: "Could not prepare the system command.") }
    let result = script.executeAndReturnError(&error)
    if let error { throw AppError(message: LaunchAccessRecovery.automationFailure(error[NSAppleScript.errorMessage] as? String ?? "System command failed.", code: error[NSAppleScript.errorNumber] as? Int)) }
    return result
}

// Current protection must not adopt a system override it does not own.
func unownedSleepOverride() throws -> Bool { try LidSleepOverride.systemDisabled() && !LidSleepOverride.owned }

final class Awake {
    private var ids: [IOPMAssertionID] = []
    var enabled: Bool { !ids.isEmpty }
    func set(_ enabled: Bool) throws {
        if !enabled { ids.forEach { IOPMAssertionRelease($0) }; ids.removeAll(); return }
        guard ids.isEmpty else { return }
        for type in [kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Perch: keep Mac awake" as CFString, &id)
            guard result == kIOReturnSuccess else {
                try? set(false)
                throw AppError(message: "Could not keep the Mac awake (\(result)).")
            }
            ids.append(id)
        }
    }
    deinit { ids.forEach { IOPMAssertionRelease($0) } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let appReplacement = AppReplacementMonitor()
    var replacementInfoItem: NSMenuItem?
    var replacementRestartItem: NSMenuItem?
    var replacementRestartTestDriver: (() -> Void)?
    let systemMonitor = SystemMonitor()
    var systemItems: [NSMenuItem] = []
    var permissionSetup: PermissionSetup?
    var checkedStartupInputAccess = false
    let inputStartupGraceEnds = Date().addingTimeInterval(4)
    let inputs = InputControls()
    var inputTimer: Timer?
    var loginItem: NSMenuItem!
    var trackpadItem: NSMenuItem!
    var wheelItem: NSMenuItem!
    var swapItem: NSMenuItem!
    var externalKeyboardSection: NSMenuItem!
    var externalSwapItem: NSMenuItem!
    let keyboardModes = KeyboardModeMonitor()
    var nativeKeyboards: [NativeKeyboard] = []
    var fnItem: NSMenuItem!
    var externalFnItem: NSMenuItem!
    var keyboardSetupItem: NSMenuItem!
    var homeEndItem: NSMenuItem!
    var pageKeysItem: NSMenuItem!
    var monitorInputItem: NSMenuItem!
    var deskPresetItems: [NSMenuItem] = []
    let legacyMonitorFixture: Bool
    let monitorInputs: MonitorInputController
    override convenience init() { self.init(monitorInputs: MonitorInputController(), legacyMonitorFixture: false) }
    init(monitorInputs: MonitorInputController, legacyMonitorFixture: Bool = true) { self.monitorInputs = monitorInputs; self.legacyMonitorFixture = legacyMonitorFixture; super.init() }
    var safetyItem: NSMenuItem!
    var safetyResumeItem: NSMenuItem!
    var safetySettingsItem: NSMenuItem!
    var protectionOfflineSince: Date?
    var repairPromptShown = false
    var currentProtectionIssue: ProtectionIssue?
    var notifiedCriticalIssue: String?
    var criticalIssueSince: Date?
    var safetyError: String?
    var lastTestResultID: String?
    var awaitingShortcutTest = false
    var menuOpen = false
    var menuGeneration: UInt64 = 0
    var lastBackgroundRefresh = Date.distantPast
    let menu = NSMenu()
    var menuTitleSources: [NSMenuItem: NSAttributedString] = [:]
    var menuKeyMonitor: Any?
    var status: NSStatusItem!
    private var lastStatusSymbol: String?
    private var lastStatusCritical: Bool?
    var awakeItem: NSMenuItem!
    var lidItem: NSMenuItem!
    var observedSleep: SleepStatus?
    var observedLidDisabled: Bool?
    var renderedSleep: SleepPresentation?
    let lidSleepNotice = LidSleepNotice()
    var startupKeyboardAccessNotice = StartupKeyboardAccessNotice()
    var accessNoticeStarted = false
    var accessNoticeDeadline = Date.distantPast
    var settingsRefresh: (() -> Void)?
    var keyboardActionTestDriver: ((String, Bool) -> Void)?
    var audioItem: NSMenuItem!
    var audioSection: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSettingsNavigation()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")
        status.button?.toolTip = "Perch — your Mac, ready for AI work"
        buildMenu()
        installApplicationMenu()
        status.menu = menu
        appReplacement.onChange = { [weak self] in self?.refreshAppReplacement() }
        _ = PerchVersion.current // Capture the running version before external replacement.
        appReplacement.start()
        accessNoticeStarted = true; accessNoticeDeadline = Date().addingTimeInterval(30)
        keyboardModes.onChange = { [weak self] in self?.keyboardStatusChanged() }
        keyboardModes.start()
        DeskCoordinator.shared.resumeIfConfigured()
        observeHelperPresentation()
        LidGuardClient.shared.start()
        lidSleepNotice.show = { [weak self] _, detail, acknowledge in
            guard let self else { return }
            self.withMenuClosed {
                SettingsWindow.shared.afterInteraction {
                    let alert = NSAlert(); alert.messageText = "Your Mac slept with the lid closed"
                    alert.informativeText = detail; alert.alertStyle = .informational
                    alert.addButton(withTitle: "View lid activity"); alert.addButton(withTitle: "Close")
                    SettingsWindow.shared.present(alert) { result in
                        acknowledge()
                        if result == .alertFirstButtonReturn { self.configureSettings(); self.lidActivity() }
                    }
                }
            }
        }
        lidSleepNotice.start()
        AppUpdate.completeLaunch { [weak self] in
            PerchUpdater.shared.completeLaunch { [weak self] in
                PerchUpdater.shared.showRecovery = { [weak self] in
                    self?.configureSettings(); self?.updateSettings()
                }
                PerchUpdater.shared.start()
                if !GuardianInstall.messagingInstalled {
                    do { try GuardianInstall.install() } catch { self?.safetyError = error.localizedDescription }
                }
                if CommandLine.arguments.contains("--complete-restart") || CommandLine.arguments.contains("--show-restart") {
                    self?.configureSettings(); self?.appSettings()
                }
            }
        }
        inputTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.menuOpen || Date().timeIntervalSince(self.lastBackgroundRefresh) >= 10 {
                self.lastBackgroundRefresh = Date()
                if self.menuOpen { self.nativeKeyboards = NativeModifierKeys.keyboards(); self.keyboardModes.readForPresentation() }
                self.refresh()
            } else { self.refreshSafety() }
        }
        // Continue refreshing while AppKit tracks an open menu.
        if let inputTimer { inputTimer.tolerance = 0.2; RunLoop.main.add(inputTimer, forMode: .common) }
        refresh()
        if CommandLine.arguments.contains("--show-keyboard-setup") { DispatchQueue.main.async { self.configureSettings(); self.keyboardSettings() } }
        if CommandLine.arguments.contains("--show-event-setup") { DispatchQueue.main.async { self.configureSettings(); EventCollectorSetup.shared.show(fromSettings: true) } }
        if !CommandLine.arguments.contains("--show-keyboard-setup") && !CommandLine.arguments.contains("--show-event-setup") {
            DispatchQueue.main.async { [weak self] in self?.showFirstSetupIfNeeded() }
        }
    }
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
        section("Display")
        let displayItem = add("Turn display off", #selector(turnDisplayOff), help: ControlHelp.display)
        label(displayItem, "Turn display off", hint: "Move mouse to wake")
        if legacyMonitorFixture {
            monitorInputItem = add("Cycle monitor input", #selector(cycleMonitorInput), help: ControlHelp.monitor)
            if legacyMonitorFixture { refreshMonitorInputItem() } else { refreshDeskMenu() }
        } else {
            monitorInputItem = add("Desk…", #selector(deskSettings), help: "Group Perch computers, arrange screens and choose monitor input presets.")
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
        externalFnItem = add("Use F1–F12 directly", #selector(toggleExternalFunctionKeys), help: ControlHelp.externalFn)
        homeEndItem = add("Home/End move to line edges", #selector(toggleHomeEnd), help: ControlHelp.homeEnd)
        pageKeysItem = add("Page Up/Down move the cursor", #selector(togglePageKeys), help: ControlHelp.pageKeys)
        keyboardSetupItem = add("Set up keyboard…", #selector(keyboardSettings), help: ControlHelp.keyboardSetup)
        keyboardSetupItem.isHidden = true
        section("Sleep")
        awakeItem = add("Keep awake", #selector(toggleAwake), help: ControlHelp.awake)
        lidItem = add("Including with lid closed", #selector(toggleLid), help: ControlHelp.lid)
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
        label(quit, "Quit Perch", hint: "Background controls stay on")
        for item in [awakeItem, lidItem, audioItem, trackpadItem, wheelItem, swapItem, externalSwapItem, fnItem, externalFnItem, homeEndItem, pageKeysItem, loginItem].compactMap({ $0 }) {
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
        if legacyMonitorFixture { monitorInputs.prepareForMenu() } // // Keep confirmed readiness unless macOS reports a change.
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
        if legacyMonitorFixture { refreshMonitorInputItem() } else { refreshDeskMenu() }
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        label(loginItem, "Start at login", hint: loginStatus == .requiresApproval ? "Needs approval" : "Menu app")
        loginItem.menuHelp = ControlHelp.adding(loginStatus == .requiresApproval ? "Select to open macOS Login Items and approve Perch." : nil, to: ControlHelp.login)
        do { let standard = try FunctionKeys.standard(); refreshFunctionKeyItem(standard); keyboardModes.observeStandard(standard) }
        catch { fnItem.state = .mixed; label(fnItem, "Use F1–F12 directly", hint: "Unavailable"); fnItem.menuHelp = ControlHelp.adding("The current setting could not be read. Review Keyboard settings before changing it.", to: ControlHelp.builtInFn) }
        observedSleep = try? SleepStatus.read()
        observedLidDisabled = try? unownedSleepOverride()
        LidGuardClient.shared.refresh()
        applyLidSleepPresentation()
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
    var actualLidState: NSControl.StateValue {
        LidGuardClient.controlState(unownedOverride: observedLidDisabled, status: LidGuardClient.shared.status, recordedSession: LidGuardOwnership.recorded)
    }
    func sleepPresentation() -> SleepPresentation {
        let client = LidGuardClient.shared
        return SleepPresentation(ordinary: observedSleep, actualLid: actualLidState,
            savedLid: UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey),
            masterWanted: SafetyConfiguration.load().keepAwake,
            changing: client.changing, remaining: client.status?.remaining)
    }
    func applyLidSleepPresentation() {
        guard awakeItem != nil, lidItem != nil else { return }
        let value = sleepPresentation()
        // Do not apply provisional labels or states during a background read.
        // Unchanged polling leaves the native row entirely alone.
        guard value != renderedSleep else { return }
        renderedSleep = value
        awakeItem.state = value.awake; awakeItem.isEnabled = value.awakeEnabled
        lidItem.state = value.lid; lidItem.isEnabled = value.lidEnabled
        label(awakeItem, "Keep awake", hint: value.awakeHint)
        label(lidItem, "Including with lid closed", hint: value.lidHint, hintColor: observedLidDisabled == true ? StatusColors.warning : .secondaryLabelColor)
        awakeItem.menuHelp = ControlHelp.awake
        lidItem.menuHelp = ControlHelp.adding(ControlHelp.lidSaved, to: ControlHelp.lid)
    }
    @objc func resumeLidProtection() {
        withMenuClosed { [weak self] in
            guard let self, UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey),
                  SafetyConfiguration.load().keepAwake, !LidGuardClient.shared.active,
                  !LidGuardClient.shared.changing else { return }
            self.changeSupervisedLid(true) { result in
                self.refresh()
                if case .failure(let error) = result { self.showError(error) }
            }
        }
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { showError(error) }
        refresh()
    }
    func withMenuClosed(_ action: @escaping () -> Void) {
        if menuOpen {
            menu.cancelTracking()
            // Permission prompts must start after AppKit's tracking loop unwinds.
            DispatchQueue.main.async(execute: action)
        } else { action() }
    }
    func showError(_ error: Error) {
        withMenuClosed {
            SettingsWindow.shared.afterInteraction {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Couldn’t change the setting"
                alert.informativeText = error.localizedDescription
                SettingsWindow.shared.present(alert)
            }
        }
    }
    @objc func toggleAwake() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try SleepStatus.read()
                let enabling = !(LidGuardClient.shared.active || state.perchActive || state.caffeinateActive)
                guard !enabling || GuardianInstall.alive else { throw AppError(message: "The background helper is offline. Repair it in Maintenance first.") }
                let remembered = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        var config = SafetyConfiguration.load(); config.keepAwake = enabling; try config.save()
                        if !enabling { try state.stopCaffeinate() }
                        self.refresh()
                    } catch { self.refresh(); self.showError(error) }
                }
                if enabling && remembered { self.changeSupervisedLid(true, completion: finish) }
                else if LidGuardClient.shared.status?.armed == true || LidGuardOwnership.recorded { self.changeSupervisedLid(false, completion: finish) }
                else { finish(.success(())) }
            } catch { self.refresh(); self.showError(error) }
        }
    }
    @objc func toggleLid() { changeLidChoice() }
    func changeLidChoice(readSleep: @escaping () throws -> SleepStatus = { try SleepStatus.read() }) {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try readSleep()
                let saved = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
                guard saved || LidGuardClient.shared.active || state.perchActive || state.caffeinateActive else { self.refresh(); return }
                let enabling = !saved

                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        UserDefaults.standard.set(enabling, forKey: SleepPreferences.lidPreferenceKey)
                        var config = SafetyConfiguration.load(); if enabling { config.keepAwake = true; try config.save() }
                        self.refresh(); self.settingsRefresh?()
                    } catch { self.refresh(); self.showError(error) }
                }
                if !enabling && !LidGuardOwnership.recorded && LidGuardClient.shared.status?.armed != true { finish(.success(())) }
                else { self.changeSupervisedLid(enabling, completion: finish) }
            } catch { self.refresh(); self.showError(error) }
        }
    }
    @objc func turnDisplayOff() {
        menu.cancelTracking()
        // Let the selecting mouse/keyboard event finish before sleeping the display.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.perform {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                task.arguments = ["displaysleepnow"]
                try task.run()
                task.waitUntilExit()
                guard task.terminationStatus == 0 else { throw AppError(message: "macOS could not turn off the display.") }
            }
        }
    }
    @objc func toggleAudio() {
        perform {
            let muted = try AudioStatus.muted()
            _ = try script("set volume output muted \(muted ? "false" : "true")")
            guard try AudioStatus.muted() != muted else {
                throw AppError(message: "This audio output does not support system mute. Use the output device’s volume control.")
            }
        }
    }
    func updateInputs() {
        var config = SafetyConfiguration.load()
        config.reverseTrackpad = inputs.reverseTrackpad
        config.reverseWheel = inputs.reverseWheel
        config.swapModifiers = inputs.swapModifiers
        do {
            try config.save()
        } catch { showError(error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if self.inputs.wanted && HelperStatusIPC.inputClient.value?.active != true {
                self.showInputAccessPrompt()
            }
            self.refresh()
        }
    }
    func showInputAccessPrompt() {
        SettingsWindow.shared.afterInteraction { [weak self] in
            guard let self, self.inputs.wanted, HelperStatusIPC.inputClient.value?.active != true else { return }
            self.inputPermissions()
        }
    }
    @objc func toggleTrackpad() { setScrollChoice(trackpad: true); refresh() }
    @objc func toggleWheel() { setScrollChoice(trackpad: false); refresh() }
    @objc func toggleModifiers() { setModifierGroup(true) }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // App-owned confirmations use the ordinary event loop now. Preserve
        // their exclusive action scope without a native modal window.
        if SettingsWindow.shared.modal { return false }
        if item === replacementRestartItem { return appReplacement.state.available != nil && !RestartSettingsSnapshot.current.busy }
        if item === monitorInputItem { return legacyMonitorFixture ? monitorInputMenuEnabled : true }
        if deskPresetItems.contains(item) { return DeskCoordinator.shared.runtime.map { $0.switching.readiness($0.node.group.presets[item.tag].id) == nil } ?? false }
        if item === awakeItem || item === lidItem || item === safetyResumeItem { return item.isEnabled }
        if item === fnItem { return !keyboardModes.blocksFunctionKeyChanges && fnItem.state != .mixed && nativeKeyboards.contains { $0.builtIn } }
        if item === externalFnItem { return !keyboardModes.blocksFunctionKeyChanges && (item.action == #selector(keyboardDetails) || keyboardModes.results.contains { $0.standard != nil }) }
        if item === trackpadItem || item === wheelItem || item === homeEndItem || item === pageKeysItem { return item.isEnabled }
        return true
    }
    func refreshScrolling(input: InputHelperStatus?, checking: Bool? = nil) {
        let pending = checking ?? HelperStatusIPC.inputClient.initiallyChecking
        let trusted = input?.fresh == true && input?.trusted == true
        for (item, title, action) in [(trackpadItem!, "Reverse trackpad scroll", #selector(toggleTrackpad)), (wheelItem!, "Reverse mouse wheel", #selector(toggleWheel))] {
            let saved = item.state == .on
            let canChange = saved || trusted
            item.action = canChange ? action : #selector(inputPermissionsFromSettings)
            item.isEnabled = saved || trusted || !pending
            (item.view as? MenuRowView)?.opensAnotherInterface = { !canChange }
            let hint = pending && input == nil ? "Checking input helper…" : !trusted ? "Set up in Settings" : saved && input?.active != true ? "Saved · controls not running" : "Vertical"
            label(item, title, hint: hint, hintColor: trusted && (!saved || input?.active == true) ? .secondaryLabelColor : StatusColors.warning)
            let purpose = item === trackpadItem ? ControlHelp.trackpad : ControlHelp.wheel
            let context = pending && input == nil ? "Checking input access. Your saved choice is kept." : !trusted ? (saved ? "This choice is saved. Turn it off here, or restore input access in Settings." : "Select to set up input access in Settings.") : saved && input?.active != true ? "This choice is saved, but input controls are not running. Review Scrolling settings." : nil
            item.menuHelp = ControlHelp.adding(context, to: purpose)
        }
    }
    func observeHelperPresentation() {
        let repaint = { [weak self] in
            guard let self, self.awakeItem != nil else { return }
            HelperStatusIPC.guardianClient.withCachedValue {
                HelperStatusIPC.inputClient.withCachedValue {
                    self.refreshSafety(); self.refreshScrolling(input: HelperStatusIPC.inputClient.value)
                    self.refreshNavigationItems(); self.settingsRefresh?()
                }
            }
        }
        HelperStatusIPC.guardianClient.onChange = repaint
        HelperStatusIPC.inputClient.onChange = repaint
        LidGuardClient.shared.onChange = { [weak self] in
            guard let self else { return }
            self.applyLidSleepPresentation(); self.settingsRefresh?()
        }
    }
    @objc func inputPermissionsFromSettings() {
        withMenuClosed { [self] in
            if permissionSetup == nil { permissionSetup = PermissionSetup() }
            permissionSetup?.show(fromSettings: true)
        }
    }
    @objc func inputPermissions() {
        withMenuClosed { [self] in
            if permissionSetup == nil { permissionSetup = PermissionSetup() }
            permissionSetup?.show()
        }
    }
    @objc func toggleFunctionKeys() { keyboardModes.setBuiltIn(fnItem.state != .on) }
    @objc func toggleLogin() {
        perform {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SettingsWindow.shared.handoffToExternalApp { SMAppService.openSystemSettingsLoginItems(); return true }
            default: try SMAppService.mainApp.register()
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
            .credits: NSAttributedString(string: "Your Mac, ready for AI work.\n\nShared monitor presets, keyboard preferences,\nkeep-awake controls and local workload monitoring.",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let reply = PerchUpdater.shared.terminationReply(sender, willExit: { [weak self] in self?.inputs.stop() }) { return reply }
        inputs.stop()
        return .terminateNow
    }
}

if CommandLine.arguments.contains("--check-modifier-access") {
    NativeModifierKeys.checkExistingAccess()
    exit(0)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--restart-worker" {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    do { try AppUpdate.runWorker(CommandLine.arguments[2]); exit(0) }
    catch {
        UserDefaults.standard.set("Restart did not complete. " + error.localizedDescription, forKey: AppUpdate.noticeKey)
        fputs("Update failed: \(error.localizedDescription)\n", stderr); exit(1)
    }
}
if CommandLine.arguments == [CommandLine.arguments[0], "--check-lid-update"] {
    guard MacLidGuardHardware().observe().closed == false else {
        fputs("Open the lid before finishing the helper update. Nothing has been replaced.\n", stderr); exit(1)
    }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--update-catalog"), CommandLine.arguments.count > index + 1 {
    do { try AgentCatalog.install(from: URL(fileURLWithPath: CommandLine.arguments[index + 1])); print("Catalog updated; new targets default to checked and existing choices are preserved."); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
}
var retainedLidGuard: LidGuardService?
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--lid-override-worker", let deadline = Double(CommandLine.arguments[4]) {
    do { try LidSleepOverride.worker(CommandLine.arguments[2], token: CommandLine.arguments[3], deadline: deadline); exit(0) }
    catch { fputs("Lid override failed: \(error.localizedDescription)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--lid-recover") {
    guard geteuid() == 0 else { exit(1) }
    let activity = LidActivityRecorder(source: "Recovery")
    do {
        if try LidSleepOverride.recover(force: false) {
            activity.record("Independent recovery restored normal system sleep after an expired or missing supervisor lease.")
            let hardware = MacLidGuardHardware(), observation = hardware.observe()
            if observation.closed != false && observation.power != .external { try hardware.requestSleep(); activity.record("Independent recovery requested sleep with the lid closed without external power.") }
        }
        activity.finish(); exit(0)
    } catch { activity.record("Independent system sleep recovery failed: " + error.localizedDescription); activity.finish(); exit(1) }
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--lid-guard", let owner = UInt32(CommandLine.arguments[2]), owner >= 501, geteuid() == 0 {
    retainedLidGuard = LidGuardService(owner: owner)
    retainedLidGuard!.run()
}
if CommandLine.arguments == [CommandLine.arguments[0], "--lid-watchdog"] { runLidGuardWatchdog() }
if CommandLine.arguments == [CommandLine.arguments[0], "--lid-cleanup"] {
    guard geteuid() == 0 else { exit(1) }
    do {
        let hardware = MacLidGuardHardware(), observation = hardware.observe()
        let recovered = try LidSleepOverride.recover(force: true)
        try LidGuardOwnership.release(LidGuardEnforcer(hardware), sleep: observation.closed != false && observation.power != .external, now: LidGuardClock.now)
        if recovered && observation.closed != false && observation.power != .external { try hardware.requestSleep() }
        exit(0)
    } catch { fputs("Lid cleanup failed: \(error.localizedDescription)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--prepare-safety-config") {
    do {
        if !FileManager.default.fileExists(atPath: SafetyFiles.config.path) {
            var config = SafetyConfiguration()
            config.keepAwake = try SleepStatus.read().perchActive
            try config.save()
        }
        exit(0)
    } catch { fputs("\(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--install-watcher") {
    do { try GuardianInstall.install(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--safety-preview") {
    _ = NSApplication.shared
    let guardian = AgentGuardian()
    guardian.refreshTracking()
    let grouped = Dictionary(grouping: guardian.tracker.tracked.values, by: \.targetID)
    for (target, processes) in grouped.sorted(by: { $0.key < $1.key }) { print("\(target): \(processes.count) observed local processes") }
    print("Read-only preview. No signals or permission resets sent.")
    exit(0)
}
if CommandLine.arguments.contains("--input-helper") {
    _ = NSApplication.shared
    let helper = InputHelper()
    withExtendedLifetime(helper) { helper.run() }
    exit(0)
}
if CommandLine.arguments.contains("--guardian") {
    _ = NSApplication.shared
    let guardian = AgentGuardian()
    withExtendedLifetime(guardian) { guardian.run() }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--panic-worker"), CommandLine.arguments.count > index + 1 {
    exit(PanicReset.worker(planURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
}
if CommandLine.arguments.contains("--status-stream") { runStatusStream(); exit(0) }
if CommandLine.arguments.contains("--ipc-self-test") {
    do { try runHelperStatusTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--cpu-benchmark") {
    runProcessCPUBenchmark()
    do { try runProcessCPULiveTest(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--settings-self-test") {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    do { try runSettingsTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--event-self-test") {
    do { try runProcessEventTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--navigation-device-info") {
    let connected = NavigationProbeKeyboard.connected()
    let saved = (try? KeyboardNavigationProfiles.read()) ?? []
    let registrations = connected.map { KeyboardRegistrationStatus.assess($0.identity, saved: saved) }
    let devices = NavigationEventDevices.read(profiles: registrations.compactMap { $0.profile })
    let native = NativeModifierKeys.keyboards().map { keyboard -> [String:Any] in
        let result: [String:Any] = ["name":keyboard.name,"vendor":keyboard.vendor,"builtIn":keyboard.builtIn,"id":IOHIDServiceClientGetRegistryID(keyboard.service),"product":IOHIDServiceClientCopyProperty(keyboard.service,"ProductID" as CFString) ?? NSNull(),"transport":IOHIDServiceClientCopyProperty(keyboard.service,"Transport" as CFString) ?? NSNull()]
        return result
    }
    let physical = connected.map { ["name":$0.name,"vendor":$0.identity.vendor,"product":$0.identity.product,"transport":$0.transport,"usages":$0.identity.usages] as [String:Any] }
    let registration = registrations.map { ["name":$0.name,"needsSetup":$0.needsSetup,"detail":$0.detail] as [String:Any] }
    let output: [String:Any] = ["native":native,"physical":physical,"registration":registration,"profiles":BundledNavigationProfiles.entries.count,"matched":devices.map { ["sender":String($0.key),"keyCount":$0.value.count] as [String:Any] }]
    if let data = try? JSONSerialization.data(withJSONObject: output,options:[.sortedKeys]), let text = String(data:data,encoding:.utf8) { print(text) }
    exit(0)
}
if CommandLine.arguments.contains("--self-test") {
    do {
        let awake = Awake()
        try awake.set(true)
        guard try SleepStatus.read().currentProcessActive else { throw AppError(message: "Awake assertion failed") }
        try awake.set(false)
        guard try !SleepStatus.read().currentProcessActive else { throw AppError(message: "Assertion release failed") }
        try runCaffeinateTests()
        try runCatalogTests()
        try runSystemTests()
        try runProcessCPUTests()
        try runProtectionIssueTests()
        try runProcessEventTests()
        try runHelperStatusTests()
        try runAgentSafetyTests()
        try runHousekeepingTests()
        try runPanicTests()
        try runPanicHotKeyTests()
        try runInputTests()
        try runKeyboardModeTests()
        try runNavigationKeyTests()
        try runNavigationRuntimeTests()
        try runSettingsResetTests()
        try runMonitorConnectionTests()
        try runMonitorInputTests()
        try runMonitorTransactionTests()
        try runNavigationProbeTests()
        try runKeyboardRegistrationTests()
        print("PASS: function-key mode = \(try FunctionKeys.standard())")
        print("PASS: create/release Mac sleep assertion")
        print("PASS: read sleep override = \(try LidSleepOverride.systemDisabled())")
        print("PASS: read audio muted = \(try AudioStatus.muted()); native read supported = \(AudioStatus.nativeMuted() != nil)")
        exit(0)
    } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
