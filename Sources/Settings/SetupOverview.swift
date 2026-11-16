import AppKit
import ServiceManagement

/// The five Setup steps. Each Setup row opens its own step, the one the
/// sidebar lists under Setup (Scott, November 16, 2026).
enum SetupRoute: String {
    case maintenance, keyboardAccess, inputAccess, sharingAccess, lidSetup
}

struct SetupCheck: Equatable {
    enum State: String { case ready = "Ready", attention = "Needs attention", optional = "Optional", checking = "Checking" }
    /// The step's sidebar id.
    let id: String
    /// The step's sidebar name.
    let title: String
    let state: State
    let detail: String
    let route: SetupRoute
}

/// A checklist of observed capability, not a history of clicked setup buttons.
/// Missing helpers leave dependent permissions unknown; they never prove denial.
///
/// Setup lists exactly its five steps, with the sidebar's names, order and
/// state, so the page and the sidebar never disagree. Feature state (keyboard
/// modes, the desk's monitors, keep-awake sessions) belongs to its feature;
/// the sidebar flags Keyboards and Desk when they need attention.
struct SetupSnapshot {
    var guardian: SafetyStatus?
    var input: InputHelperStatus?
    var config: SafetyConfiguration
    var keyboardAccessNeeded = false
    var keyboardSetupWanted = false
    /// Perch's own Input Monitoring, which Keyboard access sets up.
    var keyboardAccessGranted = false
    /// Accessibility and Input Monitoring for Perch, which Shared input access sets up.
    var sharingAccessGranted = false
    var deskInputEnabled = false
    var lidDisabled: Bool?
    var lidWanted = false
    var lidGuard: LidGuardStatus?
    var lidHelperUpdatePending = false
    var lidHelperInstalled = false
    var lidHelperBusy = false
    var lidChanging = false
    var loginNeedsApproval = false
    var helperRecoveryFailure: String?
    /// The Agent Kill Switch's root process watcher is still on this Mac.
    var watcherInstalled = false
    /// Permissions Perch removed for this publisher that are still missing.
    var accessRestoreNeeded: [PermissionService] = []
    /// Keyboards and Desk, flagged in the sidebar only when they need attention.
    var keyboardsNeedAttention = false
    var deskNeedsAttention = false

