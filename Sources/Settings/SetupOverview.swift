import AppKit
import ServiceManagement

enum SetupRoute: String {
    case login, maintenance, inputAccess, keyboardAccess, sharingAccess, lidSetup, keyboards, displays, deskInput, awake, agents, events, settings
}

struct SetupCheck: Equatable {
    enum State: String { case ready = "Ready", attention = "Needs attention", optional = "Optional", checking = "Checking", unverified = "Unverified" }
    let id: String
    let title: String
    let state: State
    let detail: String
    let action: String
    let route: SetupRoute
}

/// A checklist of observed capability, not a history of clicked setup buttons.
/// Missing helpers leave dependent permissions unknown; they never prove denial.
struct SetupSnapshot {
    var guardian: SafetyStatus?
    var input: InputHelperStatus?
    var config: SafetyConfiguration
    var keyboardCount = 0
    var keyboardsBusy = false
    var keyboardAccessNeeded = false
    var keyboardErrors = false
    var keyboardSetupWanted = false
    var navigationNeedsLearning = false
    var monitorConfigured = false
    var monitorAvailable = false
    var monitorBusy = false
    var monitorWarning = false
    var monitorNeedsVerification = false
    var monitorDetail = "Connect an external monitor to set up input switching."
    var deskInputEnabled = false
    var deskInputActive = false
    var deskInputProblem: String?
    var deskInputAccessNeeded = false
    var collectorInstalled = false
    var collectorNeedsRepair = false
    var collectorWaitingForSession = false
    var lidDisabled: Bool?
    var lidWanted = false
    var lidGuard: LidGuardStatus?
    var lidHelperUpdatePending = false
    var lidHelperInstalled = false
    var loginNeedsApproval = false
    var helperRecoveryFailure: String?
    /// Permissions Perch removed for this publisher that are still missing.
    var accessRestoreNeeded: [PermissionService] = []
    var collectorChecking = false
    var lidHelperBusy = false

