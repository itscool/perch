import AppKit
import Carbon

final class MonitorGroupsPage: NSObject {
    let monitor: MonitorInputController
    private var selected: String?
    private var view = NSView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let results = NSTextField(wrappingLabelWithString: "")
    private var buttons: [NSControl] = []
    private var retry: NSButton?
    init(_ monitor: MonitorInputController) { self.monitor = monitor; selected = monitor.groups.active?.id }
    func show() {
        build()
        SettingsWindow.shared.show(.init(title: "Switching groups", detail: "Choose one display or several that should move to the same computer. Name that computer once, then map its input on each display. A newly connected display is never added automatically.", view: view, leave: { [self] in monitor.groups.onChange = nil }, refresh: { [weak self] in self?.reload() }))
        monitor.groups.onChange = { [weak self] in self?.update() }; update()
    }
    private func reload() { build(); show() }
    private func build() {
        let groups = monitor.groups.settings.groups
        if !groups.contains(where: { $0.id == selected }) { selected = monitor.groups.active?.id ?? groups.first?.id }
        let group = groups.first { $0.id == selected }
        let height = CGFloat(480 + (group?.destinations.count ?? 0) * 42 + (group?.members.count ?? 0) * 82)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height)); buttons = []
        var y = height - 34
        func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
            let b = SettingsActionButton(title: title, action: action); b.frame = NSRect(x: 0, y: y, width: 572, height: 30)
            view.addSubview(b); buttons.append(b); y -= 42; return b
        }
        func showResults() {
            status.frame = NSRect(x: 8, y: y-60, width: 556, height: 88); view.addSubview(status); y -= 92
            let resultHeight = CGFloat(max(1, group?.members.count ?? 0) * 82)
            results.frame = NSRect(x: 8, y: y-resultHeight+28, width: 556, height: resultHeight); results.font = .systemFont(ofSize: 12); view.addSubview(results); y -= resultHeight+8
        }
        if let group {
            let choice = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 572, height: 30), pullsDown: false)
            choice.identifier = .init("group.selection"); choice.setAccessibilityLabel("Display group to review")
            groups.forEach { choice.addItem(withTitle: $0.name); choice.lastItem?.representedObject = $0.id }
            choice.selectItem(at: groups.firstIndex(of: group) ?? 0); choice.target = self; choice.action = #selector(selectGroup(_:))
            view.addSubview(choice); buttons.append(choice); y -= 42
            let active = button("Use this group for the menu’s Cycle monitor input", { [weak self] in
                guard let self else { return }; var settings = self.monitor.groups.settings
                settings.activeID = settings.activeID == group.id ? nil : group.id
                do { try self.monitor.groups.save(settings); self.reload() } catch { self.status.stringValue = error.localizedDescription }
            }); active.setButtonType(.switch); active.state = monitor.groups.settings.activeID == group.id ? .on : .off
            for destination in group.destinations {
                _ = button("Switch \(group.name) to \(destination.name)") { [weak self] in self?.monitor.groups.choose(group, destination: destination) }
            }
            _ = button("Check current inputs") { [weak self] in self?.monitor.groups.checkInputs(group) }
            showResults()
            retry = button("Retry unconfirmed displays") { [weak self] in self?.monitor.groups.retry() }
            _ = button("Edit displays, destinations and shortcut…") { [weak self] in guard let self else { return }; MonitorGroupEditor(self.monitor, group: group).show() }
        }
        _ = button("Add switching group…") { [weak self] in guard let self else { return }; MonitorGroupEditor(self.monitor).show() }
        if group == nil { showResults() }
        if let group {
            _ = button("Remove this group…") { [weak self] in
                guard let self else { return }
                let alert = NSAlert(); alert.messageText = "Remove \(group.name)?"; alert.informativeText = "This removes the group and its destination mappings. Individual display setups are kept. No display will switch."
                alert.addButton(withTitle: "Remove group"); alert.addButton(withTitle: "Cancel")
                SettingsWindow.shared.present(alert) { response in
                    guard response == .alertFirstButtonReturn else { return }
                    var settings = self.monitor.groups.settings; settings.groups.removeAll { $0.id == group.id }; if settings.activeID == group.id { settings.activeID = nil }
                    do { try self.monitor.groups.save(settings); self.reload() } catch { self.status.stringValue = error.localizedDescription }
                }
            }
        }
    }
    @objc private func selectGroup(_ sender: NSPopUpButton) { selected = sender.selectedItem?.representedObject as? String; reload() }
    private func update() {
        guard SettingsWindow.shared.pages.last?.view === view else { return }
        let controller = monitor.groups
        status.stringValue = controller.message
        buttons.forEach { $0.isEnabled = !monitor.busy && !controller.busy && controller.loadError == nil }
        retry?.isEnabled = controller.canRetry && controller.resultGroupID == selected
        let group = controller.settings.groups.first { $0.id == selected }
        results.stringValue = group?.members.map { member in
            let identity = "\(member.name) · \(member.display.suffix(8))"
            guard controller.resultGroupID == group?.id, let result = controller.results.first(where: { $0.display == member.display }) else { return identity + "\nIncluded in this group. No result from this session." }
            return identity + " — \(result.state.rawValue) at \(result.checkedAt.formatted(date: .omitted, time: .standard))\n\(result.detail)"
        }.joined(separator: "\n\n") ?? "Start with Add switching group. Set up each display’s inputs in Monitor input switching before mapping its destinations here."
    }
}