    var checks: [SetupCheck] { [helpers, keyboardAccess, scrolling, sharing, lid] }
    /// The sidebar's state for every row that shows one.
    var sidebar: [String: SetupCheck.State] {
        var states = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0.state) })
        if keyboardsNeedAttention { states["keyboard"] = .attention }
        if deskNeedsAttention { states["desk"] = .attention }
        return states
    }

    private var inputWanted: Bool { config.reverseTrackpad || config.reverseWheel || config.navigation?.enabled == true || config.keypadNavigation == true }
    private static func restore(_ service: PermissionService) -> String {
        "Perch removed its old \(service.title) entry, which no longer worked for this copy. Grant \(service.title) to Perch again."
    }

    var helpers: SetupCheck {
        func row(_ state: SetupCheck.State, _ detail: String) -> SetupCheck {
            .init(id: "maintenance", title: "Background helpers", state: state, detail: detail, route: .maintenance)
        }
        if watcherInstalled { return row(.attention, "The old process watcher is still running and slowing this Mac down. Remove it in this step; macOS asks for your password.") }
        if loginNeedsApproval { return row(.attention, "Starting Perch at login needs your approval in macOS Login Items.") }
        if guardian?.fresh == true && (!inputWanted || input?.fresh == true) { return row(.ready, "Perch’s background helpers are responding and up to date.") }
        if let helperRecoveryFailure { return row(.attention, helperRecoveryFailure) }
        return inputWanted || config.keepAwake
            ? row(.checking, "Perch is checking or restoring a helper automatically.")
            : row(.optional, "Needed for scrolling, Keep awake and putting back desk screens.")
    }
    var keyboardAccess: SetupCheck {
        func row(_ state: SetupCheck.State, _ detail: String) -> SetupCheck {
            .init(id: "keyboard-access", title: "Keyboard access", state: state, detail: detail, route: .keyboardAccess)
        }
        if keyboardAccessGranted { return row(.ready, "Perch can read your keyboards.") }
        if accessRestoreNeeded.contains(.inputMonitoring) { return row(.attention, Self.restore(.inputMonitoring)) }
        return keyboardSetupWanted || keyboardAccessNeeded || deskInputEnabled
            ? row(.attention, "Input Monitoring for Perch is off. Keyboard modes, layouts and keyboard sharing need it.")
            : row(.optional, "Needed for keyboard modes and layouts, and for sharing the keyboard.")
    }
    var scrolling: SetupCheck {
        func row(_ state: SetupCheck.State, _ detail: String) -> SetupCheck {
            .init(id: "input-access", title: "Scrolling & navigation", state: state, detail: detail, route: .inputAccess)
        }
        let fresh = input?.fresh == true, trusted = input?.trusted == true
        if fresh && trusted && (!inputWanted || input?.active == true) {
            return row(.ready, inputWanted ? "Perch Helper has Accessibility access, and your scrolling and navigation choices are running." : "Perch Helper has Accessibility access.")
        }
        if !inputWanted { return row(.optional, "Scroll reversal and navigation keys need Accessibility for Perch Helper.") }
        if !fresh { return row(.checking, "Waiting for Perch Helper. Its Accessibility access isn’t known yet.") }
        if !trusted { return row(.attention, "Accessibility for Perch Helper is off. Your choices are kept.") }
        return row(.attention, "Accessibility is on, but your scrolling and navigation choices aren’t running.")
    }
    var sharing: SetupCheck {
        func row(_ state: SetupCheck.State, _ detail: String) -> SetupCheck {
            .init(id: "sharing-access", title: "Shared input access", state: state, detail: detail, route: .sharingAccess)
        }
        if sharingAccessGranted { return row(.ready, "Perch has Accessibility and Input Monitoring for keyboard and mouse sharing.") }
        if accessRestoreNeeded.contains(.accessibility) { return row(.attention, Self.restore(.accessibility)) }
        return deskInputEnabled
            ? row(.attention, "Keyboard and mouse sharing is on, but Perch doesn’t have Accessibility and Input Monitoring.")
            : row(.optional, "Needed to share the keyboard and mouse between your Macs.")
    }
    var lid: SetupCheck {
        func row(_ state: SetupCheck.State, _ detail: String) -> SetupCheck {
            .init(id: "lid-setup", title: "Lid protection", state: state, detail: detail, route: .lidSetup)
        }
        if lidHelperBusy || lidChanging { return row(.checking, "Updating the lid helper. Your saved choices are kept.") }
        if lidHelperUpdatePending { return row(.attention, "The last lid helper update didn’t finish. Open this step to finish it.") }
        if !lidHelperInstalled {
            if lidWanted { return row(.attention, "Install the lid helper so this Mac keeps working with its lid closed.") }
            return row(.optional, lidDisabled == true ? "Sleep was disabled outside Perch. Set up lid protection and Perch takes it over." : "Needed to keep this Mac working with its lid closed.")
        }
        if let status = lidGuard, status.fresh, let error = status.error { return row(.attention, error) }
        return row(.ready, "The lid helper is installed.")
    }
    var summary: String {
        let items = checks
        let count: (SetupCheck.State) -> Int = { state in items.filter { $0.state == state }.count }
        return "\(count(.attention)) \(count(.attention) == 1 ? "needs" : "need") attention · \(count(.ready)) ready · \(count(.optional)) optional" + (count(.checking) > 0 ? " · \(count(.checking)) checking" : "")
    }
}

