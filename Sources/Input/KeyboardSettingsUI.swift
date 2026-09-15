import AppKit
import IOKit.hidsystem

extension AppDelegate {
    func refreshModifierItems() {
        guard swapItem != nil else { return }
        for (item, builtIn) in [(swapItem!, true), (externalSwapItem!, false)] {
            let devices = nativeKeyboards.filter { $0.builtIn == builtIn }
            let modes = devices.map { $0.swapped }
            if devices.isEmpty { item.state = UserDefaults.standard.bool(forKey: NativeModifierKeys.intentKey(builtIn)) ? .on : .off }
            else if modes.allSatisfy({ $0 == true }) { item.state = .on }
            else if modes.allSatisfy({ $0 == false }) { item.state = .off }
            else { item.state = .mixed }
            label(item, "Swap Control ↔ Command keys")
            let context = devices.isEmpty ? "No keyboard in this group is connected. Your saved choice is kept." : item.state == .mixed ? "Connected keyboards have different or custom mappings. Review Settings → Keyboards for details." : nil
            item.menuHelp = ControlHelp.adding(context, to: builtIn ? ControlHelp.builtInModifiers : ControlHelp.externalModifiers)
        }
    }
    func refreshFunctionKeyItem(_ standard: Bool) {
        fnItem.state = standard ? .on : .off
        label(fnItem, "Use F1–F12 directly", hint: standard ? "Without Fn" : "Hold Fn")
        fnItem.menuHelp = ControlHelp.adding(keyboardModes.blocksFunctionKeyChanges ? "Checking keyboard settings before changes are available." : !nativeKeyboards.contains(where: { $0.builtIn }) ? "No built-in keyboard is connected." : nil, to: ControlHelp.builtInFn)
        fnItem.isEnabled = !keyboardModes.blocksFunctionKeyChanges && nativeKeyboards.contains { $0.builtIn }
        refreshExternalFunctionKeyItem()
    }
    func refreshExternalFunctionKeyItem() {
        guard let item = externalFnItem else { return }
        let results = keyboardModes.results
        let modes = Set(results.compactMap { $0.standard })
        item.state = modes.count > 1 || (modes.isEmpty && !results.isEmpty) ? .mixed : modes.first == true ? .on : .off
        let failed = results.filter { !$0.verified }
        let hint: String
        if keyboardModes.blocksFunctionKeyChanges { hint = "Checking keyboards…"; item.state = .mixed }
        else if keyboardModes.needsAccess { hint = "Input Monitoring unavailable" }
        else if !failed.isEmpty { hint = "⚠ \(failed.count) need setup · see Settings" }
        else if modes.count > 1 { hint = "Mixed modes" }
        else if let mode = modes.first { hint = mode ? "Without Fn" : "Hold Fn" }
        else { hint = "No keyboard" }
        label(item, "Use F1–F12 directly", hint: hint, hintColor: failed.isEmpty ? .secondaryLabelColor : StatusColors.warning)
        item.isEnabled = !keyboardModes.blocksFunctionKeyChanges && (!modes.isEmpty || !failed.isEmpty)
        item.action = failed.isEmpty ? #selector(toggleExternalFunctionKeys) : #selector(keyboardDetails)
        (item.view as? MenuRowView)?.opensAnotherInterface = { !failed.isEmpty }
        let context = keyboardModes.blocksFunctionKeyChanges ? "Checking keyboard settings before changes are available." : keyboardModes.needsAccess ? "Input Monitoring is unavailable in this launch. Open Setup → Keyboard access for the already-enabled recovery steps." : !failed.isEmpty ? "Select to review the keyboards that need setup. This opens details instead of changing their mode." : modes.count > 1 ? "Connected keyboards currently use different modes. Turning this on applies it to all supported external keyboards." : results.isEmpty ? "Connect a supported external keyboard to use this control." : nil
        item.menuHelp = ControlHelp.adding(context, to: ControlHelp.externalFn)
    }
    @objc func toggleExternalFunctionKeys() {
        let desired = externalFnItem.state != .on
        UserDefaults.standard.set(desired, forKey: NativeFunctionKeys.externalIntentKey)
        keyboardModes.queue(reapplyExternal: true)
    }
    func keyboardStatusChanged() {
        considerKeyboardAccessNotice()
        synchronizeNavigationProfiles()
        nativeKeyboards = NativeModifierKeys.keyboards()
        refreshModifierItems()
        if let standard = try? FunctionKeys.standard(), fnItem != nil { refreshFunctionKeyItem(standard) }
        refreshKeyboardAttention()
        let host = SettingsWindow.shared
        if host.window.isVisible && !host.modal {
            if host.pages.last?.title == "Keyboards" { keyboardSettings() }
            else if host.pages.last?.title == "Perch settings" { configureSettings() }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--keyboard-diagnostics"), CommandLine.arguments.count > index+1 {
            let output: [String:Any] = ["busy":keyboardModes.working, "registration":keyboardModes.registrations.map { ["name":$0.name,"needsSetup":$0.needsSetup,"detail":$0.detail] as [String:Any] }, "registrationError":keyboardModes.registrationError as Any? ?? NSNull(), "functionKeys":keyboardModes.results.map { ["name":$0.name,"detail":$0.detail,"verified":$0.verified,"needsAccess":$0.needsAccess,"standard":$0.standard as Any? ?? NSNull()] as [String:Any] }, "modifiers":nativeKeyboards.map { ["name":$0.name,"builtIn":$0.builtIn,"swapped":$0.swapped as Any? ?? NSNull()] }, "errors":keyboardModes.modifierErrors]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]), options: .atomic) }
        }
    }
    func setModifierGroup(_ builtIn: Bool) {
        nativeKeyboards = NativeModifierKeys.keyboards(); refreshModifierItems()
        let desired = (builtIn ? swapItem : externalSwapItem)?.state != .on
        let failures = NativeModifierKeys.applyGroup(desired, builtIn: builtIn)
        if failures.isEmpty { UserDefaults.standard.set(desired, forKey: NativeModifierKeys.intentKey(builtIn)) }
        keyboardModes.modifierErrors = failures
        keyboardStatusChanged()
        if !failures.isEmpty { withMenuClosed { [weak self] in self?.keyboardSettings() } }
    }
    @objc func toggleExternalModifiers() { setModifierGroup(false) }
    func refreshKeyboardAttention() {
        refreshNavigationItems()
        if let item = keyboardSetupItem {
            item.isHidden = !keyboardModes.registrationNeedsSetup
            label(item, "Set up keyboard…", hint: "⚠ Review navigation keys", hintColor: StatusColors.warning)
            item.menuHelp = ControlHelp.adding(keyboardModes.attentionDetail, to: ControlHelp.keyboardSetup)
        }
        refreshExternalKeyboardSection()
        if currentProtectionIssue == nil, let item = safetySettingsItem {
            label(item, "Settings…", hint: keyboardModes.attentionHint, hintColor: StatusColors.warning)
            item.menuHelp = ControlHelp.adding(keyboardModes.warning ? keyboardModes.attentionDetail : nil, to: ControlHelp.settings)
        }
    }
    func refreshExternalKeyboardSection() {
        guard let heading = externalKeyboardSection else { return }
        let registrations = keyboardModes.registrations
        let names = registrations.isEmpty ? nativeKeyboards.filter { !$0.builtIn }.map { $0.name } : registrations.map { $0.name }
        let unknown = keyboardModes.registrationNeedsSetup
        let title = keyboardModes.registrationPending ? "External keyboards · Checking…" : names.count > 1 ? "External keyboards · \(names.count) keyboards" : "External keyboard · " + (names.first ?? (unknown ? "Detection unavailable" : "None connected"))
        if heading.title != title { heading.title = title }
        (heading.view as? MenuRowView)?.text = NSAttributedString(string:title, attributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.secondaryLabelColor])
        let hideControls = names.isEmpty
        if externalSwapItem.isHidden != hideControls { externalSwapItem.isHidden = hideControls }
        if externalFnItem.isHidden != hideControls { externalFnItem.isHidden = hideControls }
        keypadItem?.isHidden = hideControls
        refreshKeypadNavigation()
        let profiles = registrations.compactMap { $0.profile }
        homeEndItem.isHidden = hideControls || !profiles.contains { $0.hasHomeEnd }
        pageKeysItem.isHidden = hideControls || !profiles.contains { $0.hasPageKeys }
        keyboardSetupItem.isHidden = !unknown
    }
    @objc func keyboardSettings() { keyboardSettingsView() }
    func openKeyboardPreferences(permission: Bool) {
        if permission { keyboardAccessRecovery(); return }
        SettingsWindow.shared.openSystemSettings(.keyboard)
    }
    @objc func keyboardDetails() { keyboardSettings() }
    func keyboardSettingsView() {
        if menuOpen { withMenuClosed { [weak self] in self?.keyboardSettingsView() }; return }
        nativeKeyboards = NativeModifierKeys.keyboards()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 145, width: 556, height: 325))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder
        let registration = keyboardModes.registrations.map { KeyboardModeResult(name: $0.name + " · Recognition", detail: $0.detail, verified: !$0.needsSetup) }
        let errors = keyboardModes.registrationError.map { [KeyboardModeResult(name: "Keyboard registration", detail: "⚠ " + $0, verified: false)] } ?? []
        var navigationStatus: [KeyboardModeResult] = []
        if SafetyConfiguration.load().navigation?.enabled == true {
            let input = HelperStatusIPC.inputClient.value
            let verified = input?.fresh == true && input?.active == true && input?.navigationObserved == true && input?.navigationUnidentified != true
            let message = input?.navigationUnidentified == true ? "⚠ macOS did not identify the source keyboard. Those keys keep their native behavior." : verified ? "✓ External navigation events received and identified." : "Navigation is ready to check when you use an external key."
            navigationStatus = [.init(name:"Navigation",detail:message,verified:verified)]
        }
        let entries = errors + registration + navigationStatus + keyboardModes.results.filter { !$0.verified } + keyboardModes.modifierErrors.map { KeyboardModeResult(name: "Modifier keys", detail: "⚠ " + $0, verified: false) }
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 530,height: max(scroll.contentSize.height,CGFloat(entries.count*70))))
        for (index, entry) in entries.enumerated() {
            let label = NSTextField(wrappingLabelWithString: entry.name + "\n" + entry.detail)
            label.textColor = entry.verified ? StatusColors.success : StatusColors.warning
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: 8, y: document.frame.height-CGFloat((index+1)*70), width: 514, height: 64)
            document.addSubview(label)
        }
        if entries.isEmpty {
            let label = NSTextField(wrappingLabelWithString: keyboardModes.working ? "Checking connected keyboards…" : nativeKeyboards.contains { !$0.builtIn } ? "An external keyboard is connected. Recheck keyboards to read its Fn mode and navigation layout." : "No external keyboards detected.")
            label.frame = NSRect(x: 8,y: document.bounds.height-54,width: 510,height: 48); label.textColor = .secondaryLabelColor; document.addSubview(label)
        }
        scroll.documentView = document; view.addSubview(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height-scroll.contentSize.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        let navigation = SettingsActionButton(title: keyboardModes.registrationNeedsSetup ? "Set up keyboard layout…" : "Learn or change a layout…") { [weak self] in self?.testNavigationKeys() }
        if keyboardModes.registrationNeedsSetup {
            navigation.attributedTitle = NSAttributedString(string: navigation.title, attributes: [.foregroundColor: StatusColors.warning, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        }
        navigation.frame = NSRect(x: 8, y: 105, width: 547, height: 30); view.addSubview(navigation)
        let retry = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.keyboardModes.recheck() }
        retry.isEnabled = !keyboardModes.working; retry.frame = NSRect(x: 8,y: 51,width: 185,height: 30); view.addSubview(retry)
        let open = SettingsActionButton(title: keyboardModes.needsAccess ? "Keyboard access in Setup…" : "Open macOS Keyboard Settings") { [weak self] in
            let permission = self?.keyboardModes.needsAccess == true
            self?.openKeyboardPreferences(permission: permission)
        }
        open.frame = NSRect(x: 200,y: 51,width: 355,height: 30); view.addSubview(open)
        SettingsWindow.shared.show(.init(title: "Keyboards", detail: "Layouts and device readiness. Behavior switches are in the Perch menu.", view: view, refresh: { [weak self] in self?.keyboardDetails() }))
    }
}


