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
            label(item, "Swap Control ↔ Command keys", hint: builtIn ? "Built-in" : "External")
            item.toolTip = devices.isEmpty ? "No \(builtIn ? "built-in" : "external") keyboard connected. Your choice applies when one connects." : devices.map { $0.name + ": " + ($0.swapped == true ? "swapped" : $0.swapped == false ? "unswapped" : "custom mapping") }.joined(separator: "\n")
        }
    }
    func refreshFunctionKeyItem(_ standard: Bool) {
        fnItem.state = standard ? .on : .off // The checkbox always represents macOS.
        let failed = keyboardModes.results.filter { !$0.verified }
        let hint = keyboardModes.busy ? "Applying to keyboards…" : failed.isEmpty ? "Without Fn" : "⚠ \(failed.count) keyboard\(failed.count == 1 ? "" : "s") · see Settings"
        label(fnItem, "Use F1–F12 directly", hint: hint, hintColor: failed.isEmpty ? .secondaryLabelColor : StatusColors.warning)
        fnItem.toolTip = "Changes macOS’s actual function-key setting and supported external keyboards’ Fn Lock.\n" + keyboardModes.results.map { $0.name + ": " + $0.detail }.joined(separator: "\n")
    }
    func keyboardStatusChanged() {
        nativeKeyboards = NativeModifierKeys.keyboards()
        refreshModifierItems()
        if let standard = try? FunctionKeys.standard(), fnItem != nil { refreshFunctionKeyItem(standard) }
        let host = SettingsWindow.shared
        if host.window.isVisible && !host.modal {
            if host.pages.last?.title == "Keyboard settings" { keyboardSettings() }
            else if host.pages.last?.title == "Perch settings" { configureSettings() }
        }
        if keyboardModes.warning && currentProtectionIssue == nil && safetySettingsItem != nil {
            label(safetySettingsItem, "Settings…", hint: "⚠ Review keyboards", hintColor: StatusColors.warning)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--keyboard-diagnostics"), CommandLine.arguments.count > index+1 {
            let output: [String:Any] = ["busy":keyboardModes.busy, "functionKeys":keyboardModes.results.map { ["name":$0.name,"detail":$0.detail,"verified":$0.verified,"needsAccess":$0.needsAccess] as [String:Any] }, "modifiers":nativeKeyboards.map { ["name":$0.name,"builtIn":$0.builtIn,"swapped":$0.swapped as Any? ?? NSNull()] }, "errors":keyboardModes.modifierErrors]
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
        if !failures.isEmpty { menu.cancelTracking(); keyboardSettings() }
    }
    @objc func toggleExternalModifiers() { setModifierGroup(false) }
    @objc func keyboardSettings() {
        nativeKeyboards = NativeModifierKeys.keyboards()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 490))
        func text(_ value: String, _ y: CGFloat, _ height: CGFloat, color: NSColor = .labelColor) {
            let label = NSTextField(wrappingLabelWithString: value)
            label.font = .systemFont(ofSize: 13); label.textColor = color
            label.frame = NSRect(x: 8, y: y, width: 556, height: height); view.addSubview(label)
        }
        let nativeMode = (try? FunctionKeys.standard()).map { $0 ? "✓ macOS: F1–F12 directly" : "✓ macOS: hold Fn for F1–F12" } ?? "⚠ macOS function-key mode unavailable"
        text(nativeMode, 448, 30, color: nativeMode.hasPrefix("✓") ? StatusColors.success : StatusColors.warning)
        text(keyboardModes.busy ? "Applying the macOS setting to connected keyboards…" : "External Fn modes are checked at connection, on wake, and when you change this setting.", 407, 40, color: .secondaryLabelColor)
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 103, width: 556, height: 295))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder
        let entries = keyboardModes.results + keyboardModes.modifierErrors.map { KeyboardModeResult(name: "Modifier keys", detail: "⚠ " + $0, verified: false) }
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 530,height: max(290,CGFloat(entries.count*70))))
        for (index, entry) in entries.enumerated() {
            let label = NSTextField(wrappingLabelWithString: entry.name + "\n" + entry.detail)
            label.textColor = entry.verified ? StatusColors.success : StatusColors.warning
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: 8, y: document.frame.height-CGFloat((index+1)*70), width: 514, height: 64)
            document.addSubview(label)
        }
        if entries.isEmpty {
            let label = NSTextField(labelWithString: keyboardModes.busy ? "Checking connected keyboards…" : "No external keyboards detected.")
            label.frame = NSRect(x: 8,y: 245,width: 510,height: 28); label.textColor = .secondaryLabelColor; document.addSubview(label)
        }
        scroll.documentView = document; view.addSubview(scroll)
        let retry = SettingsActionButton(title: "Recheck keyboards") { [weak self] in self?.keyboardModes.queue() }
        retry.isEnabled = !keyboardModes.busy; retry.frame = NSRect(x: 8,y: 51,width: 185,height: 30); view.addSubview(retry)
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
        SettingsWindow.shared.show(.init(title: "Keyboard settings", detail: "Keyboard compatibility, permissions, and setup results. Change function keys and Control/Command swaps in the Input section of Perch’s menu.", view: view))
    }
}
