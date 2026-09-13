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
    var selectedProfile: MonitorProfile? { selectedDisplay?.profile(choice: profileName) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contents
            // Temporary sheets already present model.problem; stable sidebar pages own their error display.
            if let error = error ?? (kind == "computer" ? node.pairingProblem ?? node.displayProblem : node.displayProblem), ["hotkeys", "input"].contains(kind) || error != runtime.model.problem { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.onAppear { computer = node.localID; if kind == "screen" { runtime.refreshAllDisplays() }; if kind == "removeComputer" { removing = true }; if ["control", "monitorSetup"].contains(kind) { loadControl() }; if kind == "monitorSetup", let computer, !display.isEmpty { runtime.inspect(display, computer: computer) } }
            .onChange(of: node.completedPairing) { _, value in if kind == "computer", value != nil { close() } }
            .onDisappear { if kind == "computer" { node.closePairing() } }
    }
    func perform(_ action: () throws -> Void) { do { try action(); error = nil } catch { self.error = error.localizedDescription } }
    @ViewBuilder var contents: some View {
        switch kind {
        case "computer": pairing
        case "screen": addScreen
        case "hotkeys": shortcutSettings
        case "input": DeskInputSettings(runtime: runtime, input: runtime.input, adapter: runtime.inputAdapter)
        case "computerDetails", "removeComputer": computerDetails
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
        case "control": control
        case "monitorSetup": monitorSetup
        default: EmptyView()
        }
    }
    var pairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a computer").font(.title2.bold())
            if !node.pairingOpen {
                Text("Keep this desk’s screens and presets by inviting the other Mac. To use the other Mac’s desk instead, join it.").foregroundStyle(.secondary)
                HStack {
                    Button("Invite to this desk") { node.openPairing(hosting: true) }.disabled(!node.isOwner || node.group.computers.count >= 16)
                    if !node.hasOtherMembers { Button("Join another desk") { node.openPairing(hosting: false) } }
                }
                if !node.isOwner { Text("\(node.ownerName) approves membership. Open Add computer there.").font(.callout) }
            } else {
                Text(node.inviting ? "Inviting a Mac to \(node.group.name)" : "Joining another desk")
                    .font(.headline)
                Text(node.inviting
                     ? "On the other Mac, open Desk → Add a computer → Join another desk. Then select a Mac below on either screen — only one of you needs to do this."
                     : "On the Mac whose desk you want to use, open Desk → Add a computer → Invite to this desk. Then select a Mac below on either screen — only one of you needs to do this.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Available for two minutes. Both Macs must approve before anything is shared.").font(.caption).foregroundStyle(.secondary)
                if node.pairings.isEmpty {
                    if let issue = node.discoveryProblem { Text(issue).foregroundStyle(.orange).font(.callout) }
                    if node.pairingConnection != nil { Text("Connecting… The comparison code will appear on both Macs.") }
                    if node.nearby.isEmpty { Text("Looking for nearby Macs…") }
                    ForEach(node.nearby.filter { nearby in !node.group.computers.contains { $0.id.uuidString == nearby.id } }) { nearby in
                        VStack(alignment: .leading, spacing: 4) {
                            Button(node.inviting ? "Invite \(nearby.name)" : "Join \(nearby.name)’s desk") { node.connect(nearby.endpoint) }
                                .disabled(!node.canSelect(nearby))
                            Text(nearbyStatus(nearby)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("Connect by address") {
                        Text("On the other Mac, use the address shown below. Both Macs must be reachable; nearby discovery also supports compatible peer-to-peer Wi-Fi.").font(.callout)
                        TextField("Other Mac’s address:port", text: $address).textFieldStyle(.roundedBorder)
                        Button("Connect") { perform { try node.connect(address: address) } }.disabled(node.pairingConnection != nil)
                        if let port = node.transport.listener?.port?.rawValue {
                            Text("This Mac’s address: \(Host.current().localizedName ?? node.localName) · Port \(port)").font(.caption)
                            Text("\(Host.current().name ?? "Mac address unavailable"):\(port)").font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    Text("This Mac: \(node.localName)").font(.caption)
                }
                ForEach(node.pairings) { pairing in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(node.inviting ? "Add \(pairing.card.name) to this desk" : "Join \(pairing.card.name)’s desk").font(.headline)
                        Text("Comparison code — must match on both Macs").font(.caption)
                        Text(pairing.comparison).font(.system(size: 24, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("Only approve if this exact code is on the other Mac’s Perch screen.").font(.callout)
                        if pairing.approvedHere { Text("Approved here. Waiting for the other Mac…").foregroundStyle(.secondary) }
                        else { Button("Codes match — approve") { node.approve(pairing.id) }.buttonStyle(.borderedProminent) }
                        Button("Reject connection") { node.reject(pairing.id) }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Button(node.inviting ? "Stop inviting" : "Stop joining") { node.closePairing() }
            }
        }
    }
    func nearbyStatus(_ nearby: KVMPeerTransport.Nearby) -> String {
        switch nearby.pairingRole {
        case "invite": return node.inviting ? "Also inviting. Choose Join another desk on this Mac to join it." : "Sharing \(nearby.deskName ?? "its desk")"
        case "join": return node.inviting ? "Ready to join this desk" : "Also joining. Choose Invite to this desk on one Mac."
        case "closed": return "Open Add a computer on that Mac, then choose \(node.inviting ? "Join another desk" : "Invite to this desk")."
        default: return "Confirm the Mac’s name and comparison code after connecting."
        }
    }
    var addScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a monitor").font(.title2.bold())
            Text("Add each physical monitor once. After that, connect other computers to its ports on the desk.").font(.callout).foregroundStyle(.secondary)
            Picker("Connected computer", selection: $computer) { ForEach(node.group.computers) { Text($0.name + (node.online.contains($0.id) ? "" : " · Offline")).tag(Optional($0.id)) } }.onChange(of: computer) { _, _ in display = ""; input = 0 }
            Picker("Detected display", selection: $display) {
                Text("Choose display").tag("")
                ForEach(Array((runtime.displays[computer ?? node.localID] ?? []).enumerated()), id: \.element.id) { index, value in Text("Display \(index + 1): \(value.name)").tag(value.id) }
            }.onChange(of: display) { _, value in input = 0; profileName = ""; if let computer { runtime.inspect(value, computer: computer) } }
            if let detected = selectedDisplay {
                if let existing = node.group.connections.first(where: { $0.computer == computer && $0.localDisplay == display }), let monitor = node.group.monitors.first(where: { $0.id == existing.monitor }) {
                    Text("This monitor is already on your desk as \(monitor.name).").font(.headline)
                    Button("Show \(monitor.name)") { runtime.model.selected = monitor.id; close() }
                } else {
                if detected.serial != 0 { Text("Serial \(detected.serial)").font(.caption).foregroundStyle(.secondary) }
                if !detected.canControl { Text("DDC/CI is unavailable through this cable. After adding the screen, choose its USB, network or serial control connection in Monitor control.").font(.callout).foregroundStyle(.orange) }
                if let computer, let suggestion = runtime.suggestedScreens(computer: computer, display: detected).first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("May be your \(suggestion.name) screen").font(.headline)
                        Text("Its model and serial match a monitor already on the desk. Use Identify to check. If it is the same monitor, show it on the desk and connect this computer to its port.").font(.caption)
                        HStack {
                            Button(runtime.identifications.active[computer.uuidString + "|" + display] != nil ? "Stop identifying" : "Identify this display") { runtime.identifyDetected(display, computer: computer, name: detected.name) }
                            Button("Show \(suggestion.name) on the desk") { runtime.model.selected = suggestion.id; close() }
                        }
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                TextField("Screen name", text: $name).textFieldStyle(.roundedBorder)
                Picker("Monitor profile", selection: $profileName) {
                    Text(detected.profile(choice: "").map { "Suggested controls: " + $0.name } ?? "Ports reported by the monitor").tag("")
                    if detected.profile(choice: "") != nil || profileName == DeskDetectedDisplay.reportedInputsChoice { Text("Use reported ports instead").tag(DeskDetectedDisplay.reportedInputsChoice) }
                    ForEach(MonitorProfiles.entries.filter { $0.vendor == detected.vendor }, id: \.name) { Text($0.name).tag($0.name) }
                }.onChange(of: selectedProfile?.name) { _, _ in input = 0 }
                if let issue = detected.inspectionProblem { Text("Could not read monitor details: " + issue).font(.callout).foregroundStyle(.orange) }
                if detected.profile(choice: "") == nil {
                    Text(detected.inspected == true ? "The exact model was not identified. A generic name from macOS does not identify a retail model. Choose a profile only when its documented controls match your monitor." : "Reading monitor details…").font(.caption).foregroundStyle(.secondary)
                }
                if let family = detected.firmwareFamily {
                    Text("LG firmware family: \(family). This can suggest input settings; it does not confirm the retail model or a shared physical screen.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Enter a different input", isOn: $customInput)
                if customInput {
                    TextField("Port name", text: $inputName).textFieldStyle(.roundedBorder)
                    TextField("Input code (decimal)", text: $code).textFieldStyle(.roundedBorder)
                    Text("Use the code from this model’s monitor documentation. USB-C has no universal code.").font(.caption).foregroundStyle(.secondary)
                } else {
                Picker("This cable is plugged into", selection: $input) {
                    Text("Choose monitor input").tag(UInt16(0))
                    ForEach(detected.portOptions(choice: profileName), id: \.code) { Text($0.name).tag($0.code) }
                }
                }
                Text("Use the input name printed on the monitor or shown in its on-screen menu. Detection alone cannot tell which picture is visible.").font(.caption).foregroundStyle(.secondary)
                Button("Add monitor") {
                    perform { try runtime.addScreen(name: name, existing: nil, computer: computer!, display: display, input: customInput ? (UInt16(code) ?? 0) : input, profile: selectedProfile, custom: customInput ? MonitorInput(code: UInt16(code) ?? 0, name: inputName) : nil); close() }
                }.buttonStyle(.borderedProminent).disabled(customInput ? (UInt16(code) ?? 0) == 0 || inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !(detected.portOptions(choice: profileName)).contains(where: { $0.code == input }))
                }
            }
            Button("Refresh connected screens") { runtime.refreshAllDisplays() }.disabled(runtime.discovering)
        }
    }
    var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(node.group.presets.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.group.presets[i].name).font(.headline)
                    HStack {
                        Picker("Key", selection: Binding(get: { node.group.presets[i].shortcut.key }, set: { key in changeShortcut(i) { $0.key = key } })) { ForEach(DeskShortcutKey.names, id: \.self) { Text($0).tag($0) } }.frame(width: 100)
                        modifier("Ctrl", \.control, i); modifier("Opt", \.option, i); modifier("Cmd", \.command, i); modifier("Shift", \.shift, i)
                    }
                }
            }
            Text("Desk shortcuts are shared with every computer in this desk. Editing does not switch the screens.").font(.callout).foregroundStyle(.secondary)
            if !node.pendingPeers.isEmpty { Text("Saved here. Waiting for \(node.group.computers.filter { node.pendingPeers.contains($0.id) }.map(\.name).joined(separator: ", ")) to acknowledge the latest change.").font(.callout).foregroundStyle(.orange) }
            if let issue = runtime.shortcutProblem { Text(issue).foregroundStyle(.orange) }
        }
    }
    func changeShortcut(_ i: Int, _ edit: (inout KVMShortcut) -> Void) { perform { var group = node.group; edit(&group.presets[i].shortcut); guard !([SafetyConfiguration.load().shortcut, LidCountdownController.shared.shortcuts.increase, LidCountdownController.shared.shortcuts.decrease].contains { group.presets[i].shortcut.matches($0) }) else { throw KVMError("Those keys are used by another Perch action on this Mac. Choose another combination.") }; try node.edit(group) } }
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
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(group.reviewDetails.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
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
            if group.monitors[i].control?.mode != mode { group.monitors[i].inputProfile = nil }
            group.monitors[i].control = .init(computer: computer, localDisplay: display, mode: mode)
            try node.edit(group)
        }
    }
    @ViewBuilder var monitorSetup: some View {
        if let selection, let monitor = node.group.monitors.first(where: { $0.id == selection }) {
            Text("\(monitor.name) setup").font(.title2.bold())
            Text("The input profile defines this monitor’s port codes and control protocol. Cable connections and the three Desk presets are configured on the desk.").font(.callout).foregroundStyle(.secondary)
            let detected = monitor.control.flatMap { control in runtime.displays[control.computer]?.first { $0.id == control.localDisplay } }
            Picker("Input profile", selection: Binding(get: { monitor.inputProfile ?? "" }, set: { value in
                guard let profile = MonitorProfiles.entries.first(where: { $0.name == value }) else { return }
                perform { try runtime.configureMonitor(selection, profile: profile); loadControl() }
            })) {
                if monitor.inputProfile == nil { Text("Current custom controls").tag("") }
                ForEach(MonitorProfiles.entries.filter { $0.vendor == detected?.vendor || $0.name == monitor.inputProfile }, id: \.name) { Text($0.name).tag($0.name) }
            }
            Text("Matching ports keep their cables and preset choices. A profile adds its known ports; it does not remove extra ports you configured.").font(.caption).foregroundStyle(.secondary)
            if let detected {
                if detected.profile(choice: "") == nil { Text("No verified automatic profile match. The model name printed on the monitor may be more specific than the name macOS reports.").font(.callout).foregroundStyle(.secondary) }
                else if let suggested = detected.profile(choice: ""), monitor.inputProfile != suggested.name {
                    Button("Use suggested controls: \(suggested.name)") { perform { try runtime.configureMonitor(selection, profile: suggested); loadControl() } }
                }
                DisclosureGroup("Detection details") {
                    Text("macOS name: \(detected.name)")
                    Text("Vendor \(detected.vendor) · Product \(detected.model)")
                    if let family = detected.firmwareFamily { Text("Firmware family: " + family) }
                    if let issue = detected.inspectionProblem { Text(issue).foregroundStyle(.orange) }
                    Text("A firmware family suggests input controls; it does not prove the retail suffix or identify a unique physical screen.").font(.caption).foregroundStyle(.secondary)
                    Button("Read monitor details again") { if let control = monitor.control { runtime.inspect(control.localDisplay, computer: control.computer) } }
                }
            } else { Text("Reconnect the control computer to read this monitor’s details.").foregroundStyle(.secondary) }
            DisclosureGroup("Advanced control connection") { control }
        } else { Text("This screen was removed from the desk.") }
    }
    var control: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitor control").font(.title2.bold())
            Text("This connection sends input commands and reads the monitor’s current input. It can differ from the computer shown on the screen. Valid changes save immediately; editing does not switch inputs.").font(.callout).foregroundStyle(.secondary)
            Picker("Control through", selection: Binding(get: { computer.map { $0.uuidString + "|" + display } ?? "" }, set: { choice in let parts = choice.split(separator: "|"); if parts.count == 2 { computer = UUID(uuidString: String(parts[0])); display = String(parts[1]); saveControl() } })) {
                Text("Choose connection").tag("")
                ForEach(runtime.mappingOptions) { option in Text((node.group.computers.first { $0.id == option.computer }?.name ?? "Computer") + " · " + option.label).tag(option.id) }
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
                Text("Set up monitor presets first. Keyboard and mouse sharing is optional: enable it for each Mac in Keyboard & mouse sharing when you are ready. Secure password entry always needs a local keyboard.").foregroundStyle(.secondary)
                Button("Set up this desk") { coordinator.enable() }.buttonStyle(.borderedProminent)
                if let problem = coordinator.problem { Text(problem).foregroundStyle(.orange); Button("Try opening Desk again") { coordinator.enable() } }
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
extension AppDelegate {
    @objc func deskSettings() {
        let view = NSHostingView(rootView: DeskSettingsRoot())
        view.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        SettingsWindow.shared.show(.init(title: "Desk", detail: "Arrange shared screens and edit three presets. Play switches the actual inputs. Keyboard & mouse sharing has its own page in the sidebar.", view: view, preferredBodyWidth: 720))
    }
}

extension AppDelegate {
    func refreshDeskMenu() {
        let runtime = DeskCoordinator.shared.runtime
        runtime?.registerShortcuts()
        for item in deskPresetItems {
            item.isHidden = runtime == nil
            guard let runtime else { continue }
            let preset = runtime.node.group.presets[item.tag]
            let issue = runtime.switching.readiness(preset.id)
            label(item, preset.name, hint: runtime.switching.activePreset == preset.id ? "Confirmed" : "")
            (item.view as? MenuRowView)?.shortcutHint = preset.shortcut.label
            item.isEnabled = issue == nil
            item.menuHelp = issue ?? DeskModel.presetActivationHelp
        }
    }
    @objc func useDeskPreset(_ item: NSMenuItem) {
        guard let runtime = DeskCoordinator.shared.runtime, runtime.node.group.presets.indices.contains(item.tag) else { return }
        withMenuClosed { runtime.activatePreset(runtime.node.group.presets[item.tag].id) }
    }
}

/// Ordinary settings remain navigable; only bounded operations use Desk sheets.
struct DeskPreferencesRoot: View {
    @ObservedObject var coordinator = DeskCoordinator.shared
    let kind: String
    var body: some View {
        if let runtime = coordinator.runtime { DeskPreferencesMember(runtime: runtime, node: runtime.node, kind: kind) }
        else { DeskSettingsRoot() }
    }
}
struct DeskPreferencesMember: View {
    let runtime: DeskRuntime
    @ObservedObject var node: KVMDeskNode
    let kind: String
    var body: some View {
        if node.isMember {
            ScrollView {
                DeskLiveSheet(runtime: runtime, kind: kind, selection: nil, close: {})
                    .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else { DeskMemberRoot(runtime: runtime, node: node) }
    }
}
extension AppDelegate {
    @objc func deskPreferences() { hotkeySettings() }
    @objc func deskInputPreferences() {
        let view = NSHostingView(rootView: DeskPreferencesRoot(kind: "input"))
        view.frame = NSRect(x: 0, y: 0, width: 650, height: 610)
        SettingsWindow.shared.show(.init(title: "Keyboard & mouse sharing",
            detail: "Enable control on this Mac and manage shared keyboards. Changes save immediately; sharing a session is a separate action.",
            view: view, preferredBodyWidth: 650))
    }
}
