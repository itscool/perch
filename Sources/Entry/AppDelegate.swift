import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import IOKit.pwr_mgt

/// The menu app. State lives here; the menu, sleep and input behaviors are
/// grouped in the AppDelegate+ files next to this one.
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
    var keypadItem: NSMenuItem!
    var keyboardSetupItem: NSMenuItem!
    var homeEndItem: NSMenuItem!
    var pageKeysItem: NSMenuItem!
    var shareInputItem: NSMenuItem!
    var deskPresetItems: [NSMenuItem] = []
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
    // Status-item rendering state, updated by refresh() in AppDelegate+Menu.
    var lastStatusSymbol: String?
    var lastStatusCritical: Bool?
    var awakeItem: NSMenuItem!
    var lidItem: NSMenuItem!
    var idleLockItem: NSMenuItem!
    let idleLock = IdleLockPreventer()
    var observedSleep: SleepStatus?
    var observedLidDisabled: Bool?
    var automaticLidResume = LidAutomaticResume()
    var automaticLidResumeReady = false
    var renderedSleep: SleepPresentation?
    let lidSleepNotice = LidSleepNotice()
    var startupKeyboardAccessNotice = StartupKeyboardAccessNotice()
    var accessNoticeStarted = false
    var accessNoticeDeadline = Date.distantPast
    var settingsRefresh: (() -> Void)?
    var keyboardActionTestDriver: ((String, Bool) -> Void)?
    var audioItem: NSMenuItem!
    var audioSection: NSMenuItem!
    /// Set by a confirmed manual Quit; restarts and resets terminate without one.
    var pendingQuit: QuitPlan?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSettingsNavigation()
        // Permission entries an earlier, differently signed Perch left behind look
        // granted but do nothing. Remove them before anything asks for access.
        if !SettingsWindow.shared.testing {
            PermissionRecovery.startAtLaunch { [weak self] in self?.settingsRefresh?(); self?.refreshSafety() }
        }
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
        idleLock.set(UserDefaults.standard.bool(forKey: SleepPreferences.preventIdleLockKey))
        observeHelperPresentation()
        LidGuardClient.shared.start()
        lidSleepNotice.show = { [weak self] _, detail, acknowledge in
            self?.presentLidSleepNotice(detail: detail, acknowledge: acknowledge)
        }
        lidSleepNotice.start()
        LidCountdownController.shared.start()
        LidCountdownController.shared.openSetup = { [weak self] in self?.openSetupStage("lid-setup") }
        AppUpdate.completeLaunch { [weak self] in
            PerchUpdater.shared.completeLaunch { [weak self] in
                PerchUpdater.shared.showRecovery = { [weak self] in
                    self?.configureSettings(); self?.updateSettings()
                }
                PerchUpdater.shared.start()
                do { try HelperLifecycle.startForLaunch() }
                catch {
                    self?.safetyError = error.localizedDescription
                    BackgroundHelperRecovery.shared.recordFailure(error)
                    self?.advancedSafetySettings()
                }
                if CommandLine.arguments.contains("--complete-restart") || CommandLine.arguments.contains("--show-restart") {
                    self?.configureSettings(); self?.appSettings()
                }
                LidHelperUpdate.shared.afterLaunch(explain: { [weak self] in
                    self?.configureSettings(); self?.lidProtectionSetup()
                }, refresh: { [weak self] in self?.settingsRefresh?() }, completion: { [weak self] in
                    EventCollectorSetup.shared.afterLaunch { self?.processEventSetup() }
                })
                self?.automaticLidResumeReady = true
                self?.resumeSavedLidProtectionIfReady()
            }
        }
        inputTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.automaticLidResumeReady { BackgroundHelperRecovery.shared.check() }
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
        if CommandLine.arguments.contains("--show-event-setup") { DispatchQueue.main.async { self.processEventSetup() } }
        if !CommandLine.arguments.contains("--show-keyboard-setup") && !CommandLine.arguments.contains("--show-event-setup") {
            DispatchQueue.main.async { [weak self] in self?.showFirstSetupIfNeeded() }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let plan = pendingQuit; pendingQuit = nil
        return Self.terminationReply(plan: plan,
            updater: { PerchUpdater.shared.terminationReply(sender, willExit: $0) },
            // Release shared input, restore handed-away displays and tell desk
            // peers this is a deliberate stop, not a lost connection.
            shutdown: { [weak self] in self?.inputs.stop(); DeskCoordinator.shared.shutdown() },
            turnOff: { [weak self] plan, done in if let self { self.turnOffForQuit(plan, completion: done) } else { done() } },
            // Let the desk's goodbye frames leave before the process exits.
            reply: { TerminationReply.send(true, after: 0.3, to: sender) })
    }
    /// Only a confirmed manual Quit turns features off. A pending update owns
    /// its reply and shutdown timing; any other termination shuts down and replies.
    static func terminationReply(plan: QuitPlan?, updater: (@escaping () -> Void) -> NSApplication.TerminateReply?,
                                 shutdown: @escaping () -> Void, turnOff: (QuitPlan, @escaping () -> Void) -> Void,
                                 reply: @escaping () -> Void) -> NSApplication.TerminateReply {
        if let answer = updater(shutdown) { return answer }
        shutdown()
        if let plan { turnOff(plan, reply) } else { reply() }
        return .terminateLater
    }
}
