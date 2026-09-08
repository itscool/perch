import AppKit
import Carbon

final class MonitorInputPage: NSObject {
    let controller: MonitorInputController
    let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
    let monitors = NSPopUpButton(), protocolChoice = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "")
    var candidates: [MonitorInput] = []
    var selectedCodes = Set<UInt16>()
    let inputList = NSScrollView(frame: NSRect(x: 0,y: 155,width: 572,height: 118))
    let blind = NSButton(checkboxWithTitle: "If the current input can’t be read, cycle from the last command sent", target: nil, action: nil)
    let enabled = NSButton(checkboxWithTitle: "Enable monitor shortcut", target: nil, action: nil)
    let keys = NSPopUpButton()
    var modifiers: [(NSButton,UInt32)] = []
    var detect: SettingsActionButton!
    var save: SettingsActionButton!
    var worked: SettingsActionButton!
    var failed: SettingsActionButton!
    private var lastDDCIndex = 0
    private var controlConnection: MonitorConnection?
    private var chosenProfile: String?
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
        protocolChoice.addItems(withTitles: ["Standard DDC", "LG alternate input control", "USB / NEC connection…"])
        protocolChoice.frame = NSRect(x: 360,y: 452,width: 212,height: 30)
        protocolChoice.target = self; protocolChoice.action = #selector(protocolChanged)
        status.frame = NSRect(x: 4,y: 374,width: 564,height: 73); status.font = .systemFont(ofSize: 12)
        worked = SettingsActionButton(title: "Yes, it switched") { [weak controller] in controller?.confirmSwitch(true) }
        failed = SettingsActionButton(title: "No, troubleshoot") { [weak controller] in controller?.confirmSwitch(false) }
        worked.frame = NSRect(x: 0,y: 345,width: 230,height: 26)
        failed.frame = NSRect(x: 240,y: 345,width: 230,height: 26)
        view.addSubview(worked); view.addSubview(failed)
        detect = SettingsActionButton(title: "Detect inputs") { [weak self] in self?.detectInputs() }
        detect.frame = NSRect(x: 0,y: 308,width: 175,height: 30)
        let recheck = SettingsActionButton(title: "Recheck monitors") { [weak controller] in controller?.refresh() }
        recheck.frame = NSRect(x: 185,y: 308,width: 180,height: 30)
        label("Choose at least two inputs. Checked inputs cycle from top to bottom.", NSRect(x: 4,y: 278,width: 564,height: 26))
        inputList.hasVerticalScroller = true; inputList.autohidesScrollers = false; inputList.borderType = .bezelBorder
        let custom = SettingsActionButton(title: "Model & inputs…") { [weak self] in self?.editInputs() }
        custom.frame = NSRect(x: 375,y: 308,width: 197,height: 30)
        blind.frame = NSRect(x: 0,y: 121,width: 572,height: 28)
        enabled.frame = NSRect(x: 0,y: 89,width: 280,height: 28)
        keys.addItems(withTitles: PanicShortcut.keys.map { $0.0 }); keys.frame = NSRect(x: 465,y: 55,width: 107,height: 28)
        for (index, pair) in [("Control",controlKey),("Option",optionKey),("Shift",shiftKey),("Command",cmdKey)].enumerated() {
            let box = NSButton(checkboxWithTitle: pair.0, target: nil, action: nil)
            box.frame = NSRect(x: CGFloat(index*112),y: 55,width: 112,height: 28)
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
        lastDDCIndex = controller.plan.alternate ? 1 : 0
        controlConnection = controller.plan.controlConnection
        chosenProfile = controller.plan.profileName
        editedDisplay = controller.plan.display
        candidates = controller.plan.inputs; selectedCodes = Set(candidates.map { $0.code })
        renderInputs()
        protocolChoice.selectItem(at: controlConnection != nil ? 2 : controller.plan.alternate ? 1 : 0)
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
        let scroll = NSScrollView(frame: NSRect(x: 0,y: 110,width: 572,height: 315))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder; scroll.documentView = text
        var pendingProfile = chosenProfile
        var pendingAlternate = protocolChoice.indexOfSelectedItem == 1
        let preset = NSPopUpButton(frame: NSRect(x: 0,y: 443,width: 380,height: 30))
        let profiles = controlConnection == nil ? MonitorProfiles.entries.filter { $0.vendor == listed.first(where: { $0.id == editedDisplay })?.vendor && $0.confidence != "suggested" } : []
        preset.addItem(withTitle: "Choose your exact model…")
        preset.addItems(withTitles: profiles.map { $0.name })
        if let name = chosenProfile, let index = profiles.firstIndex(where: { $0.name == name }) { preset.selectItem(at: index + 1) }
        let usePreset = SettingsActionButton(title: "Use preset") {
            guard profiles.indices.contains(preset.indexOfSelectedItem - 1) else { return }
            let profile = profiles[preset.indexOfSelectedItem - 1]
            text.string = Self.lines(profile.inputs)
            pendingAlternate = profile.alternate
            pendingProfile = profile.name
        }
        usePreset.frame = NSRect(x: 390,y: 443,width: 182,height: 30)
        usePreset.isEnabled = !profiles.isEmpty
        page.addSubview(preset); page.addSubview(usePreset)
        let error = NSTextField(wrappingLabelWithString: ""); error.frame = NSRect(x: 4,y: 48,width: 564,height: 55); error.textColor = StatusColors.warning
        let apply = SettingsActionButton(title: "Use this input list") { [weak self] in
            do {
                let values = try Self.parse(text.string)
                self?.chosenProfile = profiles.first(where: { $0.name == pendingProfile })?.inputs == values ? pendingProfile : nil
                self?.protocolChoice.selectItem(at: self?.controlConnection != nil ? 2 : pendingAlternate ? 1 : 0)
                self?.candidates = values; self?.selectedCodes.formIntersection(values.map { $0.code }); self?.renderInputs()
                SettingsWindow.shared.goBack()
            } catch let failure { error.stringValue = failure.localizedDescription }
        }
        let troubleshoot = SettingsActionButton(title: "Compatibility test…") { [weak self] in
            self?.compatibilityTest { input, alternate in
                var values = alternate == pendingAlternate ? ((try? Self.parse(text.string, minimum: 1)) ?? []) : []
                values.removeAll { $0.name == input.name || $0.code == input.code }
                values.append(input)
                text.string = Self.lines(values); pendingAlternate = alternate; pendingProfile = nil
            }
        }
        troubleshoot.isEnabled = controlConnection == nil
        troubleshoot.frame = NSRect(x: 0,y: 5,width: 270,height: 32)
        page.addSubview(troubleshoot)
        apply.frame = NSRect(x: 315,y: 5,width: 257,height: 32)
        [scroll,error,apply].forEach { page.addSubview($0) }
        SettingsWindow.shared.show(.init(title: "Edit monitor inputs", detail: "Choose a documented preset for your exact model, or edit codes manually. The generic display name does not identify every LG model. Enter one input per line as decimal code = name. Standard examples: 17 = HDMI 1, 18 = HDMI 2, 15 = DisplayPort. USB-C has no universal code. LG alternate codes depend on the exact model: USB-C can be 209, 210, or 192. Do not assume a code from the generic display name. This only edits the list; it does not switch inputs.", view: page))
    }
    private func compatibilityTest(apply: @escaping (MonitorInput, Bool) -> Void) {
        guard let display = listed.first(where: { $0.id == editedDisplay }) else { return }
        let page = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 350))
        let prerequisite = NSButton(checkboxWithTitle: "The detected inputs or exact-model preset did not work", target: nil, action: nil)
        prerequisite.frame = NSRect(x: 0,y: 308,width: 572,height: 30)
        struct Candidate { let input: MonitorInput; let alternate: Bool }
        var choices: [Candidate] = []
        // Only input-selection values from this vendor's evidenced profiles.
        for profile in MonitorProfiles.entries where profile.vendor == display.vendor && profile.confidence != "suggested" {
            for input in profile.inputs where !choices.contains(where: { $0.input == input && $0.alternate == profile.alternate }) {
                choices.append(Candidate(input: input, alternate: profile.alternate))
            }
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0,y: 261,width: 572,height: 30))
        picker.addItem(withTitle: "Choose one destination and command to test…")
        picker.addItems(withTitles: choices.map { "\($0.input.name) · \($0.alternate ? "LG alternate" : "Standard") · code \($0.input.code)" })
        let result = NSTextField(wrappingLabelWithString: "Start with your exact model preset. If it failed, choose one alternative above. This may remove this Mac’s picture. Return using the monitor’s own input controls; Perch cannot restore a disconnected display automatically.")
        result.frame = NSRect(x: 4,y: 132,width: 564,height: 113); result.textColor = .secondaryLabelColor
        var awaiting: Candidate?
        var active = true
        var test: SettingsActionButton!
        var yes: SettingsActionButton!
        var no: SettingsActionButton!
        final class Controls { weak var test: NSButton?; weak var yes: NSButton?; weak var no: NSButton?; weak var picker: NSPopUpButton? }
        let controls = Controls(); controls.picker = picker
        func ready() {
            controls.test?.isEnabled = active && !controller.busy && awaiting == nil
            controls.yes?.isEnabled = active && !controller.busy && awaiting != nil
            controls.no?.isEnabled = controls.yes?.isEnabled == true
            controls.picker?.isEnabled = controls.test?.isEnabled == true
        }
        test = SettingsActionButton(title: "Test selected command") { [weak self] in
            guard let self else { return }
            guard prerequisite.state == .on, choices.indices.contains(picker.indexOfSelectedItem - 1) else {
                result.stringValue = "Confirm the defined method failed, then select one candidate. No command sent."
                result.textColor = StatusColors.warning; return
            }
            let candidate = choices[picker.indexOfSelectedItem - 1]
            awaiting = candidate
            self.controller.testInput(candidate.input, display: display.id, alternate: candidate.alternate) { accepted in
                guard active else { return }
                if accepted {
                    result.stringValue = "Command sent for \(candidate.input.name), code \(candidate.input.code). Did the monitor show the intended input? A black screen alone is not confirmation."
                    result.textColor = StatusColors.warning
                } else {
                    awaiting = nil; result.stringValue = self.controller.message + " " + MonitorInputController.connectionAdvice
                    result.textColor = StatusColors.warning
                }
                ready()
            }
            ready()
        }
        yes = SettingsActionButton(title: "Yes — use this mapping") {
            guard let candidate = awaiting else { return }
            apply(candidate.input, candidate.alternate)
            SettingsWindow.shared.goBack()
        }
        no = SettingsActionButton(title: "No — choose another") {
            awaiting = nil
            result.stringValue = "Mapping not changed. Check the adapter/cable and DDC/CI setting, or explicitly choose another candidate. Nothing is sent automatically."
            result.textColor = StatusColors.warning; ready()
        }
        test.frame = NSRect(x: 0,y: 86,width: 572,height: 32)
        yes.frame = NSRect(x: 0,y: 38,width: 278,height: 32)
        no.frame = NSRect(x: 288,y: 38,width: 284,height: 32)
        [prerequisite,picker,result,test!,yes!,no!].forEach { page.addSubview($0) }
        controls.test = test; controls.yes = yes; controls.no = no
        ready()
        SettingsWindow.shared.show(.init(title: "Monitor compatibility test", detail: "One command per click. Back cancels the test; successful mappings are only saved when you save monitor settings. Candidates are reports from other models, not a promise of compatibility.", view: page, leave: { active = false }))
    }
    static func lines(_ inputs: [MonitorInput]) -> String { inputs.map { "\($0.code) = \($0.name)" }.joined(separator: "\n") }
    static func parse(_ text: String, minimum: Int = 2) throws -> [MonitorInput] {
        guard text.utf8.count <= 4096 else { throw AppError(message: "The input list is too long.") }
        let inputs = try text.split(whereSeparator: { $0.isNewline }).map { line -> MonitorInput in
            let parts = line.split(separator: "=",maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let code = UInt16(parts[0]), MonitorInput(code: code,name: parts[1]).valid else { throw AppError(message: "Use one input per line, such as 17 = HDMI 1. Codes must be 1–65535.") }
            return MonitorInput(code: code,name: parts[1])
        }
        guard inputs.count >= minimum && inputs.count <= 16 && Set(inputs.map { $0.code }).count == inputs.count else { throw AppError(message: "Choose 2–16 inputs with different codes, in the order you want to cycle them.") }
        return inputs
    }
    func show() {
        shown = true
        SettingsWindow.shared.show(.init(title: "Monitor inputs", detail: "Cycle a connected monitor to another input using the menu or a shortcut. The Mac’s picture may disappear; use the monitor’s own controls to return if it disconnects. Port lists do not tell us which inputs have another computer connected. Select the inputs you use; inactive ports cannot reliably be skipped automatically.", view: view, leave: { [self] in shown = false; controller.pageChanged = nil }))
        autoDetect()
    }
    private func autoDetect() {
        if shown && protocolChoice.indexOfSelectedItem != 2 && !SettingsWindow.shared.testing && !didAutoDetect && candidates.isEmpty && !controller.busy && !editedDisplay.isEmpty {
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
        detect.isEnabled = !controller.busy && (selected?.ddcAvailable == true || controlConnection != nil)
        save.isEnabled = !controller.busy
        worked.isHidden = controller.pendingConfirmation == nil
        failed.isHidden = controller.pendingConfirmation == nil
        worked.isEnabled = !controller.busy; failed.isEnabled = !controller.busy
        status.stringValue = controller.busy ? "Checking monitor… You can continue using your Mac." : controller.message
        status.textColor = controller.warning ? StatusColors.warning : controller.message.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor
        autoDetect()
    }
    @objc private func selectedMonitor() {
        guard listed.indices.contains(monitors.indexOfSelectedItem) else { return }
        let id = listed[monitors.indexOfSelectedItem].id
        guard editedDisplay != id else { return }
        controlConnection = nil
        editedDisplay = id; chosenProfile = nil; candidates = []; selectedCodes = []; renderInputs(); protocolChoice.selectItem(at: MonitorProfiles.match(listed[monitors.indexOfSelectedItem]).map { $0.alternate && $0.confidence != "suggested" } == true ? 1 : 0)
        refresh(); detectInputs()
    }
    @objc private func protocolChanged() {
        if protocolChoice.indexOfSelectedItem == 2 { connectionSettings(); return }
        lastDDCIndex = protocolChoice.indexOfSelectedItem
        controlConnection = nil
        chosenProfile = nil
        candidates = []; selectedCodes = []; renderInputs(); detectInputs()
    }
    private func detectInputs() {
        guard let display = listed.first(where: { $0.id == editedDisplay }), (display.ddcAvailable || controlConnection != nil), !controller.busy else { return }
        if controlConnection == nil, let profile = MonitorProfiles.match(display), profile.alternate, profile.confidence != "suggested", candidates.isEmpty, !didAutoDetect { protocolChoice.selectItem(at: 1) }
        let alternate = protocolChoice.indexOfSelectedItem == 1
        let original = candidates
        controller.inspect(editedDisplay, alternate: alternate, connection: controlConnection) { [weak self] result in
            guard let self, self.shown, self.editedDisplay == display.id,
                  (self.protocolChoice.indexOfSelectedItem == 1) == alternate, self.candidates == original else { return }
            switch result {
            case .success(let inspection):
                if self.controlConnection != nil {
                    if let inputs = inspection.transportInputs { self.candidates = MonitorCapabilities.merge(self.candidates, reported: inputs) }
                    self.controller.message = "✓ Control connection responded. " + (inspection.transportModel ?? "USB MCCS monitor") + ". Choose inputs in Model & inputs if no list is reported."
                    self.controller.warning = false; self.renderInputs(); self.refresh(); return
                }
                let codes = inspection.capabilities.map(MonitorCapabilities.inputs) ?? []
                let reportedModel = inspection.lgFirmwareModel ?? inspection.capabilities.flatMap(MonitorCapabilities.model)
                let profile = MonitorProfiles.entries.first { $0.name == self.chosenProfile && $0.vendor == display.vendor }
                    ?? (display.vendor == 7789 ? LGFirmwareProfiles.inputs(identity: inspection.lgIdentity, extended: inspection.lgExtendedIdentity) : nil)
                    ?? MonitorProfiles.match(display, reportedModel: reportedModel)
                let documented = profile.flatMap { $0.confidence != "suggested" && $0.alternate == alternate ? $0 : nil }
                if self.candidates.isEmpty, let profile, profile.confidence != "suggested", profile.alternate != alternate {
                    self.protocolChoice.selectItem(at: profile.alternate ? 1 : 0)
                    self.candidates = profile.inputs; self.chosenProfile = profile.name
                    self.controller.message = "Documented model: \(profile.name). Its input protocol and codes are selected; choose the ports to cycle."
                    self.controller.warning = false
                } else if !codes.isEmpty {
                    let reported = documented?.inputs ?? codes.map { MonitorInput(code: $0, name: MonitorInput.name($0, alternate: alternate)) }
                    self.candidates = MonitorCapabilities.merge(self.candidates, reported: reported)
                    self.controller.message = "✓ Input list checked. Documented model codes take priority. Existing selections and names kept; new ports are unchecked. Connected devices on other inputs: unknown."
                    self.controller.warning = false
                } else if !self.candidates.isEmpty {
                    self.controller.message = "Input list unavailable. Your input codes, names and selections are unchanged. Connected devices on other inputs: unknown."
                    self.controller.warning = false
                } else if let documented {
                    self.candidates = documented.inputs; self.chosenProfile = documented.name
                    self.controller.message = "Documented model: \(documented.name). Select the ports you use. Switching still needs confirmation on this connection."
                    self.controller.warning = false
                } else {
                    // Do not replace absent evidence with a plausible-looking USB-C code.
                    self.controller.message = "⚠ Exact model/input list unavailable. Open Model & inputs to choose your model. If it is unlisted, use manual setup. Check adapters if commands fail."
                    self.controller.warning = true
                }
                if documented?.readbackUnavailable == true {
                    self.controller.message += " This model has write-only input control; enable cycling from the last command if you want to use it."
                }
                if let firmware = inspection.lgFirmwareModel {
                    self.controller.message += " LG reports firmware family \(firmware); retail suffix unverified."
                }
                self.renderInputs()

            case .failure(let error): self.controller.message = error.localizedDescription; self.controller.warning = true
            }
            self.refresh()
        }
    }

    private func connectionSettings() {
        let page = MonitorConnectionView(frame:NSRect(x:0,y:0,width:572,height:310))
        var active = true
        let selectedDisplay = editedDisplay
        let kinds = ["msi-usb","mccs-usb","nec-lan","nec-serial"]
        let type = NSPopUpButton(frame:NSRect(x:0,y:260,width:572,height:30))
        type.addItems(withTitles:["MSI USB control", "USB MCCS (including supported Eizo models)", "NEC network connection", "NEC serial connection"])
        if let connection = controlConnection, let i = kinds.firstIndex(of:connection.kind) { type.selectItem(at:i) }
        let endpoint = NSTextField(frame:NSRect(x:0,y:215,width:572,height:28))
        endpoint.placeholderString = "USB identity below, IPv4 address, or /dev/cu. device"
        endpoint.stringValue = controlConnection?.endpoint ?? ""
        let devices = NSPopUpButton(frame:NSRect(x:0,y:175,width:572,height:28)); devices.addItem(withTitle:"Choose a detected USB monitor")
        var found: [MonitorUSBDevice] = []
        let message = NSTextField(wrappingLabelWithString:"USB needs the monitor’s upstream data cable. NEC uses port 7142 or 9600-baud serial. Select the monitor ID (usually 1).")
        message.frame = NSRect(x:0,y:70,width:572,height:65); message.textColor = .secondaryLabelColor
        let address = NSPopUpButton(frame:NSRect(x:410,y:138,width:162,height:28)); address.addItems(withTitles:(1...26).map { "Monitor ID \($0)" }); address.selectItem(at:(controlConnection?.address ?? 1)-1)
        let scan = SettingsActionButton(title:"Find USB monitors") { [weak self] in
            guard let self, !self.controller.busy, !SettingsWindow.shared.testing else { return }
            self.controller.usbDevices { result in
                guard active else { return }
                switch result {
                case .success(let values): found = values; devices.removeAllItems(); devices.addItem(withTitle:"Choose a detected USB monitor"); devices.addItems(withTitles:values.map { $0.name + " · " + $0.endpoint }); message.stringValue = values.isEmpty ? "No compatible USB control interface found. Check the upstream USB cable." : "Choose the USB device belonging to this monitor, then check the connection."
                case .failure(let error): message.stringValue = error.localizedDescription
                }
            }
        }
        scan.frame = NSRect(x:0,y:138,width:230,height:28)
        let check = SettingsActionButton(title:"Check connection & use") { [weak self] in
            guard let self, !self.controller.busy, !SettingsWindow.shared.testing else { return }
            var route = MonitorConnection(kind:kinds[type.indexOfSelectedItem],endpoint:endpoint.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),address:address.indexOfSelectedItem+1)
            if type.indexOfSelectedItem < 2, found.indices.contains(devices.indexOfSelectedItem-1) {
                let device = found[devices.indexOfSelectedItem-1]; route.kind = device.kind; route.endpoint = device.endpoint
            }
            guard route.valid else { message.stringValue = "Choose a USB monitor or enter the NEC connection address."; return }
            self.controller.inspect(selectedDisplay,alternate:false,connection:route) { result in
                guard active, self.editedDisplay == selectedDisplay else { return }
                switch result {
                case .success(let info):
                    route.model = info.transportModel
                    self.controlConnection = route; self.chosenProfile = nil; self.candidates = info.transportInputs ?? []; self.selectedCodes = []; self.renderInputs()
                    self.protocolChoice.selectItem(at:2); self.controller.message = "✓ Connection checked. Select inputs and save to enable it."; self.controller.warning = false
                    SettingsWindow.shared.goBack(); self.refresh()
                case .failure(let error): message.stringValue = "⚠ " + error.localizedDescription; message.textColor = StatusColors.warning
                }
            }
        }
        check.frame = NSRect(x:265,y:15,width:307,height:32)
        [type,endpoint,devices,address,message,scan,check].forEach { page.addSubview($0) }
        page.selectionChanged = {
            let usb = type.indexOfSelectedItem < 2
            endpoint.isHidden = usb; address.isHidden = usb
            devices.isHidden = !usb; scan.isHidden = !usb
            endpoint.placeholderString = type.indexOfSelectedItem == 2 ? "Monitor’s IPv4 address, e.g. 192.168.1.50" : "Serial device, e.g. /dev/cu.usbserial-…"
            message.stringValue = usb ? "Choose this monitor’s USB control device. Connect its upstream USB cable if it is missing." : "Enter this monitor’s connection address and monitor ID (usually 1)."
            message.textColor = .secondaryLabelColor
        }
        type.target = page; type.action = #selector(MonitorConnectionView.updateSelection)
        page.updateSelection()

        SettingsWindow.shared.show(.init(title:"Monitor control connection",detail:"Associate this control connection with the selected display. Checking reads identity and current input; it does not switch inputs. Standard DDC remains available in the previous page’s protocol menu.",view:page,leave: { active = false; if self.controlConnection == nil { self.protocolChoice.selectItem(at:self.lastDDCIndex) } }))
        if type.indexOfSelectedItem < 2 { scan.performClick(nil) }
    }

    @discardableResult private func saveSettings(back: Bool = true) -> Bool {
        do {
            guard UUID(uuidString: editedDisplay) != nil else { throw AppError(message: "Select a connected monitor first.") }
            var plan = MonitorInputPlan()
            plan.controlConnection = controlConnection
            plan.profileName = chosenProfile
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
        let hint = monitorInputs.busy ? "Working…" : monitorInputs.warning ? "⚠ See monitor settings" : monitorInputs.connected == nil && monitorInputs.plan.controlConnection == nil ? "Set up in Settings" : monitorInputs.shortcutActive ? monitorInputs.plan.shortcut.title : monitorInputs.plan.inputs.count >= 2 ? "Shortcut off" : "Choose inputs in Settings"
        label(item, "Cycle monitor input", hint: hint, hintColor: monitorInputs.warning ? StatusColors.warning : .secondaryLabelColor)
        item.toolTip = monitorInputs.message
    }
    @objc func cycleMonitorInput() { monitorInputs.cycle() }
    @objc func monitorInputSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.monitorInputSettings() }; return }
        MonitorInputPage(monitorInputs).show()
    }
}
