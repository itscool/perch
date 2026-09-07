import AppKit
import Carbon

final class MonitorInputPage: NSObject {
    let controller: MonitorInputController
    let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
    let monitors = NSPopUpButton(), protocolChoice = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "")
    var candidates: [MonitorInput] = []
    var selectedCodes = Set<UInt16>()
    let inputList = NSScrollView(frame: NSRect(x: 0,y: 177,width: 572,height: 118))
    let blind = NSButton(checkboxWithTitle: "If the current input can’t be read, cycle from the last command sent", target: nil, action: nil)
    let enabled = NSButton(checkboxWithTitle: "Enable monitor shortcut", target: nil, action: nil)
    let keys = NSPopUpButton()
    var modifiers: [(NSButton,UInt32)] = []
    var detect: SettingsActionButton!
    var save: SettingsActionButton!
    private var listed: [MonitorDescriptor] = []
    private var editedDisplay = ""
    private var shown = false
    private var didAutoDetect = false
    init(_ controller: MonitorInputController) {
        self.controller = controller; super.init()
        func label(_ text: String, _ frame: NSRect) {
            let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.frame = frame; view.addSubview(label)
        }
        monitors.frame = NSRect(x: 0,y: 452,width: 350,height: 30); monitors.target = self; monitors.action = #selector(selectedMonitor)
        protocolChoice.addItems(withTitles: ["Standard DDC", "LG alternate input control"])
        protocolChoice.frame = NSRect(x: 360,y: 452,width: 212,height: 30)
        protocolChoice.target = self; protocolChoice.action = #selector(protocolChanged)
        status.frame = NSRect(x: 4,y: 387,width: 564,height: 60); status.font = .systemFont(ofSize: 12)
        detect = SettingsActionButton(title: "Detect inputs") { [weak self] in self?.detectInputs() }
        detect.frame = NSRect(x: 0,y: 348,width: 175,height: 30)
        let recheck = SettingsActionButton(title: "Recheck monitors") { [weak controller] in controller?.refresh() }
        recheck.frame = NSRect(x: 185,y: 348,width: 180,height: 30)
        label("Choose at least two inputs. Checked inputs cycle from top to bottom.", NSRect(x: 4,y: 307,width: 564,height: 30))
        inputList.hasVerticalScroller = true; inputList.autohidesScrollers = false; inputList.borderType = .bezelBorder
        let custom = SettingsActionButton(title: "Edit inputs…") { [weak self] in self?.editInputs() }
        custom.frame = NSRect(x: 375,y: 348,width: 197,height: 30)
        blind.frame = NSRect(x: 0,y: 143,width: 572,height: 28)
        enabled.frame = NSRect(x: 0,y: 109,width: 280,height: 28)
        keys.addItems(withTitles: PanicShortcut.keys.map { $0.0 }); keys.frame = NSRect(x: 465,y: 73,width: 107,height: 28)
        for (index, pair) in [("Control",controlKey),("Option",optionKey),("Shift",shiftKey),("Command",cmdKey)].enumerated() {
            let box = NSButton(checkboxWithTitle: pair.0, target: nil, action: nil)
            box.frame = NSRect(x: CGFloat(index*112),y: 73,width: 112,height: 28)
            modifiers.append((box,UInt32(pair.1))); view.addSubview(box)
        }
        save = SettingsActionButton(title: "Save") { [weak self] in self?.saveSettings() }
        save.frame = NSRect(x: 402,y: 12,width: 170,height: 32)
        let cycle = SettingsActionButton(title: "Cycle input now") { [weak self] in
            guard let self else { return }
            if self.saveSettings(back: false) { self.controller.cycle() }
        }
        cycle.frame = NSRect(x: 200,y: 12,width: 195,height: 32)
        [monitors,protocolChoice,status,detect,recheck,custom,inputList,blind,enabled,keys,save,cycle].forEach { view.addSubview($0) }
        editedDisplay = controller.plan.display
        candidates = controller.plan.inputs; selectedCodes = Set(candidates.map { $0.code })
        renderInputs()
        protocolChoice.selectItem(at: controller.plan.alternate ? 1 : 0)
        blind.state = controller.plan.allowUnconfirmedCycle ? .on : .off
        enabled.state = controller.plan.shortcut.enabled ? .on : .off
        keys.selectItem(at: PanicShortcut.keys.firstIndex { $0.1 == controller.plan.shortcut.key } ?? 0)
        for (box, flag) in modifiers { box.state = controller.plan.shortcut.modifiers & flag != 0 ? .on : .off }
        controller.pageChanged = { [weak self] in self?.refresh() }
        refresh()
    }
    private func renderInputs() {
        let document = NSView(frame: NSRect(x: 0,y: 0,width: 548,height: max(118,CGFloat(candidates.count*32))))
        if candidates.isEmpty {
            let label = NSTextField(labelWithString: "Detect inputs to populate this list, or use Edit inputs.")
            label.textColor = .secondaryLabelColor; label.frame = NSRect(x: 8,y: document.frame.height-32,width: 525,height: 25); document.addSubview(label)
        }
        for (index, input) in candidates.enumerated() {
            let y = document.frame.height-CGFloat((index+1)*32)
            let check = NSButton(checkboxWithTitle: input.name,target: self,action: #selector(inputChecked(_:)))
            check.tag = index; check.state = selectedCodes.contains(input.code) ? .on : .off
            check.frame = NSRect(x: 8,y: y,width: 429,height: 30); document.addSubview(check)
            for (delta,x,title) in [(-1,440.0,"↑"),(1,490.0,"↓")] {
                let button = SettingsActionButton(title: title) { [weak self] in
                    guard let self, self.candidates.indices.contains(index+delta) else { return }
                    self.candidates.swapAt(index,index+delta); self.renderInputs()
                }
                button.frame = NSRect(x: x,y: y,width: 44,height: 28)
                button.isEnabled = candidates.indices.contains(index+delta); button.toolTip = delta < 0 ? "Move earlier in cycle" : "Move later in cycle"
                document.addSubview(button)
            }
        }
        inputList.documentView = document
        inputList.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.frame.height-inputList.contentSize.height)))
        inputList.reflectScrolledClipView(inputList.contentView)
    }
    @objc private func inputChecked(_ sender: NSButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        let code = candidates[sender.tag].code
        if sender.state == .on { selectedCodes.insert(code) } else { selectedCodes.remove(code) }
    }
    private func editInputs() {
        let page = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
        let text = NSTextView(frame: NSRect(x: 0,y: 0,width: 548,height: 360))
        text.isRichText = false; text.font = .monospacedSystemFont(ofSize: 13,weight: .regular)
        text.textColor = .labelColor; text.backgroundColor = .textBackgroundColor
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.textContainer?.widthTracksTextView = true
        text.string = Self.lines(candidates)
        let scroll = NSScrollView(frame: NSRect(x: 0,y: 110,width: 572,height: 370))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder; scroll.documentView = text
        let error = NSTextField(wrappingLabelWithString: ""); error.frame = NSRect(x: 4,y: 48,width: 564,height: 55); error.textColor = StatusColors.warning
        let apply = SettingsActionButton(title: "Use this input list") { [weak self] in
            do {
                let values = try Self.parse(text.string)
                self?.candidates = values; self?.selectedCodes.formIntersection(values.map { $0.code }); self?.renderInputs()
                SettingsWindow.shared.goBack()
            } catch let failure { error.stringValue = failure.localizedDescription }
        }
        apply.frame = NSRect(x: 315,y: 5,width: 257,height: 32)
        [scroll,error,apply].forEach { page.addSubview($0) }
        SettingsWindow.shared.show(.init(title: "Edit monitor inputs", detail: "Manual fallback when your monitor reports no input list or uses unusual codes. Enter one input per line as decimal code = name. Standard examples: 17 = HDMI 1, 18 = HDMI 2, 15 = DisplayPort, 27 = USB-C. LG alternate codes depend on the exact model: USB-C can be 209, 210, or 192. Do not assume a code from the generic display name. This only edits the list; it does not switch inputs.", view: page))
    }
    static func lines(_ inputs: [MonitorInput]) -> String { inputs.map { "\($0.code) = \($0.name)" }.joined(separator: "\n") }
    static func parse(_ text: String) throws -> [MonitorInput] {
        guard text.utf8.count <= 4096 else { throw AppError(message: "The input list is too long.") }
        let inputs = try text.split(whereSeparator: { $0.isNewline }).map { line -> MonitorInput in
            let parts = line.split(separator: "=",maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let code = UInt16(parts[0]), MonitorInput(code: code,name: parts[1]).valid else { throw AppError(message: "Use one input per line, such as 17 = HDMI 1. Codes must be 1–65535.") }
            return MonitorInput(code: code,name: parts[1])
        }
        guard inputs.count >= 2 && inputs.count <= 16 && Set(inputs.map { $0.code }).count == inputs.count else { throw AppError(message: "Choose 2–16 inputs with different codes, in the order you want to cycle them.") }
        return inputs
    }
    func show() {
        shown = true
        SettingsWindow.shared.show(.init(title: "Monitor inputs", detail: "Cycle a connected monitor to another input using the menu or a shortcut. The Mac’s picture may disappear; use the monitor’s own controls to return if it disconnects. Another device does not need to be detected on the destination input.", view: view, leave: { [self] in shown = false; controller.pageChanged = nil }))
        autoDetect()
    }
    private func autoDetect() {
        if shown && !SettingsWindow.shared.testing && !didAutoDetect && candidates.isEmpty && !controller.busy && !editedDisplay.isEmpty {
            didAutoDetect = true
            DispatchQueue.main.async { [weak self] in self?.detectInputs() }
        }
    }
    func refresh() {
        if listed != controller.displays {
            listed = controller.displays; monitors.removeAllItems()
            monitors.addItems(withTitles: listed.map { $0.name })
            if let index = listed.firstIndex(where: { $0.id == editedDisplay }) { monitors.selectItem(at: index) }
            else if editedDisplay.isEmpty && listed.count == 1 { editedDisplay = listed[0].id; monitors.selectItem(at: 0)
                protocolChoice.selectItem(at: MonitorProfiles.match(listed[0]).map { $0.alternate && $0.confidence != "suggested" } == true ? 1 : 0) }
            else { monitors.select(nil) }
        }
        let selected = listed.first { $0.id == editedDisplay }
        protocolChoice.item(at: 1)?.isEnabled = selected?.vendor == 0x1e6d
        monitors.isEnabled = !controller.busy
        protocolChoice.isEnabled = !controller.busy
        detect.isEnabled = !controller.busy && selected?.ddcAvailable == true
        save.isEnabled = !controller.busy
        status.stringValue = controller.busy ? "Checking monitor… You can continue using your Mac." : controller.message
        status.textColor = controller.warning ? StatusColors.warning : controller.message.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor
        autoDetect()
    }
    @objc private func selectedMonitor() {
        guard listed.indices.contains(monitors.indexOfSelectedItem) else { return }
        let id = listed[monitors.indexOfSelectedItem].id
        guard editedDisplay != id else { return }
        editedDisplay = id; candidates = []; selectedCodes = []; renderInputs(); protocolChoice.selectItem(at: MonitorProfiles.match(listed[monitors.indexOfSelectedItem]).map { $0.alternate && $0.confidence != "suggested" } == true ? 1 : 0)
        refresh(); detectInputs()
    }
    @objc private func protocolChanged() {
        candidates = []; selectedCodes = []; renderInputs(); detectInputs()
    }
    private func detectInputs() {
        guard let display = listed.first(where: { $0.id == editedDisplay }), display.ddcAvailable, !controller.busy else { return }
        if let profile = MonitorProfiles.match(display), profile.alternate, profile.confidence != "suggested", candidates.isEmpty, !didAutoDetect { protocolChoice.selectItem(at: 1) }
        let alternate = protocolChoice.indexOfSelectedItem == 1
        controller.inspect(editedDisplay, alternate: alternate) { [weak self] result in
            guard let self, self.shown else { return }
            switch result {
            case .success(let inspection):
                let codes = inspection.capabilities.map(MonitorCapabilities.inputs) ?? []
                if !codes.isEmpty {
                    self.candidates = codes.map { MonitorInput(code: $0,name: MonitorInput.name($0,alternate: alternate)) }; self.selectedCodes.formIntersection(codes); self.renderInputs()
                    self.controller.message = "✓ Inputs reported by monitor. Current: \(inspection.current.map { MonitorInput.name($0,alternate: alternate) } ?? "unavailable"). Remove inputs you don’t want to cycle."
                    self.controller.warning = false
                } else {
                    if let profile = MonitorProfiles.match(display), profile.alternate == alternate {
                        self.candidates = profile.inputs
                        self.controller.message = "⚠ Using a bundled \(profile.confidence == "suggested" ? "suggested" : "community-documented") profile for \(profile.name). Check the ports before saving. Input list was not reported. LG port codes vary by exact model; this profile is not proof of support. Use Edit inputs to correct codes."
                    } else {
                        let suggested: [UInt16] = alternate ? [144,145,208,210] : [17,18,15,27]
                        self.candidates = suggested.map { MonitorInput(code: $0,name: MonitorInput.name($0,alternate: alternate)) }
                        self.controller.message = "⚠ Input detection unavailable. These are common port suggestions; choose only ports your monitor has. Edit inputs can correct their codes."
                    }
                    self.selectedCodes = []; self.renderInputs()
                    self.controller.warning = true
                }
            case .failure(let error): self.controller.message = error.localizedDescription; self.controller.warning = true
            }
            self.refresh()
        }
    }
    @discardableResult private func saveSettings(back: Bool = true) -> Bool {
        do {
            guard UUID(uuidString: editedDisplay) != nil else { throw AppError(message: "Select a connected monitor first.") }
            var plan = MonitorInputPlan()
            plan.display = editedDisplay; plan.alternate = protocolChoice.indexOfSelectedItem == 1
            plan.inputs = candidates.filter { selectedCodes.contains($0.code) }; plan.allowUnconfirmedCycle = blind.state == .on
            guard plan.inputs.count >= 2 else { throw AppError(message: "Check at least two inputs to cycle between.") }
            let mask = modifiers.filter { $0.0.state == .on }.reduce(UInt32(0)) { $0 | $1.1 }
            plan.shortcut = PanicShortcut(key: PanicShortcut.keys[keys.indexOfSelectedItem].1,modifiers: mask,enabled: enabled.state == .on)
            try controller.save(plan)
            if back { SettingsWindow.shared.goBack() }
            return true
        } catch { status.stringValue = "⚠ " + error.localizedDescription; status.textColor = StatusColors.warning; return false }
    }
}

extension AppDelegate {
    func refreshMonitorInputItem() {
        guard let item = monitorInputItem else { return }
        item.isEnabled = monitorInputs.canCycle
        let hint = monitorInputs.busy ? "Working…" : monitorInputs.warning ? "⚠ See monitor settings" : monitorInputs.connected == nil ? "Set up in Settings" : monitorInputs.shortcutActive ? monitorInputs.plan.shortcut.title : monitorInputs.plan.inputs.count >= 2 ? "Shortcut off" : "Choose inputs in Settings"
        label(item, "Cycle monitor input", hint: hint, hintColor: monitorInputs.warning ? StatusColors.warning : .secondaryLabelColor)
        item.toolTip = monitorInputs.message
    }
    @objc func cycleMonitorInput() { monitorInputs.cycle() }
    @objc func monitorInputSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.monitorInputSettings() }; return }
        MonitorInputPage(monitorInputs).show()
    }
}
