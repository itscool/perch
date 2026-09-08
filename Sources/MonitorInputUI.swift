import AppKit
import Carbon

final class MonitorInputPage: NSObject {
    let controller: MonitorInputController
    let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 490))
    let monitors = NSPopUpButton(), protocolChoice = NSPopUpButton()
    let currentChoice = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "")
    let currentStatus = NSTextField(labelWithString: "Current input unknown")
    let statusScroll = NSScrollView(frame: NSRect(x: 4,y: 374,width: 564,height: 50))
    var candidates: [MonitorInput] = []
    var selectedCodes = Set<UInt16>()
    let inputList = NSScrollView(frame: NSRect(x: 0,y: 155,width: 572,height: 118))
    let blind = NSButton(checkboxWithTitle: "Allow one cycle from an input I confirm when readback is unavailable", target: nil, action: nil)
    let enabled = NSButton(checkboxWithTitle: "Enable monitor shortcut", target: nil, action: nil)
    let keys = NSPopUpButton()
    var modifiers: [(NSButton,UInt32)] = []
    var detect: SettingsActionButton!
    var save: SettingsActionButton!
    var worked: SettingsActionButton!
    var failed: SettingsActionButton!
    private var cycleButton: SettingsActionButton!
    private var identifyButton: SettingsActionButton!
    private var identificationNeeded = false
    private var undoPlan: MonitorInputPlan?
    private var undoButton: SettingsActionButton!
    private var lastDDCIndex = 0
    private var controlConnection: MonitorConnection?
    private var chosenProfile: String?
    private var listed: [MonitorDescriptor] = []
    private var editedDisplay = ""
    private var shown = false
    private var didAutoDetect = false
    private let editingSetup: Bool
    private var draftMessage = "Review the connection method and available inputs. Detection or an exact-model preset can help fill in the list."
    private var draftWarning = false
    private var message: String {
        get { editingSetup ? draftMessage : controller.message }
        set { if editingSetup { draftMessage = newValue } else { controller.message = newValue } }
    }
    private var warning: Bool {
        get { editingSetup ? draftWarning : controller.warning }
        set { if editingSetup { draftWarning = newValue } else { controller.warning = newValue } }
    }
    private var setupSaved = false
    private var setupClosed: ((Bool, MonitorInputPlan) -> Void)?
    private let originalPlan: MonitorInputPlan
    init(_ controller: MonitorInputController, editingSetup: Bool = false) {
        self.controller = controller; self.editingSetup = editingSetup
        originalPlan = controller.plan
        super.init()
        func label(_ text: String, _ frame: NSRect) {
            let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.frame = frame; view.addSubview(label)
        }
        monitors.frame = NSRect(x: 0,y: 452,width: 350,height: 30); monitors.target = self; monitors.action = #selector(selectedMonitor)
        protocolChoice.addItems(withTitles: ["Standard DDC", "LG alternate input control", "USB / NEC connection…"])
        protocolChoice.frame = NSRect(x: 360,y: 452,width: 212,height: 30)
        protocolChoice.target = self; protocolChoice.action = #selector(protocolChanged)
        protocolChoice.isHidden = !editingSetup
        if !editingSetup {
            let setup = SettingsActionButton(title: "Connection & inputs…") { [weak self] in self?.editSetup() }
            setup.frame = protocolChoice.frame; view.addSubview(setup)
        }
        currentStatus.frame = NSRect(x: 4,y: 425,width: 564,height: 22)
        currentStatus.font = .systemFont(ofSize: 12, weight: .semibold); view.addSubview(currentStatus)
        status.frame = NSRect(x: 4,y: 374,width: 564,height: 50); status.font = .systemFont(ofSize: 12)
        statusScroll.hasVerticalScroller = true; statusScroll.autohidesScrollers = true; statusScroll.drawsBackground = false
        statusScroll.scrollerStyle = .legacy
        statusScroll.documentView = status
        worked = SettingsActionButton(title: "Yes, it switched") { [weak controller] in controller?.confirmSwitch(true) }
        failed = SettingsActionButton(title: "No, troubleshoot") { [weak controller] in controller?.confirmSwitch(false) }
        worked.frame = NSRect(x: 0,y: 345,width: 230,height: 26)
        failed.frame = NSRect(x: 240,y: 345,width: 230,height: 26)
        view.addSubview(worked); view.addSubview(failed)
        currentChoice.frame = NSRect(x:0,y:345,width:572,height:26)
        currentChoice.target = self; currentChoice.action = #selector(currentChosen)
        view.addSubview(currentChoice)
        detect = SettingsActionButton(title: "Detect input list") { [weak self] in
            guard let self, self.editingSetup else { return }
            self.detectInputs(replace: true)
        }
        detect.frame = NSRect(x: 0,y: 308,width: 175,height: 30)
        detect.isHidden = !editingSetup
        let recheck = SettingsActionButton(title: "Read current input") { [weak self] in self?.readCurrentInput() }
        recheck.frame = NSRect(x: 185,y: 308,width: 180,height: 30)
        label("Checked inputs cycle in order. Unchecked inputs stay saved.", NSRect(x: 4,y: editingSetup ? 259 : 278,width: 564,height: 26))
        inputList.hasVerticalScroller = true; inputList.autohidesScrollers = false; inputList.borderType = .bezelBorder
        inputList.scrollerStyle = .legacy
        let custom = SettingsActionButton(title: "Model & inputs…") { [weak self] in self?.editInputs() }
        custom.frame = NSRect(x: 375,y: 308,width: 197,height: 30)
        custom.isHidden = !editingSetup
        if !editingSetup { recheck.frame = NSRect(x: 0, y: 308, width: 572, height: 30) }
        blind.frame = NSRect(x: 0,y: 121,width: 572,height: 28)
        enabled.frame = NSRect(x: 0,y: 89,width: 280,height: 28)
        keys.addItems(withTitles: PanicShortcut.keys.map { $0.0 }); keys.frame = NSRect(x: 465,y: 55,width: 107,height: 28)
        for (index, pair) in [("Control",controlKey),("Option",optionKey),("Shift",shiftKey),("Command",cmdKey)].enumerated() {
            let box = NSButton(checkboxWithTitle: pair.0, target: nil, action: nil)
            box.frame = NSRect(x: CGFloat(index*112),y: 55,width: 112,height: 28)
            modifiers.append((box,UInt32(pair.1))); view.addSubview(box)
        }
        save = SettingsActionButton(title: "Save") { [weak self] in
            guard let self, self.editingSetup, self.saveSettings(back: false) else { return }
            self.setupSaved = true
            SettingsWindow.shared.goBack()
        }
        save.frame = NSRect(x: 402,y: 12,width: 170,height: 32)
        save.isHidden = !editingSetup
        if editingSetup { save.keyEquivalent = "\r" }
        let cycle = SettingsActionButton(title: "Cycle input now") { [weak self] in
            guard let self, !self.editingSetup else { return }
            self.controller.cycle()
        }
        cycleButton = cycle
        identifyButton = SettingsActionButton(title:"Identify input…") { [weak self] in self?.identifyInput() }
        identifyButton.frame = NSRect(x:0,y:12,width:278,height:32); view.addSubview(identifyButton)
        cycle.frame = NSRect(x: 288,y: 12,width: 284,height: 32)
        [monitors,protocolChoice,statusScroll,detect,recheck,custom,inputList,blind,enabled,keys,save,cycle].forEach { view.addSubview($0) }
        lastDDCIndex = controller.plan.alternate ? 1 : 0
        controlConnection = controller.plan.controlConnection
        chosenProfile = controller.plan.profileName
        editedDisplay = controller.plan.display
        candidates = controller.plan.availableInputs ?? controller.plan.inputs; selectedCodes = Set(controller.plan.inputs.map { $0.code })
        renderInputs()
        protocolChoice.selectItem(at: controlConnection != nil ? 2 : controller.plan.alternate ? 1 : 0)
        blind.state = controller.plan.allowUnconfirmedCycle ? .on : .off
        enabled.state = controller.plan.shortcut.enabled ? .on : .off
        keys.selectItem(at: PanicShortcut.keys.firstIndex { $0.1 == controller.plan.shortcut.key } ?? 0)
        for (box, flag) in modifiers { box.state = controller.plan.shortcut.modifiers & flag != 0 ? .on : .off }
        for box in [blind,enabled] + modifiers.map({ $0.0 }) { box.target = self; box.action = #selector(settingChanged) }
        keys.target = self; keys.action = #selector(settingChanged)
        undoButton = SettingsActionButton(title:"Undo setup change") { [weak self] in
            guard let self, let old = self.undoPlan else { return }
            do { try self.controller.save(old); self.loadSaved(); self.undoPlan = nil; self.undoButton.isHidden = true } catch { self.status.stringValue = error.localizedDescription }
        }
        undoButton.frame = NSRect(x:300,y:89,width:170,height:28); undoButton.isHidden = true; view.addSubview(undoButton)
        if editingSetup {
            [blind, enabled, keys, cycle].forEach { $0.isHidden = true }
            modifiers.forEach { $0.0.isHidden = true }
            let cancel = SettingsActionButton(title: "Cancel") { SettingsWindow.shared.goBack() }
            cancel.keyEquivalent = "\u{1b}"
            cancel.frame = NSRect(x: 220, y: 12, width: 170, height: 32); view.addSubview(cancel)
            statusScroll.frame = NSRect(x: 4, y: 335, width: 564, height: 75)
            for button in [detect!, recheck, custom] { button.frame.origin.y = 292 }
            inputList.frame = NSRect(x: 0, y: 80, width: 572, height: 174)
            label("Saving this setup will not switch the monitor.", NSRect(x: 4, y: 46, width: 564, height: 30))
        }
        renderInputs(); refresh()
    }
    @discardableResult func editSetup() -> MonitorInputPage {
        let editor = MonitorInputPage(controller, editingSetup: true)
        editor.editedDisplay = editedDisplay
        editor.protocolChoice.selectItem(at: protocolChoice.indexOfSelectedItem)
        editor.setupClosed = { [weak self] saved, previous in
            guard let self else { return }
            if saved {
                self.loadSaved(); self.undoPlan = previous; self.undoButton.isHidden = previous.display.isEmpty
                self.message = "✓ Monitor setup saved." + (previous.shortcut.enabled && !self.controller.plan.shortcut.enabled ? " The shortcut is off because fewer than two inputs are selected." : "")
                self.warning = false
            }
            self.refresh()
        }
        editor.show()
        return editor
    }
    @objc private func settingChanged() {
        if editingSetup { refresh() }
        else if saveSettings(back: false) { undoPlan = nil; undoButton.isHidden = true }
    }
    private func saveDetection() {
        if !editingSetup { _ = saveSettings(back: false, preserveMessage: true) }
        else { message += " Preview only. Save keeps this setup; Cancel keeps your previous setup." }
    }
    private func loadSaved() {
        let plan = controller.plan
        candidates = plan.availableInputs ?? plan.inputs; selectedCodes = Set(plan.inputs.map { $0.code })
        controlConnection = plan.controlConnection; chosenProfile = plan.profileName; editedDisplay = plan.display
        protocolChoice.selectItem(at:controlConnection != nil ? 2 : plan.alternate ? 1 : 0)
        enabled.state = plan.shortcut.enabled ? .on : .off; blind.state = plan.allowUnconfirmedCycle ? .on : .off
        keys.selectItem(at:PanicShortcut.keys.firstIndex { $0.1 == plan.shortcut.key } ?? 0)
        for (box,flag) in modifiers { box.state = plan.shortcut.modifiers & flag != 0 ? .on : .off }
        renderInputs()
    }
    @objc private func currentChosen() {
        if let code = currentChoice.selectedItem?.representedObject as? UInt16 {
            blind.state = .on
            if saveSettings(back: false) { controller.useCurrentInput(code) }
            currentChoice.selectItem(at: 0)
        }
    }
    private func readCurrentInput() {
        guard !editedDisplay.isEmpty, !controller.busy else { return }
        controller.readInput(editedDisplay,mode:controlConnection?.argument ?? (protocolChoice.indexOfSelectedItem == 1 ? "lg" : "standard")) { [weak self] result in
            guard let self, self.shown else { return }
            switch result {
            case .success(let info):
                if let code = info.current, code > 0 {
                    self.identificationNeeded = false
                    self.message = "Current input reported: " + (self.candidates.first { $0.code == code }?.name ?? "code \(code)")
                    self.warning = false
                } else {
                    self.identificationNeeded = true
                    self.message = "Current input unavailable. Show a named input directly, or confirm what is showing before each cycle."
                    self.warning = true
                }
            case .failure(let error): self.identificationNeeded = true; self.message = error.localizedDescription; self.warning = true
            }
            self.refresh()
        }
    }
    private func identifyInput() {
        guard identificationNeeded, !controller.busy, !candidates.isEmpty else { return }
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:470))
        var active = true, tested: UInt16? = nil
        let cancellation = MonitorProbeCancellation()
        let choose = NSPopUpButton(frame:NSRect(x:0,y:165,width:572,height:30))
        let inputs = candidates; choose.addItems(withTitles:inputs.map { $0.name })
        let text = NSTextField(wrappingLabelWithString:"Or choose an input here and click Test selected input. When the monitor shows this Mac, save it below. This mapping does not expire.")
        text.frame = NSRect(x:0,y:78,width:572,height:75); text.textColor = .secondaryLabelColor
        let accept = SettingsActionButton(title:"Save as this Mac’s input") { [weak self] in
            guard let self, let code = tested, !self.controller.busy else { return }
            self.blind.state = .on; self.settingChanged()
            var plan = self.controller.plan; plan.macInput = code
            plan.macInputConnection = self.controlConnection?.argument ?? self.controller.connected?.connection
            do { try self.controller.save(plan) } catch { text.stringValue = error.localizedDescription; return }
            self.message = "Saved: this Mac uses " + (inputs.first { $0.code == code }?.name ?? "this input") + ". Use Show beside a destination to switch to it; this mapping does not expire."
            self.warning = false; SettingsWindow.shared.goBack(); self.refresh()
        }
        accept.frame = NSRect(x:215,y:15,width:357,height:32); accept.isEnabled = false
        let test = SettingsActionButton(title:"Test selected input") { [weak self] in
            guard let self, active, !self.controller.busy, !SettingsWindow.shared.testing else { return }
            let input = inputs[choose.indexOfSelectedItem]; tested = nil; accept.isEnabled = false
            self.controller.testInput(input,display:self.editedDisplay,alternate:self.protocolChoice.indexOfSelectedItem == 1,connection:self.controlConnection) { sent in
                guard active else { return }
                if sent { tested = input.code; accept.isEnabled = true; text.stringValue = "Command sent for " + input.name + ". Confirm only if the monitor is now showing this Mac. A connected display alone is not proof." }
                else { text.stringValue = self.message }
            }
        }
        test.frame = NSRect(x:0,y:15,width:205,height:32)
        let results = NSTextView(frame: NSRect(x:0,y:0,width:548,height:190))
        results.isEditable = false; results.isSelectable = true; results.font = .systemFont(ofSize:12)
        results.textContainer?.widthTracksTextView = true; results.autoresizingMask = .width; results.isVerticallyResizable = true
        results.string = "Ready to try the known inputs. Perch will look for this monitor disconnecting and reconnecting to this Mac. If that does not identify a port, you can confirm the picture yourself."
        let scroll = NSScrollView(frame:NSRect(x:0,y:208,width:572,height:198))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = results
        let stop = SettingsActionButton(title:"Stop test") { cancellation.cancel() }
        stop.frame = NSRect(x:390,y:426,width:182,height:32); stop.isEnabled = false
        weak var automatic: SettingsActionButton?
        let automaticButton = SettingsActionButton(title:"Find this Mac automatically") { [weak self] in
            guard let self, active, !self.controller.busy, !SettingsWindow.shared.testing else { return }
            tested = nil; accept.isEnabled = false; test.isEnabled = false; automatic?.isEnabled = false; stop.isEnabled = true
            self.controller.probeInputs(inputs, display:self.editedDisplay,
                mode:self.controlConnection?.argument ?? (self.protocolChoice.indexOfSelectedItem == 1 ? "lg" : "standard"),
                returnInput:self.controller.plan.macInputConnection == (self.controlConnection?.argument ?? self.controller.connected?.connection) ? self.controller.plan.macInput : nil,
                cancellation:cancellation, progress: { value in if active { results.string = value } }) { result in
                    guard active else { return }; results.string = result.lines.joined(separator:"\n")
                    stop.isEnabled = false; test.isEnabled = true
                    if let input = result.suggested, result.showing?.code == input.code {
                        choose.selectItem(at:inputs.firstIndex { $0.code == input.code } ?? 0); tested = input.code; accept.isEnabled = true
                        text.stringValue = "The connection changes suggest " + input.name + ". Confirm below only if this monitor now shows this Mac."
                    } else { text.stringValue = "The test could not identify a unique input. Choose a port, test it, and confirm the picture. Use the monitor’s Input button to restore this Mac if needed." }
                }
        }
        automatic = automaticButton
        automaticButton.frame = NSRect(x:0,y:426,width:378,height:32)
        [choose,text,accept,test,scroll,automaticButton,stop].forEach { page.addSubview($0) }
        SettingsWindow.shared.show(.init(title:"Identify this Mac’s input",detail:"This briefly changes inputs on the selected monitor. Keep this window on the laptop screen. Perch will try to bring the picture back; the monitor’s Input button is your fallback. Stop or Back ends the test.",view:page,leave:{active=false; cancellation.cancel()}))
    }
    private func renderInputs() {
        let selectedCurrent = currentChoice.selectedItem?.representedObject as? UInt16
        currentChoice.removeAllItems(); currentChoice.addItem(withTitle:"Current input: detect automatically, or choose what is showing…")
        for input in candidates { currentChoice.addItem(withTitle:"Currently showing: " + input.name); currentChoice.lastItem?.representedObject = input.code }
        if let selectedCurrent, let index = candidates.firstIndex(where: { $0.code == selectedCurrent }) { currentChoice.selectItem(at:index+1) }

        let document = NSView(frame: NSRect(x: 0,y: 0,width: 548,height: max(inputList.contentSize.height,CGFloat(candidates.count*32))))
        if candidates.isEmpty {
            let label = NSTextField(labelWithString: editingSetup ? "Use Detect input list or Model & inputs to add inputs." : "Choose Connection & inputs to set up this monitor.")
            label.textColor = .secondaryLabelColor; label.frame = NSRect(x: 8,y: document.frame.height-32,width: 525,height: 25); document.addSubview(label)
        }
        for (index, input) in candidates.enumerated() {
            let y = document.frame.height-CGFloat((index+1)*32)
            let check = NSButton(checkboxWithTitle: input.name,target: self,action: #selector(inputChecked(_:)))
            check.tag = index; check.state = selectedCodes.contains(input.code) ? .on : .off
            check.frame = NSRect(x: 8,y: y,width: 298,height: 30); document.addSubview(check)
            let show = SettingsActionButton(title: "Show this input") { [weak self] in
                guard let self, !self.editingSetup else { return }
                self.controller.cycle(destination: input)
            }
            show.frame = NSRect(x: 310,y: y,width: 124,height: 28)
            show.identifier = NSUserInterfaceItemIdentifier("monitor.showInput")
            show.isEnabled = !editingSetup && controller.canSwitch
            show.isHidden = editingSetup
            show.toolTip = "Show \(input.name). This may hide this Mac; use the monitor’s buttons to return."
            document.addSubview(show)
            for (delta,x,title) in [(-1,440.0,"↑"),(1,490.0,"↓")] {
                let button = SettingsActionButton(title: title) { [weak self] in
                    guard let self, self.candidates.indices.contains(index+delta) else { return }
                    self.candidates.swapAt(index,index+delta); self.renderInputs(); self.settingChanged()
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
        settingChanged()
    }
    private func editInputs() {
        guard editingSetup else { return }
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
                self?.candidates = values; self?.selectedCodes.formIntersection(values.map { $0.code }); self?.renderInputs(); self?.settingChanged()
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
        SettingsWindow.shared.show(.init(title: "Edit monitor inputs", detail: "Choose a preset for your exact model, or enter decimal code = name on each line. Use this input list returns your edits to the setup preview; Save there keeps them. Cancel keeps the draft list as it was. Standard examples: 17 = HDMI 1, 18 = HDMI 2, 15 = DisplayPort. USB-C and LG alternate codes depend on the exact model. Editing this list does not switch inputs.", view: page, backTitle: "Cancel"))
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
        SettingsWindow.shared.show(.init(title: "Monitor compatibility test", detail: "One command per click. Back cancels the test; confirmed mappings are added to the editor; choose Use this input list to apply them. Candidates are reports from other models, not a promise of compatibility.", view: page, leave: { active = false }))
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
        let previousCallback = editingSetup ? controller.pageChanged : nil
        SettingsWindow.shared.show(.init(title: editingSetup ? "Monitor connection & inputs" : "Monitor inputs",
            detail: editingSetup ? "Edit this monitor’s connection and input list as one setup. Checks only read the monitor; Save keeps the proposed setup and Cancel preserves the working one. The saved setup remains active until you save." : "Input selections and shortcut choices save automatically. Switching may hide this Mac’s picture; use the monitor’s buttons to return.",
            view: view, leave: { [self] in
                shown = false; controller.pageChanged = previousCallback
                setupClosed?(setupSaved, originalPlan)
            }, backTitle: editingSetup ? "Cancel" : nil))
        controller.pageChanged = { [weak self] in self?.refresh() }
        refresh()
        if !editingSetup && !candidates.isEmpty && !SettingsWindow.shared.testing { readCurrentInput() } else { autoDetect() }
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
        monitors.isEnabled = !controller.busy && !editingSetup
        protocolChoice.isEnabled = !controller.busy
        detect.isEnabled = !controller.busy && (selected?.ddcAvailable == true || controlConnection != nil)
        save.isEnabled = !controller.busy
        cycleButton.isEnabled = !editingSetup && controller.canCycle
        cycleButton.toolTip = "Read the current input, then switch to the next checked input."
        inputList.documentView?.subviews.compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue == "monitor.showInput" }.forEach { $0.isEnabled = !editingSetup && controller.canSwitch }
        identifyButton.isHidden = editingSetup || !identificationNeeded
        identifyButton.isEnabled = !controller.busy
        currentChoice.isEnabled = !controller.busy && !editingSetup
        currentChoice.isHidden = editingSetup || !identificationNeeded || controller.pendingConfirmation != nil
        worked.isHidden = editingSetup || controller.pendingConfirmation == nil
        failed.isHidden = editingSetup || controller.pendingConfirmation == nil
        worked.isEnabled = !controller.busy; failed.isEnabled = !controller.busy
        let nextMessage = controller.busy ? "Checking monitor… You can continue using your Mac." : message
        let messageChanged = status.stringValue != nextMessage
        status.stringValue = nextMessage
        currentStatus.stringValue = editingSetup ? "Setup preview · not saved" : controller.currentSummary
        status.textColor = warning ? StatusColors.warning : message.hasPrefix("✓") ? StatusColors.success : .secondaryLabelColor
        let width: CGFloat = 548
        let height = ceil(status.attributedStringValue.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
        let newFrame = NSRect(x: 0, y: 0, width: width, height: max(statusScroll.contentSize.height, height))
        statusScroll.autohidesScrollers = height <= statusScroll.contentSize.height
        if status.frame != newFrame || messageChanged {
            status.frame = newFrame
            statusScroll.tile()
            statusScroll.contentView.scroll(to: .zero)
            statusScroll.reflectScrolledClipView(statusScroll.contentView)
        }
        autoDetect()
    }
    @objc private func selectedMonitor() {
        guard !editingSetup, listed.indices.contains(monitors.indexOfSelectedItem) else { return }
        let id = listed[monitors.indexOfSelectedItem].id
        guard editedDisplay != id else { return }
        var selected = controller.savedPlan(for: id) ?? MonitorInputPlan()
        selected.display = id
        if controller.savedPlan(for: id) == nil { selected.alternate = MonitorProfiles.match(listed[monitors.indexOfSelectedItem]).map { $0.alternate && $0.confidence != "suggested" } == true }
        do { try controller.save(selected) }
        catch { message = error.localizedDescription; warning = true; refresh(); return }
        undoButton.isHidden = true
        loadSaved(); refresh(); detectInputs()
    }
    @objc private func protocolChanged() {
        guard editingSetup else { return }
        if protocolChoice.indexOfSelectedItem == 2 { connectionSettings(); return }
        lastDDCIndex = protocolChoice.indexOfSelectedItem
        controlConnection = nil
        chosenProfile = nil
        message = "Checking the proposed connection. Your saved setup is unchanged until Save."
        refresh(); detectInputs()
    }
    private func detectInputs(replace: Bool = false) {
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
                    if replace && inspection.transportInputs == nil { self.message = "No reliable fresh input list was returned. Your settings are unchanged."; self.warning = true; self.refresh(); return }
                    if let inputs = inspection.transportInputs { self.candidates = replace ? inputs : MonitorCapabilities.merge(self.candidates, reported: inputs); if replace { self.selectedCodes.formIntersection(inputs.map { $0.code }) } }
                    self.message = "✓ Control connection responded. " + (inspection.transportModel ?? "USB MCCS monitor") + ". Choose inputs in Model & inputs if no list is reported."
                    self.warning = false; self.renderInputs(); self.saveDetection(); self.refresh(); return
                }
                let codes = inspection.capabilities.map(MonitorCapabilities.inputs) ?? []
                let reportedModel = inspection.lgFirmwareModel ?? inspection.capabilities.flatMap(MonitorCapabilities.model)
                let profile = (replace ? nil : MonitorProfiles.entries.first { $0.name == self.chosenProfile && $0.vendor == display.vendor })
                    ?? (display.vendor == 7789 ? LGFirmwareProfiles.inputs(identity: inspection.lgIdentity, extended: inspection.lgExtendedIdentity) : nil)
                    ?? MonitorProfiles.match(display, reportedModel: reportedModel)
                if replace {
                    let fresh = profile.flatMap { $0.confidence != "suggested" ? $0.inputs : nil } ?? (codes.isEmpty ? nil : codes.map { MonitorInput(code:$0,name:MonitorInput.name($0)) })
                    guard let fresh else { self.message = "No reliable fresh input settings were returned. Your settings are unchanged."; self.warning = true; self.refresh(); return }
                    self.candidates = fresh; self.selectedCodes.formIntersection(fresh.map { $0.code }); self.chosenProfile = profile?.confidence != "suggested" ? profile?.name : nil
                    if let profile, profile.confidence != "suggested" { self.protocolChoice.selectItem(at:profile.alternate ? 1 : 0) }
                    self.message = "Detected inputs are ready to review. Choose which inputs to include in the cycle."; self.warning = false
                    self.renderInputs(); self.currentChoice.selectItem(at:0); self.saveDetection(); self.refresh(); return
                }
                let documented = profile.flatMap { $0.confidence != "suggested" && $0.alternate == alternate ? $0 : nil }
                if self.candidates.isEmpty, let profile, profile.confidence != "suggested", profile.alternate != alternate {
                    self.protocolChoice.selectItem(at: profile.alternate ? 1 : 0)
                    self.candidates = profile.inputs; self.chosenProfile = profile.name
                    self.message = "Documented model: \(profile.name). Its input protocol and codes are selected; choose the ports to cycle."
                    self.warning = false
                } else if !codes.isEmpty {
                    let reported = documented?.inputs ?? codes.map { MonitorInput(code: $0, name: MonitorInput.name($0, alternate: alternate)) }
                    self.candidates = MonitorCapabilities.merge(self.candidates, reported: reported)
                    self.message = "✓ Input list checked. Documented model codes take priority. Existing selections and names kept; new ports are unchecked. Connected devices on other inputs: unknown."
                    self.warning = false
                } else if !self.candidates.isEmpty {
                    self.message = "Input list unavailable. Your input codes, names and selections are unchanged. Connected devices on other inputs: unknown."
                    self.warning = false
                } else if let documented {
                    self.candidates = documented.inputs; self.chosenProfile = documented.name
                    self.message = "Documented model: \(documented.name). Select the ports you use. Switching still needs confirmation on this connection."
                    self.warning = false
                } else {
                    // Do not replace absent evidence with a plausible-looking USB-C code.
                    self.message = "⚠ Exact model/input list unavailable. Open Model & inputs to choose your model. If it is unlisted, use manual setup. Check adapters if commands fail."
                    self.warning = true
                }
                if documented?.readbackUnavailable == true {
                    self.message += " This model has write-only control. Choose a named input directly, or confirm its input before each cycle."
                }
                if let firmware = inspection.lgFirmwareModel {
                    self.message += " LG reports firmware family \(firmware); retail suffix unverified."
                }
                self.renderInputs(); self.saveDetection()

            case .failure(let error): self.message = error.localizedDescription; self.warning = true
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
        func proposedConnection() -> MonitorConnection {
            var route = MonitorConnection(kind:kinds[type.indexOfSelectedItem],endpoint:endpoint.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),address:address.indexOfSelectedItem+1)
            if type.indexOfSelectedItem < 2, found.indices.contains(devices.indexOfSelectedItem-1) {
                let device = found[devices.indexOfSelectedItem-1]; route.kind = device.kind; route.endpoint = device.endpoint
            }
            return route
        }
        var checked: (MonitorConnection, MonitorInspection)?
        let use = SettingsActionButton(title: "Use this connection") { [weak self] in
            guard let self, !self.controller.busy, let (route, info) = checked, route == proposedConnection() else {
                message.stringValue = "Check the current connection details before using them."; return
            }
            self.controlConnection = route; self.controlConnection?.model = info.transportModel
            self.chosenProfile = nil
            if let inputs = info.transportInputs { self.candidates = inputs; self.selectedCodes.formIntersection(inputs.map { $0.code }) }
            self.renderInputs(); self.protocolChoice.selectItem(at: 2)
            self.message = "Connection added to the setup preview. Save keeps it; Cancel preserves your previous setup."
            self.warning = false
            self.settingChanged(); SettingsWindow.shared.goBack(); self.refresh()
        }
        use.isEnabled = false; use.frame = NSRect(x: 285, y: 15, width: 287, height: 32)
        let check = SettingsActionButton(title:"Check connection") { [weak self, weak use] in
            guard let self, !self.controller.busy else { return }
            let route = proposedConnection()
            checked = nil; use?.isEnabled = false
            guard route.valid else { message.stringValue = "Choose a USB monitor or enter the NEC connection address."; return }
            self.controller.inspect(selectedDisplay,alternate:false,connection:route) { result in
                guard active, self.editedDisplay == selectedDisplay, route == proposedConnection() else { return }
                switch result {
                case .success(let info):
                    checked = (route, info); use?.isEnabled = true
                    message.stringValue = "✓ The connection responded. Use this connection adds it to your setup preview; nothing has been saved or switched."
                    message.textColor = StatusColors.success
                case .failure(let error): message.stringValue = "⚠ " + error.localizedDescription; message.textColor = StatusColors.warning
                }
            }
        }
        check.frame = NSRect(x: 0, y: 15, width: 275, height: 32)
        [type,endpoint,devices,address,message,scan,check,use].forEach { page.addSubview($0) }
        page.selectionChanged = { [weak use] in
            checked = nil; use?.isEnabled = false
            let usb = type.indexOfSelectedItem < 2
            endpoint.isHidden = usb; address.isHidden = usb
            devices.isHidden = !usb; scan.isHidden = !usb
            endpoint.placeholderString = type.indexOfSelectedItem == 2 ? "Monitor’s IPv4 address, e.g. 192.168.1.50" : "Serial device, e.g. /dev/cu.usbserial-…"
            message.stringValue = usb ? "Choose this monitor’s USB control device. Connect its upstream USB cable if it is missing." : "Enter this monitor’s connection address and monitor ID (usually 1)."
            message.textColor = .secondaryLabelColor
        }
        type.target = page; type.action = #selector(MonitorConnectionView.updateSelection)
        page.updateSelection()

        SettingsWindow.shared.show(.init(title:"Monitor control connection",detail:"Check reads identity and current input without saving or switching. Use this connection returns to your setup preview. Save on that page keeps the setup; Cancel here leaves the preview unchanged.",view:page,leave: { active = false; if self.controlConnection == nil { self.protocolChoice.selectItem(at:self.lastDDCIndex) } }, backTitle: "Cancel"))
        if type.indexOfSelectedItem < 2 { scan.performClick(nil) }
    }

    @discardableResult private func saveSettings(back: Bool = true, preserveMessage: Bool = false) -> Bool {
        do {
            guard UUID(uuidString: editedDisplay) != nil else { throw AppError(message: "Select a connected monitor first.") }
            var plan = controller.plan
            if plan.display != editedDisplay || plan.controlConnection != controlConnection || plan.alternate != (protocolChoice.indexOfSelectedItem == 1) { plan.macInput = nil; plan.macInputConnection = nil }
            plan.controlConnection = controlConnection
            plan.availableInputs = candidates
            if let code = plan.macInput, !candidates.contains(where: { $0.code == code }) { plan.macInput = nil; plan.macInputConnection = nil }
            plan.profileName = chosenProfile
            plan.display = editedDisplay; plan.alternate = protocolChoice.indexOfSelectedItem == 1
            plan.inputs = candidates.filter { selectedCodes.contains($0.code) }; plan.allowUnconfirmedCycle = blind.state == .on
            if plan.inputs.count < 2 { enabled.state = .off }
            let mask = modifiers.filter { $0.0.state == .on }.reduce(UInt32(0)) { $0 | $1.1 }
            plan.shortcut = PanicShortcut(key: PanicShortcut.keys[keys.indexOfSelectedItem].1,modifiers: mask,enabled: enabled.state == .on)
            try controller.save(plan, preserveMessage: preserveMessage)
            if back { SettingsWindow.shared.goBack() }
            return true
        } catch { message = "⚠ Not saved: " + error.localizedDescription; warning = true; refresh(); return false }
    }
}

extension AppDelegate {
    var monitorInputMenuEnabled: Bool { !monitorInputs.checkingDisplays && !monitorInputs.busy && !monitorInputs.groups.busy }
    func refreshMonitorInputItem() {
        guard let item = monitorInputItem else { return }
        let shortcut = monitorInputs.groups.active?.shortcut ?? monitorInputs.plan.shortcut
        (item.view as? MenuRowView)?.shortcutHint = shortcut.enabled ? shortcut.menuTitle : ""
        item.isEnabled = monitorInputMenuEnabled
        if monitorInputs.checkingDisplays {
            item.action = #selector(cycleMonitorInput)
            label(item, "Cycle monitor input", hint: "Checking monitors…")
            item.toolTip = "Checking connected displays before making monitor controls available. This does not switch inputs."
            return
        }
        if let group = monitorInputs.groups.active {
            let needsSettings = !monitorInputs.groups.canCycle || monitorInputs.groups.hasAttention
            item.action = needsSettings ? #selector(monitorGroupSettings) : #selector(cycleMonitorInput)
            label(item, "Cycle monitor input", hint: monitorInputs.busy || monitorInputs.groups.busy ? "Working…" : needsSettings ? "See display group settings" : "\(group.name) · \(group.members.count) display\(group.members.count == 1 ? "" : "s")", hintColor: monitorInputs.groups.hasAttention ? StatusColors.warning : .secondaryLabelColor)
            item.toolTip = monitorInputs.groups.message
            return
        }
        item.action = !monitorInputs.canCycle || monitorInputs.warning ? #selector(monitorInputSettings) : #selector(cycleMonitorInput)
        let hint = monitorInputs.busy ? "Working…" : monitorInputs.warning ? "⚠ See monitor settings" : monitorInputs.connected == nil && monitorInputs.plan.controlConnection == nil ? "Set up in Settings" : monitorInputs.shortcutActive ? "" : monitorInputs.plan.inputs.count >= 2 ? (shortcut.enabled ? "Shortcut unavailable" : "Shortcut off") : "Choose inputs in Settings"
        label(item, "Cycle monitor input", hint: hint, hintColor: monitorInputs.warning ? StatusColors.warning : .secondaryLabelColor)
        item.toolTip = monitorInputs.message
    }
    @objc func cycleMonitorInput() { if monitorInputs.groups.active != nil { monitorInputs.groups.cycle() } else { monitorInputs.cycle() } }
    @objc func monitorInputSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.monitorInputSettings() }; return }
        MonitorInputPage(monitorInputs).show()
    }
}
