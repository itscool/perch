import AppKit
import ServiceManagement

/// Simple task pages keep the same controls while observed status refreshes.
/// Only explicit control actions change preferences or request system changes.
final class SettingsTaskPage {
    let title: String
    let detail: String
    let view: NSView
    let status = SettingsStatusField(wrappingLabelWithString: "")
    var update: (() -> Void)?
    private var timer: Timer?
    private var y: CGFloat
    private var statusHeight: CGFloat
    private var hiddenRows: [NSButton] = []
    private var footerHeight: CGFloat = 0
    private var rows: [(button: NSButton, label: NSTextField)] = []
    init(title: String, detail: String, height: CGFloat, statusHeight: CGFloat = 60) {
        self.title = title; self.detail = detail; self.statusHeight = statusHeight
        view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height))
        status.font = .systemFont(ofSize: 13)
        status.frame = NSRect(x: 8, y: height-statusHeight-5, width: 556, height: statusHeight)
        view.addSubview(status); y = height-statusHeight-83
    }
    @discardableResult
    func add(_ title: String, detail: String, checkbox: Bool = false, action: @escaping () -> Void) -> NSButton {
        // A painted child outside its parent's bounds cannot receive a real
        // mouse click. Grow the document before adding rows, including on pages
        // whose original height predates additional actions.
        if y < 16 {
            let growth = 16 - y
            view.frame.size.height += growth
            for child in view.subviews { child.frame.origin.y += growth }
            y += growth
        }
        let button = SettingsActionButton(title: title, action: action)
        button.identifier = .init("settings.task." + title)
        button.toolTip = detail
        button.setAccessibilityHelp(detail)
        if checkbox { button.setButtonType(.switch); button.allowsMixedState = true }
        button.frame = NSRect(x: 0, y: y+34, width: 572, height: 30)
        let label = NSTextField(wrappingLabelWithString: detail)
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 8, y: y, width: 556, height: 32)
        view.addSubview(button); view.addSubview(label); y -= 74
        rows.append((button, label))
        return button
    }
    /// Reflow optional instructions as one row, including their explanation.
    /// Hidden setup controls must not leave stale instructions or empty blocks.
    func arrangeRows(hiding hidden: [NSButton], footerHeight: CGFloat = 0) {
        hiddenRows = hidden; self.footerHeight = footerHeight
        statusHeight = status.measuredHeight(width: 556)
        let visible = rows.filter { row in !hidden.contains { $0 === row.button } }
        let height = statusHeight + 54 + CGFloat(visible.count) * 74 + footerHeight
        let resized = view.frame.height != height
        view.frame.size.height = height
        status.frame = NSRect(x: 8, y: height-statusHeight-5, width: 556, height: statusHeight)
        var y = height - statusHeight - 83
        for row in rows {
            let hide = hidden.contains { $0 === row.button }
            row.button.isHidden = hide; row.label.isHidden = hide
            if !hide {
                row.button.frame.origin.y = y + 34; row.label.frame.origin.y = y
                y -= 74
            }
        }
        guard view.window != nil else { return }
        let host = SettingsWindow.shared
        if host.pages.last?.view === view, let focused = host.window.firstResponder as? NSView,
           focused.isHiddenOrHasHiddenAncestor {
            host.window.makeFirstResponder(visible.first?.button ?? host.sidebar.table)
        }
        if resized, let current = host.pages.last, current.view === view { host.display(current) }
    }
    func refresh() {
        guard !SettingsWindow.shared.interactionBusy, SettingsWindow.shared.pages.last?.view === view else { return }
        update?()
        arrangeRows(hiding: hiddenRows, footerHeight: footerHeight)
    }
    func show(delegate: AppDelegate? = nil) {
        let host = SettingsWindow.shared
        host.show(.init(title: title, detail: detail, view: view, leave: { [self] in self.timer?.invalidate(); self.timer = nil }, refresh: { [weak self] in self?.refresh() }))
        delegate?.settingsRefresh = { [weak self] in self?.refresh() }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard !host.interactionBusy else { return }
            self?.refresh()
        }
        timer.tolerance = 0.2; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
}

extension AppDelegate {
    @objc func displaySettings() { deskSettings() }
    @objc func scrollingSettings() { openSetupStage("input-access") }
    func setScrollChoice(trackpad: Bool) {
        // Disabling a saved choice remains possible after a permission reset and
        // does not request a grant just to turn that feature off.
        var config = SafetyConfiguration.load()
        let wasEnabled = trackpad ? config.reverseTrackpad : config.reverseWheel
        guard wasEnabled || (HelperStatusIPC.inputClient.value?.fresh == true && HelperStatusIPC.inputClient.value?.trusted == true) else { return }
        if trackpad { config.reverseTrackpad.toggle() } else { config.reverseWheel.toggle() }
        do {
            try config.save()
            inputs.reverseTrackpad = config.reverseTrackpad; inputs.reverseWheel = config.reverseWheel
        } catch { showError(error) }
        settingsRefresh?()
    }

    @objc func keepAwakeSettings() { lidActivity() }
    @objc func appSettings() { presentAppSettings(readRestart: { .current }, restart: { AppUpdate.shared.restartCurrentApp() }) }
    func presentAppSettings(readRestart: @escaping () -> RestartSettingsSnapshot, restart: @escaping () -> Void) {
        let page = SettingsTaskPage(title: "App settings", detail: "Preferences for Perch itself.", height: 260)
        let cpu = page.add("Show top process and Perch CPU usage", detail: "Updates every 10 seconds while the menu is open. Percentages use total CPU capacity.", checkbox: true) {
            let sender = NSButton(); sender.state = CPUDisplaySettings.enabled() ? .off : .on
            self.toggleProcessCPU(sender)
        }
        cpu.identifier = NSUserInterfaceItemIdentifier(CPUDisplaySettings.key)
        let restartButton = page.add("Restart Perch", detail: "Close and reopen Perch, keeping your saved choices. An active lid session keeps its existing timeout.") { [weak page] in restart(); page?.refresh() }
        page.update = { [weak page] in
            cpu.state = CPUDisplaySettings.enabled() ? .on : .off
            let restartState = readRestart()
            restartButton.isEnabled = !restartState.busy
            restartButton.title = restartState.busy ? "Please wait…" : "Restart Perch"
            page?.status.stringValue = !restartState.message.isEmpty ? restartState.message : "Changes save automatically."
        }
        page.show(delegate: self)
    }
    @objc func perchPrivacyResetFromSettings() { openReset(.perchPrivacy) }
}
