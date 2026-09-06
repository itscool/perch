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
    var externalSwapItem: NSMenuItem!
    let keyboardModes = KeyboardModeMonitor()
    var nativeKeyboards: [NativeKeyboard] = []
    var fnItem: NSMenuItem!
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
    let menu = AppearanceAwareMenu()
    var menuTitleSources: [NSMenuItem: NSAttributedString] = [:]
    var menuAppearanceObservation: NSKeyValueObservation?
    var status: NSStatusItem!
    private var lastStatusSymbol: String?
    private var lastStatusCritical: Bool?
    var awakeItem: NSMenuItem!
    var lidItem: NSMenuItem!
    var audioItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")
        status.button?.toolTip = "Perch — your Mac, ready for AI work"
        buildMenu()
        status.menu = menu
        keyboardModes.onChange = { [weak self] in self?.keyboardStatusChanged() }
        keyboardModes.start()
        if !GuardianInstall.messagingInstalled {
            do { try GuardianInstall.install() } catch { safetyError = error.localizedDescription }
        }
        inputTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.menuOpen || Date().timeIntervalSince(self.lastBackgroundRefresh) >= 10 {
                self.lastBackgroundRefresh = Date()
                self.refresh()
            } else { self.refreshSafety() }
        }
        // Continue refreshing while AppKit tracks an open menu.
        if let inputTimer { inputTimer.tolerance = 0.2; RunLoop.main.add(inputTimer, forMode: .common) }
        refresh()
        if CommandLine.arguments.contains("--show-keyboard-setup") { DispatchQueue.main.async { self.configureSettings(); self.keyboardSettings() } }
        if CommandLine.arguments.contains("--show-event-setup") { DispatchQueue.main.async { self.configureSettings(); EventCollectorSetup.shared.show(fromSettings: true) } }
    }
    // Kept separate from helper installation so the real menu can be checked safely.
    func buildMenu() {
        menu.delegate = self
        menu.appearanceChanged = { [weak self] in self?.refreshMenuAppearance() }
        menuAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in self?.refreshMenuAppearance() }
        section("System")
        for _ in 0..<5 { let item = NSMenuItem(title: "Sampling…", action: nil, keyEquivalent: ""); menu.addItem(item); systemItems.append(item) }
        section("Sleep")
        awakeItem = add("Keep awake", #selector(toggleAwake))
        awakeItem.toolTip = "Keep the Mac awake while allowing the display to sleep. Turning this off also stops your active caffeinate sessions."
        lidItem = add("Keep awake with lid closed", #selector(toggleLid))
        lidItem.toolTip = "Prevents all system sleep, including on battery. Requires administrator authorization. Turn off before putting your Mac in a bag."
        let displayItem = add("Turn display off", #selector(turnDisplayOff))
        label(displayItem, "Turn display off", hint: "Move mouse to wake")
        displayItem.toolTip = "Turn off the display now. Moving the mouse or pressing a key wakes it. Your Mac can keep working while Keep awake is enabled."
        section("Audio")
        audioItem = add("Mute audio", #selector(toggleAudio))
        section("Input")
        trackpadItem = add("Reverse trackpad scroll", #selector(toggleTrackpad))
        wheelItem = add("Reverse mouse wheel", #selector(toggleWheel))
        swapItem = add("Swap Control ↔ Command keys", #selector(toggleModifiers))
        externalSwapItem = add("Swap Control ↔ Command keys", #selector(toggleExternalModifiers))
        fnItem = add("Use F1–F12 directly", #selector(toggleFunctionKeys))
        fnItem.toolTip = "Checked: use F1–F12 without Fn; hold Fn for brightness and media. Unchecked: hold Fn for F1–F12."
        setupSafetyMenu()
        section("Perch")
        loginItem = add("Start at login", #selector(toggleLogin))
        safetySettingsItem = add("Settings…", #selector(configureSettings))
        _ = add("About Perch", #selector(about))
        let quit = add("Quit Perch", #selector(quit))
        quit.keyEquivalent = "q"
        label(quit, "Quit Perch", hint: "Controls stay on")
        for item in [awakeItem, lidItem, audioItem, trackpadItem, wheelItem, swapItem, externalSwapItem, fnItem, loginItem].compactMap({ $0 }) {
            item.view = ToggleMenuView(item: item)
        }
        systemMonitor.processCPU.onUpdate = { [weak self] in
            guard let self, self.menuOpen, self.systemItems.count > 1 else { return }
            self.showSystemReading(self.systemItems[1], self.systemMonitor.cpuReading)
        }
    }
    func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }
    func section(_ title: String) {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: title))
        } else {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(item)
        }
    }
    func label(_ item: NSMenuItem, _ title: String, hint: String = "", hintColor: NSColor = .secondaryLabelColor) {
        let text = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        if !hint.isEmpty {
            text.append(NSAttributedString(string: "  \u{2002}" + hint, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: hintColor]))
        }
        item.title = title
        setMenuTitle(item, text)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true; menuGeneration &+= 1
        let generation = menuGeneration
        refreshMenuAppearance()
        nativeKeyboards = NativeModifierKeys.keyboards()
        refresh()
        // One quick second interval, then the existing menu refresh cadence.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.menuOpen, self.menuGeneration == generation else { return }
            self.refreshSystem()
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false; menuGeneration &+= 1; systemMonitor.menuClosed()
    }
    func showSystemReading(_ item: NSMenuItem, _ reading: (String, String, String)) {
        let color: NSColor
        if reading.1.contains("Critical") { color = StatusColors.critical }
        else if reading.1.contains("Elevated") || reading.1.contains("Warm") || reading.1.contains("High ·") { color = StatusColors.warning }
        else if reading.1.contains("Unavailable") { color = .secondaryLabelColor }
        else { color = StatusColors.information }
        label(item, reading.0, hint: reading.1, hintColor: color)
        item.toolTip = reading.2
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
        inputs.swapModifiers = false // Modifier swaps now run in macOS, per keyboard.
        for (item, enabled) in [(trackpadItem!, inputs.reverseTrackpad), (wheelItem!, inputs.reverseWheel)] {
            item.state = enabled ? .on : .off
        }
        label(trackpadItem, "Reverse trackpad scroll", hint: "Vertical")
        label(wheelItem, "Reverse mouse wheel", hint: "Vertical")
        refreshModifierItems()
        if !checkedStartupInputAccess, Date() >= inputStartupGraceEnds,
           let protection = GuardianInstall.status, protection.fresh, protection.inputTrusted != nil {
            checkedStartupInputAccess = true
            if inputs.wanted && protection.inputTrusted == false {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputs.wanted, GuardianInstall.status?.inputTrusted == false else { return }
                    self.showInputAccessPrompt()
                }
            }
        }
        refreshSafety()
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        label(loginItem, "Start at login", hint: loginStatus == .requiresApproval ? "Needs approval" : "Menu app")
        do { let standard = try FunctionKeys.standard(); refreshFunctionKeyItem(standard); keyboardModes.observeStandard(standard) }
        catch { fnItem.state = .mixed; label(fnItem, "Use F1–F12 directly", hint: "Unavailable") }
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
            lidItem.state = disabled ? .on : .off
            label(lidItem, "Keep awake with lid closed", hint: disabled ? "⚠ Keep ventilated" : "Currently sleeps on lid close", hintColor: disabled ? StatusColors.warning : StatusColors.success)
        } catch { label(lidItem, "Keep awake with lid closed", hint: "Unavailable"); lidItem.state = .mixed }
        do {
            let muted = try AudioStatus.muted()
            audioItem.state = muted ? .on : .off
            label(audioItem, "Mute audio")
        } catch { label(audioItem, "Mute audio", hint: "Unavailable"); audioItem.state = .mixed }
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
        let symbol = awakeItem.state != .off || lidItem.state == .on ? "cup.and.saucer.fill" : "bird"
        if lastStatusSymbol != symbol {
            lastStatusSymbol = symbol
            status?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Perch")
        }
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { showError(error) }
        refresh()
    }
    func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn’t change the setting"
        alert.informativeText = error.localizedDescription
        SettingsWindow.shared.run(alert)
    }
    @objc func toggleAwake() {
        perform {
            let state = try SleepStatus.read()
            var config = SafetyConfiguration.load()
            if state.perchActive || state.caffeinateActive || config.keepAwake {
                config.keepAwake = false
                try config.save()
                try state.stopCaffeinate()
            } else {
                guard GuardianInstall.alive else { throw AppError(message: "The background helper is offline. Repair it in Agent safety first.") }
                config.keepAwake = true
                try config.save()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
        }
    }
    @objc func toggleLid() {
        perform {
            let target = try !sleepDisabled()
            try setSleepDisabled(target)
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
            try SafetyFiles.send("input-access")
        } catch { showError(error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if self.inputs.wanted && GuardianInstall.status?.inputActive != true {
                self.showInputAccessPrompt()
            }
            self.refresh()
        }
    }
    func showInputAccessPrompt() { inputPermissions() }
    @objc func toggleTrackpad() { inputs.reverseTrackpad.toggle(); updateInputs() }
    @objc func toggleWheel() { inputs.reverseWheel.toggle(); updateInputs() }
    @objc func toggleModifiers() { setModifierGroup(true) }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if [#selector(toggleTrackpad), #selector(toggleWheel)].contains(item.action) {
            return GuardianInstall.status?.fresh == true && GuardianInstall.status?.inputTrusted == true
        }
        return true
    }
    @objc func inputPermissionsFromSettings() {
        if permissionSetup == nil { permissionSetup = PermissionSetup() }
        permissionSetup?.show(fromSettings: true)
    }
    @objc func inputPermissions() {
        if permissionSetup == nil { permissionSetup = PermissionSetup() }
        permissionSetup?.show()
    }
    @objc func toggleFunctionKeys() { perform { try FunctionKeys.setStandard(!FunctionKeys.standard()); keyboardModes.queue() } }
    @objc func toggleLogin() {
        perform {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        }
    }
    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "Perch"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        alert.informativeText = "Your Mac, ready for AI work.\n\nKeep your Mac awake through long tasks, control sound and input preferences, and see how local workloads use CPU, GPU, and memory.\n\nIf you need control back, Panic terminates selected agents and their tracked child processes, with an option to reset privacy permissions.\n\nVersion \(version)"

        SettingsWindow.shared.run(alert)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        inputs.stop()
        return .terminateNow
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--update-catalog"), CommandLine.arguments.count > index + 1 {
    do { try AgentCatalog.install(from: URL(fileURLWithPath: CommandLine.arguments[index + 1])); print("Catalog updated; new targets default to checked and existing choices are preserved."); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
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
