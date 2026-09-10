import AppKit
import SwiftUI

struct DeskLiveSheet: View {
    @ObservedObject var runtime: DeskRuntime
    @ObservedObject var node: KVMDeskNode
    let kind: String
    let selection: UUID?
    let close: () -> Void
    @State private var address = ""
    @State private var computer: UUID?
    @State private var display = ""
    @State private var screen: UUID?
    @State private var input: UInt16 = 0
    @State private var name = "New screen"
    @State private var code = ""
    @State private var error: String?
    @State private var removing = false
    @State private var controlKind = "standard"
    @State private var endpoint = ""
    @State private var unit = 1
    @State private var profileName = ""
    @State private var customInput = false
    @State private var inputName = "USB-C"
    init(runtime: DeskRuntime, kind: String, selection: UUID?, close: @escaping () -> Void) {
        self.runtime = runtime; node = runtime.node; self.kind = kind; self.selection = selection; self.close = close
    }
    var selectedDisplay: DeskDetectedDisplay? { computer.flatMap { runtime.displays[$0]?.first { $0.id == display } } }
    var selectedProfile: MonitorProfile? { MonitorProfiles.entries.first { $0.name == profileName } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contents
            if let error = error ?? node.problem { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.onAppear { computer = node.localID; if kind == "screen" { runtime.refreshAllDisplays() }; if kind == "control" { loadControl() } }
            .onChange(of: node.completedPairing) { _, value in if kind == "computer", value != nil { close() } }
            .onDisappear { if kind == "computer" { node.closePairing() } }
    }
    func perform(_ action: () throws -> Void) { do { try action(); error = nil } catch { self.error = error.localizedDescription } }
    @ViewBuilder var contents: some View {
        switch kind {
        case "computer": pairing
        case "screen": addScreen
        case "desk": deskSettings
        case "computerDetails": computerDetails
        case "conflict": conflict
        case "connections":
            Text("Add an input").font(.title2.bold())
            Text("Add a physical port on this monitor. It stays selectable even when no computer is mapped to it.").foregroundStyle(.secondary)
            TextField("Input name, such as HDMI 2", text: $name).textFieldStyle(.roundedBorder)
            TextField("Monitor input code (decimal)", text: $code).textFieldStyle(.roundedBorder)
            Text("Use the monitor profile or DDC/CI documentation for its input code. USB-C does not use one universal code.").font(.callout).foregroundStyle(.secondary)
            Button("Add input") { perform { guard let selection, let input = UInt16(code), input > 0 else { throw KVMError("Enter this port’s input code.") }; var group = node.group; group.connections.append(.init(monitor: selection, computer: nil, localDisplay: nil, inputName: name, inputCode: input)); try node.edit(group); close() } }.buttonStyle(.borderedProminent)
        case "removeConnection":
            Text("Remove this input?").font(.title2.bold())
            Text("Its selections in all three presets will be cleared. Other inputs and the screen stay in your desk.")
            Button("Remove input", role: .destructive) { runtime.model.removeConnection(selection!); if runtime.model.problem == nil { close() } }
        case "correctConnection":
            Text("Correct the physical screen").font(.title2.bold())
            Text("Move this cable mapping to the physical screen it belongs to. Its preset selections are cleared so you can choose them again.")
            Picker("Physical screen", selection: $screen) { Text("Choose screen").tag(nil as UUID?); ForEach(node.group.monitors) { Text($0.name).tag(Optional($0.id)) } }
            Button("Correct screen match") { guard let screen, let selection else { return }; runtime.model.correctConnection(selection, physicalScreen: screen); if runtime.model.problem == nil { close() } }.disabled(screen == nil)
        case "control": control
        default: EmptyView()
        }
    }
    var pairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a computer").font(.title2.bold())
            if !node.pairingOpen {
                Text("Open Desk on the other Mac too. Invite it to this desk, or join a desk that is inviting you. Compare the same code on both screens before approving.").foregroundStyle(.secondary)
                HStack {
                    Button("Invite to this desk") { node.openPairing(hosting: true) }.disabled(!node.isOwner || node.group.computers.count >= 16)
                    if !node.hasOtherMembers { Button("Join another desk") { node.openPairing(hosting: false) } }
                }
                if !node.isOwner { Text("\(node.ownerName) approves membership. Open Add computer there.").font(.callout) }
            } else {
                Text("Waiting for approval · this invitation expires in two minutes.").font(.callout).foregroundStyle(.secondary)
                if node.pairings.isEmpty {
                    if node.nearby.isEmpty { Text("Looking for nearby Perches…") }
                    ForEach(node.nearby.filter { nearby in !node.group.computers.contains { $0.id.uuidString == nearby.id } }) { nearby in
                        Button(nearby.name) { node.connect(nearby.endpoint) }
                    }
                    DisclosureGroup("Connect by address") {
                        Text("On the other Mac, use the address shown below. Both Macs must be reachable; nearby discovery also supports compatible peer-to-peer Wi-Fi.").font(.callout)
                        TextField("Other Mac’s address:port", text: $address).textFieldStyle(.roundedBorder)
                        Button("Connect") { perform { try node.connect(address: address) } }
                    }
                    Text("This Mac: \(Host.current().name ?? "Mac address unavailable") · Desk port \(node.transport.listener?.port?.rawValue ?? 0)").font(.caption).textSelection(.enabled)
                }
                ForEach(node.pairings) { pairing in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(pairing.card.name).font(.headline)
                        Text(pairing.comparison).font(.system(size: 24, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("Only approve if this exact code is on the other Mac’s Perch screen.").font(.callout)
                        if pairing.approvedHere { Text("Approved here. Waiting for the other Mac…").foregroundStyle(.secondary) }
                        else { Button("Codes match — approve") { node.approve(pairing.id) }.buttonStyle(.borderedProminent) }
                        Button("Reject connection") { node.reject(pairing.id) }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Button("End invitation") { node.closePairing() }
            }
        }
    }
    var addScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add or identify a screen").font(.title2.bold())
            Text("Choose a detected display, then tell Perch whether it is a new physical screen or one already shared in this desk. Identical models are kept separate until you confirm a match.").font(.callout).foregroundStyle(.secondary)
            Picker("Connected computer", selection: $computer) { ForEach(node.group.computers) { Text($0.name + (node.online.contains($0.id) ? "" : " · Offline")).tag(Optional($0.id)) } }.onChange(of: computer) { _, _ in display = ""; input = 0 }
            Picker("Detected display", selection: $display) {
                Text("Choose display").tag("")
                ForEach(runtime.displays[computer ?? node.localID] ?? []) { Text($0.name + " · " + String($0.id.prefix(8))).tag($0.id) }
            }.onChange(of: display) { _, value in input = 0; if let computer { runtime.inspect(value, computer: computer) } }
            if let detected = selectedDisplay {
                if detected.serial != 0 { Text("Serial \(detected.serial)").font(.caption).foregroundStyle(.secondary) }
                if !detected.canControl { Text("DDC/CI is unavailable through this cable. After adding the screen, choose its USB, network or serial control connection in Monitor control.").font(.callout).foregroundStyle(.orange) }
                Picker("Physical screen", selection: $screen) {
                    Text("A new screen").tag(nil as UUID?)
                    ForEach(node.group.monitors) { Text($0.name).tag(Optional($0.id)) }
                }
                if screen == nil { TextField("Screen name", text: $name).textFieldStyle(.roundedBorder) }
                Picker("Monitor profile", selection: $profileName) {
                    Text("Detected inputs").tag("")
                    ForEach(MonitorProfiles.entries.filter { $0.vendor == detected.vendor }, id: \.name) { Text($0.name).tag($0.name) }
                }.onChange(of: profileName) { _, _ in input = 0 }
                Toggle("Enter a different input", isOn: $customInput)
                if customInput {
                    TextField("Port name", text: $inputName).textFieldStyle(.roundedBorder)
                    TextField("Input code (decimal)", text: $code).textFieldStyle(.roundedBorder)
                    Text("Use the code from this model’s monitor documentation. USB-C has no universal code.").font(.caption).foregroundStyle(.secondary)
                } else {
                Picker("This cable is plugged into", selection: $input) {
                    Text("Choose monitor input").tag(UInt16(0))
                    ForEach(selectedProfile?.inputs ?? detected.inputs, id: \.code) { Text($0.name + " (\($0.code))").tag($0.code) }
                }
                }
                Text("Use the input name printed on the monitor or shown in its on-screen menu. Detection alone cannot tell which picture is visible.").font(.caption).foregroundStyle(.secondary)
                Button(screen == nil ? "Add screen" : "Confirm shared screen") {
                    perform { try runtime.addScreen(name: name, existing: screen, computer: computer!, display: display, input: customInput ? (UInt16(code) ?? 0) : input, profile: selectedProfile, custom: customInput ? MonitorInput(code: UInt16(code) ?? 0, name: inputName) : nil); close() }
                }.buttonStyle(.borderedProminent).disabled(customInput ? (UInt16(code) ?? 0) == 0 || inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : input == 0)
            }
            Button("Refresh connected screens") { runtime.refreshAllDisplays() }.disabled(runtime.discovering)
            if let problem = runtime.discoveryProblem { Text(problem).foregroundStyle(.orange) }
        }
    }
    var deskSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Desk settings").font(.title2.bold())
            TextField("Desk name", text: Binding(get: { node.group.name }, set: { value in perform { var group = node.group; group.name = value; try node.edit(group) } })).textFieldStyle(.roundedBorder)
            ForEach(node.group.presets.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Preset \(i+1)", text: Binding(get: { node.group.presets[i].name }, set: { value in perform { var group = node.group; group.presets[i].name = value; try node.edit(group) } })).textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Key", selection: Binding(get: { node.group.presets[i].shortcut.key }, set: { key in changeShortcut(i) { $0.key = key } })) { ForEach(1...20, id: \.self) { Text("F\($0)").tag("F\($0)") } }.frame(width: 100)
                        modifier("Ctrl", \.control, i); modifier("Opt", \.option, i); modifier("Cmd", \.command, i); modifier("Shift", \.shift, i)
                    }
                }
            }
            Text("These names, presets and shortcuts are shared with the desk. Keyboard and mouse sharing is not enabled; a preset changes monitor inputs only.").font(.callout).foregroundStyle(.secondary)
            if !node.pendingPeers.isEmpty { Text("Saved here. Waiting for \(node.group.computers.filter { node.pendingPeers.contains($0.id) }.map(\.name).joined(separator: ", ")) to acknowledge the latest change.").font(.callout).foregroundStyle(.orange) }
            if let issue = runtime.shortcutProblem { Text(issue).foregroundStyle(.orange) }
        }
    }
    func changeShortcut(_ i: Int, _ edit: (inout KVMShortcut) -> Void) { perform { var group = node.group; edit(&group.presets[i].shortcut); try node.edit(group) } }
    func modifier(_ title: String, _ key: WritableKeyPath<KVMShortcut, Bool>, _ i: Int) -> some View {
        Toggle(title, isOn: Binding(get: { node.group.presets[i].shortcut[keyPath: key] }, set: { value in changeShortcut(i) { $0[keyPath: key] = value } }))
    }
    var computerDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            let peer = node.group.computers.first { $0.id == selection }
            Text(peer?.name ?? "Computer").font(.title2.bold())
            Text(node.online.contains(selection ?? UUID()) ? "Connected securely" : "Offline · saved setup is kept").foregroundStyle(.secondary)
            if selection == node.ownerID { Text("Approves computers joining or leaving this desk. Every member can edit the desk and use its presets.").font(.callout) }
            if selection != node.localID {
                if removing {
                    Text("Remove this computer? Its physical monitor inputs remain selectable, marked Unassigned. Its trusted connection is revoked.")
                    Button("Remove computer", role: .destructive) { perform { try node.removePeer(selection!); close() } }.disabled(!node.isOwner)
                } else { Button("Remove from desk…", role: .destructive) { removing = true }.disabled(!node.isOwner) }
                if !node.isOwner { Text("Remove members from \(node.ownerName).").font(.caption) }
            }
        }
    }
    var conflict: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review desk changes").font(.title2.bold())
            Text("Both versions are preserved. Choose the arrangement to keep; it will synchronize to the other computers.").foregroundStyle(.secondary)
            if let recovered = node.recoveredDraft {
                Text("Membership changed while this Mac had another saved version. Removed computers will not be restored.").font(.callout)
                version(node.group, title: "Keep the current shared desk")
                version(recovered, title: "Use this Mac’s saved arrangement")
            } else {
                ForEach(Array(node.conflicts.enumerated()), id: \.offset) { i, group in version(group, title: "Use version \(i+1): \(group.name)") }
            }
        }
    }
    func version(_ group: KVMGroup, title: String) -> some View {
        DisclosureGroup(title) {
            Text(group.monitors.map { monitor in monitor.name + " · \(Int(monitor.geometry.x)), \(Int(monitor.geometry.y)) · \(monitor.geometry.rotation.rawValue)°" }.joined(separator: "\n")).font(.caption)
            ForEach(group.presets) { preset in Text(preset.name + ": " + preset.assignments.compactMap { a in group.connections.first { $0.id == a.connection }.map { $0.inputName } }.joined(separator: ", ")).font(.caption) }
            Button("Keep this version") { perform { try node.resolve(group); close() } }.buttonStyle(.borderedProminent)
        }
    }
    func loadControl() {
        guard let control = node.group.monitors.first(where: { $0.id == selection })?.control else { return }
        computer = control.computer; display = control.localDisplay
        if control.mode.hasPrefix("route:"), let data = Data(base64Encoded: String(control.mode.dropFirst(6))), let route = try? JSONDecoder().decode(MonitorConnection.self, from: data) { controlKind = route.kind; endpoint = route.endpoint; unit = route.address }
        else { controlKind = control.mode }
        runtime.discoverUSB()
    }
    func saveControl() {
        perform {
            guard let selection, let computer, !display.isEmpty else { throw KVMError("Choose the computer and display used to control this monitor.") }
            let mode: String
            if ["standard", "lg"].contains(controlKind) { mode = controlKind }
            else { let connection = MonitorConnection(kind: controlKind, endpoint: endpoint, address: unit); guard connection.valid else { throw KVMError("Choose or enter a complete control connection. The previous working connection is kept.") }; mode = connection.argument }
            var group = node.group
            guard let i = group.monitors.firstIndex(where: { $0.id == selection }) else { return }
            group.monitors[i].control = .init(computer: computer, localDisplay: display, mode: mode)
            try node.edit(group)
        }
    }
    var control: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitor control").font(.title2.bold())
            Text("This connection sends input commands and reads the monitor’s current input. It can differ from the computer shown on the screen. Valid changes save immediately; editing does not switch inputs.").font(.callout).foregroundStyle(.secondary)
            Picker("Control through", selection: Binding(get: { computer.map { $0.uuidString + "|" + display } ?? "" }, set: { choice in let parts = choice.split(separator: "|"); if parts.count == 2 { computer = UUID(uuidString: String(parts[0])); display = String(parts[1]); saveControl() } })) {
                Text("Choose connection").tag("")
                ForEach(runtime.mappingOptions) { Text($0.label).tag($0.id) }
            }
            Picker("Protocol", selection: $controlKind) {
                Text("Standard DDC/CI").tag("standard"); Text("LG alternate inputs").tag("lg")
                Text("USB MCCS").tag("mccs-usb"); Text("MSI USB").tag("msi-usb")
                Text("NEC network").tag("nec-lan"); Text("NEC serial").tag("nec-serial")
            }.onChange(of: controlKind) { _, _ in saveControl() }
            if !["standard", "lg"].contains(controlKind) {
                if computer == node.localID && controlKind.contains("usb") {
                    Picker("USB device", selection: $endpoint) { Text("Choose device").tag(""); ForEach(runtime.usbDevices, id: \.endpoint) { Text($0.name).tag($0.endpoint) } }.onChange(of: endpoint) { _, _ in saveControl() }
                }
                TextField(controlKind == "nec-lan" ? "Monitor network address" : "Device endpoint", text: $endpoint).textFieldStyle(.roundedBorder).onChange(of: endpoint) { _, _ in saveControl() }
                if controlKind.hasPrefix("nec") { Stepper("Monitor address: \(unit)", value: $unit, in: 1...26).onChange(of: unit) { _, _ in saveControl() } }
            }
            Text("Input codes depend on the selected protocol. Review each input’s code when changing it. The monitor profile library supplies known defaults; custom protocols still need hardware acceptance.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeskMemberRoot: View {
    let runtime: DeskRuntime
    @ObservedObject var node: KVMDeskNode
    @ObservedObject var coordinator = DeskCoordinator.shared
    var body: some View {
        if node.isMember { DeskView(model: runtime.model) }
        else {
            VStack(alignment: .leading, spacing: 16) {
                Text("This Mac was removed from the desk").font(.title2.bold())
                Text("Its saved arrangement is preserved. Start a new desk here, then use Add computer to ask the other desk to invite you again.")
                Button("Start a new desk") { coordinator.startAfterRemoval() }.buttonStyle(.borderedProminent)
                if let problem = coordinator.problem { Text(problem).foregroundStyle(.orange) }
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
struct DeskSettingsRoot: View {
    @ObservedObject var coordinator = DeskCoordinator.shared
    var body: some View {
        if let runtime = coordinator.runtime { DeskMemberRoot(runtime: runtime, node: runtime.node) }
        else {
            VStack(alignment: .leading, spacing: 18) {
                Label("One desk, all your screens", systemImage: "display.2").font(.title.bold())
                Text("Group your Perch computers, arrange up to 16 physical screens, and switch their monitor inputs with three shared presets.")
                Text("This first version switches monitor pictures. Your keyboard and mouse keep working on the computer they are connected to.").foregroundStyle(.secondary)
                Button("Set up this desk") { coordinator.enable() }.buttonStyle(.borderedProminent)
                if let problem = coordinator.problem { Text(problem).foregroundStyle(.orange); Button("Try opening Desk again") { coordinator.enable() } }
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
extension AppDelegate {
    @objc func deskSettings() {
        let view = NSHostingView(rootView: DeskSettingsRoot())
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 640)
        SettingsWindow.shared.show(.init(title: "Desk", detail: "Shared monitor layouts and presets. Editing saves your setup; Play switches the actual inputs. Keyboard and mouse sharing comes later.", view: view, preferredBodyWidth: 1000))
    }
}

extension AppDelegate {
    func refreshDeskMenu() {
        let runtime = DeskCoordinator.shared.runtime
        for item in deskPresetItems {
            item.isHidden = runtime == nil
            guard let runtime else { continue }
            let preset = runtime.node.group.presets[item.tag]
            let issue = runtime.switching.readiness(preset.id)
            label(item, preset.name, hint: runtime.switching.activePreset == preset.id ? "Confirmed" : "")
            (item.view as? MenuRowView)?.shortcutHint = preset.shortcut.label
            item.isEnabled = issue == nil
            item.menuHelp = issue ?? "Switch the monitor inputs to \(preset.name). Keyboard and mouse stay on their current computer."
        }
    }
    @objc func useDeskPreset(_ item: NSMenuItem) {
        guard let runtime = DeskCoordinator.shared.runtime, runtime.node.group.presets.indices.contains(item.tag) else { return }
        withMenuClosed { runtime.switching.activate(runtime.node.group.presets[item.tag].id) }
    }
}
