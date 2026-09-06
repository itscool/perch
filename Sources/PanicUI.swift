import AppKit
import Carbon
import UniformTypeIdentifiers

extension AppDelegate {
    func setupSafetyMenu() {
        section("Agent Safety")
        safetyItem = add("Panic…", #selector(stopAgents))
        safetyItem.toolTip = "Immediately stop selected agents and their observed children, then keep stopping relaunches until you resume."
        safetyResumeItem = add("Resume agent activity…", #selector(resumeAgents))
    }
    func refreshSafety() {
        let config = SafetyConfiguration.load()
        let issue = ProtectionIssue.assess(GuardianInstall.status, config: config)
        let issueChanged = currentProtectionIssue != issue
        currentProtectionIssue = issue
        if issueChanged && SettingsWindow.shared.window.isVisible && !SettingsWindow.shared.modal && SettingsWindow.shared.pages.last?.title == "Perch settings" { configureSettings() }
        label(safetySettingsItem, "Settings…", hint: issue.map { "⚠ " + $0.title } ?? "")
        if let issue, let title = safetySettingsItem.attributedTitle {
            let colored = NSMutableAttributedString(attributedString: title)
            let range = (colored.string as NSString).range(of: "⚠")
            if range.location != NSNotFound {
                colored.addAttributes([.foregroundColor: issue.severity == .critical ? StatusColors.critical : StatusColors.warning, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)], range: NSRange(location: range.location, length: colored.length-range.location))
            }
            safetySettingsItem.attributedTitle = colored
        }
        safetySettingsItem.toolTip = issue?.detail ?? "Configure input access, agent safety, and maintenance."
        if let issue, issue.severity == .critical {
            if criticalIssueSince == nil { criticalIssueSince = Date() }
            // One in-app notice per critical condition; no extra permission or popup window.
            if notifiedCriticalIssue != issue.title && Date().timeIntervalSince(criticalIssueSince!) >= 10 && !SettingsWindow.shared.modal {
                notifiedCriticalIssue = issue.title
                DispatchQueue.main.async { [weak self] in self?.configureSettings(); SettingsWindow.shared.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
            }
        } else { criticalIssueSince = nil; notifiedCriticalIssue = nil }
        guard let state = GuardianInstall.status, state.fresh else {
            label(safetyItem, "Panic…", hint: "Watcher offline")
            safetyItem.toolTip = safetyError ?? "Watcher offline — repair before relying on panic"
            safetyResumeItem.isHidden = true
            return
        }
        if let result = state.testResultID, result != lastTestResultID {
            lastTestResultID = result
            if awaitingShortcutTest {
                awaitingShortcutTest = false
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Shortcut worked"
                    alert.informativeText = "Perch received your shortcut. No agents were stopped and no permissions were changed. Test mode has ended and your previous shortcut settings have been restored."
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    SettingsWindow.shared.run(alert)
                }
            }
        }
        let shortcut = state.shortcutActive ? "Immediate: " + SafetyConfiguration.load().shortcut.title : "Shortcut off"
        let activity = state.locked ? "Stopping relaunches" : (state.testUntil != nil ? "Test mode" : shortcut)
        let attention = state.error == nil ? "" : " · Needs attention"
        label(safetyItem, "Panic…", hint: "\(state.trackedCount) tracked · \(activity)\(attention)")
        safetyItem.toolTip = state.error ?? (state.testUntil != nil ? state.message : "Immediately stop selected agents and their observed children. \(state.trackedCount) processes currently tracked. Keep stopping relaunches until you resume.")
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
    @objc func settingsChoice(_ sender: NSButton) {
        NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: sender.tag))
    }
    func chooseSafetyAction(title: String, detail: String, options: [(String, String, Selector)]) {
        SettingsWindow.shared.list(title: title, detail: detail, options: options, delegate: self)
    }
    @objc func toggleProcessCPU(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: CPUDisplaySettings.key)
        systemMonitor.processCPU.setActive(menuOpen && sender.state == .on)
    }
    @objc func configureSettings() {
        let health = GuardianInstall.status
        let configuration = SafetyConfiguration.load()
        let inputWanted = configuration.reverseTrackpad || configuration.reverseWheel || configuration.swapModifiers
        let input = InputReadiness.assess(health, config: configuration)
        let inputReady = input.ready
        let issueNow = ProtectionIssue.assess(health, config: configuration)
        var options: [(String,String,Selector)] = [
            (inputReady ? "✓ Input controls…" : (inputWanted ? "⚠ Input controls…" : "Input controls…"), inputReady || inputWanted ? input.message : "Grant Perch Accessibility access when you want to use scrolling or key swapping.", #selector(inputPermissionsFromSettings)),
            (issueNow == nil ? "✓ Agent safety…" : "⚠ Agent safety…", "Choose agents to terminate, test the immediate shortcut, and choose privacy permissions to revoke on panic.", #selector(configurePanic)),
            ("Advanced…", "Recognition catalog and background-helper maintenance, with explanations.", #selector(advancedSafetySettings))]
        let issue = ProtectionIssue.assess(GuardianInstall.status, config: SafetyConfiguration.load())
        if let issue {
            let action: Selector
            switch issue.route {
            case "repair": action = #selector(repairWatcher)
            case "events": action = #selector(processEventSetup)
            case "input": action = #selector(inputPermissionsFromSettings)
            default: action = #selector(configurePanic)
            }
            options.insert(((issue.severity == .critical ? "⛔ " : "⚠ ") + issue.title + "…", issue.detail, action), at: 0)
        }
        chooseSafetyAction(title: "Perch settings", detail: issue.map { $0.title + "\n" + $0.detail } ?? "Permissions Perch needs are under Input controls. Permissions panic revokes are under Agent safety.", options: options)
    }
    @objc func configurePanic() {
        var options: [(String,String,Selector)] = [
            ("Agents, shortcut & panic actions…", "Choose which agents panic terminates, its key combination, and which privacy grants it resets.", #selector(editSafetyConfiguration)),
            (GuardianInstall.status?.eventCoverage == "Process events active" ? "✓ Process event collection…" : "⚠ Process event collection…", GuardianInstall.status?.eventCoverage == "Process events active" ? "Live event collection verified. Review setup and current health." : "Complete setup or review the specific collection problem.", #selector(processEventSetup)),
            ("Preview panic targets…", "Preview the currently tracked processes and recent actions. This does not terminate anything.", #selector(safetyReport)),
            (GuardianInstall.status?.shortcutActive == true ? "✓ Shortcut registered · Test…" : (SafetyConfiguration.load().shortcut.enabled ? "⛔ Shortcut unavailable · Test…" : "Test shortcut…"), "Registration is confirmed separately from testing the physical key combination. This test does not terminate processes or change permissions.", #selector(testPanicShortcut))]
        if !GuardianInstall.alive {
            options.insert(("Repair background protection…", "The helper is not responding. Reinstall and restart it before relying on panic.", #selector(repairWatcher)), at: 0)
        }
        chooseSafetyAction(title: "Safety settings", detail: GuardianInstall.alive ? "✓ Background protection is running." : "⛔ Background protection is unavailable. Repair it below.", options: options)
    }
    @objc func advancedSafetySettings() {
        chooseSafetyAction(title: "Advanced safety settings", detail: "These controls are for occasional setup and recovery.", options: [
            ("Add agent app…", "Include an application missing from the agent selection list.", #selector(addAgentApp)),
            ("Add agent executable…", "Include a command-line agent and its observed children, using its executable path.", #selector(addAgentExecutable)),
            ("Import recognition catalog…", "Load updated agent suggestions from a JSON file. New entries default to checked; existing choices are preserved.", #selector(importAgentCatalog)),
            ("Review recognition updates…", "Review changes to existing agent matching rules before applying them.", #selector(reviewCatalogChanges)),
            ("Protect background helper files…", "Require administrator authorization to replace helper files. This does not prevent disabling protection.", #selector(protectWatcher)),
            ("Stop agents & reset all app permissions…", "Separate immediate action, with confirmation. Includes unrelated apps and Perch; grants may need reapproval.", #selector(broadLockdown))])
    }
    @objc func editSafetyConfiguration() {
        let current = SafetyConfiguration.load()
        var config = AgentCatalog.available()?.suggestions(for: current) ?? current
        let alert = NSAlert()
        alert.messageText = "Agent safety"
        alert.informativeText = "Panic freezes and force-quits selected local agents and their observed children, then blocks relaunches until you resume. Unsaved agent work can be lost.\n\nThe watcher runs separately from Perch. It cannot stop remote jobs, root processes, or children it never observed."
        let targetCount = config.targets.count
        let listHeight = CGFloat(min(targetCount * 27, 162))
        let height = 225 + listHeight
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: height))
        func caption(_ text: String, y: CGFloat) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 465, height: 20)
            view.addSubview(label)
        }
        caption("AGENTS TO STOP · \(targetCount) apps / tools · Scroll for more", y: height - 22)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 196, width: 470, height: listHeight))
        scroll.hasVerticalScroller = targetCount * 27 > 162
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        let targetList = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: CGFloat(targetCount * 27)))
        scroll.documentView = targetList
        view.addSubview(scroll)
        var boxes: [NSButton] = []
        for (index, target) in config.targets.enumerated() {
            let box = NSButton(checkboxWithTitle: target.name, target: nil, action: nil)
            box.frame = NSRect(x: 0, y: CGFloat((targetCount - index - 1) * 27), width: 448, height: 24)
            box.state = target.enabled ? .on : .off
            targetList.addSubview(box)
            boxes.append(box)
        }
        caption("EMERGENCY SHORTCUT", y: 174)
        let enabled = NSButton(checkboxWithTitle: "Enable shortcut — fires immediately, without confirmation", target: nil, action: nil)
        enabled.frame = NSRect(x: 0, y: 146, width: 465, height: 24)
        enabled.state = config.shortcut.enabled ? .on : .off
        view.addSubview(enabled)
        var modifiers: [(NSButton, UInt32)] = []
        for (index, pair) in [("Control",controlKey),("Option",optionKey),("Shift",shiftKey),("Command",cmdKey)].enumerated() {
            let box = NSButton(checkboxWithTitle: pair.0, target: nil, action: nil)
            box.frame = NSRect(x: index * 115, y: 114, width: 112, height: 24)
            box.state = config.shortcut.modifiers & UInt32(pair.1) != 0 ? .on : .off
            view.addSubview(box)
            modifiers.append((box, UInt32(pair.1)))
        }
        let keys = NSPopUpButton(frame: NSRect(x: 0, y: 75, width: 160, height: 28), pullsDown: false)
        keys.addItems(withTitles: PanicShortcut.keys.map(\.0))
        keys.selectItem(at: PanicShortcut.keys.firstIndex { $0.1 == config.shortcut.key } ?? 0)
        view.addSubview(keys)
        let reset = NSPopUpButton(frame: NSRect(x: 0, y: 28, width: 465, height: 28), pullsDown: false)
        reset.addItems(withTitles: ["Privacy reset: None", "Privacy reset: Selected agent apps", "Privacy reset: All apps, including Perch"])
        reset.selectItem(at: config.resetAgentPermissions ? (config.resetAllPermissions == true ? 2 : 1) : 0)
        reset.toolTip = "All apps requests a broad macOS privacy reset after stopping agents. You will need to grant permissions again; some protected or managed grants may remain."
        view.addSubview(reset)
        alert.accessoryView = view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard SettingsWindow.shared.run(alert) == .alertFirstButtonReturn else { return }
        let mask = modifiers.filter { $0.0.state == .on }.reduce(UInt32(0)) { $0 | $1.1 }
        guard mask.nonzeroBitCount >= 2 else { showError(AppError(message: "Choose at least two shortcut modifiers.")); return }
        for index in boxes.indices { config.targets[index].enabled = boxes[index].state == .on }
        guard config.targets.contains(where: \.enabled) else { showError(AppError(message: "Select at least one agent.")); return }
        config.shortcut = PanicShortcut(key: PanicShortcut.keys[keys.indexOfSelectedItem].1, modifiers: mask, enabled: enabled.state == .on)
        config.resetAgentPermissions = reset.indexOfSelectedItem != 0
        config.resetAllPermissions = reset.indexOfSelectedItem == 2
        do { try config.save(); SettingsWindow.shared.feedback = "✓ Settings saved." } catch { showError(error) }
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
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 2101))
            } else if state?.fresh != true {
                outcome = "Background protection stopped responding"
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 2102))
            } else if deadline.map({ Date() >= $0 }) ?? (Date().timeIntervalSince(preparationStarted) >= 5) {
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 2102))
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
            result.addButton(withTitle: "Back to Safety settings")
            SettingsWindow.shared.run(result)
        }
        do {
            try send("finish-test")
            let cleanup = NSAlert()
            cleanup.messageText = "Ending shortcut test…"
            cleanup.informativeText = "Waiting for background protection to restore your shortcut settings."
            let expires = Date().addingTimeInterval(5)
            var restored = false
            let poll = Timer(timeInterval: 0.1, repeats: true) { _ in
                if let state = readStatus(), state.fresh, state.testUntil == nil {
                    restored = true
                    NSApp.stopModal()
                } else if Date() >= expires { NSApp.stopModal() }
            }
            RunLoop.main.add(poll, forMode: .modalPanel)
            SettingsWindow.shared.run(cleanup)
            poll.invalidate()
            if !restored { showError(AppError(message: "Could not confirm test cleanup. Background protection may be unavailable; repair it in Safety settings before relying on the shortcut.")) }
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
        alert.addButton(withTitle: "Reset All")
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
        SettingsWindow.shared.show(.init(title: "Preview panic targets", detail: "A read-only preview of processes panic would attempt to terminate. Use Back to return to Agent safety.", view: scroll, leave: { poll?.invalidate(); poll = nil }))
    }
    @objc func repairWatcher() {
        do { try GuardianInstall.install(); safetyError = nil } catch { safetyError = error.localizedDescription; showError(error) }
    }
    @objc func protectWatcher() {
        let alert = NSAlert()
        alert.messageText = "Protect the watcher executable"
        alert.informativeText = "Install an administrator-owned copy so ordinary agent commands cannot overwrite the watcher binary. macOS will ask for your password.\n\nThe watcher still runs as your user. Another process with your account’s access can stop or disable it; this is extra protection against accidental changes, not isolation from a hostile agent."
        alert.addButton(withTitle: "Install Protected Copy")
        alert.addButton(withTitle: "Cancel")
        if SettingsWindow.shared.run(alert) == .alertFirstButtonReturn {
            do { try GuardianInstall.protectExecutable() } catch { showError(error) }
        }
    }
}
