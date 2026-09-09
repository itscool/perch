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
    if let error { throw AppError(message: error[NSAppleScript.errorMessage] as? String ?? "System command failed.") }
    return result
}

func sleepDisabled() throws -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0, let output = String(data: data, encoding: .utf8), output.contains("System-wide power settings:") else {
        throw AppError(message: "Could not read the Mac’s sleep settings.")
    }
    for line in output.split(separator: "\n") {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        if fields.first == "SleepDisabled" {
            guard let value = fields.last, value == "0" || value == "1" else { throw AppError(message: "Unrecognized sleep setting.") }
            return value == "1"
        }
    }
    return false // macOS omits this key when the default is in use.
}

func setSleepDisabled(_ disabled: Bool) throws {
    _ = try script("do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with administrator privileges")
    guard try sleepDisabled() == disabled else { throw AppError(message: "macOS did not apply the sleep setting.") }
}

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
    let monitorInputs: MonitorInputController
    override convenience init() { self.init(monitorInputs: MonitorInputController()) }
    init(monitorInputs: MonitorInputController) { self.monitorInputs = monitorInputs; super.init() }
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
    var observedLidDisabled: Bool?
    var settingsRefresh: (() -> Void)?
    var keyboardActionTestDriver: ((String, Bool) -> Void)?
    var audioItem: NSMenuItem!
    var audioSection: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")
        status.button?.toolTip = "Perch — your Mac, ready for AI work"
        buildMenu()
        status.menu = menu
        keyboardModes.onChange = { [weak self] in self?.keyboardStatusChanged() }
        keyboardModes.start()
        monitorInputs.onChange = { [weak self] in self?.refreshMonitorInputItem() }
        monitorInputs.start()
        monitorInputs.groups.onNeedsDestination = { [weak self] in self?.monitorGroupSettings() }
        observeHelperPresentation()
        LidGuardClient.shared.start()
        AppUpdate.completeLaunch { [weak self] in
            if !GuardianInstall.messagingInstalled {
                do { try GuardianInstall.install() } catch { self?.safetyError = error.localizedDescription }
            }
            if CommandLine.arguments.contains("--complete-update") || CommandLine.arguments.contains("--show-updates") {
                self?.configureSettings(); self?.appSettings(); self?.updateSettings()
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
        let displayItem = add("Turn display off", #selector(turnDisplayOff))
        label(displayItem, "Turn display off", hint: "Move mouse to wake")
        displayItem.toolTip = "Turn off the display now. Moving the mouse or pressing a key wakes it. Your Mac can keep working while Keep awake is enabled."
        monitorInputItem = add("Cycle monitor input", #selector(cycleMonitorInput))
        refreshMonitorInputItem()
        audioSection = section("Audio")
        audioItem = add("Mute audio", #selector(toggleAudio))
        section("Scrolling")
        trackpadItem = add("Reverse trackpad scroll", #selector(toggleTrackpad))
        wheelItem = add("Reverse mouse wheel", #selector(toggleWheel))
        section("Built-in keyboard")
        swapItem = add("Swap Control ↔ Command keys", #selector(toggleModifiers))
        fnItem = add("Use F1–F12 directly", #selector(toggleFunctionKeys))
        externalKeyboardSection = section("External keyboards")
        externalSwapItem = add("Swap Control ↔ Command keys", #selector(toggleExternalModifiers))
        externalFnItem = add("Use F1–F12 directly", #selector(toggleExternalFunctionKeys))
        homeEndItem = add("Home/End move to line edges", #selector(toggleHomeEnd))
        pageKeysItem = add("Page Up/Down move the cursor", #selector(togglePageKeys))
        keyboardSetupItem = add("Set up keyboard…", #selector(keyboardSettings))
        keyboardSetupItem.isHidden = true
        section("Sleep")
        awakeItem = add("Keep awake", #selector(toggleAwake))
        awakeItem.toolTip = "Keep the Mac awake while allowing the display to sleep. Turning this off also stops your active caffeinate sessions."
        lidItem = add("Including with lid closed", #selector(toggleLid))
        lidItem.toolTip = "Prevents all system sleep, including on battery. Requires administrator authorization. Turn off before putting your Mac in a bag."
        section("Perch")
        loginItem = add("Start at login", #selector(toggleLogin))
        safetySettingsItem = add("Settings…", #selector(configureSettings))
        _ = add("About Perch", #selector(about))
        let quit = add("Quit Perch", #selector(quit))
        quit.keyEquivalent = "q"
        label(quit, "Quit Perch", hint: "Background controls stay on")
        quit.toolTip = "Input controls, ordinary keep-awake and agent protection continue. Monitor shortcuts and supervised lid protection stop. If the lid stays closed on battery, the lid helper requests sleep."
        for item in [awakeItem, lidItem, audioItem, trackpadItem, wheelItem, swapItem, externalSwapItem, fnItem, externalFnItem, homeEndItem, pageKeysItem, loginItem].compactMap({ $0 }) {
            item.view = MenuRowView(item: item, kind: .toggle, text: menuTitleSources[item])
        }
        (lidItem.view as? MenuRowView)?.opensAnotherInterface = { true }
        (awakeItem.view as? MenuRowView)?.opensAnotherInterface = { [weak self] in
            self?.lidItem.state != .off || UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey)
        }
        (loginItem.view as? MenuRowView)?.opensAnotherInterface = { SMAppService.mainApp.status == .requiresApproval }
        styleMenuSections()
        systemMonitor.processCPU.onUpdate = { [weak self] in
            guard let self, self.menuOpen, self.systemItems.count > 1 else { return }
            self.showSystemReading(self.systemItems[1], self.systemMonitor.cpuReading)
        }
    }
    func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
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
        menuOpen = true; menuGeneration &+= 1
        monitorInputs.prepareForMenu() // Keep confirmed readiness unless macOS reports a change.
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
        item.toolTip = reading.help
    }
    func refreshSystem() {
        guard menuOpen else { return }
        for (item, reading) in zip(systemItems, systemMonitor.read()) { showSystemReading(item, reading) }
    }
    func refresh() {
        refreshSystem()
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
        refreshMonitorInputItem()
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        label(loginItem, "Start at login", hint: loginStatus == .requiresApproval ? "Needs approval" : "Menu app")
        do { let standard = try FunctionKeys.standard(); refreshFunctionKeyItem(standard); keyboardModes.observeStandard(standard) }
        catch { fnItem.state = .mixed; label(fnItem, "Use F1–F12 directly", hint: "Unavailable") }
        awakeItem.isEnabled = true
        do {
            let sleep = try SleepStatus.read()
            awakeItem.state = (sleep.perchActive || sleep.caffeinateActive) ? .on : .off
            label(awakeItem, "Keep awake", hint: sleep.caffeinateActive ? "caffeinate active" : "Mac only")
        } catch {
            awakeItem.state = .mixed
            label(awakeItem, "Keep awake", hint: "Unavailable")
        }
        do {
            let disabled = try sleepDisabled()
            observedLidDisabled = disabled
            LidGuardClient.shared.refresh()
            refreshLidStatus(legacyDisabled: disabled)
        } catch { observedLidDisabled = nil; label(lidItem, "Including with lid closed", hint: "Unavailable"); lidItem.state = .mixed }
        applyLidSleepPresentation()
        do {
            let muted = try AudioStatus.muted()
            audioItem.state = muted ? .on : .off
            label(audioItem, "Mute audio")
        } catch { label(audioItem, "Mute audio", hint: "Unavailable"); audioItem.state = .mixed }
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
    func refreshLidStatus(legacyDisabled: Bool) {
        let client = LidGuardClient.shared
        lidItem.state = LidGuardClient.controlState(legacyDisabled: legacyDisabled, status: client.status, recordedSession: LidGuardOwnership.exists)
        let hint = legacyDisabled ? "Old override · review sleep settings" : client.active ? (client.status?.remaining.map { "Requested · \($0)s remaining" } ?? "Requested · unverified") : lidItem.state == .mixed || client.status?.error != nil ? "Review lid protection" : "Normal lid sleep"
        label(lidItem, "Including with lid closed", hint: hint, hintColor: legacyDisabled ? StatusColors.warning : .secondaryLabelColor)
    }
    func applyLidSleepPresentation() {
        let actualLid = lidItem.state
        if actualLid == .on { awakeItem.state = .on }
        awakeItem.isEnabled = actualLid != .mixed && awakeItem.state != .mixed && !LidGuardClient.shared.changing
        lidItem.isEnabled = awakeItem.isEnabled && awakeItem.state == .on
        if !lidItem.isEnabled && actualLid == .off && awakeItem.state == .off {
            lidItem.state = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey) ? .on : .off
            label(lidItem, "Including with lid closed", hint: "Applies when Keep awake is on")
        }
        if actualLid == .on { label(awakeItem, "Keep awake", hint: "Lid mode requested") }
        awakeItem.toolTip = "Master switch for idle-sleep prevention and supervised lid operation. Turning off releases lid protection and also stops your active caffeinate sessions."
        lidItem.toolTip = "Request closed-lid keep-awake on external power, with 60 seconds to open the lid or reconnect power after undocking. macOS can override this request; continued protection is unverified. Set up with the lid open or external power connected."
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
                SettingsWindow.shared.run(alert)
            }
        }
    }
    @objc func toggleAwake() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try SleepStatus.read(), legacy = try sleepDisabled()
                let enabling = !(legacy || LidGuardClient.shared.active || state.perchActive || state.caffeinateActive)
                guard !enabling || GuardianInstall.alive else { throw AppError(message: "The background helper is offline. Repair it in Maintenance first.") }
                let remembered = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey)
                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        var config = SafetyConfiguration.load(); config.keepAwake = enabling; try config.save()
                        if !enabling { try state.stopCaffeinate() }
                        self.refresh()
                    } catch { self.refresh(); self.showError(error) }
                }
                if legacy { try setSleepDisabled(false) }
                if enabling && remembered { self.changeSupervisedLid(true, completion: finish) }
                else if LidGuardClient.shared.status?.armed == true || LidGuardOwnership.exists { self.changeSupervisedLid(false, completion: finish) }
                else { finish(.success(())) }
            } catch { self.refresh(); self.showError(error) }
        }
    }
    @objc func toggleLid() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try SleepStatus.read(), legacy = try sleepDisabled()
                guard legacy || LidGuardClient.shared.active || state.perchActive || state.caffeinateActive else { self.refresh(); return }
                let enabling = !(legacy || LidGuardClient.shared.active)
                if legacy { try setSleepDisabled(false) }
                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        UserDefaults.standard.set(enabling, forKey: SleepMasterChange.lidPreferenceKey)
                        var config = SafetyConfiguration.load(); config.keepAwake = true; try config.save()
                        self.refresh(); self.settingsRefresh?()
                    } catch { self.refresh(); self.showError(error) }
                }
                if legacy && !LidGuardOwnership.exists && LidGuardClient.shared.status?.armed != true { finish(.success(())) }
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
        if item === monitorInputItem { return monitorInputMenuEnabled }
        if item === awakeItem || item === lidItem || item === safetyResumeItem { return item.isEnabled }
        if item === fnItem { return !keyboardModes.blocksFunctionKeyChanges && fnItem.state != .mixed && nativeKeyboards.contains { $0.builtIn } }
        if item === externalFnItem { return !keyboardModes.blocksFunctionKeyChanges && (item.action == #selector(keyboardSettings) || keyboardModes.results.contains { $0.standard != nil }) }
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
            item.toolTip = saved && !trusted ? "This choice is saved. You can turn it off here, or restore input access in Settings." : "Changes vertical scrolling. Input controls must be running for the saved choice to take effect."
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
            guard let self, let legacy = self.observedLidDisabled else { return }
            self.refreshLidStatus(legacyDisabled: legacy)
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
        let alert = NSAlert()
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        alert.messageText = "Perch \(version) · build \(build)"
        alert.informativeText = "Your Mac, ready for AI work.\n\nKeep your Mac awake through long tasks, control sound and input preferences, and see how local workloads use CPU, GPU, and memory.\n\nIf you need control back, Panic terminates selected agents and their tracked child processes, with an option to reset privacy permissions.\n\nVersion \(version) (build \(build))"

        SettingsWindow.shared.run(alert)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        inputs.stop()
        return .terminateNow
    }
}

if CommandLine.arguments.contains("--check-modifier-access") {
    NativeModifierKeys.checkExistingAccess()
    exit(0)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--apply-update" {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    do { try AppUpdate.runWorker(CommandLine.arguments[2]); exit(0) }
    catch {
        UserDefaults.standard.set("Update did not complete. " + error.localizedDescription, forKey: AppUpdate.noticeKey)
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
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--lid-guard", let owner = UInt32(CommandLine.arguments[2]), owner >= 501, geteuid() == 0 {
    retainedLidGuard = LidGuardService(owner: owner)
    retainedLidGuard!.run()
}
if CommandLine.arguments == [CommandLine.arguments[0], "--lid-watchdog"] { runLidGuardWatchdog() }
if CommandLine.arguments == [CommandLine.arguments[0], "--lid-cleanup"] {
    guard geteuid() == 0 else { exit(1) }
    do {
        let hardware = MacLidGuardHardware(), observation = hardware.observe()
        try LidGuardOwnership.release(LidGuardEnforcer(hardware), sleep: observation.closed != false && observation.power != .external, now: LidGuardClock.now)
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
        print("PASS: read sleep override = \(try sleepDisabled())")
        print("PASS: read audio muted = \(try AudioStatus.muted()); native read supported = \(AudioStatus.nativeMuted() != nil)")
        exit(0)
    } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
