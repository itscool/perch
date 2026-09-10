import SwiftUI
import AppKit

struct DeskInputSettings: View {
    let runtime: DeskRuntime
    @ObservedObject var input: KVMInputSession
    @ObservedObject var adapter: DeskInputAdapter
    @ObservedObject private var node: KVMDeskNode
    @State private var presetIndex = 0
    @State private var keyboardName = "Shared keyboard"
    @State private var keyboardError: String?
    @State private var keyboardNames: [UUID: String] = [:]
    init(runtime: DeskRuntime, input: KVMInputSession, adapter: DeskInputAdapter) {
        self.runtime = runtime; self.input = input; self.adapter = adapter; node = runtime.node
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard & mouse sharing").font(.headline)
            Toggle("Enable sharing on this Mac for this session", isOn: Binding(get: { input.enabled }, set: { adapter.enable($0) }))
                .help("Allows this Mac to send and receive keyboard and mouse input within your approved desk. Starts off after Perch restarts.")
            Text("Enable on the participating Macs, then choose the screen to control. Move across touching screen edges to change computers. Press Ctrl–Opt–Esc on a connected keyboard to return to local control.").font(.callout).foregroundStyle(.secondary)
            Text("\(node.ownerName) coordinates input and must stay connected. Closing Settings keeps sharing active; quitting Perch ends it. Secure password entry needs a local keyboard.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Pointer speed")
                Slider(value: $adapter.pointerSpeed, in: 0.25...4, step: 0.05)
                Text(String(format: "%.2f×", adapter.pointerSpeed)).monospacedDigit().frame(width: 55)
            }.help("Saved immediately on this Mac. Adjusts pointer movement sent by devices connected here while sharing.")
            if let issue = adapter.accessProblem {
                Text(issue).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Accessibility settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                    Button("Input Monitoring settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
                }
                Button("Recheck access") { adapter.enable(true) }
            }
            if input.enabled {
                Picker("Screens currently showing", selection: $presetIndex) {
                    ForEach(node.group.presets.indices, id: \.self) { i in Text(node.group.presets[i].name).tag(i) }
                }.help("Choose the preset whose inputs are visible. This selection does not switch monitors; Perch checks the actual input before sharing.")
                ForEach(node.group.monitors) { screen in
                    HStack {
                        Text(screen.name)
                        Spacer()
                        if input.focus?.monitor == screen.id { Text("Controlling").foregroundStyle(.secondary) }
                        else {
                            Button("Control here") { input.start(preset: node.group.presets[presetIndex].id, monitor: screen.id) }
                                .disabled(input.readinessIssue(preset: node.group.presets[presetIndex].id, monitor: screen.id) != nil)
                                .help("Move keyboard and mouse control to the computer currently mapped to this screen in the selected preset.")
                        }
                    }
                    if let issue = input.readinessIssue(preset: node.group.presets[presetIndex].id, monitor: screen.id) {
                        Text(issue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let issue = input.problem { Text(issue).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                if input.focus != nil { Button("Return to local control") { input.stop() } }
                if node.group.monitors.isEmpty { Text("Add a screen to Desk before starting input sharing.").foregroundStyle(.secondary) }
            }
            DisclosureGroup("Follow a keyboard’s host switch") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a name once, then select that same physical keyboard on each Mac while it is connected there. Perch follows a confirmed disconnect and reconnect, not a guessed Bluetooth slot. Sharing must be enabled on both Macs; the destination needs a visible screen in the active preset.").font(.caption)
                    ForEach(node.group.sharedKeyboards ?? []) { keyboard in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Keyboard name", text: Binding(get: { keyboardNames[keyboard.id] ?? keyboard.name }, set: { value in
                                    keyboardNames[keyboard.id] = value
                                    if editKeyboards({ values in if let i = values.firstIndex(where: { $0.id == keyboard.id }) { values[i].name = value } }) { keyboardNames[keyboard.id] = nil }
                                })).textFieldStyle(.roundedBorder).help("Names save immediately across the desk. An incomplete name keeps the previous saved value.")
                                Spacer()
                                Button("Remove") { editKeyboards { $0.removeAll { $0.id == keyboard.id } } }
                                    .help("Remove this keyboard’s follow setup from the shared desk. Native keyboard settings stay as they are.")
                            }
                            Picker("This Mac’s attachment", selection: Binding(get: { keyboard.bindings[node.localID] ?? "" }, set: { value in
                                editKeyboards { values in if let i = values.firstIndex(where: { $0.id == keyboard.id }) { values[i].bindings[node.localID] = value.isEmpty ? nil : value } }
                            })) {
                                Text("Not mapped on this Mac").tag("")
                                ForEach(uniqueKeyboards, id: \.preferenceKey) { device in Text(device.name).tag(device.preferenceKey) }
                                if let saved = keyboard.bindings[node.localID], !uniqueKeyboards.contains(where: { $0.preferenceKey == saved }) { Text("Saved attachment · not uniquely detected").tag(saved) }
                            }.help("Confirm that this is the same physical keyboard named above. Its native settings are unchanged.")
                            Toggle("Follow this keyboard", isOn: Binding(get: { keyboard.follow }, set: { value in
                                editKeyboards { values in if let i = values.firstIndex(where: { $0.id == keyboard.id }) { values[i].follow = value } }
                            })).help("Use confirmed keyboard attachment changes to choose its computer while sharing is active.")
                        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        TextField("Keyboard name", text: $keyboardName).textFieldStyle(.roundedBorder)
                        Button("Add keyboard") { editKeyboards { $0.append(.init(name: keyboardName)) } }.disabled((node.group.sharedKeyboards?.count ?? 0) >= 16)
                            .help("Add a shared name, then confirm this keyboard’s attachment on each Mac.")
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
    @discardableResult private func editKeyboards(_ change: (inout [KVMSharedKeyboard]) -> Void) -> Bool {
        do {
            var group = node.group; var keyboards = group.sharedKeyboards ?? []
            change(&keyboards); group.sharedKeyboards = keyboards
            try node.edit(group); keyboardError = nil; return true
        } catch { keyboardError = "The previous setup is still saved. " + error.localizedDescription; return false }
    }
}