/// Setup's own page: its five steps with their state. Every row opens its
/// step, the same one the sidebar shows beneath Setup. It keeps itself current
/// once a second, so it has no Recheck, and the rows needing attention carry
/// their own buttons, so it has no "next issue" button (Scott, November 16).
final class SetupOverviewPage {
    static let seenKey = "setup.overviewSeen.v1"
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 574))
    let summary = NSTextField(labelWithString: "Checking setup…")
    var timer: Timer? { SettingsWindow.shared.pollTimer(for: view) }
    private(set) var checks: [SetupCheck] = []
    private let read: () -> SetupSnapshot
    private let navigate: (SetupRoute) -> Void
    private let firstVisit: Bool
    private var labels: [NSTextField] = []
    private var buttons: [SettingsActionButton] = []
    private let scroll = NSScrollView()
    private let rows = NSView()
    init(firstVisit: Bool, read: @escaping () -> SetupSnapshot, navigate: @escaping (SetupRoute) -> Void) {
        self.firstVisit = firstVisit; self.read = read; self.navigate = navigate
        summary.font = .systemFont(ofSize: 14, weight: .semibold)
        summary.frame = NSRect(x: 8, y: 541, width: 556, height: 26); view.addSubview(summary)
        scroll.frame = NSRect(x: 0, y: 0, width: 572, height: 530)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        scroll.documentView = rows; view.addSubview(scroll)
    }
    func show() {
        let host = SettingsWindow.shared
        host.show(.init(title: "Setup & status", detail: firstVisit ? "Welcome to Perch. Each step below sets up something a feature needs. Steps marked Needs attention are for features you turned on; optional ones can wait." : "What each step needs. Open a step to set it up or repair it. Visiting this page changes nothing.", view: view, refresh: { [weak self] in self?.refresh() }, preferredBodyHeight: 574, layout: { [weak self] size in self?.resize(to: size) }, poll: .init(every: 1) { [weak self] in self?.refresh() }, owner: self))
        refresh()
    }
    func resize(to size: NSSize) {
        view.setFrameSize(size)
        summary.frame = NSRect(x: 8, y: size.height-33, width: size.width-16, height: 26)
        scroll.frame = NSRect(x: 0, y: 0, width: size.width, height: max(96, size.height-44))
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
                let button = SettingsActionButton(title: "Open") { [weak self] in
                    guard let self, self.checks.indices.contains(index) else { return }
                    self.navigate(self.checks[index].route)
                }
                buttons.append(button); rows.addSubview(button)
            }
        }
        for (index, item) in checks.enumerated() {
            let color: NSColor = item.state == .attention ? StatusColors.warning : item.state == .ready ? StatusColors.success : .labelColor
            let text = NSMutableAttributedString(string: item.title + " · " + item.state.rawValue + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
            text.append(NSAttributedString(string: item.detail, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
            labels[index].attributedStringValue = text
            labels[index].toolTip = item.detail
            buttons[index].toolTip = "Open " + item.title + "."
            buttons[index].setAccessibilityLabel("Open " + item.title)
        }
        let buttonWidth: CGFloat = 96
        let labelWidth = max(180, scroll.contentSize.width - buttonWidth - 36)
        let heights = labels.map { max(64, ceil($0.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: 10000)).height ?? 0) + 16) }
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
    }
}

extension AppDelegate {
    func setupSnapshot() -> SetupSnapshot {
        let config = SafetyConfiguration.load()
        var result = SetupSnapshot(guardian: GuardianInstall.status, input: HelperStatusIPC.inputClient.value, config: config)
        result.loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        result.keyboardAccessNeeded = keyboardModes.needsAccess
        result.keyboardSetupWanted = config.navigation?.enabled == true || NativeFunctionKeys.externalIntent() != nil || UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(false)) != nil
        result.keyboardAccessGranted = AccessCheck.hidListening
        result.sharingAccessGranted = AccessCheck.sharing
        result.keyboardsNeedAttention = keyboardModes.warning
        if let desk = DeskCoordinator.shared.runtime {
            result.deskInputEnabled = desk.input.enabled
            // The Desk page's own Needs attention: a failed action or a failed switch.
            result.deskNeedsAttention = desk.model.problem != nil || !desk.model.monitorProblems.isEmpty
        }
        result.helperRecoveryFailure = BackgroundHelperRecovery.shared.failure
        result.watcherInstalled = RetiredProcessWatcher.installed()
        result.accessRestoreNeeded = PermissionRecovery.restoreNeeded()
        result.lidDisabled = observedLidDisabled
        result.lidWanted = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
        result.lidGuard = LidGuardClient.shared.status
        result.lidHelperUpdatePending = LidHelperUpdate.shared.state.pending
        result.lidHelperInstalled = LidHelperUpdate.shared.state.installed
        result.lidHelperBusy = LidHelperUpdate.shared.busy
        result.lidChanging = LidGuardClient.shared.changing
        return result
    }
    func showFirstSetupIfNeeded(snapshot: SetupSnapshot? = nil) {
        guard !SettingsWindow.shared.window.isVisible else { return }
        guard !SettingsWindow.shared.interactionBusy else {
            SettingsWindow.shared.afterInteraction { [weak self] in self?.showFirstSetupIfNeeded(snapshot: snapshot) }; return
        }
        // Only a step that needs the person: one still checking finishes by itself.
        let needsSetup = (snapshot ?? setupSnapshot()).checks.contains { $0.state == .attention }
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
        let page = SetupOverviewPage(firstVisit: first, read: { [weak self] in self?.setupSnapshot() ?? SetupSnapshot(config: SafetyConfiguration()) },
                                     navigate: { [weak self] route in self?.openSetupRoute(route) })
        page.show()
        if !SettingsWindow.shared.testing { keyboardModes.recheck() }
    }
    func openSetupRoute(_ route: SetupRoute) {
        switch route {
        case .maintenance: advancedSafetySettings()
        case .keyboardAccess: keyboardAccessRecovery()
        case .inputAccess: inputPermissionsFromSettings()
        case .sharingAccess: sharingAccessSetup()
        case .lidSetup: lidProtectionSetup()
        }
    }
}
