import AppKit
import SwiftUI

private struct EmergencyShortcutEditor: NSViewRepresentable {
    let page: AgentSettingsPage
    func makeNSView(context: Context) -> NSView { page.view }
    func updateNSView(_ view: NSView, context: Context) { page.updateStatus() }
}

struct HotkeySettings: View {
    let emergency: AgentSettingsPage
    let testEmergency: () -> Void
    @ObservedObject var coordinator = DeskCoordinator.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Agent Kill Switch · this Mac").font(.headline)
            EmergencyShortcutEditor(page: emergency).frame(height: 300)
            Button("Test emergency shortcut…", action: testEmergency)
                .help("Starts a harmless test. No agents are stopped and no permissions are changed.")
            Divider()
            Text("Keep-awake countdown · this Mac").font(.headline)
            CountdownShortcutSettings(model: .shared)
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
            .onReceive(timer) { _ in emergency.updateStatus() }
    }
}

extension AppDelegate {
    @objc func hotkeySettings() {
        let emergency = makeAgentSettingsPage(mode: .shortcut)
        let root = HotkeySettings(emergency: emergency, testEmergency: { [weak self] in self?.testPanicShortcut() })
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 1400)
        view.layoutSubtreeIfNeeded()
        view.frame.size.height = max(500, view.fittingSize.height)
        SettingsWindow.shared.show(.init(title: "Hotkeys", detail: "Valid changes save automatically. Incomplete emergency-shortcut edits keep the saved combination; leaving discards those unfinished edits.", view: view, preferredBodyWidth: 640))
    }
}
