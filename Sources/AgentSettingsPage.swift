import AppKit
import Carbon

/// A regular settings page: no nested modal session or detached alert accessory.
/// Each change merges into fresh configuration, preserving unrelated settings.
final class AgentSettingsPage: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 500))
    let status = SettingsStatusField(wrappingLabelWithString: "")
    let enabled = NSButton(checkboxWithTitle: "Enable emergency shortcut", target: nil, action: nil)
    let keys = NSPopUpButton(frame: .zero, pullsDown: false)
    let reset = NSPopUpButton(frame: .zero, pullsDown: false)
    let retry = NSButton(title: "Retry saving", target: nil, action: nil)
    var agents: [(String, NSButton)] = []
    var modifiers: [(NSButton, UInt32)] = []
    private let load: () -> SafetyConfiguration
    private let save: (SafetyConfiguration) throws -> Void
    private let conflicts: (PanicShortcut) -> Bool
    private let didSave: () -> Void
    private enum Change { case agent(String, Bool), shortcut(PanicShortcut), reset(Int) }
    private var pending: Change?
    private var message = "Choices save automatically."
    private var shortcutIssue: String?

    init(load: @escaping () -> SafetyConfiguration = SafetyConfiguration.load,
         save: @escaping (SafetyConfiguration) throws -> Void,
         conflicts: @escaping (PanicShortcut) -> Bool, didSave: @escaping () -> Void = {}) {
        self.load = load; self.save = save; self.conflicts = conflicts; self.didSave = didSave
        super.init()
        let config = load()
        func caption(_ text: String, _ y: CGFloat) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.frame = NSRect(x: 8, y: y, width: 556, height: 20); view.addSubview(label)
        }
        caption("Agents to stop", 475)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 290, width: 572, height: 178))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder; scroll.drawsBackground = false
        let list = NSView(frame: NSRect(x: 0, y: 0, width: 546, height: max(174, config.targets.count * 28)))
        scroll.documentView = list; view.addSubview(scroll)
        for (index, target) in config.targets.enumerated() {
            let box = NSButton(checkboxWithTitle: target.name, target: self, action: #selector(agentChanged(_:)))
            box.frame = NSRect(x: 8, y: list.frame.height - CGFloat((index+1)*28), width: 530, height: 26)
            box.toolTip = "Include this agent and its observed child processes when Panic runs. Changing this choice saves immediately; it does not stop anything now."
            box.state = target.enabled ? .on : .off
            list.addSubview(box); agents.append((target.id, box))
        }
        caption("Emergency shortcut · fires immediately, without confirmation", 263)
        enabled.frame = NSRect(x: 8, y: 232, width: 548, height: 28)
        enabled.toolTip = "Enable the configured emergency shortcut. Outside Test shortcut, it runs Panic immediately without confirmation."
        enabled.state = config.shortcut.enabled ? .on : .off
        enabled.target = self; enabled.action = #selector(shortcutChanged)
        view.addSubview(enabled)
        for (index, pair) in [("Control", controlKey), ("Option", optionKey), ("Shift", shiftKey), ("Command", cmdKey)].enumerated() {
            let box = NSButton(checkboxWithTitle: pair.0, target: self, action: #selector(shortcutChanged))
            box.frame = NSRect(x: 8+index*112, y: 200, width: 112, height: 28)
            box.toolTip = "Require this modifier along with the other selected keys. Valid combinations save immediately."
            box.state = config.shortcut.modifiers & UInt32(pair.1) != 0 ? .on : .off
            modifiers.append((box, UInt32(pair.1))); view.addSubview(box)
        }
        keys.identifier = .init("agent.shortcut.key"); keys.setAccessibilityLabel("Emergency shortcut key")
        reset.identifier = .init("agent.privacy.scope"); reset.setAccessibilityLabel("Privacy permissions to reset after Panic")
        keys.frame = NSRect(x: 460, y: 200, width: 104, height: 28)
        keys.toolTip = "Choose the key to press with the selected modifiers. Valid combinations save immediately."
        keys.addItems(withTitles: PanicShortcut.keys.map(\.0))
        keys.selectItem(at: PanicShortcut.keys.firstIndex { $0.1 == config.shortcut.key } ?? 0)
        keys.target = self; keys.action = #selector(shortcutChanged); view.addSubview(keys)
        caption("After stopping agents", 164)
        reset.frame = NSRect(x: 8, y: 128, width: 556, height: 30)
        reset.toolTip = "Choose which privacy permissions Panic resets after stopping agents. This saves your choice; no permissions change now."
        reset.addItems(withTitles: ["Privacy reset: None", "Privacy reset: Selected agent apps", "Privacy reset: All apps, including Perch"])
        reset.selectItem(at: config.resetAgentPermissions ? (config.resetAllPermissions == true ? 2 : 1) : 0)
        reset.target = self; reset.action = #selector(resetChanged); view.addSubview(reset)
        let note = NSTextField(wrappingLabelWithString: "Changing this choice does not reset permissions now. A reset during Panic requires granting access again afterward.")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 8, y: 86, width: 556, height: 38); view.addSubview(note)
        status.font = .systemFont(ofSize: 12)
        status.frame = NSRect(x: 8, y: 8, width: 412, height: 72); view.addSubview(status)
        retry.frame = NSRect(x: 430, y: 30, width: 134, height: 30); retry.bezelStyle = .rounded
        retry.target = self; retry.action = #selector(retrySaving); retry.isHidden = true; view.addSubview(retry)
        updateStatus()
    }
    func show() {
        SettingsWindow.shared.show(.init(title: "Agents, shortcut & panic actions", detail: "Panic force-quits selected local agents and their observed children, then blocks relaunches until you resume. Unsaved work can be lost. The watcher cannot stop remote jobs, root processes or children it never observed.\n\nChanges save automatically. Incomplete shortcut edits keep the saved shortcut. Back discards unsaved shortcut edits.", view: view, refresh: { [self] in updateStatus() }))
    }
    private var shortcut: PanicShortcut {
        .init(key: PanicShortcut.keys[max(0, keys.indexOfSelectedItem)].1,
              modifiers: modifiers.filter { $0.0.state == .on }.reduce(0) { $0 | $1.1 }, enabled: enabled.state == .on)
    }
    @objc private func agentChanged(_ sender: NSButton) {
        guard let id = agents.first(where: { $0.1 === sender })?.0 else { return }
        apply(.agent(id, sender.state == .on))
    }
    @objc private func shortcutChanged() { apply(.shortcut(shortcut)) }
    @objc private func resetChanged() { apply(.reset(reset.indexOfSelectedItem)) }
    @objc private func retrySaving() { if let pending { apply(pending) } }
    private func updateStatus() {
        let saved = load().shortcut
        let current = saved.enabled ? "Saved shortcut: \(saved.title)." : "Emergency shortcut is off."
        let unsaved = shortcut != saved ? " Shortcut edits are not saved. \(shortcutIssue ?? "The saved shortcut remains in effect.")" : ""
        status.stringValue = message + "\n" + current + unsaved
        status.textColor = pending != nil || !unsaved.isEmpty ? StatusColors.warning : .secondaryLabelColor
    }
    private func apply(_ change: Change) {
        var config = load()
        switch change {
        case let .agent(id, value):
            guard let index = config.targets.firstIndex(where: { $0.id == id }) else { message = "This agent was removed. Reopen the page to refresh the list."; updateStatus(); return }
            config.targets[index].enabled = value
            guard config.targets.contains(where: \.enabled) else {
                agents.first { $0.0 == id }?.1.state = .on
                message = "Keep at least one agent selected."; updateStatus(); return
            }
        case let .shortcut(value):
            if value.enabled && !config.targets.contains(where: \.enabled) {
                pending = nil; retry.isHidden = true; shortcutIssue = "Select an agent before enabling the shortcut."; updateStatus(); return
            }
            if value.enabled && value.modifiers.nonzeroBitCount < 2 {
                pending = nil; retry.isHidden = true; shortcutIssue = "Choose at least two modifiers."; updateStatus(); return
            }
            if value.enabled && conflicts(value) {
                pending = nil; retry.isHidden = true; shortcutIssue = "Those keys already switch displays. Choose another combination."; updateStatus(); return
            }
            config.shortcut = value
        case let .reset(index):
            config.resetAgentPermissions = index != 0; config.resetAllPermissions = index == 2
        }
        do {
            try save(config); pending = nil; retry.isHidden = true
            if case .shortcut = change { shortcutIssue = nil }
            message = "✓ Change saved."; didSave()
        } catch {
            pending = change; retry.isHidden = false; message = "Not saved: " + error.localizedDescription
            // Ordinary controls show the retained value; Retry remembers the requested change.
            let saved = load()
            if case let .agent(id, _) = change { agents.first { $0.0 == id }?.1.state = saved.targets.first { $0.id == id }?.enabled == true ? .on : .off }
            if case .reset = change { reset.selectItem(at: saved.resetAgentPermissions ? (saved.resetAllPermissions == true ? 2 : 1) : 0) }
        }
        if pending == nil {
            for (id, box) in agents { box.state = config.targets.first { $0.id == id }?.enabled == true ? .on : .off }
            reset.selectItem(at: config.resetAgentPermissions ? (config.resetAllPermissions == true ? 2 : 1) : 0)
        }
        updateStatus()
    }
}
