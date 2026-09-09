import AppKit

enum SetupRoute: String {
    case maintenance, inputAccess, keyboards, displays, awake, agents, events, settings
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
    var collectorInstalled = false
    var lidDisabled: Bool?
    var lidWanted = false
    var lidGuard: LidGuardStatus?
    var lidHelperUpdatePending = false

    var checks: [SetupCheck] {
        let agentWanted = config.shortcut.enabled || config.targets.contains(where: \.enabled)
        let inputWanted = config.reverseTrackpad || config.reverseWheel || config.navigation?.enabled == true
        let helperWanted = agentWanted || inputWanted || config.keepAwake
        let guardianReady = guardian?.fresh == true
        let inputReady = input?.fresh == true
        var items: [SetupCheck] = []
        func add(_ id: String, _ title: String, _ state: SetupCheck.State, _ detail: String, _ action: String, _ route: SetupRoute) {
            items.append(.init(id: id, title: title, state: state, detail: detail, action: action, route: route))
        }
        let helpersReady = guardianReady && (!inputWanted || inputReady)
        add("helpers", "Background controls", helpersReady ? .ready : helperWanted ? .attention : .optional,
            helpersReady ? "Perch’s background controls are responding and up to date." : helperWanted ? "A required helper is unavailable or outdated. Repair it to restore the features that depend on it." : "Needed for scrolling, keep-awake requests and agent protection.",
            helpersReady ? "Maintenance…" : "Review repair…", .maintenance)

        if inputReady && input?.trusted == true && (!inputWanted || input?.active == true) {
            add("scrolling", "Scrolling & navigation access", .ready, inputWanted ? "Perch Helper has Accessibility access and the enabled input controls are running." : "Perch Helper has Accessibility access. Choose scroll or navigation behavior in Settings.", "Open scrolling…", .settings)
        } else if !inputWanted {
            add("scrolling", "Scrolling & navigation access", .optional, "Enable scroll reversal or navigation changes when you want them. Perch Helper will need Accessibility access.", "Set up access…", .inputAccess)
        } else if !inputReady {
            add("scrolling", "Scrolling & navigation access", .checking, "Waiting for the input helper. Its Accessibility permission is not yet known.", "Review helpers…", .maintenance)
        } else if input?.trusted != true {
            add("scrolling", "Scrolling & navigation access", .attention, "Accessibility access for Perch Helper is missing. Your saved input choices are retained.", "Restore access…", .inputAccess)
        } else {
            add("scrolling", "Scrolling & navigation access", .attention, "Accessibility is granted, but enabled input controls are not running.", "Review repair…", .maintenance)
        }

        let keyboardNeedsWork = keyboardAccessNeeded || keyboardErrors || (config.navigation?.enabled == true && navigationNeedsLearning)
        add("keyboards", "Keyboards", keyboardsBusy ? .checking : keyboardNeedsWork ? (keyboardSetupWanted ? .attention : .optional) : keyboardCount > 0 ? .ready : .optional,
            keyboardsBusy ? "Reading connected keyboards without applying saved modes." : keyboardAccessNeeded ? LaunchAccessRecovery.summary : keyboardNeedsWork ? "Review the affected keyboard or navigation layout. Other supported controls remain available." : keyboardCount > 0 ? "Connected keyboards are available. Known navigation layouts are recognized automatically." : "Connect a keyboard to review its supported controls or saved layout.", "Review keyboards…", .keyboards)

        let monitorState: SetupCheck.State = monitorBusy ? .checking : !monitorConfigured ? .optional : !monitorAvailable || monitorWarning ? .attention : monitorNeedsVerification ? .unverified : .ready
        add("displays", "Display input switching", monitorState,
            monitorBusy ? "Checking which displays are available." : !monitorConfigured ? "Choose a display and its inputs if you want to switch between computers." : monitorState == .unverified ? "Your inputs are saved. Current input unknown; read or confirm it in monitor settings before cycling." : monitorDetail,
            monitorConfigured ? "Review display…" : "Set up display…", .displays)

        if lidDisabled == true {
            add("awake", "Keep awake", .attention, "An older system-wide sleep override is active without a timeout. Remove it before setting up supervised lid protection.", "Review sleep…", .awake)
        } else if lidHelperUpdatePending {
            add("awake", "Keep awake", .attention, "Lid helper update queued. Open the lid and review Keep awake to finish. The existing helper is kept until then.", "Review helper update…", .awake)
        } else if lidGuard?.error != nil {
            add("awake", "Keep awake", .attention, lidGuard!.detail, "Review sleep…", .awake)
        } else if lidGuard?.fresh == true && lidGuard?.armed == true {
            add("awake", "Keep awake", .unverified, "Lid mode is requested. macOS can override it; continued sleep prevention cannot be verified.", "Review sleep…", .awake)
        } else if !config.keepAwake && lidDisabled != true {
            add("awake", "Keep awake", .optional, lidDisabled == nil ? "Perch’s request is off. The macOS lid override has not been verified." : "Currently off. Enable it when you want the Mac to keep working.", "Choose behavior…", .awake)
        } else if !guardianReady && config.keepAwake {
            add("awake", "Keep awake", .checking, "Waiting for the helper to confirm the saved keep-awake request.", "Review helpers…", .maintenance)
        } else if !config.keepAwake && lidDisabled == true {
            add("awake", "Keep awake", .attention, "macOS has the lid override on while Perch’s keep-awake request is off. Review the actual sleep behavior.", "Review sleep…", .awake)
        } else if guardian?.keepAwakeActive != true || (lidWanted && lidGuard?.armed != true) {
            add("awake", "Keep awake", .attention, lidWanted && lidGuard?.armed != true ? "Your lid choice is saved, but protection is stopped or unconfirmed. Review Keep awake for status and Resume lid protection." : "The observed sleep state does not confirm your saved keep-awake request.", "Review sleep…", .awake)
        } else {
            add("awake", "Keep awake", .ready, lidDisabled == true ? "Lid-closed override is active, including on battery. Keep the Mac ventilated." : "Perch’s idle-sleep prevention is active. Lid-closed behavior is separate.", "Adjust sleep…", .awake)
        }

        if !agentWanted {
            add("agents", "Agent Kill Switch", .optional, "Choose the agents and effects you want before relying on an emergency stop.", "Choose agents…", .agents)
        } else if !guardianReady {
            add("agents", "Agent Kill Switch", .checking, "Waiting for the protection helper. A saved shortcut does not establish that it is registered.", "Review helpers…", .maintenance)
        } else if guardian?.locked == true {
            add("agents", "Agent Kill Switch", .attention, "Agent activity is blocked after a previous stop. Review protection to resume when you are ready.", "Review protection…", .agents)
        } else if config.shortcut.enabled && guardian?.shortcutActive != true && guardian?.testUntil == nil {
            add("agents", "Agent Kill Switch", .attention, "Your enabled emergency shortcut is not registered. Review it and run the harmless shortcut test.", "Review protection…", .agents)
        } else if let error = guardian?.error, error.contains("configuration is unreadable") || error.contains("Lockdown could not be saved") {
            add("agents", "Agent Kill Switch", .attention, "Perch could not read or save protection state. Review the repair details before relying on it.", "Review repair…", .maintenance)
        } else {
            add("agents", "Agent Kill Switch", .ready, config.shortcut.enabled ? "Protection is responding and the shortcut is registered. Use the harmless test to check the physical keys." : "Protection is responding. The keyboard shortcut is intentionally off.", "Review or test…", .agents)
        }

        if !collectorInstalled {
            add("events", "Live agent tracking", .optional, "Improves tracking of short-lived agent subprocesses. Setup uses Full Disk Access for Apple’s eslogger.", "Set up tracking…", .events)
        } else if !guardianReady {
            add("events", "Live agent tracking", .checking, "The collector is installed. Waiting for Perch to verify received events and access.", "Review helpers…", .maintenance)
        } else if guardian?.eventCoverage == "Process events active" && guardian?.eventConnected == true && guardian?.eventLastSeen.map({ Date().timeIntervalSince($0) < 45 }) == true {
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
    private(set) var timer: Timer?
    private(set) var checks: [SetupCheck] = []
    private let read: () -> SetupSnapshot
    private let recheck: () -> Void
    private let navigate: (SetupRoute, String) -> Void
    private let firstVisit: Bool
    private var labels: [NSTextField] = []
    private var buttons: [SettingsActionButton] = []
    private var next: SettingsActionButton!
    init(firstVisit: Bool, read: @escaping () -> SetupSnapshot, recheck: @escaping () -> Void, navigate: @escaping (SetupRoute, String) -> Void) {
        self.firstVisit = firstVisit; self.read = read; self.recheck = recheck; self.navigate = navigate
        summary.font = .systemFont(ofSize: 14, weight: .semibold)
        summary.frame = NSRect(x: 8, y: 541, width: 556, height: 26); view.addSubview(summary)
        for index in 0..<7 {
            let label = NSTextField(wrappingLabelWithString: "")
            label.frame = NSRect(x: 8, y: 428-index*68, width: 372, height: 59)
            label.font = .systemFont(ofSize: 12); labels.append(label); view.addSubview(label)
            let button = SettingsActionButton(title: "Checking…") { [weak self] in
                guard let self, self.checks.indices.contains(index) else { return }
                let item = self.checks[index]; self.navigate(item.route, item.id)
            }
            button.frame = NSRect(x: 390, y: 442-index*68, width: 182, height: 30)
            buttons.append(button); view.addSubview(button)
        }
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
        host.show(.init(title: "Setup & status", detail: firstVisit ? "Welcome to Perch. Start with the features you want; optional items can wait. Return here any time to check setup or restore missing access." : "See what is ready and what needs attention. Open any item to adjust or repair it, then return here for the next check. Optional items can wait. Nothing is reset or enabled by visiting this page.", view: view, leave: { [self] in self.timer?.invalidate(); self.timer = nil }, refresh: { [weak self] in self?.refresh() }, preferredBodyHeight: 574))
        refresh()
        self.timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard SettingsWindow.shared.pages.last?.title == "Setup & status", !SettingsWindow.shared.interactionBusy else { return }
            self?.refresh()
        }
        timer.tolerance = 0.2; self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func refresh() {
        let snapshot = read(); checks = snapshot.checks; summary.stringValue = snapshot.summary
        summary.textColor = checks.contains { $0.state == .attention } ? StatusColors.warning : .labelColor
        for (index, item) in checks.enumerated() {
            let color: NSColor = item.state == .attention || item.state == .unverified ? StatusColors.warning : item.state == .ready ? StatusColors.success : .labelColor
            let text = NSMutableAttributedString(string: item.title + " · " + item.state.rawValue + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
            text.append(NSAttributedString(string: item.detail, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
            labels[index].attributedStringValue = text
            labels[index].toolTip = item.detail
            buttons[index].title = item.action
            buttons[index].setAccessibilityLabel(item.action + " " + item.title)
        }
        next.title = checks.contains { $0.state == .attention } ? (firstVisit ? "Continue setup" : "Fix next issue") : "Open settings"
    }
}

extension AppDelegate {
    func setupSnapshot() -> SetupSnapshot {
        let config = SafetyConfiguration.load()
        var result = SetupSnapshot(guardian: GuardianInstall.status, input: HelperStatusIPC.inputClient.value, config: config)
        result.keyboardCount = nativeKeyboards.count
        result.keyboardsBusy = keyboardModes.working
        result.keyboardAccessNeeded = keyboardModes.needsAccess
        result.keyboardErrors = keyboardModes.results.contains { !$0.verified } || !keyboardModes.modifierErrors.isEmpty || keyboardModes.registrationError != nil
        result.keyboardSetupWanted = config.navigation?.enabled == true || NativeFunctionKeys.externalIntent() != nil || UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(false)) != nil
        result.navigationNeedsLearning = keyboardModes.registrationNeedsSetup
        result.monitorConfigured = !monitorInputs.plan.display.isEmpty && !(monitorInputs.plan.availableInputs ?? monitorInputs.plan.inputs).isEmpty
        result.monitorAvailable = monitorInputs.canSwitch
        result.monitorBusy = monitorInputs.checkingDisplays || monitorInputs.busy || monitorInputs.groups.busy
        result.monitorWarning = monitorInputs.warning || (monitorInputs.plan.shortcut.enabled && !monitorInputs.shortcutActive)
        result.monitorNeedsVerification = !monitorInputs.currentInputKnown
        result.monitorDetail = monitorInputs.warning ? monitorInputs.message : monitorInputs.plan.shortcut.enabled && !monitorInputs.shortcutActive ? "The input shortcut is unavailable. Review its keys and the display’s connection." : !monitorInputs.canSwitch ? "The saved display or its control connection is unavailable. Review the connection and inputs." : monitorInputs.currentSummary
        if let group = monitorInputs.groups.active, let destination = group.destinations.first {
            // Named group destinations issue explicit per-display inputs; they
            // do not infer a next input from a remembered current position.
            result.monitorNeedsVerification = false
            result.monitorConfigured = true
            result.monitorAvailable = !result.monitorBusy && monitorInputs.groups.requests(group, destination: destination).allSatisfy { $0.unavailable == nil }
            result.monitorWarning = monitorInputs.groups.hasAttention
            result.monitorDetail = "\(group.name): \(group.members.count) selected displays. " + monitorInputs.groups.message
        }
        result.collectorInstalled = EventCollectorSetup.shared.installed
        result.lidDisabled = observedLidDisabled
        result.lidWanted = UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey)
        result.lidGuard = LidGuardClient.shared.status
        result.lidHelperUpdatePending = LidHelperUpdate.shared.state.pending
        return result
    }
    func showFirstSetupIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: SetupOverviewPage.seenKey), !SettingsWindow.shared.window.isVisible, !SettingsWindow.shared.interactionBusy else { return }
        configureSettings(); setupOverview()
    }
    @objc func setupOverview() {
        if menuOpen { withMenuClosed { [weak self] in self?.setupOverview() }; return }
        let host = SettingsWindow.shared
        guard !host.interactionBusy else { host.afterInteraction { [weak self] in self?.setupOverview() }; return }
        if let index = host.pages.firstIndex(where: { $0.title == "Setup & status" }) {
            while host.pages.count > index + 1 { host.goBack() }
            host.pages.last?.refresh?()
            return
        }
        let first = !UserDefaults.standard.bool(forKey: SetupOverviewPage.seenKey)
        UserDefaults.standard.set(true, forKey: SetupOverviewPage.seenKey)
        let page = SetupOverviewPage(firstVisit: first, read: { [weak self] in self?.setupSnapshot() ?? SetupSnapshot(config: SafetyConfiguration()) }, recheck: { [weak self] in
            self?.keyboardModes.recheck(); self?.monitorInputs.refresh()
            HelperStatusIPC.guardianClient.refresh(); HelperStatusIPC.inputClient.refresh()
            self?.refresh()
        }, navigate: { [weak self] route, id in self?.openSetupRoute(route, id: id) })
        page.show()
        if !SettingsWindow.shared.testing { keyboardModes.recheck() }
    }
    func openSetupRoute(_ route: SetupRoute, id: String = "") {
        switch route {
        case .maintenance: advancedSafetySettings()
        case .inputAccess: inputPermissionsFromSettings()
        case .keyboards: keyboardSettings()
        case .displays: if monitorInputs.groups.active != nil { monitorGroupSettings() } else { displaySettings() }
        case .awake: keepAwakeSettings()
        case .agents: configurePanic()
        case .events: processEventSetup()
        case .settings: if id == "scrolling" { scrollingSettings() } else { configureSettings() }
        }
    }
}
