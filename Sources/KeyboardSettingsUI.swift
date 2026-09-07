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
        fnItem.isEnabled = !keyboardModes.working && nativeKeyboards.contains { $0.builtIn }
        refreshExternalFunctionKeyItem()
    }
    func refreshExternalFunctionKeyItem() {
        guard let item = externalFnItem else { return }
        let results = keyboardModes.results
        let modes = Set(results.compactMap { $0.standard })
        item.state = modes.count > 1 ? .mixed : modes.first == true ? .on : .off
        let failed = results.filter { !$0.verified }
        let hint: String
        if keyboardModes.working { hint = "Checking keyboards…" }
        else if !failed.isEmpty { hint = "⚠ \(failed.count) need setup · see Settings" }
        else if modes.count > 1 { hint = "Mixed modes" }
        else if let mode = modes.first { hint = mode ? "Without Fn" : "Hold Fn" }
        else { hint = "No keyboard" }
        label(item, "Use F1–F12 directly", hint: hint, hintColor: failed.isEmpty ? .secondaryLabelColor : StatusColors.warning)
        item.isEnabled = !keyboardModes.working && !modes.isEmpty
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
        if currentProtectionIssue == nil, let item = safetySettingsItem {
            label(item, "Settings…", hint: keyboardModes.attentionHint, hintColor: StatusColors.warning)
            item.toolTip = keyboardModes.attentionDetail
        }
    }
    @objc func keyboardSettings() {
        nativeKeyboards = NativeModifierKeys.keyboards()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        func text(_ value: String, _ y: CGFloat, _ height: CGFloat, color: NSColor = .labelColor) {
            let label = NSTextField(wrappingLabelWithString: value)
            label.font = .systemFont(ofSize: 13); label.textColor = color
            label.frame = NSRect(x: 8, y: y, width: 556, height: height); view.addSubview(label)
        }
        let nativeMode = (try? FunctionKeys.standard()).map { $0 ? "✓ Built-in keyboard: F1–F12 directly" : "✓ Built-in keyboard: hold Fn for F1–F12" } ?? "⚠ macOS function-key mode unavailable"
        text(nativeMode, 448, 30, color: nativeMode.hasPrefix("✓") ? StatusColors.success : StatusColors.warning)
        text(keyboardModes.working ? "Checking each keyboard’s own setting…" : "Built-in and external Fn choices are independent. Existing modes are read first; only choices you make are saved and reapplied.", 407, 40, color: .secondaryLabelColor)
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 145, width: 556, height: 253))
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
        let entries = errors + navigationStatus + registration + keyboardModes.results + keyboardModes.modifierErrors.map { KeyboardModeResult(name: "Modifier keys", detail: "⚠ " + $0, verified: false) }
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 530,height: max(scroll.contentSize.height,CGFloat(entries.count*70))))
        for (index, entry) in entries.enumerated() {
            let label = NSTextField(wrappingLabelWithString: entry.name + "\n" + entry.detail)
            label.textColor = entry.verified ? StatusColors.success : StatusColors.warning
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: 8, y: document.frame.height-CGFloat((index+1)*70), width: 514, height: 64)
            document.addSubview(label)
        }
        if entries.isEmpty {
            let label = NSTextField(labelWithString: keyboardModes.working ? "Checking connected keyboards…" : "No external keyboards detected.")
            label.frame = NSRect(x: 8,y: document.bounds.height-36,width: 510,height: 28); label.textColor = .secondaryLabelColor; document.addSubview(label)
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
        let retry = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.keyboardModes.queue(reapplyExternal: true) }
        retry.isEnabled = !keyboardModes.working; retry.frame = NSRect(x: 8,y: 51,width: 185,height: 30); view.addSubview(retry)
        let open = SettingsActionButton(title: keyboardModes.needsAccess ? "Open Input Monitoring" : "Open Keyboard Settings") { [weak self] in
            let permission = self?.keyboardModes.needsAccess == true
            if permission { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            NSWorkspace.shared.open(URL(string: permission ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" : "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
        open.frame = NSRect(x: 200,y: 51,width: 355,height: 30); view.addSubview(open)
        if keyboardModes.needsAccess {
            let drag = PermissionDragItem(title: "Drag Perch → Input Monitoring, then enable it") { Bundle.main.bundleURL }
            drag.frame = NSRect(x: 8,y: 2,width: 548,height: 40); view.addSubview(drag)
        }
        SettingsWindow.shared.show(.init(title: "Keyboard settings", detail: keyboardModes.registrationNeedsSetup ? keyboardModes.attentionDetail : "Keyboard recognition, permissions, and setup results. Change Fn modes, Control/Command swaps, and external navigation modes in Perch’s menu.", view: view, refresh: { [weak self] in self?.keyboardSettings() }))
    }
}
