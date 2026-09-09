import AppKit
import Carbon
import UniformTypeIdentifiers

extension AppDelegate {
    func setupSafetyMenu() {
        section("Agent Kill Switch")
        safetyItem = add("Panic…", #selector(stopAgents))
        safetyItem.menuHelp = "Immediately stop selected agents and their observed children, then keep stopping relaunches until you resume."
        _ = add("Reset all apps’ privacy permissions…", #selector(globalPrivacyReset))
        safetyResumeItem = add("Resume agent activity…", #selector(resumeAgents))
    }
    func refreshSafety(status: SafetyStatus? = GuardianInstall.status, config: SafetyConfiguration = SafetyConfiguration.load(), checking: Bool? = nil) {
        let checking = checking ?? (status == nil && HelperStatusIPC.guardianClient.initiallyChecking)
        (safetyItem?.view as? MenuRowView)?.shortcutHint = config.shortcut.enabled ? config.shortcut.menuTitle : ""
        let issue = checking ? nil : ProtectionIssue.assess(status, config: config)
        let issueChanged = currentProtectionIssue != issue
        currentProtectionIssue = issue
        if issueChanged && SettingsWindow.shared.window.isVisible && !SettingsWindow.shared.modal && SettingsWindow.shared.pages.last?.title == "Perch settings" { configureSettings() }
        label(safetySettingsItem, "Settings…", hint: issue.map { $0.severity == .critical ? "⚠ Repair needed" : "⚠ Review setup" } ?? keyboardModes.attentionHint, hintColor: keyboardModes.warning && issue == nil ? StatusColors.warning : .secondaryLabelColor)
        if let issue, let title = menuTitleSources[safetySettingsItem] {
            let colored = NSMutableAttributedString(attributedString: title)
            let range = (colored.string as NSString).range(of: "⚠")
            if range.location != NSNotFound {
                colored.addAttributes([.foregroundColor: issue.severity == .critical ? StatusColors.critical : StatusColors.warning, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)], range: NSRange(location: range.location, length: colored.length-range.location))
            }
            setMenuTitle(safetySettingsItem, colored)
        }
        safetySettingsItem.menuHelp = issue?.detail ?? (keyboardModes.warning ? keyboardModes.attentionDetail : "Configure input access, Agent Kill Switch, and maintenance.")
        if let issue, issue.severity == .critical {
            if criticalIssueSince == nil { criticalIssueSince = Date() }
            // One in-app notice per critical condition; no extra permission or popup window.
            if notifiedCriticalIssue != issue.title && Date().timeIntervalSince(criticalIssueSince!) >= 10 && !SettingsWindow.shared.interactionBusy && !SettingsWindow.shared.testing && !SettingsWindow.shared.window.isVisible {
                notifiedCriticalIssue = issue.title
                DispatchQueue.main.async { [weak self] in
                    guard !SettingsWindow.shared.interactionBusy, !SettingsWindow.shared.window.isVisible,
                          self?.currentProtectionIssue?.title == issue.title else { self?.notifiedCriticalIssue = nil; return }
                    self?.configureSettings(); self?.setupOverview(); SettingsWindow.shared.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                }
            }
        } else { criticalIssueSince = nil; notifiedCriticalIssue = nil }
        guard let state = status, state.fresh else {
            label(safetyItem, "Panic…", hint: checking ? "Checking watcher…" : "Watcher offline")
            safetyItem.menuHelp = checking ? "Waiting for the watcher’s first status reply." : safetyError ?? "Watcher offline — repair before relying on panic"
            safetyResumeItem.isHidden = !checking
            safetyResumeItem.isEnabled = !checking
            label(safetyResumeItem, "Resume agent activity…", hint: checking ? "Checking watcher…" : "")
            return
        }
        if let result = state.testResultID, result != lastTestResultID {
            lastTestResultID = result
            if awaitingShortcutTest {
                awaitingShortcutTest = false
                DispatchQueue.main.async {
                    SettingsWindow.shared.afterInteraction {
                        let alert = NSAlert()
                        alert.messageText = "Shortcut worked"
                        alert.informativeText = "Perch received your shortcut. No agents were stopped and no permissions were changed. Test mode has ended and your previous shortcut settings have been restored."
                        alert.addButton(withTitle: "OK")
                        NSApp.activate(ignoringOtherApps: true)
                        SettingsWindow.shared.run(alert)
                    }
                }
            }
        }
        let shortcut = state.shortcutActive ? "Immediate Kill" : config.shortcut.enabled ? "Shortcut unavailable" : "Shortcut off"
        let activity = state.locked ? "Stopping relaunches" : (state.testUntil != nil ? "Test mode" : shortcut)
        let attention = state.error == nil ? "" : " · Needs attention"
        label(safetyItem, "Panic…", hint: "\(state.trackedCount) tracked\u{2003}\u{2003}\(activity)\(attention)")
        safetyItem.menuHelp = state.error ?? (state.testUntil != nil ? state.message : "Immediately stop selected agents and their observed children. \(state.trackedCount) processes currently tracked. Keep stopping relaunches until you resume.")
        safetyResumeItem.isEnabled = true
        label(safetyResumeItem, "Resume agent activity…")
        safetyResumeItem.isHidden = !state.locked && state.pendingLaunchJobs == 0
    }
    func safetyRequest(_ action: String) {
        guard GuardianInstall.alive else {
            showError(AppError(message: "The watcher is not responding. Use Repair watcher before relying on the emergency stop."))
            return
        }
        do { try SafetyFiles.send(action) } catch { showError(error) }
    }
    @objc func stopAgents() {
        menu.cancelTracking()
        let config = SafetyConfiguration.load()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Terminate selected agents now?"
        var detail = "Perch will freeze and force-terminate selected agents and their observed child processes, then keep blocking relaunches until you resume. Unsaved work may be lost."
        if config.resetAgentPermissions {
            detail += config.resetAllPermissions == true
                ? "\n\nThis will also reset privacy permissions for all apps, including Perch. Apps may ask for permission again."
                : "\n\nThis will also reset privacy permissions for the selected agent apps. Apps may ask for permission again."
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Terminate agents")
        guard SettingsWindow.shared.run(alert) == .alertSecondButtonReturn else { return }
        safetyRequest("stop")
    }
    @objc func resumeAgents() {
        let alert = NSAlert()
        alert.messageText = "Allow agents to run again?"
        alert.informativeText = "Perch will stop blocking their relaunch. It won’t reopen apps or restore privacy permissions. Reopen only the agents you want to use."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Resume")
        if SettingsWindow.shared.run(alert) == .alertSecondButtonReturn { safetyRequest("resume") }
    }
    func chooseSafetyAction(title: String, detail: String, options: [(String, String, Selector)]) {
        SettingsWindow.shared.list(title: title, detail: detail, options: options, delegate: self)
    }
    @objc func toggleProcessCPU(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: CPUDisplaySettings.key)
        systemMonitor.processCPU.setActive(menuOpen && sender.state == .on)
    }
    @objc func configureSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.configureSettings() }; return }
        chooseSafetyAction(title: "Perch settings", detail: "Choose what you want to use or change. Setup & status brings missing steps and recovery together.", options: [
            ("Setup & status…", setupSnapshot().summary + ". Start here on first use or when something stops working.", #selector(setupOverview)),
            ("Displays…", "Turn a display off or set up input switching between computers.", #selector(displaySettings)),
            ("Keyboards…", "Function keys, Control/Command swaps and external navigation keys.", #selector(keyboardSettings)),
            ("Scrolling…", "Choose the vertical scroll direction for your trackpad and mouse wheel.", #selector(scrollingSettings)),
            ("Keep awake…", "Review sleep behavior and choose whether to keep the Mac working.", #selector(keepAwakeSettings)),
            ("Agent Kill Switch…", "Choose agents, emergency actions and a shortcut; preview or test protection.", #selector(configurePanic)),
            ("App settings…", "Start at login, menu CPU information, maintenance and Perch preferences.", #selector(appSettings))])
    }

    @objc func configurePanic() {
        var options: [(String,String,Selector)] = [
            ("Agents, shortcut & panic actions…", "Choose which agents panic terminates, its key combination, and which privacy grants it resets.", #selector(editSafetyConfiguration)),
            ("Add or remove agents…", "Add a missing app or executable, or forget one custom entry without resetting the others.", #selector(manageAgents)),
            ("Agent recognition…", "Import definitions and review changes to how agents are identified.", #selector(agentRecognition)),
            (GuardianInstall.status?.eventCoverage == "Process events active" ? "✓ Process event collection…" : "⚠ Process event collection…", GuardianInstall.status?.eventCoverage == "Process events active" ? "Live event collection verified. Review setup and current health." : "Complete setup or review the specific collection problem.", #selector(processEventSetup)),
            ("Preview panic targets…", "Preview the currently tracked processes and recent actions. This does not terminate anything.", #selector(safetyReport)),
            (GuardianInstall.status?.shortcutActive == true ? "✓ Shortcut registered · Test…" : (SafetyConfiguration.load().shortcut.enabled ? "⛔ Shortcut unavailable · Test…" : "Test shortcut…"), "Registration is confirmed separately from testing the physical key combination. This test does not terminate processes or change permissions.", #selector(testPanicShortcut)),
            ("Stop agents & reset all app permissions…", "Emergency action with confirmation: stops selected agents and resets system privacy permissions, including unrelated apps.", #selector(broadLockdown))]
        if !GuardianInstall.alive {
            options.insert(("Repair background protection…", "The helper is not responding. Reinstall and restart it before relying on panic.", #selector(repairWatcher)), at: 0)
        }
        chooseSafetyAction(title: "Agent Kill Switch", detail: GuardianInstall.alive ? "✓ Background protection is running." : "⛔ Background protection is unavailable. Repair it below.", options: options)
    }
    @objc func advancedSafetySettings() {
        let issue = ProtectionIssue.assess(GuardianInstall.status, config: SafetyConfiguration.load())
        let problem = issue.flatMap { $0.route == "repair" ? $0.detail + "\n\n" : nil } ?? ""
        chooseSafetyAction(title: "Maintenance", detail: problem + "Repair or protect Perch’s background helpers. Your feature choices are retained when repairing. These actions explain any administrator approval before making changes.", options: [
            ("Repair background helpers…", "Install the current Perch build and restart its helpers. Existing feature choices are retained.", #selector(repairWatcher)),
            ("Protect background helper files…", "Require administrator authorization to replace helper files. This does not prevent disabling protection.", #selector(protectWatcher)),
            ("Reset Perch’s privacy permissions…", "Only for repairing Perch’s grants. Review the scope before resetting; existing choices are kept.", #selector(perchPrivacyResetFromSettings))])
    }
    @objc func agentRecognition() {
        chooseSafetyAction(title: "Agent recognition", detail: "Review the scope of new or changed matching rules before applying them.", options: [
            ("Import recognition catalog…", "Load updated agent suggestions from a JSON file. New entries default to checked; existing choices are preserved.", #selector(importAgentCatalog)),
            ("Review recognition updates…", "Review changes to existing agent matching rules before applying them.", #selector(reviewCatalogChanges))])
    }
    @objc func manageAgents() {
        let targets = SafetyConfiguration.load().targets.filter { $0.id.hasPrefix("custom-") }
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: max(180, 90 + targets.count * 60)))
        let addApp = SettingsActionButton(title: "Add app…") { [weak self] in self?.addAgentApp(); self?.manageAgents() }
        let addExecutable = SettingsActionButton(title: "Add executable…") { [weak self] in self?.addAgentExecutable(); self?.manageAgents() }
        addApp.frame = NSRect(x: 0, y: view.frame.height-32, width: 278, height: 32)
        addExecutable.frame = NSRect(x: 288, y: view.frame.height-32, width: 284, height: 32)
        view.addSubview(addApp); view.addSubview(addExecutable)
        for (index, target) in targets.enumerated() {
            let y = view.frame.height - CGFloat(92 + index*60)
            let label = NSTextField(wrappingLabelWithString: target.name + "\n" + target.match)
            label.frame = NSRect(x: 0, y: y, width: 410, height: 48); label.font = .systemFont(ofSize: 12)
            let remove = SettingsActionButton(title: "Forget entry") { [weak self] in
                do {
                    var config = SafetyConfiguration.load()
                    config.targets.removeAll { $0.id == target.id }
                    try config.save(); self?.manageAgents()
                } catch { self?.showError(error) }
            }
            remove.frame = NSRect(x: 428, y: y+8, width: 144, height: 30)
            view.addSubview(label); view.addSubview(remove)
        }
        SettingsWindow.shared.show(.init(title: "Add or remove agents", detail: "Custom entries are listed below. Forget entry removes only its Perch configuration; the app remains installed and running. Built-in agents can be unchecked in Agents, shortcut & panic actions.", view: view))
    }
    @objc func editSafetyConfiguration() {
        editSafetyForm(save: { try $0.save() })
    }
    @discardableResult
    func editSafetyForm(save: @escaping (SafetyConfiguration) throws -> Void) -> AgentSettingsPage {
        let page = AgentSettingsPage(save: save, conflicts: { [weak self] shortcut in
            guard let self else { return false }
            return [self.monitorInputs.plan.shortcut, self.monitorInputs.groups.active?.shortcut].compactMap { $0 }.contains { $0.enabled && $0.key == shortcut.key && $0.modifiers == shortcut.modifiers }
        }, didSave: { [weak self] in
            if self?.safetyItem != nil { self?.refreshSafety() }
        })
        page.show()
        return page
    }
    @objc func addAgentApp() { addTarget(app: true) }
    @objc func addAgentExecutable() { addTarget(app: false) }
    func addTarget(app: Bool) {
        let panel = NSOpenPanel()
        panel.title = app ? "Choose an agent app" : "Choose an agent executable"
        panel.message = app ? "Perch will include this app and its observed child processes." : "Choose the agent itself, not a general-purpose shell, node, or Python runtime."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if app { panel.allowedContentTypes = [.applicationBundle] }
        guard SettingsWindow.shared.open(panel) == .OK, let url = panel.url else { return }
        var config = SafetyConfiguration.load()
        let target: AgentTarget
        if app {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != "local.scott.perch" else { showError(AppError(message: "Choose another application with a bundle identifier.")); return }
            target = AgentTarget(id: "custom-app:\(id)", name: url.deletingPathExtension().lastPathComponent, kind: "app", match: id)
        } else {
            let path = url.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: path.path), !["sh", "bash", "zsh", "fish", "node", "python", "python3", "bun", "Perch", "PerchGuard"].contains(path.lastPathComponent) else { showError(AppError(message: "Choose a specific agent executable, not a shared runtime or Perch.")); return }
            target = AgentTarget(id: "custom-exec:\(path.path)", name: path.lastPathComponent, kind: "executable", match: path.path)
        }
        if !config.targets.contains(where: { $0.id == target.id }) { config.targets.append(target) }
        do { try config.save(); SettingsWindow.shared.feedback = "✓ Settings saved." } catch { showError(error) }
    }
    @objc func testPanicShortcut() {
        runShortcutTest(readStatus: { GuardianInstall.status }, send: { try SafetyFiles.send($0) }, keepAlive: {
            try SafetyFiles.write(Date(), to: SafetyFiles.base.appendingPathComponent("shortcut-test-lease.json"))
        })
    }
    // Explicit dependencies let release tests exercise the dialog without arming the real helper.
    func runShortcutTest(readStatus: @escaping () -> SafetyStatus?, send: (String) throws -> Void, keepAlive: @escaping () throws -> Void) {
        guard !SettingsWindow.shared.interactionBusy else { return }
        guard readStatus()?.fresh == true else { showError(AppError(message: "Background protection is unavailable. Repair it before testing.")); return }
        let previousResult = readStatus()?.testResultID
        let shortcut = SafetyConfiguration.load().shortcut.title
        do { try keepAlive(); try send("test") } catch { showError(error); return }
        let heartbeat = Timer(timeInterval: 1, repeats: true) { _ in try? keepAlive() }
        RunLoop.main.add(heartbeat, forMode: .common)
        RunLoop.main.add(heartbeat, forMode: .modalPanel)
        defer { heartbeat.invalidate() }
        let alert = NSAlert()
        alert.messageText = "Test shortcut"
        alert.informativeText = "Preparing harmless test… Wait before pressing the shortcut."
        alert.addButton(withTitle: "Cancel")
        let countdown = NSTextField(labelWithString: "10 seconds remaining")
        countdown.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
        alert.accessoryView = countdown
        let preparationStarted = Date()
        var deadline: Date?
        var outcome = "No shortcut received"
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            let state = readStatus()
            if deadline == nil, let until = state?.testUntil, until > preparationStarted, state?.fresh == true {
                deadline = Date().addingTimeInterval(10)
            }
            countdown.stringValue = deadline.map { "\(max(0, Int(ceil($0.timeIntervalSinceNow)))) seconds remaining" } ?? "Preparing — don’t press yet"
            if let result = state?.testResultID, result != previousResult {
                outcome = "Shortcut worked"
                SettingsWindow.shared.finish(alert, response: NSApplication.ModalResponse(rawValue: 2101))
            } else if state?.fresh != true {
                outcome = "Background protection stopped responding"
                SettingsWindow.shared.finish(alert, response: NSApplication.ModalResponse(rawValue: 2102))
            } else if deadline.map({ Date() >= $0 }) ?? (Date().timeIntervalSince(preparationStarted) >= 5) {
                SettingsWindow.shared.finish(alert, response: NSApplication.ModalResponse(rawValue: 2102))
            } else if deadline != nil {
                alert.informativeText = "Press \(shortcut). This test will not terminate processes or reset permissions."
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let response = SettingsWindow.shared.run(alert)
        timer.invalidate()
        if response != .alertFirstButtonReturn {
            let result = NSAlert()
            result.messageText = outcome
            result.informativeText = outcome == "Shortcut worked"
                ? "Perch received the combination. The shortcut is still harmless. Returning to settings ends the test and restores your configured shortcut."
                : "The test did not succeed. Check the combination and try again. Returning to settings ends the test."
            result.addButton(withTitle: "Back")
            SettingsWindow.shared.run(result)
        }
        do {
            try send("finish-test")
            let cleanup = NSAlert()
            cleanup.messageText = "Ending shortcut test…"
            cleanup.informativeText = "Waiting for background protection to restore your shortcut settings."
            cleanup.addButton(withTitle: "Waiting…").isEnabled = false
            let expires = Date().addingTimeInterval(5)
            var restored = false
            let poll = Timer(timeInterval: 0.1, repeats: true) { _ in
                if let state = readStatus(), state.fresh, state.testUntil == nil {
                    restored = true
                    SettingsWindow.shared.finish(cleanup)
                } else if Date() >= expires { SettingsWindow.shared.finish(cleanup) }
            }
            RunLoop.main.add(poll, forMode: .modalPanel)
            SettingsWindow.shared.run(cleanup, allowsCancel: false)
            poll.invalidate()
            if !restored { showError(AppError(message: "Could not confirm test cleanup. Background protection may be unavailable; repair it in Agent Kill Switch before relying on the shortcut.")) }
        } catch { showError(error) }
        heartbeat.invalidate()
    }
    @objc func finishPanicTest() { safetyRequest("finish-test") }
    @objc func broadLockdown() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Stop agents and reset all app privacy permissions?"
        alert.informativeText = "This also resets permissions for unrelated apps and Perch. Apps may ask for access again. It does not remove administrator rights, stop remote jobs, or cover every security setting. Agent relaunch blocking remains active."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Stop agents & reset permissions")
        if SettingsWindow.shared.run(alert) == .alertSecondButtonReturn { safetyRequest("lockdown") }
    }
    @objc func safetyReport() {
        let started = Date()
        safetyRequest("preview")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.string = "Preparing a fresh preview… No processes will be terminated."
        scroll.documentView = text
        var poll: Timer?
        poll = Timer(timeInterval: 0.25, repeats: true) { _ in
            let modified = (try? FileManager.default.attributesOfItem(atPath: SafetyFiles.report.path)[.modificationDate]) as? Date
            if let modified, modified >= started, let report = try? String(contentsOf: SafetyFiles.report, encoding: .utf8) { text.string = report; poll?.invalidate() }
            else if Date().timeIntervalSince(started) > 5 { text.string = "The background helper did not return a preview. Check protection status in Settings."; poll?.invalidate() }
        }
        if let poll { RunLoop.main.add(poll, forMode: .common) }
        SettingsWindow.shared.show(.init(title: "Preview panic targets", detail: "A read-only preview of processes panic would attempt to terminate. Use Back to return to Agent Kill Switch.", view: scroll, leave: { poll?.invalidate(); poll = nil }))
    }
    @objc func repairWatcher() {
        do {
            try GuardianInstall.install(); safetyError = nil
            let result = NSAlert(); result.messageText = "Helper installation finished"
            result.informativeText = "Perch’s current helper files and launch jobs are installed. Setup & status will check that the helpers respond and show any access still needed. Your feature choices are retained."
            result.addButton(withTitle: "Check setup & status")
            result.addButton(withTitle: "Back")
            if SettingsWindow.shared.run(result) == .alertFirstButtonReturn { setupOverview() }
        } catch { safetyError = error.localizedDescription; showError(error) }
    }
    @objc func protectWatcher() {
        let alert = NSAlert()
        alert.messageText = "Protect the watcher executable"
        alert.informativeText = "Install an administrator-owned copy so ordinary agent commands cannot overwrite the watcher binary. macOS will ask for your password.\n\nThe watcher still runs as your user. Another process with your account’s access can stop or disable it; this is extra protection against accidental changes, not isolation from a hostile agent."
        alert.addButton(withTitle: "Install Protected Copy")
        alert.addButton(withTitle: "Cancel")
        if SettingsWindow.shared.run(alert) == .alertFirstButtonReturn {
            do {
                try GuardianInstall.protectExecutable()
                let result = NSAlert(); result.messageText = "Helper files protected"
                result.informativeText = "The administrator-owned copy was installed and the background helpers restarted. Their status is checked in Settings."
                SettingsWindow.shared.run(result)
            } catch { showError(error) }
        }
    }
}
