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
    private var routeComputer: UUID? {
        guard let connection = route.flatMap({ assignment in node.group.connections.first { $0.id == assignment.connection } }) else { return nil }
        return connection.computer
    }
    private var issue: String? {
        guard let screen else { return "Select a screen in the desk to choose where control starts." }
        guard route != nil else { return "This screen is unchanged in the editing preset. Choose one of its inputs to include it." }
        return input.readinessIssue(preset: preset, monitor: screen.id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Keyboard & mouse").font(.headline)
            if !input.enabled {
                Text("Turn on Share on this Mac in the Perch menu on each Mac you want to control. An active preset with a remote screen starts control automatically.")
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
                    SettingsFeedback(text: problem)
                    if adapter.needsPermissionSetup {
                        Button("Set up shared input access…") { SettingsWindow.shared.navigateToSetupStage("sharing-access") }
                    } else { Button("Restart input sharing") { adapter.restart(); input.refreshReadiness() }
                        .help("Rebuild Perch’s local input tap after macOS stopped it. This does not change permissions.") }
                }
                if let screen, routeComputer != node.localID {
                    Button("Test remote control") { input.start(preset: preset, monitor: screen.id) }
                        .frame(maxWidth: .infinity)
                        .disabled(issue != nil)
                        .help("Start keyboard and mouse control on this screen using the editing preset. This does not switch the picture; Play applies its monitor inputs.")
                }
                if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                if let screen, let note = input.inputStatusNote(preset: preset, monitor: screen.id) {
                    Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !node.online.contains(node.ownerID) || node.online.count < node.group.computers.count {
                    Button("Retry desk connection") { node.retryConnections(); input.refreshReadiness() }
                        .help("Retry offline approved computers. Existing connections, sharing choices and desk setup stay intact.")
                }
                if let focus = input.focus, input.active {
                    Text("Controlling " + (node.group.monitors.first { $0.id == focus.monitor }?.name ?? "screen"))
                        .font(.caption).foregroundStyle(.teal)
                }
                if let problem = input.problem { SettingsFeedback(text: problem) }
                if let problem = input.problem {
                    let lower = problem.lowercased()
                    if lower.contains("offline") || lower.contains("reconnect") || lower.contains("waiting") || lower.contains("another computer") {
                        Button("Reconnect desk") { node.retryConnections(); input.refreshReadiness() }
                            .help("Reconnect approved Perch computers, then check sharing readiness again.")
                    }
                }
                if input.focus != nil { Button("Return to local control") { input.stopForLocalControl() } }
                Text("Move across touching screen edges to change computers. Ctrl–Opt–Esc returns control locally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct DeskInputSettings: View {
    let runtime: DeskRuntime
    @ObservedObject var input: KVMInputSession
    @ObservedObject var adapter: DeskInputAdapter
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pointer speed")
                Slider(value: $adapter.pointerSpeed, in: 0.25...4, step: 0.05)
                Text(String(format: "%.2f×", adapter.pointerSpeed)).monospacedDigit().frame(width: 55)
            }.help("Saved immediately on this Mac. Adjusts movement sent by devices connected here while sharing.")
            ForEach(KVMSharedInputKind.allCases, id: \.self) { kind in
                DeskFollowDeviceSettings(node: runtime.node, input: input, adapter: adapter, kind: kind)
            }
        }
    }
}

