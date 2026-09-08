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
            item.toolTip = devices.isEmpty ? "No \(builtIn ? "built-in" : "external") keyboard connected. Your choice applies when one connects." : devices.map { $0.name + ": " + ($0.swapped == true ? "swapped" : $0.swapped == false ? "unswapped" : "custom mapping") }.joined(separator: "\n")
        }
    }
    func refreshFunctionKeyItem(_ standard: Bool) {
        fnItem.state = standard ? .on : .off
        label(fnItem, "Use F1–F12 directly", hint: standard ? "Without Fn" : "Hold Fn")
        fnItem.toolTip = "Changes the real macOS function-key setting while preserving connected external keyboards’ Fn modes."
        fnItem.isEnabled = !keyboardModes.blocksFunctionKeyChanges && nativeKeyboards.contains { $0.builtIn }
        refreshExternalFunctionKeyItem()
    }
    func refreshExternalFunctionKeyItem() {
        guard let item = externalFnItem else { return }
        let results = keyboardModes.results
        let modes = Set(results.compactMap { $0.standard })
        item.state = modes.count > 1 ? .mixed : modes.first == true ? .on : .off
        let failed = results.filter { !$0.verified }
        let hint: String
        if keyboardModes.blocksFunctionKeyChanges { hint = "Updating keyboards…" }
        else if !failed.isEmpty { hint = "⚠ \(failed.count) need setup · see Settings" }
        else if modes.count > 1 { hint = "Mixed modes" }
        else if let mode = modes.first { hint = mode ? "Without Fn" : "Hold Fn" }
        else { hint = "No keyboard" }
        label(item, "Use F1–F12 directly", hint: hint, hintColor: failed.isEmpty ? .secondaryLabelColor : StatusColors.warning)
        item.isEnabled = !keyboardModes.blocksFunctionKeyChanges && (!modes.isEmpty || !failed.isEmpty)
        item.action = failed.isEmpty ? #selector(toggleExternalFunctionKeys) : #selector(keyboardSettings)
        (item.view as? MenuRowView)?.opensAnotherInterface = { !failed.isEmpty }
        item.toolTip = "Changes only external keyboards. Supported Logitech devices use their own Fn Lock; Apple keyboards use a native per-device override, reapplied on connection while Perch runs.\n" + results.map { $0.name + ": " + $0.detail }.joined(separator: "\n")
    }
    @objc func toggleExternalFunctionKeys() {
        let desired = externalFnItem.state != .on
        UserDefaults.standard.set(desired, forKey: NativeFunctionKeys.externalIntentKey)
        keyboardModes.queue(reapplyExternal: true)
    }
    func keyboardStatusChanged() {
        synchronizeNavigationProfiles()
        nativeKeyboards = NativeModifierKeys.keyboards()
        refreshModifierItems()
        if let standard = try? FunctionKeys.standard(), fnItem != nil { refreshFunctionKeyItem(standard) }
        refreshKeyboardAttention()
        let host = SettingsWindow.shared
        if host.window.isVisible && !host.modal {
            if host.pages.last?.title == "Keyboard settings" { keyboardSettings() }
            else if host.pages.last?.title == "Keyboard details" { keyboardDetails() }
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
            label(item, "Set up keyboard…", hint: "⚠ Unrecognized layout", hintColor: StatusColors.warning)
            item.toolTip = keyboardModes.attentionDetail
        }
        refreshExternalKeyboardSection()
        if currentProtectionIssue == nil, let item = safetySettingsItem {
            label(item, "Settings…", hint: keyboardModes.attentionHint, hintColor: StatusColors.warning)
            item.toolTip = keyboardModes.attentionDetail
        }
    }
    func refreshExternalKeyboardSection() {
        guard let heading = externalKeyboardSection else { return }
        let registrations = keyboardModes.registrations
        let names = registrations.isEmpty ? nativeKeyboards.filter { !$0.builtIn }.map { $0.name } : registrations.map { $0.name }
        let unknown = keyboardModes.registrationNeedsSetup
        let title = names.count > 1 ? "External keyboards · \(names.count) keyboards" : "External keyboard · " + (names.first ?? (unknown ? "Detection unavailable" : "None connected"))
        heading.title = title
        (heading.view as? MenuRowView)?.text = NSAttributedString(string:title, attributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.secondaryLabelColor])
        let hideControls = names.isEmpty
        externalSwapItem.isHidden = hideControls
        externalFnItem.isHidden = hideControls
        let profiles = registrations.compactMap { $0.profile }
        homeEndItem.isHidden = hideControls || !profiles.contains { $0.hasHomeEnd }
        pageKeysItem.isHidden = hideControls || !profiles.contains { $0.hasPageKeys }
        keyboardSetupItem.isHidden = !unknown
    }
    @objc func keyboardSettings() { keyboardSettingsView(details: false) }
    @objc func keyboardDetails() { keyboardSettingsView(details: true) }
    func keyboardSettingsView(details: Bool) {
        if menuOpen { withMenuClosed { [weak self] in self?.keyboardSettings() }; return }
        nativeKeyboards = NativeModifierKeys.keyboards()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        func text(_ value: String, _ y: CGFloat, _ height: CGFloat, color: NSColor = .labelColor) {
            let label = NSTextField(wrappingLabelWithString: value)
            label.font = .systemFont(ofSize: 13); label.textColor = color
            label.frame = NSRect(x: 8, y: y, width: 556, height: height); view.addSubview(label)
        }
        let nativeMode = try? FunctionKeys.standard()
        let externalModes = Set(keyboardModes.results.compactMap { $0.standard })
        for (builtIn, x) in [(true, CGFloat(8)), (false, CGFloat(287))] {
            let heading = NSTextField(labelWithString: builtIn ? "Built-in keyboard" : "All external keyboards")
            heading.font = .systemFont(ofSize: 14, weight: .semibold)
            heading.frame = NSRect(x: x, y: 458, width: 269, height: 24); view.addSubview(heading)
            let fn = SettingsActionButton(title: "F1–F12 directly") { [weak self] in
                guard let self, self.fnItem != nil else { return }
                if builtIn { self.toggleFunctionKeys() } else { self.toggleExternalFunctionKeys() }
                self.keyboardSettings()
            }
            fn.setButtonType(.switch); fn.allowsMixedState = true
            fn.state = builtIn ? nativeMode.map { $0 ? .on : .off } ?? .mixed : externalModes.count > 1 ? .mixed : externalModes.first == true ? .on : .off
            fn.isEnabled = !keyboardModes.blocksFunctionKeyChanges && (builtIn ? nativeMode != nil && nativeKeyboards.contains { $0.builtIn } : !externalModes.isEmpty)
            fn.toolTip = builtIn ? "On: F1–F12 without Fn. Off: media controls without Fn. External choices are preserved." : "Applies to all supported external keyboards. Mixed indicates different observed modes. Unavailable devices are explained below."
            fn.frame = NSRect(x: x, y: 423, width: 269, height: 28); view.addSubview(fn)
            let devices = nativeKeyboards.filter { $0.builtIn == builtIn }
            let swap = SettingsActionButton(title: "Swap Control and Command") { [weak self] in
                guard let self, self.swapItem != nil else { return }
                self.setModifierGroup(builtIn); self.keyboardSettings()
            }
            swap.setButtonType(.switch); swap.allowsMixedState = true
            swap.state = devices.isEmpty ? .off : devices.allSatisfy { $0.swapped == true } ? .on : devices.allSatisfy { $0.swapped == false } ? .off : .mixed
            swap.isEnabled = !devices.isEmpty
            swap.toolTip = builtIn ? "Changes only the built-in keyboard." : "Changes all connected external keyboards and remembers this group choice for reconnection."
            swap.frame = NSRect(x: x, y: 389, width: 269, height: 28); view.addSubview(swap)
        }
        text(keyboardModes.working ? "Checking keyboard settings…" : "On: F1–F12 work without holding Fn. Off: media controls work directly. Checkmarks show observed settings; mixed means different or custom settings.", 340, 43, color: .secondaryLabelColor)
        if !details {
            let status = keyboardModes.working ? "Reading connected keyboards…" : keyboardModes.needsAccess ? "Some external controls need Input Monitoring. Open keyboard details for the affected devices and access setup." : keyboardModes.results.contains(where: { !$0.verified }) || !keyboardModes.modifierErrors.isEmpty ? "Some keyboard controls need attention. Keyboard details lists the affected devices and the next step." : !nativeKeyboards.contains(where: { !$0.builtIn }) ? "No external keyboard is connected. Its controls become available when one connects." : externalModes.isEmpty ? "External F1–F12 status is unavailable. Recheck keyboards, or open details for supported controls and access setup." : "Connected keyboard controls are available. Navigation keys and app exceptions are optional choices below."
            text(status, 250, 70, color: .secondaryLabelColor)
            let navigation = SettingsActionButton(title: "Navigation keys…") { [weak self] in self?.navigationSettings() }
            navigation.frame = NSRect(x: 0, y: 205, width: 572, height: 32); view.addSubview(navigation)
            text("Behavior, app exceptions, learning and saved layouts in one place.", 172, 28, color: .secondaryLabelColor)
            let diagnostics = SettingsActionButton(title: "Keyboard details & troubleshooting…") { [weak self] in self?.keyboardDetails() }
            diagnostics.frame = NSRect(x: 0, y: 123, width: 572, height: 32); view.addSubview(diagnostics)
            text("See each connected keyboard’s results, access setup and macOS settings.", 89, 28, color: .secondaryLabelColor)
            let retry = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.keyboardModes.recheck() }
            retry.isEnabled = !keyboardModes.working; retry.frame = NSRect(x: 0, y: 15, width: 572, height: 32); view.addSubview(retry)
            SettingsWindow.shared.show(.init(title: "Keyboard settings", detail: "Choose the keyboard group and behavior you want. Built-in and external choices are independent. Changes apply immediately.", view: view, refresh: { [weak self] in self?.keyboardSettings() }))
            return
        }
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 145, width: 556, height: 185))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder
        let registration = keyboardModes.registrations.map { KeyboardModeResult(name: $0.name + " · Recognition", detail: $0.detail, verified: !$0.needsSetup) }
        let errors = keyboardModes.registrationError.map { [KeyboardModeResult(name: "Keyboard registration", detail: "⚠ " + $0, verified: false)] } ?? []
        var navigationStatus: [KeyboardModeResult] = []
        if SafetyConfiguration.load().navigation?.enabled == true {
            let input = HelperStatusIPC.inputClient.value
            let verified = input?.fresh == true && input?.active == true && input?.navigationObserved == true && input?.navigationUnidentified != true
            let message = input?.navigationUnidentified == true ? "⚠ macOS did not identify the source keyboard. Those keys keep their native behavior." : verified ? "✓ External navigation events received and identified." : "Waiting for an external navigation key. App exceptions are listed below."
            navigationStatus = [.init(name:"Navigation",detail:message,verified:verified)]
        }
        let entries = errors + registration + navigationStatus + keyboardModes.results + keyboardModes.modifierErrors.map { KeyboardModeResult(name: "Modifier keys", detail: "⚠ " + $0, verified: false) }
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
        let exceptions = SettingsActionButton(title: "Navigation app exceptions…") { [weak self] in self?.navigationExceptions() }
        exceptions.frame = NSRect(x: 287,y: 105,width: 269,height: 30); view.addSubview(exceptions)
        let navigation = SettingsActionButton(title: keyboardModes.registrationNeedsSetup ? "⚠ Set up navigation keys…" : "Set up navigation keys…") { [weak self] in self?.testNavigationKeys() }
        if keyboardModes.registrationNeedsSetup {
            navigation.attributedTitle = NSAttributedString(string: navigation.title, attributes: [.foregroundColor: StatusColors.warning, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        }
        navigation.frame = NSRect(x: 8, y: 105, width: 273, height: 30); view.addSubview(navigation)
        let retry = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.keyboardModes.recheck() }
        retry.isEnabled = !keyboardModes.working; retry.frame = NSRect(x: 8,y: 51,width: 185,height: 30); view.addSubview(retry)
        let open = SettingsActionButton(title: keyboardModes.needsAccess ? "Open macOS Input Monitoring" : "Open macOS Keyboard Settings") { [weak self] in
            let permission = self?.keyboardModes.needsAccess == true
            if permission { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            NSWorkspace.shared.open(URL(string: permission ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" : "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
        open.frame = NSRect(x: 200,y: 51,width: 355,height: 30); view.addSubview(open)
        if keyboardModes.needsAccess {
            let drag = PermissionDragItem(title: "Drag Perch → Input Monitoring, then enable it") { Bundle.main.bundleURL }
            drag.frame = NSRect(x: 8,y: 2,width: 548,height: 40); view.addSubview(drag)
        }
        SettingsWindow.shared.show(.init(title: "Keyboard details", detail: "Read the result for the affected keyboard. Recheck only reads device state; it does not reapply saved choices. Navigation recognition is separate from function keys and modifier swaps.", view: view, refresh: { [weak self] in self?.keyboardDetails() }))
    }
}