    var checks: [SetupCheck] {
        let agentWanted = config.shortcut.enabled || config.targets.contains(where: \.enabled)
        let inputWanted = config.reverseTrackpad || config.reverseWheel || config.navigation?.enabled == true || config.keypadNavigation == true
        let helperWanted = agentWanted || inputWanted || config.keepAwake
        let guardianReady = guardian?.fresh == true
        let inputReady = input?.fresh == true
        var items: [SetupCheck] = []
        func add(_ id: String, _ title: String, _ state: SetupCheck.State, _ detail: String, _ action: String, _ route: SetupRoute) {
            items.append(.init(id: id, title: title, state: state, detail: detail, action: action, route: route))
        }
        if loginNeedsApproval {
            add("login", "Start at login", .attention, "Your startup choice needs macOS approval. Open Login Items to allow Perch.", "Open macOS Login Items…", .login)
        }
        let helpersReady = guardianReady && (!inputWanted || inputReady)
        add("helpers", "Background controls", helpersReady ? .ready : helperRecoveryFailure != nil ? .attention : helperWanted ? .checking : .optional,
            helpersReady ? "Perch’s background controls are responding and up to date." : helperRecoveryFailure ?? (helperWanted ? "Perch is checking or restoring a required helper automatically." : "Needed for scrolling, keep-awake requests and agent protection."),
            "Background helpers…", .maintenance)

        if !accessRestoreNeeded.isEmpty {
            add("access", "Perch’s access", .attention,
                "Perch removed permission entries that no longer work for this copy. macOS needs \(PermissionService.list(accessRestoreNeeded)) granted again for Perch.",
                "Restore access…", .inputAccess)
        }

        if inputReady && input?.trusted == true && (!inputWanted || input?.active == true) {
            add("scrolling", "Scrolling & navigation access", .ready, inputWanted ? "Perch Helper has Accessibility access and the enabled input controls are running." : "Perch Helper has Accessibility access. Choose scrolling in the main menu or navigation behavior in Keyboards.", "View access…", .inputAccess)
        } else if !inputWanted {
            add("scrolling", "Scrolling & navigation access", .optional, "Enable scroll reversal or navigation changes when you want them. Perch Helper will need Accessibility access.", "Set up access…", .inputAccess)
        } else if !inputReady {
            add("scrolling", "Scrolling & navigation access", .checking, "Waiting for the input helper. Its Accessibility permission is not yet known.", "Background helpers…", .maintenance)
        } else if input?.trusted != true {
            add("scrolling", "Scrolling & navigation access", .attention, "Accessibility access for Perch Helper is missing. Your saved input choices are retained.", "Restore access…", .inputAccess)
        } else {
            add("scrolling", "Scrolling & navigation access", .attention, "Accessibility is granted, but enabled input controls are not running.", "Background helpers…", .maintenance)
        }

        let keyboardNeedsWork = keyboardAccessNeeded || keyboardErrors || (config.navigation?.enabled == true && navigationNeedsLearning)
        add("keyboards", "Keyboards", keyboardsBusy ? .checking : keyboardNeedsWork ? (keyboardSetupWanted || (keyboardAccessNeeded && keyboardCount > 0) ? .attention : .optional) : keyboardCount > 0 ? .ready : .optional,
            keyboardsBusy ? "Reading connected keyboards without applying saved modes." : keyboardAccessNeeded ? LaunchAccessRecovery.summary : keyboardNeedsWork ? "Review the affected keyboard or navigation layout. Other supported controls remain available." : keyboardCount > 0 ? "Connected keyboards are available. Known navigation layouts are recognized automatically." : "Connect a keyboard to review its supported controls or saved layout.", keyboardAccessNeeded ? "Keyboard access…" : "Keyboards…", keyboardAccessNeeded ? .keyboardAccess : .keyboards)

        let monitorState: SetupCheck.State = monitorBusy ? .checking : !monitorConfigured ? .optional : !monitorAvailable || monitorWarning ? .attention : monitorNeedsVerification ? .unverified : .ready
        add("displays", "Desk monitor presets", monitorState,
            monitorBusy ? "Checking which displays are available." : !monitorConfigured ? "Group computers and map monitor inputs in Desk if you want to use shared presets." : monitorState == .unverified ? "Your inputs are saved. Open Desk to review the current monitor state." : monitorDetail,
            monitorConfigured ? "Displays…" : "Set up display…", .displays)
        add("desk-input", "Desk keyboard & mouse sharing", !deskInputEnabled ? .optional : deskInputProblem != nil ? .attention : .ready,
            !deskInputEnabled ? "Optional: turn on Share on this Mac from the Perch menu on each participating Mac. Ctrl–Opt–Esc returns to local control during sharing." : deskInputProblem ?? (deskInputActive ? "Input sharing is active for this session. Ctrl–Opt–Esc returns control locally." : "Sharing is enabled here. An active preset with a remote screen starts control automatically."), deskInputAccessNeeded ? "Shared input access…" : "Open Desk…", deskInputAccessNeeded ? .sharingAccess : .deskInput)

        if lidHelperBusy {
            add("lid-setup", "Lid protection setup", .checking, "Updating the lid helper and checking its response. Your saved choices are kept.", "View progress…", .lidSetup)
        } else if !lidHelperInstalled || lidHelperUpdatePending {
            add("lid-setup", "Lid protection setup", lidWanted ? .attention : .optional,
                lidHelperUpdatePending ? "A previous lid helper update is incomplete. Open Setup → Lid protection for its result and retry." : "Install the lid helper in Setup → Lid protection before using the Mac with its lid closed.",
                lidHelperUpdatePending ? "Retry helper update…" : "Set up lid protection…", .lidSetup)
        }

        if lidDisabled == true {
            add("awake", "Keep awake", .attention, "System sleep is disabled outside Perch’s current protection session. Restore normal system sleep before enabling lid protection.", "Lid protection setup…", .lidSetup)
        } else if lidHelperBusy {
            add("awake", "Keep awake", .checking, "The lid helper update is in progress. Your existing protection deadline is retained.", "Lid protection setup…", .lidSetup)
        } else if lidHelperUpdatePending {
            add("awake", "Keep awake", .attention, "The lid helper update is incomplete. Open Setup → Lid protection to retry.", "Lid protection setup…", .lidSetup)
        } else if lidGuard?.fresh == true && lidGuard?.error != nil {
            add("awake", "Keep awake", .attention, lidGuard!.detail, "Lid protection setup…", .lidSetup)
        } else if lidGuard?.fresh == true && lidGuard?.armed == true {
            add("awake", "Keep awake", .ready, lidGuard!.displayDetail, "Lid protection setup…", .lidSetup)
        } else if !config.keepAwake {
            add("awake", "Keep awake", .optional, lidDisabled == nil ? "Perch’s request is off. The macOS lid override has not been verified." : "Currently off. Enable it when you want the Mac to keep working.", "Lid activity…", .awake)
        } else if !guardianReady && config.keepAwake {
            add("awake", "Keep awake", .checking, "Waiting for the helper to confirm the saved keep-awake request.", "Background helpers…", .maintenance)
        } else if guardian?.keepAwakeActive != true || (lidWanted && lidGuard?.armed != true) {
            add("awake", "Keep awake", .attention, lidWanted && lidGuard?.armed != true ? "Your lid choice is saved, but protection is stopped or unconfirmed. Protection resumes automatically when ready; after a closed-lid battery timeout, open the lid or connect power. Setup → Lid protection shows any setup failure." : "The observed sleep state does not confirm your saved keep-awake request.", "Lid protection setup…", .lidSetup)
        } else {
            add("awake", "Keep awake", .ready, "Perch’s idle-sleep prevention is active. Lid-closed behavior is separate.", "Lid activity…", .awake)
        }

        if !agentWanted {
            add("agents", "Agent Kill Switch", .optional, "Choose the agents and effects you want before relying on an emergency stop.", "Choose agents…", .agents)
        } else if !guardianReady {
            add("agents", "Agent Kill Switch", .checking, "Waiting for the protection helper. A saved shortcut does not establish that it is registered.", "Background helpers…", .maintenance)
        } else if guardian?.locked == true {
            add("agents", "Agent Kill Switch", .attention, "Agent activity is blocked after a previous stop. Review protection to resume when you are ready.", "Agent Kill Switch…", .agents)
        } else if config.shortcut.enabled && guardian?.shortcutActive != true && guardian?.testUntil == nil {
            add("agents", "Agent Kill Switch", .attention, "Your enabled emergency shortcut is not registered. Review it and run the harmless shortcut test.", "Agent Kill Switch…", .agents)
        } else if let error = guardian?.error, error.contains("configuration is unreadable") || error.contains("Lockdown could not be saved") {
            add("agents", "Agent Kill Switch", .attention, "Perch could not read or save protection state. Review the repair details before relying on it.", "Background helpers…", .maintenance)
        } else {
            add("agents", "Agent Kill Switch", .ready, config.shortcut.enabled ? "Protection is responding and the shortcut is registered. Use the harmless test to check the physical keys." : "Protection is responding. The keyboard shortcut is intentionally off.", "Agent Kill Switch…", .agents)
        }

        if collectorChecking {
            add("events", "Live agent tracking", .checking, "Waiting for the collector’s current access and event checks to finish.", "View progress…", .events)
        } else if !collectorInstalled {
            add("events", "Live agent tracking", .optional, "Improves tracking of short-lived agent subprocesses. Setup uses Full Disk Access for Apple’s eslogger.", "Set up tracking…", .events)
        } else if !guardianReady {
            add("events", "Live agent tracking", .checking, "The collector is installed. Waiting for Perch to verify received events and access.", "Background helpers…", .maintenance)
        } else if EventCollectorSetup.collectionReady(guardian, installed: collectorInstalled, needsRepair: collectorNeedsRepair, waitingForSession: collectorWaitingForSession) {
            add("events", "Live agent tracking", .ready, "Recent events and the live health check confirm that collection is working.", "View status…", .events)
        } else {
            add("events", "Live agent tracking", .attention, "The installed collector’s live access or health is not verified. Review Full Disk Access and the collection checks.", "Restore tracking…", .events)
        }
        return items
    }
    var summary: String {
        let items = checks
        let count: (SetupCheck.State) -> Int = { state in items.filter { $0.state == state }.count }
        return "\(count(.attention)) \(count(.attention) == 1 ? "needs" : "need") attention · \(count(.ready)) ready · \(count(.optional)) optional" + (count(.checking) > 0 ? " · \(count(.checking)) checking" : "") + (count(.unverified) > 0 ? " · \(count(.unverified)) unverified" : "")
    }
}