private struct DeskFollowDeviceSettings: View {
    @ObservedObject var node: KVMDeskNode
    @ObservedObject var input: KVMInputSession
    @ObservedObject var adapter: DeskInputAdapter
    let kind: KVMSharedInputKind
    @State private var selection = ""
    @State private var problem: String?
    private var noun: String { kind.rawValue }
    private var connected: [(key: String, name: String)] {
        let values = kind == .keyboard ? adapter.keyboards.map { ($0.preferenceKey, $0.name) } : adapter.mice.map { ($0.preferenceKey, $0.name) }
        let counts = Dictionary(grouping: values, by: { $0.0 }).mapValues(\.count)
        return values.filter { counts[$0.0] == 1 }
    }
    var body: some View {
        DisclosureGroup("Follow a \(noun)’s computer buttons (optional)") {
            VStack(alignment: .leading, spacing: 10) {
                DeskDeviceSwitchExample(kind: kind)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Add the \(noun) connected here. It should already be paired with your Macs.")
                    Text("2. Switch it to each other Mac. In this same entry, choose the connected \(noun).")
                    Text("3. Turn on Follow and start Control in Desk. Switch the device: “Controlling” should name a screen on its new Mac.")
                }.font(.callout).fixedSize(horizontal: false, vertical: true)
                Text("Sharing must be on in Desk on every participating Mac. This is optional for moving between screens.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach((node.group.sharedKeyboards ?? []).filter { $0.deviceKind == kind }) { device in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            DeskTextSetting("Device name", saved: device.name) { value in
                                try change { if let i = $0.firstIndex(where: { $0.id == device.id }) { $0[i].name = value } }
                            }.id(device.id)
                            Button("Remove") { edit { $0.removeAll { $0.id == device.id } } }
                                .help("Remove this device’s follow setup. Native device settings stay unchanged.")
                        }
                        Picker("Connected \(noun) on this Mac", selection: Binding(get: { device.bindings[node.localID] ?? "" }, set: { key in
                            edit { if let i = $0.firstIndex(where: { $0.id == device.id }) { $0[i].bindings[node.localID] = key.isEmpty ? nil : key } }
                        })) {
                            Text("Choose this \(noun)").tag("")
                            ForEach(connected, id: \.key) { Text($0.name).tag($0.key) }
                            if let key = device.bindings[node.localID], !connected.contains(where: { $0.key == key }) {
                                Text("Saved match · not connected or ambiguous").tag(key)
                            }
                        }
                        ForEach(node.group.computers) { computer in
                            let matched = device.bindings[computer.id] != nil
                            let hereConnected = computer.id == node.localID && connected.contains { $0.key == device.bindings[computer.id] }
                            Label(computer.name + (matched ? (hereConnected ? " · matched, connected here" : " · matched") : " · choose its \(noun) there"),
                                  systemImage: matched ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.caption).foregroundStyle(matched ? Color.secondary : Color.orange)
                        }
                        Toggle("Follow this \(noun)", isOn: Binding(get: { device.follow }, set: { enabled in
                            edit { if let i = $0.firstIndex(where: { $0.id == device.id }) { $0[i].follow = enabled } }
                        })).help("Follow confirmed attachment changes while sharing is active. This does not switch the device’s hardware channels.")
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Picker("Add connected \(noun)", selection: $selection) {
                        Text("Choose a \(noun)").tag("")
                        ForEach(connected, id: \.key) { Text($0.name).tag($0.key) }
                    }
                    Button("Add") {
                        guard let device = connected.first(where: { $0.key == selection }) else { problem = "The device disconnected. Refresh and choose it again."; return }
                        if (node.group.sharedKeyboards ?? []).contains(where: { $0.bindings[node.localID] == device.key }) {
                            problem = "Already added. Use its existing entry above."; return
                        }
                        edit { $0.append(.init(name: device.name, bindings: [node.localID: device.key], kind: kind == .mouse ? .mouse : nil)) }
                        if problem == nil { selection = "" }
                    }.disabled(selection.isEmpty || (node.group.sharedKeyboards ?? []).count >= 16)
                }
                Button("Refresh connected devices") { adapter.refreshKeyboards() }
                if connected.isEmpty { Text("No uniquely identifiable \(noun) is connected. Connect it, then refresh.").font(.caption).foregroundStyle(.secondary) }
                if let problem { SettingsFeedback(text: problem) }
                if let focus = input.focus, input.active {
                    let screenName = node.group.monitors.first(where: { $0.id == focus.monitor })?.name ?? "screen"
                    let computerName = node.group.computers.first(where: { $0.id == focus.computer })?.name ?? "computer"
                    Text("Controlling: \(screenName) · \(computerName)")
                        .font(.caption).foregroundStyle(.teal)
                }
                Text("If switching is not detected, try Bluetooth: some USB receivers keep reporting a device after it switches away.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 8)
        }.onAppear { adapter.refreshKeyboards() }
    }
    private func change(_ update: (inout [KVMSharedKeyboard]) -> Void) throws {
        var group = node.group, devices = group.sharedKeyboards ?? []
        update(&devices); group.sharedKeyboards = devices; try node.edit(group)
    }
    private func edit(_ update: (inout [KVMSharedKeyboard]) -> Void) {
        do { try change(update); problem = nil }
        catch { problem = "Not saved. " + error.localizedDescription }
    }
}

/// A schematic, not a product photograph: highlights the physical 1/2/3 selector.
struct DeskDeviceSwitchExample: View {
    let kind: KVMSharedInputKind
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: kind == .keyboard ? 8 : 22)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: kind == .keyboard ? 8 : 22).stroke(Color.secondary.opacity(0.5)))
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { index in
                            Text("\(index)").font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 17)
                                .background(index == 2 ? Color.teal.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    if kind == .keyboard { Image(systemName: "keyboard").font(.system(size: 22)).foregroundStyle(.secondary) }
                    else { Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 14) }
                }
            }.frame(width: kind == .keyboard ? 130 : 88, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .keyboard ? "Example: Logitech MX Keys" : "Example: Logitech MX Master 3").font(.callout).fontWeight(.medium)
                Text(kind == .keyboard ? "Press its 1 / 2 / 3 keys to change computers." : "The 1 / 2 / 3 selector is underneath the mouse.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine).allowsHitTesting(false)
    }
}
