import AppKit
import SwiftUI

private struct EmergencyShortcutEditor: View {
    let page: AgentSettingsPage
    @State private var draft: PanicShortcut
    @State private var message = ""
    @State private var kind = SettingsFeedbackKind.information
    @State private var retry = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    init(page: AgentSettingsPage) { self.page = page; _draft = State(initialValue: page.shortcut) }
    private func refresh() {
        page.updateStatus(); draft = page.shortcut; message = page.status.stringValue
        kind = page.feedbackKind; retry = !page.retry.isHidden
    }
    private func edit(_ change: (inout PanicShortcut) -> Void) {
        var value = page.shortcut; change(&value); page.editShortcut(value); refresh()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsShortcutEditor(title: "Enable emergency shortcut",
                enabled: Binding(get: { draft.enabled }, set: { value in edit { $0.enabled = value } }),
                key: Binding(get: { draft.key }, set: { value in edit { $0.key = value } }), choices: PanicShortcut.keys,
                modifiers: Binding(get: { draft.modifiers }, set: { value in edit { $0.modifiers = value } }))
            Text("Fires immediately, without confirmation.").font(.callout).foregroundStyle(.secondary)
            SettingsFeedback(text: message, kind: kind)
            if retry { Button("Retry saving") { page.retrySaving(); refresh() } }
        }.onAppear { refresh() }.onReceive(timer) { _ in refresh() }
    }
}

struct HotkeySettings: View {
    let emergency: AgentSettingsPage
    let testEmergency: () -> Void
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @ObservedObject var coordinator = DeskCoordinator.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent Kill Switch · this Mac").font(.headline)
            EmergencyShortcutEditor(page: emergency)
            Button("Test emergency shortcut…", action: testEmergency)
                .help("Starts a harmless test. No agents are stopped and no permissions are changed.")
            Divider()
            Text("Keep-awake countdown · this Mac").font(.headline)
            CountdownShortcutSettings(model: .shared)
            Divider()
            Text("Desk sharing · this Mac").font(.headline)
            if let runtime = coordinator.runtime {
                DeskSharingShortcutEditor(runtime: runtime)
            } else {
                Text("Set up a Desk to configure its Share on this Mac shortcut.").foregroundStyle(.secondary)
            }
            Divider()
            Text("Desk presets · shared with this desk").font(.headline)
            if let runtime = coordinator.runtime {
                DeskLiveSheet(runtime: runtime, kind: "hotkeys", selection: nil, close: {})
            } else {
                Text("Set up a Desk to configure its preset shortcuts.").foregroundStyle(.secondary)
            }
            Divider()
            Text("Fixed shortcuts").font(.headline)
            LabeledContent("Return keyboard and mouse control to this Mac", value: "⌃⌥Esc")
            LabeledContent("Quit Perch while its menu is open", value: "⌘Q")
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in contentHeightChanged(height) }
            })

    }
}

private struct DeskSharingShortcutEditor: View {
    @ObservedObject var runtime: DeskRuntime
    @State private var draft: PanicShortcut
    init(runtime: DeskRuntime) { self.runtime = runtime; _draft = State(initialValue: runtime.sharingShortcut) }
    private func edit(_ change: (inout PanicShortcut) -> Void) {
        var value = draft; change(&value); draft = value; runtime.saveSharingShortcut(value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsShortcutEditor(title: "Toggle Share on this Mac",
                enabled: Binding(get: { draft.enabled }, set: { value in edit { $0.enabled = value } }),
                key: Binding(get: { draft.key }, set: { value in edit { $0.key = value } }), choices: PanicShortcut.keys,
                modifiers: Binding(get: { draft.modifiers }, set: { value in edit { $0.modifiers = value } }))
            Text("Toggles this Mac’s local consent. Default: ⌃⌥⌘S. Changes save immediately.").font(.callout).foregroundStyle(.secondary)
            SettingsFeedback(text: runtime.sharingShortcutError)
        }.onReceive(runtime.$sharingShortcutError) { _ in
            let saved = runtime.sharingShortcut
            if saved != draft { draft = saved }
        }
    }
}

extension AppDelegate {
    @objc func hotkeySettings() {
        let emergency = makeAgentSettingsPage(mode: .shortcut)
        weak var hosted: NSView?
        let root = HotkeySettings(emergency: emergency, testEmergency: { [weak self] in self?.testPanicShortcut() }, contentHeightChanged: { height in
            DispatchQueue.main.async {
                guard let view = hosted, height.isFinite, height > 0, abs(view.frame.height-height) > 0.5 else { return }
                view.frame.size.height = height
                let host = SettingsWindow.shared
                if let page = host.pages.last, page.view === view { host.display(page) }
            }
        })
        let view = NSHostingView(rootView: root)
        hosted = view
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 1400)
        view.layoutSubtreeIfNeeded()
        view.frame.size.height = max(500, view.fittingSize.height)
        SettingsWindow.shared.show(.init(title: "Hotkeys", detail: "Valid changes save automatically. Incomplete emergency-shortcut edits keep the saved combination; leaving discards those unfinished edits.", view: view, preferredBodyWidth: 640))
    }
}