final class SetupOverviewPage {
    static let seenKey = "setup.overviewSeen.v1"
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 574))
    let summary = NSTextField(labelWithString: "Checking setup…")
    var timer: Timer? { SettingsWindow.shared.pollTimer(for: view) }
    private(set) var checks: [SetupCheck] = []
    private let read: () -> SetupSnapshot
    private let recheck: () -> Void
    private let navigate: (SetupRoute, String) -> Void
    private let firstVisit: Bool
    private var labels: [NSTextField] = []
    private var buttons: [SettingsActionButton] = []
    private var next: SettingsActionButton!
    private let scroll = NSScrollView()
    private let rows = NSView()
    init(firstVisit: Bool, read: @escaping () -> SetupSnapshot, recheck: @escaping () -> Void, navigate: @escaping (SetupRoute, String) -> Void) {
        self.firstVisit = firstVisit; self.read = read; self.recheck = recheck; self.navigate = navigate
        summary.font = .systemFont(ofSize: 14, weight: .semibold)
        summary.frame = NSRect(x: 8, y: 541, width: 556, height: 26); view.addSubview(summary)
        scroll.frame = NSRect(x: 0, y: 0, width: 572, height: 486)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        scroll.documentView = rows; view.addSubview(scroll)
        let check = SettingsActionButton(title: "Recheck") { [weak self] in self?.recheck(); self?.refresh() }
        check.frame = NSRect(x: 0, y: 497, width: 278, height: 32); view.addSubview(check)
        next = SettingsActionButton(title: "Continue setup") { [weak self] in
            guard let self else { return }
            if let item = self.checks.first(where: { $0.state == .attention }) { self.navigate(item.route, item.id) }
            else { self.navigate(.settings, "") }
        }
        next.frame = NSRect(x: 288, y: 497, width: 284, height: 32); view.addSubview(next)
    }
    func show() {
        let host = SettingsWindow.shared
        host.show(.init(title: "Setup & status", detail: firstVisit ? "Welcome to Perch. Complete the items marked Needs attention for the features you choose before relying on them. Optional features can wait. Lid protection has its own setup step below. Return here whenever access or setup changes." : "See what is ready and what needs attention. Open any item to adjust or repair it, then return here for the next check. Optional items can wait. Nothing is reset or enabled by visiting this page.", view: view, refresh: { [weak self] in self?.refresh() }, preferredBodyHeight: 574, layout: { [weak self] size in self?.resize(to: size) }, poll: .init(every: 1) { [weak self] in self?.refresh() }, owner: self))
        refresh()
    }
    func resize(to size: NSSize) {
        view.setFrameSize(size)
        summary.frame = NSRect(x: 8, y: size.height-33, width: size.width-16, height: 26)
        let controls = view.subviews.compactMap { $0 as? NSButton }
        for (i, button) in controls.enumerated() { button.frame = NSRect(x: CGFloat(i)*(size.width/2+2), y: size.height-77, width: size.width/2-4, height: 32) }
        scroll.frame = NSRect(x: 0, y: 0, width: size.width, height: max(96, size.height-88))
        refresh()
    }
    func refresh() {
        let snapshot = read(); checks = snapshot.checks; summary.stringValue = snapshot.summary
        summary.textColor = checks.contains { $0.state == .attention } ? StatusColors.warning : .labelColor
        if labels.count != checks.count {
            rows.subviews.forEach { $0.removeFromSuperview() }; labels = []; buttons = []
            for index in checks.indices {
                let label = NSTextField(wrappingLabelWithString: "")
                label.font = .systemFont(ofSize: 12); labels.append(label); rows.addSubview(label)
                let button = SettingsActionButton(title: "Checking…") { [weak self] in
                    guard let self, self.checks.indices.contains(index) else { return }
                    let item = self.checks[index]; self.navigate(item.route, item.id)
                }
                buttons.append(button); rows.addSubview(button)
            }
        }
        for (index, item) in checks.enumerated() {
            let color: NSColor = item.state == .attention || item.state == .unverified ? StatusColors.warning : item.state == .ready ? StatusColors.success : .labelColor
            let text = NSMutableAttributedString(string: item.title + " · " + item.state.rawValue + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
            text.append(NSAttributedString(string: item.detail, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
            labels[index].attributedStringValue = text
            labels[index].toolTip = item.detail
            buttons[index].title = item.action
            buttons[index].setAccessibilityLabel(item.action + " " + item.title)
        }
        let widestButton = buttons.map { ceil(($0.title as NSString).size(withAttributes: [.font: $0.font ?? NSFont.systemFont(ofSize: 13)]).width) + 32 }.max() ?? 164
        let buttonWidth = min(scroll.contentSize.width * 0.42, max(164, widestButton))
        let labelWidth = max(180, scroll.contentSize.width - buttonWidth - 36)
        let heights = labels.map { max(76, ceil($0.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: 10000)).height ?? 0) + 16) }
        let top = max(0, rows.frame.height - scroll.contentView.bounds.maxY)
        let height = max(scroll.contentSize.height, heights.reduce(0, +))
        let changedHeight = rows.frame.height != height
        rows.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
        var y = height
        for index in labels.indices {
            y -= heights[index]
            labels[index].frame = NSRect(x: 8, y: y + 8, width: labelWidth, height: heights[index] - 16)
            buttons[index].frame = NSRect(x: scroll.contentSize.width - buttonWidth - 18, y: y + heights[index] - 38, width: buttonWidth, height: 30)
        }
        if changedHeight {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, height - scroll.contentSize.height - top)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        let needsAttention = checks.contains { $0.state == .attention }
        let checking = checks.contains { $0.state == .checking }
        next.isEnabled = needsAttention || !checking
        next.title = needsAttention ? (firstVisit ? "Continue setup" : "Fix next issue") : checking ? "Checking setup…" : "App settings"
    }
}