/// A group is one transaction: Back/Close discards the entire draft, and Save
/// persists mappings without sending hardware commands.
final class MonitorGroupEditor: NSObject {
    let monitor: MonitorInputController
    var draft: MonitorGroup
    private var candidates: [MonitorGroupMember] = []
    private var names: [String: NSTextField] = [:]
    private var displayLabels: [String: NSTextField] = [:]
    private var groupName = NSTextField()
    private var shortcutEnabled = NSButton()
    private var shortcutKey = NSPopUpButton()
    private var modifiers: [(NSButton, UInt32)] = []
    private var error = ""
    init(_ monitor: MonitorInputController, group: MonitorGroup = MonitorGroup()) {
        self.monitor = monitor; draft = group
        super.init()
        do {
            var saved = try monitor.savedPlans(); if !monitor.plan.display.isEmpty { saved[monitor.plan.display] = monitor.plan }
            var known = Dictionary(uniqueKeysWithValues: group.members.map { ($0.display, $0) })
            for (id, plan) in saved { known[id] = .init(display: id, name: plan.displayName ?? known[id]?.name ?? "Saved display") }
            for display in monitor.displays { known[display.id] = known[display.id] ?? .init(display: display.id, name: display.name) }
            for member in group.members { known[member.display] = member }
            candidates = known.values.sorted { ($0.name, $0.display) < ($1.name, $1.display) }
        } catch { self.error = error.localizedDescription }
    }
    private func capture() {
        draft.name = groupName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in draft.destinations.indices { if let field = names[draft.destinations[i].id] { draft.destinations[i].name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) } }
        for i in draft.members.indices { if let field = displayLabels[draft.members[i].display], !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.members[i].name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) } }
        draft.shortcut.enabled = shortcutEnabled.state == .on
        draft.shortcut.key = UInt32(shortcutKey.selectedItem?.tag ?? Int(kVK_F8))
        draft.shortcut.modifiers = modifiers.filter { $0.0.state == .on }.reduce(0) { $0 | $1.1 }
    }
    func show(focusDestination: String? = nil) {
        names = [:]; modifiers = []; displayLabels = [:]
        let height = CGFloat(542 + candidates.count * 36 + draft.destinations.count * (86 + draft.members.count * 38))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height)); var y = height - 28
        func label(_ text: String, height: CGFloat = 24) {
            let field = NSTextField(wrappingLabelWithString: text); field.frame = NSRect(x: 8, y: y-height+24, width: 556, height: height); view.addSubview(field); y -= height+8
        }
        func button(_ text: String, action: @escaping () -> Void) -> NSButton {
            let b = SettingsActionButton(title: text, action: action); b.frame = NSRect(x: 0, y: y, width: 572, height: 28); view.addSubview(b); y -= 36; return b
        }
        label("Group name")
        groupName = NSTextField(string: draft.name); groupName.setAccessibilityLabel("Display group name"); groupName.identifier = .init("group.name"); groupName.frame = NSRect(x: 8, y: y, width: 556, height: 26); groupName.placeholderString = "For example, Desk displays"; view.addSubview(groupName); y -= 38
        label("Displays to include — select exactly the ones you want to switch")
        _ = button("Set up individual display inputs…") { [weak self] in
            guard let self else { return }; self.capture(); MonitorInputPage(self.monitor).show()
        }
        _ = button("Identify connected displays") { [weak self] in self?.identify() }
        for member in candidates {
            let connected = monitor.displays.contains { $0.id == member.display }
            let configured = monitor.plan.display == member.display || monitor.savedPlan(for: member.display) != nil
            let b = button("\(member.name) · \(member.display.suffix(8))\(connected ? "" : " · disconnected")\(configured ? "" : " · needs input setup")") { [weak self] in
                guard let self else { return }; self.capture()
                if self.draft.members.contains(where: { $0.display == member.display }) { self.draft.members.removeAll { $0.display == member.display }; for i in self.draft.destinations.indices { self.draft.destinations[i].inputs.removeValue(forKey: member.display) } }
                else { self.draft.members.append(member) }
                self.show()
            }; b.identifier = .init("group.member." + member.display); b.setButtonType(.switch); b.state = draft.members.contains { $0.display == member.display } ? .on : .off
            if let selected = draft.members.first(where: { $0.display == member.display }) {
                b.frame.size.width = 350
                let label = NSTextField(string: selected.name); label.identifier = .init("group.label." + member.display); label.setAccessibilityLabel("Display label for " + member.name); label.placeholderString = "Label, for example Left"
                label.frame = NSRect(x: 356, y: y+36, width: 208, height: 26); view.addSubview(label); displayLabels[member.display] = label
            }
        }
        for destination in draft.destinations {
            let field = NSTextField(string: destination.name); field.setAccessibilityLabel("Destination computer name"); field.identifier = .init("group.destination." + destination.id); field.placeholderString = "Destination name, for example Mac mini"
            field.frame = NSRect(x: 8, y: y, width: 420, height: 26); names[destination.id] = field; view.addSubview(field)
            let remove = SettingsActionButton(title: "Remove") { [weak self] in guard let self else { return }; self.capture(); let index = self.draft.destinations.firstIndex { $0.id == destination.id } ?? 0; self.draft.destinations.removeAll { $0.id == destination.id }; self.show(focusDestination: self.draft.destinations.isEmpty ? nil : self.draft.destinations[min(index, self.draft.destinations.count-1)].id) }
            remove.setAccessibilityLabel("Remove destination " + (destination.name.isEmpty ? "unnamed computer" : destination.name))
            remove.identifier = .init("group.remove." + destination.id)
            remove.frame = NSRect(x: 440, y: y, width: 125, height: 28); view.addSubview(remove); y -= 38
            for member in draft.members {
                let title = NSTextField(labelWithString: "\(member.name) · \(member.display.suffix(8))")
                title.lineBreakMode = .byTruncatingMiddle; title.frame = NSRect(x: 8, y: y+3, width: 270, height: 20); view.addSubview(title)
                let plan = monitor.plan.display == member.display ? monitor.plan : monitor.savedPlan(for: member.display)
                let popup = NSPopUpButton(frame: NSRect(x: 280, y: y, width: 284, height: 28), pullsDown: false)
                popup.setAccessibilityLabel("Input for " + member.name + " on " + (destination.name.isEmpty ? "unnamed destination" : destination.name))
                popup.addItem(withTitle: "Choose this computer’s input…"); popup.lastItem?.tag = 0
                for input in plan?.availableInputs ?? plan?.inputs ?? [] { popup.addItem(withTitle: "\(input.name) (\(input.code))"); popup.lastItem?.tag = Int(input.code) }
                popup.selectItem(withTag: Int(destination.inputs[member.display] ?? 0)); popup.identifier = .init(destination.id + "/" + member.display)
                popup.target = self; popup.action = #selector(mapInput(_:)); view.addSubview(popup); y -= 38
            }
            y -= 10
        }
        let add = button("Add destination") { [weak self] in guard let self else { return }; self.capture(); let destination = MonitorDestination(name: "", inputs: [:]); self.draft.destinations.append(destination); self.show(focusDestination: destination.id) }; add.isEnabled = draft.destinations.count < 8
        shortcutEnabled = button("Enable a shortcut when this is the menu’s active group") {}; shortcutEnabled.setButtonType(.switch); shortcutEnabled.state = draft.shortcut.enabled ? .on : .off
        let flags: [(String, UInt32)] = [("Control", UInt32(controlKey)), ("Option", UInt32(optionKey)), ("Shift", UInt32(shiftKey)), ("Command", UInt32(cmdKey))]
        for (index, flag) in flags.enumerated() {
            let b = NSButton(checkboxWithTitle: flag.0, target: nil, action: nil); b.frame = NSRect(x: CGFloat(index)*105, y: y, width: 104, height: 26)
            b.state = draft.shortcut.modifiers & flag.1 != 0 ? .on : .off; modifiers.append((b, flag.1)); view.addSubview(b)
        }
        shortcutKey = NSPopUpButton(frame: NSRect(x: 432, y: y, width: 132, height: 28), pullsDown: false)
        shortcutKey.identifier = .init("group.shortcut.key"); shortcutKey.setAccessibilityLabel("Display group shortcut key")
        for key in PanicShortcut.keys { shortcutKey.addItem(withTitle: key.0); shortcutKey.lastItem?.tag = Int(key.1) }
        shortcutKey.selectItem(withTag: Int(draft.shortcut.key)); view.addSubview(shortcutKey); y -= 38
        label(error.isEmpty ? "Save stores this group without switching displays. Cancel or Close discards this draft." : error, height: 54)
        let save = SettingsActionButton(title: "Save group") { [weak self] in self?.save() }; save.frame = NSRect(x: 416, y: 0, width: 148, height: 30); view.addSubview(save)
        SettingsWindow.shared.show(.init(title: "Edit switching group", detail: "Choose Save group to keep this draft; Cancel or closing keeps the saved group. Each destination names one computer and its input on every selected display. If an input is missing, open individual display setup below and return to this draft.", view: view, leave: { [self] in _ = draft }, refresh: { [weak self] in self?.show() }, backTitle: "Cancel"))
        if let focusDestination, let field = names[focusDestination] {
            field.scrollToVisible(field.bounds.insetBy(dx: 0, dy: -12))
            SettingsWindow.shared.window.makeFirstResponder(field)
        }
    }
    @objc private func mapInput(_ sender: NSPopUpButton) {
        guard let parts = sender.identifier?.rawValue.split(separator: "/"), parts.count == 2, let i = draft.destinations.firstIndex(where: { $0.id == parts[0] }) else { return }
        draft.destinations[i].inputs[String(parts[1])] = UInt16(sender.selectedItem?.tag ?? 0)
    }
    private func identify() {
        guard !SettingsWindow.shared.testing else { return }
        var panels: [NSPanel] = []
        for display in monitor.displays {
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) else { continue }
            let panel = NSPanel(contentRect: NSRect(x: screen.frame.midX-190, y: screen.frame.midY-65, width: 380, height: 130), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.level = .floating; panel.ignoresMouseEvents = true
            let label = NSTextField(wrappingLabelWithString: "\(display.name)\n\(display.id.suffix(8))")
            label.font = .systemFont(ofSize: 25, weight: .semibold); label.alignment = .center; label.frame = NSRect(x: 16, y: 20, width: 348, height: 90)
            panel.contentView?.addSubview(label); panel.orderFrontRegardless(); panels.append(panel)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { panels.forEach { $0.close() } }
    }
    private func save() {
        capture()
        do {
            for destination in draft.destinations {
                for request in monitor.groups.requests(draft, destination: destination) {
                    guard let plan = request.plan, (plan.availableInputs ?? plan.inputs).contains(where: { $0.code == request.input }) else { throw AppError(message: "Choose a saved input for every selected display under each destination.") }
                }
            }
            var settings = monitor.groups.settings
            if let i = settings.groups.firstIndex(where: { $0.id == draft.id }) { settings.groups[i] = draft } else { settings.groups.append(draft) }
            try monitor.groups.save(settings); SettingsWindow.shared.goBack()
        } catch { self.error = error.localizedDescription; show() }
    }
}

extension AppDelegate {
    @objc func monitorGroupSettings() {
        if menuOpen { withMenuClosed { [weak self] in self?.monitorGroupSettings() }; return }
        MonitorGroupsPage(monitorInputs).show()
    }
}
