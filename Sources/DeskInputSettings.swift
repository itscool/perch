import SwiftUI
import AppKit

/// Session controls live beside the screen layout; options never own a second
/// selected preset or a competing enable switch.
struct DeskSharingControls: View {
    @ObservedObject var input: KVMInputSession
    @ObservedObject var adapter: DeskInputAdapter
    @ObservedObject var node: KVMDeskNode
    let preset: UUID
    let monitor: UUID?
    private var screen: KVMMonitor? { node.group.monitors.first { $0.id == monitor } }
    private var route: KVMAssignment? { node.group.presets.first { $0.id == preset }?.assignments.first { $0.monitor == monitor } }
    private var issue: String? {
        guard let screen else { return "Select a screen in the desk to choose where control starts." }
        guard route != nil else { return "This screen is unchanged in the editing preset. Choose one of its inputs to include it." }
        return input.readinessIssue(preset: preset, monitor: screen.id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Keyboard & mouse").font(.headline)
            Toggle("Share on this Mac", isOn: Binding(get: { input.enabled }, set: { adapter.enable($0) }))
                .help("Allow keyboard and mouse input between approved desk computers for this Perch session. Starts off after restarting Perch.")
            if !input.enabled {
                Text("Turn on here and in Desk on each Mac you want to control. Then select a screen and start control below. Sharing turns off when Perch restarts.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(node.group.computers) { computer in
                    let online = computer.id == node.localID || node.online.contains(computer.id)
                    let ready = online && input.readyComputers.contains(computer.id)
                    Label(computer.name + (ready ? " · ready" : online ? " · waiting for sharing" : " · offline"),
                          systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(ready ? Color.secondary : Color.orange)
                }
                if let problem = adapter.accessProblem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                    if adapter.needsPermissionSetup {
                        Button("Set up shared input access…") { SettingsWindow.shared.navigateToSetupStage("sharing-access") }
                    } else { Button("Retry sharing") { adapter.enable(true) } }
                }
                if let screen {
                    Button("Control \(screen.name)") { input.start(preset: preset, monitor: screen.id) }
                        .disabled(issue != nil)
                        .help("Start keyboard and mouse control on this screen using the editing preset. This does not switch the picture; Play applies its monitor inputs.")
                }
                if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                if let focus = input.focus, input.active {
                    Text("Controlling " + (node.group.monitors.first { $0.id == focus.monitor }?.name ?? "screen"))
                        .font(.caption).foregroundStyle(.teal)
                }
                if let problem = input.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                if input.focus != nil { Button("Return to local control") { input.stop() } }
                Text("Move across touching screen edges to change computers. Ctrl–Opt–Esc returns control locally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Input options…") {
                let host = SettingsWindow.shared
                if let destination = host.sidebar.destinations.first(where: { $0.id == "desk-input" }) { host.navigate(to: destination) }
            }.help("Adjust pointer speed or optionally follow a keyboard’s computer-switch buttons.")
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct DeskInputSettings: View {
    let runtime: DeskRuntime
    @ObservedObject var input: KVMInputSession
    @ObservedObject var adapter: DeskInputAdapter
    @ObservedObject private var node: KVMDeskNode
    @State private var newKeyboard = ""
    @State private var keyboardError: String?
    init(runtime: DeskRuntime, input: KVMInputSession, adapter: DeskInputAdapter) {
        self.runtime = runtime; self.input = input; self.adapter = adapter; node = runtime.node
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pointer speed")
                Slider(value: $adapter.pointerSpeed, in: 0.25...4, step: 0.05)
                Text(String(format: "%.2f×", adapter.pointerSpeed)).monospacedDigit().frame(width: 55)
            }.help("Saved immediately on this Mac. Adjusts pointer movement sent by devices connected here while sharing.")
            DisclosureGroup("Follow a keyboard’s computer buttons (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("For a keyboard with computer buttons such as 1 / 2 / 3: switch the keyboard to another Mac and Perch can move control there too. You do not need this setup to move the mouse between screens.").font(.callout).foregroundStyle(.secondary)
                    Text("Add the connected keyboard once below. Then switch it to each other Mac, open this same list, and select the connected keyboard under its existing name. Turn on Follow when the Macs are matched.").font(.callout)
                    Text("Sharing must be on in Desk on both Macs, with a confirmed screen for the destination. The keyboard setup is shared; each Mac confirms its own connection.").font(.caption).foregroundStyle(.secondary)
                    ForEach(node.group.sharedKeyboards ?? []) { keyboard in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                DeskTextSetting("Keyboard name", saved: keyboard.name) { value in
                                    var group = node.group
                                    guard let index = group.sharedKeyboards?.firstIndex(where: { $0.id == keyboard.id }) else { throw KVMError("This keyboard was removed from the desk.") }
                                    group.sharedKeyboards?[index].name = value; try node.edit(group)
                                }.id(keyboard.id).help("Names save immediately across the desk. An incomplete name keeps the previous saved value.")
                                Spacer()
                                Button("Remove") { editKeyboards { $0.removeAll { $0.id == keyboard.id } } }
                                    .help("Remove this keyboard’s follow setup from the shared desk. Native keyboard settings stay as they are.")
                            }
                            Picker("Connected keyboard on this Mac", selection: Binding(get: { keyboard.bindings[node.localID] ?? "" }, set: { value in
                                editKeyboards { values in if let i = values.firstIndex(where: { $0.id == keyboard.id }) { values[i].bindings[node.localID] = value.isEmpty ? nil : value } }
                            })) {
                                Text("Choose this keyboard on this Mac").tag("")
                                ForEach(uniqueKeyboards, id: \.preferenceKey) { device in Text(device.name).tag(device.preferenceKey) }
                                if let saved = keyboard.bindings[node.localID], !uniqueKeyboards.contains(where: { $0.preferenceKey == saved }) { Text("Saved keyboard · not connected or ambiguous").tag(saved) }
                            }.help("Confirm that this is the same physical keyboard named above. Its native settings are unchanged.")
                            ForEach(node.group.computers) { computer in
                                Label(computer.name + (keyboard.bindings[computer.id] == nil ? " · needs matching" : " · matched"),
                                      systemImage: keyboard.bindings[computer.id] == nil ? "circle" : "checkmark.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Toggle("Follow this keyboard’s computer switch", isOn: Binding(get: { keyboard.follow }, set: { value in
                                editKeyboards { values in if let i = values.firstIndex(where: { $0.id == keyboard.id }) { values[i].follow = value } }
                            })).help("Use confirmed keyboard attachment changes to choose its computer while sharing is active.")
                        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        Picker("Add connected keyboard", selection: $newKeyboard) {
                            Text("Choose a keyboard").tag("")
                            ForEach(uniqueKeyboards, id: \.preferenceKey) { device in Text(device.name).tag(device.preferenceKey) }
                        }
                        Button("Add") { addConnectedKeyboard() }
                            .disabled(newKeyboard.isEmpty || (node.group.sharedKeyboards?.count ?? 0) >= 16)
                            .help("Add this keyboard to the desk and match its connection on this Mac. Following stays off until you turn it on.")
                    }
                    Button("Refresh connected keyboards") { adapter.refreshKeyboards() }
                    if let keyboardError { Text(keyboardError).foregroundStyle(.orange) }
                    if uniqueKeyboards.isEmpty { Text("No uniquely identifiable external keyboard is connected here. Connect it and refresh. Identical or virtual device entries are not guessed.").font(.caption).foregroundStyle(.secondary) }
                }
            }.onAppear { adapter.refreshKeyboards() }
        }
    }
    private var uniqueKeyboards: [NativeKeyboard] {
        let counts = Dictionary(grouping: adapter.keyboards, by: \.preferenceKey).mapValues(\.count)
        return adapter.keyboards.filter { counts[$0.preferenceKey] == 1 }
    }
    private func addConnectedKeyboard() {
        guard let device = uniqueKeyboards.first(where: { $0.preferenceKey == newKeyboard }) else {
            keyboardError = "This keyboard is no longer connected. Refresh and choose it again."; return
        }
        if (node.group.sharedKeyboards ?? []).contains(where: { $0.bindings[node.localID] == device.preferenceKey }) {
            keyboardError = "This keyboard is already in the list. Use its existing entry."; return
        }
        if editKeyboards({ $0.append(.init(name: device.name, bindings: [node.localID: device.preferenceKey])) }) {
            newKeyboard = ""
        }
    }
    @discardableResult private func editKeyboards(_ change: (inout [KVMSharedKeyboard]) -> Void) -> Bool {
        do {
            var group = node.group; var keyboards = group.sharedKeyboards ?? []
            change(&keyboards); group.sharedKeyboards = keyboards
            try node.edit(group); keyboardError = nil; return true
        } catch { keyboardError = "The previous setup is still saved. " + error.localizedDescription; return false }
    }
}