extension AppDelegate {
    func setupSnapshot() -> SetupSnapshot {
        let config = SafetyConfiguration.load()
        var result = SetupSnapshot(guardian: GuardianInstall.status, input: HelperStatusIPC.inputClient.value, config: config)
        result.loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        result.keyboardCount = nativeKeyboards.count
        result.keyboardsBusy = keyboardModes.working
        result.keyboardAccessNeeded = keyboardModes.needsAccess
        result.keyboardErrors = keyboardModes.results.contains { !$0.verified } || !keyboardModes.modifierErrors.isEmpty || keyboardModes.registrationError != nil
        result.keyboardSetupWanted = config.navigation?.enabled == true || NativeFunctionKeys.externalIntent() != nil || UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(false)) != nil
        result.navigationNeedsLearning = keyboardModes.registrationNeedsSetup
        if let desk = DeskCoordinator.shared.runtime {
            result.deskInputEnabled = desk.input.enabled
            result.deskInputActive = desk.input.active
            result.deskInputProblem = desk.inputAdapter.accessProblem ?? desk.input.problem
            result.deskInputAccessNeeded = desk.input.enabled && desk.inputAdapter.needsPermissionSetup
            result.monitorConfigured = !desk.node.group.monitors.isEmpty
            result.monitorAvailable = desk.node.group.presets.contains { desk.switching.readiness($0.id) == nil }
            result.monitorBusy = desk.switching.busy
            result.monitorWarning = desk.model.problem != nil
            result.monitorNeedsVerification = false
            result.monitorDetail = desk.model.problem ?? "\(desk.node.group.name): \(desk.node.group.monitors.count) screens. Open Desk to review connections and presets."
        }