extension AppDelegate {
    func refreshKeypadNavigation() {
        guard let item = keypadItem else { return }
        let saved = SafetyConfiguration.load().keypadNavigation == true
        let helper = HelperStatusIPC.inputClient.value
        item.state = saved ? .on : .off
        let ready = helper?.fresh == true && helper?.keypadSupported == true && helper?.trusted == true
        let nav = helper?.keypadNavigationDevices ?? 0, count = helper?.keypadDevices ?? 0
        let hint = !ready ? "Setup needed" : !saved ? "" : count == 0 ? "Waiting for keyboard" : nav == 0 ? "Numbers" : nav == count ? "Navigation" : "Mixed modes"
        label(item, "Use Num Lock for keypad navigation", hint: hint, hintColor: ready ? .secondaryLabelColor : StatusColors.warning)
        (item.view as? MenuRowView)?.opensAnotherInterface = { !saved && !ready }
    }
    @objc func toggleKeypadNavigation() {
        var config = SafetyConfiguration.load()
        if config.keypadNavigation != true {
            let helper = HelperStatusIPC.inputClient.value
            guard helper?.fresh == true && helper?.keypadSupported == true else { openSetupStage("maintenance"); return }
            guard helper?.trusted == true else { openSetupStage("input-access"); return }
        }
        config.keypadNavigation = config.keypadNavigation != true
        do { try config.save(); refreshKeypadNavigation() } catch { showError(error) }
    }
}