        result.collectorInstalled = EventCollectorSetup.shared.installed
        result.collectorNeedsRepair = EventCollectorSetup.shared.needsRepair
        result.collectorWaitingForSession = EventCollectorSetup.shared.waitingForSession
        result.collectorChecking = EventCollectorSetup.shared.checking
        result.helperRecoveryFailure = BackgroundHelperRecovery.shared.failure
        result.accessRestoreNeeded = PermissionRecovery.restoreNeeded()
        result.lidDisabled = observedLidDisabled
        result.lidWanted = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
        result.lidGuard = LidGuardClient.shared.status
        result.lidHelperUpdatePending = LidHelperUpdate.shared.state.pending
        result.lidHelperInstalled = LidHelperUpdate.shared.state.installed
        result.lidHelperBusy = LidHelperUpdate.shared.busy
        return result
    }
    func showFirstSetupIfNeeded(snapshot: SetupSnapshot? = nil) {
        guard !SettingsWindow.shared.window.isVisible else { return }
        guard !SettingsWindow.shared.interactionBusy else {
            SettingsWindow.shared.afterInteraction { [weak self] in self?.showFirstSetupIfNeeded(snapshot: snapshot) }; return
        }
        let needsSetup = (snapshot ?? setupSnapshot()).checks.contains { $0.state == .attention || $0.state == .checking }
        guard !UserDefaults.standard.bool(forKey: SetupOverviewPage.seenKey) || needsSetup else { return }
        configureSettings()
    }
    @objc func setupOverview() {
        if menuOpen { withMenuClosed { [weak self] in self?.setupOverview() }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.setupOverview() }; return }
        if let index = host.pages.firstIndex(where: { $0.title == "Setup & status" }) {
            guard host.returnToPage(at: index) else { return }
            host.pages.last?.refresh?()
            return
        }
        let first = !UserDefaults.standard.bool(forKey: SetupOverviewPage.seenKey)
        UserDefaults.standard.set(true, forKey: SetupOverviewPage.seenKey)
        let page = SetupOverviewPage(firstVisit: first, read: { [weak self] in self?.setupSnapshot() ?? SetupSnapshot(config: SafetyConfiguration()) }, recheck: { [weak self] in
            self?.keyboardModes.recheck(); DeskCoordinator.shared.runtime?.refreshAllDisplays()
            HelperStatusIPC.guardianClient.refresh(); HelperStatusIPC.inputClient.refresh()
            self?.refresh()
        }, navigate: { [weak self] route, id in self?.openSetupRoute(route, id: id) })
        page.show()
        if !SettingsWindow.shared.testing { keyboardModes.recheck() }
    }
    func openSetupRoute(_ route: SetupRoute, id: String = "") {
        switch route {
        case .login: reviewLoginApproval()
        case .maintenance: advancedSafetySettings()
        case .inputAccess: inputPermissionsFromSettings()
        case .keyboardAccess: keyboardAccessRecovery()
        case .sharingAccess: sharingAccessSetup()
        case .lidSetup: lidProtectionSetup()
        case .keyboards: keyboardSettings()
        case .displays: deskSettings()
        case .deskInput: deskSettings()
        case .awake: lidActivity()
        case .agents: configurePanic()
        case .events: processEventSetup()
        case .settings: if id == "scrolling" { scrollingSettings() } else { appSettings() }
        }
    }
}
