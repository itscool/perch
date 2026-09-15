import SwiftUI

struct DeskView: View {
    @ObservedObject var model: DeskModel
    @State private var sheet: String?
    @State private var draftName = ""
    @State private var draftInput = "HDMI 1"
    @State private var draftComputer: UUID?
    @State private var draftScreen: UUID?
    @State private var draftConnection: UUID?
    @State private var showRemove = false
    @State private var hoveredPreset: UUID?
    @State private var fallbackAspect = 16.0 / 9.0
    @State private var showingDeskAttention = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bird.fill").font(.system(size: 26)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        DeskInlineName(title: "Desk name", saved: model.group.name) { value in
                            model.edit { $0.name = value }
                            if let problem = model.problem { throw KVMError(problem) }
                        }.id(model.group.id).font(.system(size: 27, weight: .semibold)).lineLimit(1)
                        DeskAttentionBadge(model: model, showing: $showingDeskAttention)
                    }
                    Text("\(model.group.computers.count) computers · \(model.group.monitors.count) screens").foregroundStyle(.secondary)
                }
                Spacer()
                if model.live == nil { Menu {
                    Text("Simulated devices only — no network or hardware actions")
                    Toggle("Fail next switch", isOn: $model.failNextSwitch)
                    Button("Simulate concurrent edit") { model.simulateConflict() }
                    Button("First-use desk…") { draftName = "My new desk"; sheet = "newDesk" }
                } label: { Text("DESK LAB · SIMULATION").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary) }.fixedSize() }
                if model.conflict != nil { Button("Review conflicting changes") { sheet = "conflict" } }
            }.padding(24)
            // Keep each card wide enough for its title, status and shortcut.
            // The adaptive grid stacks cards once the dialog is too narrow
            // instead of letting a word wrap into a tall, broken card.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            DeskInlineName(title: "Preset \(index + 1) name", saved: preset.name, select: { model.presetIndex = index; model.problem = nil }) { value in
                                model.edit { group in
                                    if let i = group.presets.firstIndex(where: { $0.id == preset.id }) { group.presets[i].name = value }
                                }
                                if let problem = model.problem { throw KVMError(problem) }
                            }.id(preset.id).font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 6) {
                                Text(model.presetIndex == index ? "Editing" : "Click to edit")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(model.presetIndex == index ? .teal : .secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background((model.presetIndex == index ? Color.teal : Color.secondary).opacity(0.11), in: Capsule())
                                    .fixedSize()
                                    .help(model.presetIndex == index ? "This is the preset whose connections are shown below." : "Select this card to edit its connections.")
                                if let issue = model.readinessIssue(for: index) {
                                    DeskPresetAttention(title: preset.assignments.isEmpty ? "Not mapped" : "Needs attention", detail: issue)
                                } else if !preset.assignments.isEmpty {
                                    Text("\(preset.assignments.count) screens")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    Color.clear.frame(width: 1, height: 18)
                                }
                                if model.active?.id == preset.id {
                                    Text(model.changedSinceUse ? "Active now · edited" : "Active now")
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule()).fixedSize()
                                        .help(model.changedSinceUse ? "This preset is still active on the displays, but its saved connections were edited. Play it again to apply those edits." : "This is the preset currently active on the displays. Selecting another card only changes what you edit.")
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 6) {
                            Button { model.activatePreset(index) } label: { Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 23) }
                                .buttonStyle(DeskCanvasButtonStyle()).foregroundStyle(.teal).disabled(model.readinessIssue(for: index) != nil)
                                .accessibilityLabel("Switch to \(preset.name)")
                                .help(model.readinessIssue(for: index) ?? (model.live == nil ? "Switch to this preset now. The Desk Lab simulates the switch." : DeskModel.presetActivationHelp))
                            Text(preset.shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(model.presetIndex == index ? Color.teal.opacity(hoveredPreset == preset.id ? 0.16 : 0.10) : (hoveredPreset == preset.id ? Color.teal.opacity(0.06) : Color(nsColor: .controlBackgroundColor))))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.presetIndex == index ? Color.teal : Color(nsColor: .separatorColor), lineWidth: model.presetIndex == index ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { model.presetIndex = index; model.problem = nil }
                        .onHover { hovering in hoveredPreset = hovering ? preset.id : (hoveredPreset == preset.id ? nil : hoveredPreset) }
                        .accessibilityAction(named: "Edit preset") { model.presetIndex = index; model.problem = nil }
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
            DeskCanvas(model: model,
                remove: { id in model.selected = id; sheet = "removeScreen" },
                dimensions: { id in model.selected = id; sheet = "dimensions" },
                identify: { id in model.selected = id; model.identify() },
                hardware: { id in model.selected = id; sheet = "monitorSetup" },
                cable: beginCable,
                editPort: { id in draftConnection = id; sheet = "port" },
                addPort: { id in model.selected = id; draftScreen = id; sheet = "connections" },
                computerDetails: { id in draftComputer = id; draftName = model.group.computers.first { $0.id == id }?.name ?? "Computer"; sheet = "computerDetails" },
                removeComputer: { id in draftComputer = id; sheet = "removeComputer" },
                addComputer: { sheet = "computer" },
                addScreen: { draftName = "New screen"; draftComputer = model.group.computers.first?.id; draftScreen = nil; sheet = "screen" })
                .frame(minHeight: 430, maxHeight: .infinity)
                .padding(24)
                .background(Color(nsColor: .textBackgroundColor))

        }.frame(minWidth: 560, minHeight: 520)
            .onChange(of: sheet) { _, next in if next != nil { model.problem = nil; showRemove = false } }
            .sheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) { sheetView }
    }

    func beginCable(_ port: UUID, _ computer: UUID) {
        guard let connection = model.group.connections.first(where: { $0.id == port }), model.group.computers.contains(where: { $0.id == computer }) else { return }
        model.selected = connection.monitor; draftConnection = port; draftComputer = computer
        if connection.computer == computer && connection.localDisplay != nil { return }
        model.live?.refreshScreens?()
        if model.live == nil, connection.computer == nil { model.mapConnection(port, computer: computer); return }
        let options = model.cableOptions(for: computer).filter { model.cableConflict($0, port: port) == nil }
        if options.isEmpty, connection.computer == nil, let mapComputer = model.live?.mapComputer {
            mapComputer(port, computer); return
        }
        let alreadyWired = options.contains { option in model.group.connections.contains { $0.computer == computer && $0.localDisplay == option.display } }
        if let only = options.first, options.count == 1, connection.computer == nil, !alreadyWired {
            model.live?.map(port, only.id)
            if model.problem == nil { return }
        }
        sheet = "cable"
    }
    @ViewBuilder var cableSheet: some View {
        if let port = model.group.connections.first(where: { $0.id == draftConnection }),
           let computer = model.group.computers.first(where: { $0.id == draftComputer }) {
            Text("Connect \(computer.name)").font(.title2.bold())
            Text("To \(model.group.monitors.first { $0.id == port.monitor }?.name ?? "screen") · \(port.inputName)").font(.headline)
            if let old = model.group.computers.first(where: { $0.id == port.computer }), old.id != computer.id {
                Text("This replaces the saved cable from \(old.name). It does not switch the monitor’s input.").foregroundStyle(.secondary)
            }
            if let live = model.live {
                let options = model.cableOptions(for: computer.id)
                if options.isEmpty {
                    Text(port.computer == computer.id ? "Cable saved. Perch is waiting for this computer’s display identity." : "You can save this cable now and match its display when macOS reports it.").foregroundStyle(.secondary)
                    Text("If the monitor hides inactive inputs, use your preset to show this computer’s picture, then refresh here.").font(.callout).foregroundStyle(.secondary)
                    if let identifyComputer = live.identifyComputer {
                        let identifyIssue = live.peerActionReadiness?(computer.id, "Identify")
                        Button(live.identifyingComputer?(computer.id) == true ? "Stop identifying displays" : "Identify displays on \(computer.name)") {
                            identifyComputer(computer.id)
                        }
                        .disabled(identifyIssue != nil)
                        .help(identifyIssue ?? "Show a short label on every display currently visible to \(computer.name), so you can match this cable without guessing.")
                        if let identifyIssue { Text(identifyIssue).font(.caption).foregroundStyle(.secondary) }
                    }
                    if port.computer != computer.id {
                        Button("Save cable") { live.mapComputer?(port.id, computer.id); if model.problem == nil { sheet = nil } }
                    }
                } else {
                    Text("Which display on \(computer.name) is this screen? Use Identify if you’re unsure. Connecting saves the cable without changing the picture.").foregroundStyle(.secondary)
                    ForEach(options) { option in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(option.label).font(.headline)
                            if let conflict = model.cableConflict(option, port: port.id) { Text(conflict).foregroundStyle(.secondary) }
                            if let old = model.group.connections.first(where: { $0.id != port.id && $0.monitor == port.monitor && $0.computer == computer.id && $0.localDisplay == option.display }) {
                                Text("Moves this cable from \(old.inputName) to \(port.inputName).").font(.callout)
                            }
                            HStack {
                                Button(option.display.map { live.identifyingDisplay?(computer.id, $0) == true } == true ? "Stop identifying" : "Identify") { if let display = option.display { live.identifyDisplay?(computer.id, display) } }
                                    .disabled(!model.online.contains(computer.id))
                                Button("Connect here") { live.map(port.id, option.id); if model.problem == nil { sheet = nil } }
                                    .disabled(model.cableConflict(option, port: port.id) != nil)
                            }
                        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let status = live.displayStatus?(computer.id) { Text(status).foregroundStyle(.orange) }
                Button("Refresh displays on paired Macs") { live.refreshScreens?() }
            } else {
                Button("Connect cable") { model.mapConnection(port.id, computer: computer.id); if model.problem == nil { sheet = nil } }
            }
        } else { Text("This computer or port was removed. Close this step and choose another port.") }
    }
    @ViewBuilder var portSheet: some View {
        if let port = model.group.connections.first(where: { $0.id == draftConnection }) {
            Text("\(model.group.monitors.first { $0.id == port.monitor }?.name ?? "Screen") · \(port.inputName)").font(.title2.bold())
            DeskTextSetting("Port name", saved: port.inputName) { value in
                model.changeConnection(port.id, input: value); if let problem = model.problem { throw KVMError(problem) }
            }.id(port.id)
            if model.live != nil {
                DisclosureGroup("Advanced input control") {
                    Text("Only change this code using evidence for this monitor’s protocol.").font(.callout).foregroundStyle(.secondary)
                    DeskTextSetting("Input code", saved: port.inputCode.map(String.init) ?? "", numeric: true) { value in
                        guard let code = UInt16(value), code > 0 else { throw KVMError("Enter a code from 1 to 65535.") }
                        model.edit { group in if let i = group.connections.firstIndex(where: { $0.id == port.id }) {
                            group.connections[i].inputCode = code
                            if let m = group.monitors.firstIndex(where: { $0.id == port.monitor }) { group.monitors[m].inputProfile = nil }
                        } }
                        if let problem = model.problem { throw KVMError(problem) }
                    }
                }
            }
            if port.computer != nil { Button("Disconnect cable") { model.disconnectCable(port.id); if model.problem == nil { sheet = nil } } }
            Button("Remove port…", role: .destructive) { sheet = "removeConnection" }
        } else { Text("This port was removed.") }
    }

    var sheetView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(model.live == nil ? "DESK LAB" : "DESK").font(.caption).foregroundStyle(.secondary); Spacer(); Button { sheet = nil; showRemove = false } label: { Image(systemName: "xmark") }.accessibilityLabel("Close").help("Close this temporary step.").keyboardShortcut(.cancelAction) }
            ScrollView { sheetContents }.frame(maxHeight: 560)
            if let problem = model.problem { SettingsFeedback(text: problem) }
        }.padding(25).frame(width: 440)
    }

    @ViewBuilder var sheetContents: some View {
        if let live = model.live, let sheet, ["computer", "screen", "computerDetails", "removeComputer", "conflict", "connections", "removeConnection", "control", "monitorSetup"].contains(sheet) {
            live.sheet(sheet, ["computerDetails", "removeComputer"].contains(sheet) ? draftComputer : (sheet == "removeConnection" || sheet == "correctConnection" ? draftConnection : model.selected), { self.sheet = nil })
        } else {
        switch sheet {
        case "computer":
            Text("Add a computer").font(.title2).fontWeight(.semibold)
            Text("The production flow will find nearby Perches and confirm membership on both computers. Here, add a simulated member to explore a larger desk.").foregroundStyle(.secondary)
            TextField("Computer name", text: $draftName).textFieldStyle(.roundedBorder)
            Button("Add demo computer") { model.addComputer(draftName); if model.problem == nil { sheet = nil } }.buttonStyle(.borderedProminent)
        case "screen":
            Text("Identify a screen").font(.title2).fontWeight(.semibold)
            Text("Identical models aren't necessarily the same physical screen. Confirm whether this is a new screen or another connection to one already in your desk.").foregroundStyle(.secondary)
            Picker("Screen", selection: $draftScreen) { Text("A new physical screen").tag(nil as UUID?); ForEach(model.group.monitors) { Text($0.name).tag(Optional($0.id)) } }
            if draftScreen == nil { TextField("Screen name", text: $draftName).textFieldStyle(.roundedBorder) }
            Picker("Connected computer", selection: $draftComputer) { ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) } }
            Button(draftScreen == nil ? "Add demo screen" : "Confirm shared screen") {
                guard let computer = draftComputer else { return }
                if let screen = draftScreen { model.addConnection(screen: screen, computer: computer, name: "HDMI 1") } else { model.addScreen(draftName, computer: computer) }
                if model.problem == nil { sheet = nil }
            }.buttonStyle(.borderedProminent)
        case "connections":
            Text("Add a monitor port").font(.title2).fontWeight(.semibold)
            Text("Add an input on this physical screen. You can leave its computer unassigned and still select the input in a preset.").foregroundStyle(.secondary)
            Picker("Computer", selection: $draftComputer) { Text("Unassigned").tag(nil as UUID?); ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) } }
            TextField("Input, such as HDMI 1", text: $draftInput).textFieldStyle(.roundedBorder)
            Button("Add demo connection") { if let screen = draftScreen { model.addConnection(screen: screen, computer: draftComputer, name: draftInput); if model.problem == nil { sheet = nil } } }
        case "removeConnection":
            Text("Remove this port?").font(.title2).fontWeight(.semibold)
            Text("This clears its assignments from all three presets. The physical screen and other connections remain.")
            Button("Remove demo connection", role: .destructive) { if let id = draftConnection { model.removeConnection(id); if model.problem == nil { sheet = nil } } }
        case "cable": cableSheet
        case "port": portSheet
        case "removeComputer":
            Text("Remove \(model.group.computers.first { $0.id == draftComputer }?.name ?? "computer")?").font(.title2.bold())
            Text("Its cables will be disconnected. Monitor ports and preset input choices remain.")
            Button("Remove computer", role: .destructive) { if let id = draftComputer { model.removeComputer(id); if model.problem == nil { sheet = nil } } }
        case "computerDetails":
            Text(draftName).font(.title2).fontWeight(.semibold)
            Text("\(model.group.connections.filter { $0.computer == draftComputer }.count) screen connections · simulated member").foregroundStyle(.secondary)
            if let computer = draftComputer {
                Button(model.online.contains(computer) ? "Simulate going offline" : "Simulate reconnecting") { model.toggleOnline(computer); sheet = nil }
                if showRemove {
                    Text("Remove this computer from the group? Its monitor connections remain selectable, marked Unassigned. Remote input control stops for those connections.")
                    Button("Remove demo computer", role: .destructive) { model.removeComputer(computer); if model.problem == nil { sheet = nil; showRemove = false } }
                } else { Button("Remove computer…", role: .destructive) { showRemove = true }.disabled(model.group.computers.count == 1) }
            }
        case "removeScreen":
            Text("Remove \(model.selectedMonitor?.name ?? "screen")?").font(.title2).fontWeight(.semibold)
            Text("This removes the screen, its cable connections and its assignments from all three presets. Other screens stay as they are.")
            Button(model.live == nil ? "Remove demo screen" : "Remove screen", role: .destructive) { if let id = model.selected { model.removeScreen(id); if model.problem == nil { sheet = nil } } }
        case "conflict":
            Text("Review both changes").font(.title2).fontWeight(.semibold)
            Text("Two computers edited this desk while apart. Both versions are kept until you choose. This scenario changes the desk name only.").foregroundStyle(.secondary)
            Button("Keep this version: \(model.group.name)") { model.resolve(useOther: false); if model.problem == nil { sheet = nil } }
            Button("Use other version: \(model.conflict?.name ?? "")") { model.resolve(useOther: true); if model.problem == nil { sheet = nil } }
        case "newDesk":
            Text("Start a first-use demo").font(.title2).fontWeight(.semibold)
            Text("This replaces this lab's saved example with an empty desk. It doesn't change your installed Perch.")
            TextField("Desk name", text: $draftName).textFieldStyle(.roundedBorder)
            Button("Create empty demo desk") { model.newDesk(draftName); if model.problem == nil { sheet = nil } }.buttonStyle(.borderedProminent)
        case "dimensions":
            Text("Physical size").font(.title2.bold())
            Text("Use the visible panel’s physical width and height in millimetres, before rotation. Position is set directly in the Desk graph.").foregroundStyle(.secondary)
            if let monitor = model.selectedMonitor {
                let detectedAspect = model.live?.panelAspect?(monitor.id) ?? monitor.panelAspect
                let aspect = detectedAspect ?? fallbackAspect
                HStack {
                    Text("Diagonal (inches)")
                    TextField("Screen diagonal in inches", value: Binding(get: { hypot(monitor.geometry.width, monitor.geometry.height) / 25.4 }, set: { inches in
                        if let size = DeskPhysicalSize.estimate(inches: inches, aspect: aspect) { model.resize(width: size.width, height: size.height) }
                        else { model.problem = "Enter a diagonal from 1 to 300 inches." }
                    }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 90)
                }
                if detectedAspect != nil {
                    Text("Aspect ratio detected from the display. Changing the diagonal estimates the panel’s width and height below.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Aspect ratio unavailable", selection: $fallbackAspect) {
                        Text("16:9").tag(16.0 / 9.0); Text("16:10").tag(1.6); Text("21:9").tag(21.0 / 9.0); Text("32:9").tag(32.0 / 9.0); Text("4:3").tag(4.0 / 3.0)
                    }
                    Text("No display capabilities are available yet. Choose a ratio only to estimate from a diagonal; exact millimetres remain editable.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Width (mm)"); TextField("Width in millimetres", value: Binding(get: { monitor.geometry.width }, set: { model.resize(width: $0, height: monitor.geometry.height) }), format: .number).textFieldStyle(.roundedBorder)
                    Text("Height (mm)"); TextField("Height in millimetres", value: Binding(get: { monitor.geometry.height }, set: { model.resize(width: monitor.geometry.width, height: $0) }), format: .number).textFieldStyle(.roundedBorder)
                }
            }
        default: EmptyView()
        }
        }
    }
}

private struct DeskPresetAttention: View {
    let title: String
    let detail: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Label(title, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(DeskCanvasButtonStyle(padding: 0)).help(detail)
            .accessibilityLabel(title + ". " + detail)
            .popover(isPresented: $showing) { Text(detail).font(.callout).frame(width: 250, alignment: .leading).padding(14) }
    }
}

private struct DeskAttentionBadge: View {
    @ObservedObject var model: DeskModel
    @Binding var showing: Bool

    private var detail: String? {
        if let problem = model.problem { return problem }
        if !model.monitorProblems.isEmpty { return "One or more screens needs attention. Review the affected screen in the inspector." }
        return nil
    }

    var body: some View {
        Group {
            if let detail {
                Button { showing.toggle() } label: {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .buttonStyle(DeskCanvasButtonStyle(padding: 0))
                .help(detail)
                .accessibilityLabel("Desk needs attention. " + detail)
                .popover(isPresented: $showing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Desk needs attention", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if !model.monitorProblems.isEmpty {
                            Divider()
                            Text("Review affected screens").font(.subheadline.weight(.semibold))
                            ForEach(model.group.monitors.filter { model.monitorProblems.contains($0.id) }) { monitor in
                                Button("Review " + monitor.name) {
                                    model.selected = monitor.id
                                    showing = false
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    .frame(width: 310, alignment: .leading)
                    .padding(14)
                }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(maxWidth: 170, alignment: .leading)
    }
}

private struct DeskCableAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

/// Only actual controls exclude the monitor surface; passive labels and scroll
/// containers must not create dead regions around them.
private struct DeskControlFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private extension View {
    func deskControl(_ id: String) -> some View {
        background(GeometryReader { area in
            Color.clear.preference(key: DeskControlFrames.self, value: [id: area.frame(in: .named("deskScreenCanvas"))])
        })
    }
}

private struct DeskScreenDrag {
    let id: UUID
    let geometry: KVMGeometry
    let layout: DeskCanvasLayout
    var translation: CGSize
}

struct DeskCanvas: View {
    @ObservedObject var model: DeskModel
    let remove: (UUID) -> Void
    let dimensions: (UUID) -> Void
    let identify: (UUID) -> Void
    let hardware: (UUID) -> Void
    let cable: (UUID, UUID) -> Void
    let editPort: (UUID) -> Void
    let addPort: (UUID) -> Void
    let computerDetails: (UUID) -> Void
    let removeComputer: (UUID) -> Void
    let addComputer: () -> Void
    var addScreen: () -> Void = {}
    @State private var renamingMonitor: UUID?
    @State private var hoveredScreen: UUID?
    @State private var drag: DeskScreenDrag?
    @State private var controlFrames: [String: CGRect] = [:]
    @StateObject private var wire = DeskWireController()
    @State private var snapBypassed = false
    @State private var modifierMonitor: Any?
    @State private var canvasPan = CGSize.zero
    @State private var canvasPanStart: CGSize?

    var body: some View {
        GeometryReader { viewport in
        // Reserve room for the computer row and its legend. The old
        // `height - 160` proposal let the screen canvas consume nearly the
        // entire window, leaving the computers below the visible viewport.
        let graphHeight = max(210, viewport.size.height - 320)
        let rectangles = model.group.monitors.map { rectangle($0.geometry) }
        let minimumScale = DeskCanvasLayout.minimumScale(for: rectangles)
        let available = CGSize(width: max(1, viewport.size.width - 24), height: graphHeight)
        let fittingLayout = DeskCanvasLayout(rectangles: rectangles, viewport: available, minimumScale: minimumScale)
        // Once cards reach their readable minimum, let the desk grow inside
        // the outer scroller instead of shrinking labels and controls away.
        let canvasSize = CGSize(width: max(available.width, fittingLayout.bounds.width * fittingLayout.scale + 32),
                                height: max(available.height, fittingLayout.bounds.height * fittingLayout.scale + 32))
        let liveLayout = DeskCanvasLayout(rectangles: rectangles, viewport: canvasSize, minimumScale: minimumScale)
        // Store panning in physical canvas units. A resize can change the
        // zoom, but it must not reinterpret an existing pan as a different
        // physical location.
        let rawCanvasPanOffset = CGSize(width: canvasPan.width * liveLayout.scale,
                                        height: canvasPan.height * liveLayout.scale)
        // The computer row is part of the pannable desk surface. Keep the
        // surface's rendered bounds finite so resizing or dragging cannot
        // expose unbounded blank canvas or cut the lower nodes away.
        let surfaceSize = CGSize(width: canvasSize.width,
                                  height: canvasSize.height + (model.group.computers.isEmpty ? 58 : 154))
        let canvasPanOffset = DeskCanvasLayout.clampedPan(rawCanvasPanOffset,
                                                          content: surfaceSize,
                                                          viewport: available)
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
        VStack(spacing: 16) {
            HStack {
                Text("Screens").font(.headline).lineLimit(1)
                Spacer()
                Text("Preset \(model.presetIndex + 1) selected").font(.caption).foregroundStyle(.secondary)
                Button(action: addScreen) { Label("Add screen", systemImage: "plus") }
                    .disabled(model.group.monitors.count >= 16)
                    .help("Add a physical screen to this desk. Up to 16 screens.")
            }
            // Keep the graph (screens, wires and computers) pannable as one
            // unit while leaving the Screens header in the viewport.
            VStack(spacing: 16) {
            let layout = drag?.layout ?? liveLayout
            ZStack(alignment: .topLeading) {
                // The empty surface owns panning. It sits behind every
                // screen and socket, so node controls keep their hit targets
                // and a drag can start anywhere that is genuinely empty.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .onChanged { value in
                            guard drag == nil, wire.gesture.source == nil else { return }
                            if canvasPanStart == nil { canvasPanStart = canvasPan }
                            let start = canvasPanStart ?? .zero
                            let scale = max(0.000001, layout.scale)
                            let proposed = CGSize(width: start.width + value.translation.width / scale,
                                                  height: start.height + value.translation.height / scale)
                            let rendered = CGSize(width: proposed.width * scale,
                                                  height: proposed.height * scale)
                            let bounded = DeskCanvasLayout.clampedPan(rendered,
                                                                       content: surfaceSize,
                                                                       viewport: available)
                            canvasPan = CGSize(width: bounded.width / scale,
                                               height: bounded.height / scale)
                        }
                        .onEnded { _ in canvasPanStart = nil })
                if model.group.monitors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "display.2").font(.system(size: 40, weight: .light))
                        Text("Add a screen, then connect its ports to the computers below.").foregroundStyle(.secondary)
                    }.frame(width: available.width, height: available.height)
                }
                ForEach(Array(model.group.monitors.enumerated()), id: \.element.id) { index, monitor in
                    screen(monitor, index: index, layout: layout)
                }
                if let drag { snapPreview(drag) }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Computers").font(.headline)
                    Spacer()
                    Button(action: addComputer) { Label("Add computer", systemImage: "plus") }.disabled(model.group.computers.count >= 16)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], alignment: .leading, spacing: 10) {
                    ForEach(model.group.computers) { computer in
                        computerCard(computer).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6).padding(.bottom, 2)
                Text("Teal routes are selected for preset \(model.presetIndex + 1); green routes are active now. Drag a numbered computer port to a monitor input to assign that preset. Play switches the displays.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).frame(minWidth: available.width, alignment: .leading)
            // Establish coordinates before applying the surface offset. This
            // keeps socket/control hit testing stable while the graph moves.
            .coordinateSpace(name: "deskScreenCanvas")
            .offset(canvasPanOffset)
            .onChange(of: canvasSize) { _, _ in
                // A resize can make the old world-space pan invalid. Fold it
                // back into the new finite surface before the next gesture,
                // so the first drag never jumps from a stale anchor.
                let scale = max(0.000001, liveLayout.scale)
                let rendered = CGSize(width: canvasPan.width * scale, height: canvasPan.height * scale)
                let bounded = DeskCanvasLayout.clampedPan(rendered, content: surfaceSize, viewport: available)
                canvasPan = CGSize(width: bounded.width / scale, height: bounded.height / scale)
            }
            .onChange(of: model.group.monitors.map(\.id)) { _, ids in if let current = drag, !ids.contains(current.id) { finishScreenDrag() } }
            .onPreferenceChange(DeskControlFrames.self) { controlFrames = $0 }
            .onChange(of: model.group.connections) { _, _ in wire.move(to: wire.gesture.point) }
            .onAppear {
                wire.connect = cable
                wire.connection = { id in model.group.connections.first { "port:" + $0.id.uuidString == id } }
                wire.rewire = { source, target in model.rewireCable(source, to: target) }
                wire.presetConnect = { slot, computer, port in model.assignPresetPort(slot: slot, computer: computer, connection: port) }
            }
            .onDisappear { finishScreenDrag(); wire.cancel() }
            .overlay { DeskWireOverlay(controller: wire).allowsHitTesting(false) }
            .backgroundPreferenceValue(DeskCableAnchors.self) { anchors in deskWireLayer(anchors) }
        }
        // The desk is one surface: its header, graph and computer row share a
        // bounded rounded container that fills the available dialog height.
        // Nodes can move inside it; the surface itself does not grow or
        // disappear as content is rearranged.
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .underPageBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        }
    }
    private func finishScreenDrag() {
        drag = nil; snapBypassed = false
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }; modifierMonitor = nil
    }
    private func deskWireLayer(_ anchors: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { area in
            ForEach(model.group.connections.filter { wire.detachedPort != $0.id }) { connection in
                ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { slot, preset in
                    if preset.assignments.contains(where: { $0.connection == connection.id }),
                       let computer = connection.computer,
                       let start = anchors["preset:\(computer.uuidString):\(slot + 1)"], let end = anchors["port:" + connection.id.uuidString] {
                        let source = area[start], target = area[end]
                        let chosen = slot == model.presetIndex
                        let activeRoute = model.active?.id == preset.id
                        let focused = chosen && model.selected == connection.monitor
                        let startPoint = CGPoint(x: source.midX, y: source.minY)
                        let endPoint = CGPoint(x: target.midX, y: target.maxY)
                        let middleY = (startPoint.y + endPoint.y) / 2
                        let control1 = CGPoint(x: startPoint.x, y: middleY)
                        let control2 = CGPoint(x: endPoint.x, y: middleY)
                        let strokeColor: Color = activeRoute && chosen ? .purple : (activeRoute ? .green : (chosen ? .teal.opacity(focused ? 1 : 0.78) : .secondary.opacity(0.48)))
                        let lineWidth: CGFloat = activeRoute && chosen ? 3.8 : (activeRoute || focused ? 3 : (chosen ? 2.5 : 1.5))
                        Path { path in
                            path.move(to: startPoint)
                            path.addCurve(to: endPoint, control1: control1, control2: control2)
                        }.stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
        }.allowsHitTesting(false)
    }
    private func snapPreview(_ drag: DeskScreenDrag) -> some View {
        let layout = drag.layout
        let proposed = rectangle(drag.geometry).offsetBy(dx: drag.translation.width / layout.scale, dy: drag.translation.height / layout.scale)
        let preview = DeskScreenPlacement.preview(proposed, among: model.group.monitors.filter { $0.id != drag.id }.map { rectangle($0.geometry) }, scale: layout.scale, bypass: snapBypassed)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: layout.origin.x + (x - layout.bounds.minX) * layout.scale, y: layout.origin.y + (y - layout.bounds.minY) * layout.scale) }
        return ZStack(alignment: .topLeading) {
            if !snapBypassed && !preview.guides.isEmpty {
                Path { path in
                    let r = preview.rectangle, p = point(r.minX, r.minY)
                    path.addRoundedRect(in: CGRect(origin: p, size: CGSize(width: r.width * layout.scale, height: r.height * layout.scale)), cornerSize: CGSize(width: 9, height: 9))
                }.stroke(Color.teal, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                ForEach(Array(preview.guides.enumerated()), id: \.offset) { _, guide in
                    let a = guide.horizontal ? point(guide.start, guide.position) : point(guide.position, guide.start)
                    let b = guide.horizontal ? point(guide.end, guide.position) : point(guide.position, guide.end)
                    Path { path in path.move(to: a); path.addLine(to: b) }.stroke(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text(guide.label).font(.system(size: 9, weight: .medium)).padding(2)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: a.x + 3, y: a.y - 14)
                }
            }
        }.allowsHitTesting(false)
    }
    private func rectangle(_ g: KVMGeometry) -> CGRect { CGRect(x: g.x, y: g.y, width: g.displayedWidth, height: g.displayedHeight) }
    private func isScreenControl(_ point: CGPoint, monitor: UUID) -> Bool {
        var ids = ["rename:", "identify:", "hardware:", "dimensions:", "rotate:", "remove:", "addPort:"].map { $0 + monitor.uuidString }
        for port in model.group.connections where port.monitor == monitor {
            ids += ["port:" + port.id.uuidString]
        }
        return ids.contains { controlFrames[$0]?.contains(point) == true }
    }
    private func presetSummary(_ monitor: KVMMonitor) -> String {
        let prefix = "Preset \(model.presetIndex + 1) · "
        guard let port = model.preset.assignments.first(where: { $0.monitor == monitor.id }).flatMap({ a in model.group.connections.first { $0.id == a.connection } }) else { return prefix + "Unmapped" }
        let computer = model.group.computers.first { $0.id == port.computer }?.name ?? "Unassigned computer"
        return prefix + port.inputName + " · " + computer
    }
    private func screen(_ monitor: KVMMonitor, index: Int, layout: DeskCanvasLayout) -> some View {
        let g = monitor.geometry, scale = layout.scale
        let width = max(1, g.displayedWidth * scale), height = max(1, g.displayedHeight * scale)
        let compact = width < 145 || height < 140
        let portLabelHeight = max(18, min(72, height - (compact ? 70 : 104)))
        let translation = drag?.id == monitor.id ? drag!.translation : .zero
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                    if model.identifying == monitor.id || compact {
                        Text("\(index + 1)").font(.system(size: model.identifying == monitor.id ? 36 : 13, weight: .semibold)).lineLimit(1)
                    } else { Color.clear.frame(height: 20) }
                    if !compact {
                        Text(presetSummary(monitor)).font(.system(size: 10, weight: .medium)).lineLimit(1).help(presetSummary(monitor))
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 9).padding(.top, 9)
                    .frame(width: width, height: height, alignment: .topLeading).clipped()
                    .background(RoundedRectangle(cornerRadius: 9).fill(model.selected == monitor.id ? Color.teal.opacity(0.14) : (hoveredScreen == monitor.id ? Color.teal.opacity(0.06) : Color(nsColor: .controlBackgroundColor))))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.selected == monitor.id ? Color.teal : (hoveredScreen == monitor.id ? Color.teal.opacity(0.7) : Color.gray.opacity(0.65)), lineWidth: model.selected == monitor.id ? 2.5 : (hoveredScreen == monitor.id ? 2 : 1.5)))
                .allowsHitTesting(false)
                .accessibilityLabel("Screen \(index + 1), \(monitor.name), \(model.owner(monitor.id)), \(g.rotation.rawValue) degrees")
            if !compact && model.identifying != monitor.id {
                HStack(spacing: 3) {
                    Text(monitor.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).allowsHitTesting(false)
                    Button { renamingMonitor = monitor.id } label: { Image(systemName: "pencil").font(.system(size: 11)) }
                        .buttonStyle(DeskCanvasButtonStyle()).accessibilityLabel("Rename " + monitor.name)
                        .help("Rename this screen. Changes save immediately.")
                        .deskControl("rename:" + monitor.id.uuidString)
                        .popover(isPresented: Binding(get: { renamingMonitor == monitor.id }, set: { if !$0 { renamingMonitor = nil } })) {
                            DeskTextSetting("Screen name", saved: monitor.name) { value in
                                model.edit { group in if let i = group.monitors.firstIndex(where: { $0.id == monitor.id }) { group.monitors[i].name = value } }
                                if let problem = model.problem { throw KVMError(problem) }
                            }.padding(12).frame(width: 250)
                        }
                    Spacer(minLength: 0)
                }.padding(.leading, 9).padding(.trailing, 52).padding(.top, 5)
                    .frame(width: width, height: height, alignment: .topLeading)
            }
            if !compact {
                HStack(spacing: 2) {
                    Button { identify(monitor.id) } label: { Image(systemName: (model.live?.identifyingMonitor?(monitor.id) ?? (model.identifying == monitor.id)) ? "stop.circle" : "eye") }
                        .accessibilityLabel((model.live?.identifyingMonitor?(monitor.id) ?? (model.identifying == monitor.id)) ? "Stop identifying (monitor.name)" : "Identify (monitor.name)")
                        .help((model.live?.identifyingMonitor?(monitor.id) ?? (model.identifying == monitor.id)) ? "Stop identifying this screen on every Perch in the desk." : "Identify this screen on every Perch in the desk.")
                        .deskControl("identify:" + monitor.id.uuidString)
                    if model.live != nil {
                        Button { hardware(monitor.id) } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Hardware for " + monitor.name).help("Choose this screen’s hardware and control path")
                            .deskControl("hardware:" + monitor.id.uuidString)
                    }
                    Button { dimensions(monitor.id) } label: { Image(systemName: "ruler") }
                        .accessibilityLabel("Physical size for " + monitor.name).help("Edit physical size and position in millimetres")
                        .deskControl("dimensions:" + monitor.id.uuidString)
                    Button { model.rotateScreen(monitor.id) } label: { Image(systemName: "rotate.right") }
                        .accessibilityLabel("Rotate \(monitor.name)").help("Rotate clockwise")
                        .deskControl("rotate:" + monitor.id.uuidString)
                    Button { remove(monitor.id) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Remove \(monitor.name)").help("Remove screen")
                        .deskControl("remove:" + monitor.id.uuidString)
                }.font(.system(size: 11, weight: .semibold)).buttonStyle(DeskCanvasButtonStyle()).padding(5)
            }
            VStack { Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(model.group.connections.filter { $0.monitor == monitor.id }) { port in portSocket(port, labelHeight: portLabelHeight) }
                    Button { addPort(monitor.id) } label: { Text("+ Port").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(DeskCanvasButtonStyle()).help("Add a monitor port")
                        .deskControl("addPort:" + monitor.id.uuidString).padding(.bottom, 3)
                }.padding(.leading, 7).padding(.trailing, 7)
                    // Keep every input beside its neighbours and pin the
                    // socket row to the physical screen edge. The Desk canvas
                    // owns scrolling when the row or canvas is too wide.
                    .frame(maxWidth: .infinity, minHeight: portLabelHeight + 35, alignment: .bottomLeading)
            }.frame(width: width, height: height)
        }.frame(width: width, height: height)
            .contentShape(Rectangle())
                .onHover { hovering in hoveredScreen = hovering ? monitor.id : (hoveredScreen == monitor.id ? nil : hoveredScreen) }
                .help("Drag to arrange this physical screen. Guides preview edge and center alignment. Hold Shift to bypass snapping; gaps are allowed. Right-click for exact size in millimetres.")
                .contextMenu {
                    Button("Physical size…") { dimensions(monitor.id) }
                    Button("Rotate clockwise") { model.rotateScreen(monitor.id) }
                    Button("Add port…") { addPort(monitor.id) }
                    Button("Remove screen…", role: .destructive) { remove(monitor.id) }
                }
            .accessibilityAction(named: "Select screen") { model.selected = monitor.id }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("deskScreenCanvas")).onEnded { value in
                if !isScreenControl(value.location, monitor: monitor.id) { model.selected = monitor.id }
            })
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("deskScreenCanvas"))
                    .onChanged { value in
                        if drag == nil {
                            guard wire.gesture.source == nil, !isScreenControl(value.startLocation, monitor: monitor.id) else { return }
                            drag = DeskScreenDrag(id: monitor.id, geometry: g, layout: layout, translation: .zero); model.selected = monitor.id
                            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in snapBypassed = event.modifierFlags.contains(.shift); return event }
                        }
                        snapBypassed = NSEvent.modifierFlags.contains(.shift)
                        guard drag?.id == monitor.id else { return }
                        drag?.translation = value.translation
                    }.onEnded { value in
                        guard let started = drag, started.id == monitor.id else { return }
                        defer { finishScreenDrag() }
                        guard let current = model.group.monitors.first(where: { $0.id == monitor.id }), current.geometry == started.geometry else {
                            model.problem = "This screen changed on another computer while you were moving it. Try the move again."; return
                        }
                        let proposed = rectangle(started.geometry).offsetBy(dx: value.translation.width / started.layout.scale, dy: value.translation.height / started.layout.scale)
                        let placed = DeskScreenPlacement.preview(proposed, among: model.group.monitors.filter { $0.id != monitor.id }.map { rectangle($0.geometry) }, scale: started.layout.scale, bypass: NSEvent.modifierFlags.contains(.shift)).rectangle
                        model.move(monitor.id, x: placed.minX, y: placed.minY)
                    })

            .offset(x: layout.origin.x + (g.x - layout.bounds.minX) * scale + translation.width,
                    y: layout.origin.y + (g.y - layout.bounds.minY) * scale + translation.height)
    }
    private func portSocket(_ port: KVMConnection, labelHeight: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text(port.inputName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                .frame(width: labelHeight, height: 14, alignment: .leading)
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: labelHeight)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            DeskWireSocket(id: "port:" + port.id.uuidString, connected: port.computer != nil,
                           label: model.connectionLabel(port), controller: wire,
                           presetNumbers: model.group.presets.enumerated().compactMap { index, preset in preset.assignments.contains { $0.connection == port.id } ? index + 1 : nil },
                           highlighted: model.preset.assignments.contains { $0.connection == port.id },
                           activeRouting: model.active?.assignments.contains { $0.connection == port.id } == true) {
                let menu = DeskSocketMenu()
                if let force = model.live?.forceSwitchConnection ?? model.live?.switchConnection {
                    menu.action("Force switch to this input", enabled: true,
                                help: "Send the monitor command again, even if Perch thinks this input is already selected. Presets stay unchanged.") {
                        model.selected = port.monitor; force(port.id)
                    }
                    menu.addItem(.separator())
                }
                for computer in model.group.computers { menu.action("Connect " + computer.name) { cable(port.id, computer.id) } }
                if port.computer != nil { menu.action("Disconnect cable") { model.disconnectCable(port.id) } }
                menu.addItem(.separator())
                menu.action("Edit port…") { editPort(port.id) }
                return menu
            }.frame(width: 24, height: 20)
                .deskControl("port:" + port.id.uuidString)
                .anchorPreference(key: DeskCableAnchors.self, value: .bounds) { ["port:" + port.id.uuidString: $0] }
        }.frame(width: 24, height: labelHeight + 23)
            .help("\(port.inputName) input. Click for connection and switch options; drag to rewire this input.")
    }

    private func computerCard(_ computer: KVMComputer) -> some View {
        let routes = model.preset.assignments.filter { a in model.group.connections.contains { $0.id == a.connection && $0.computer == computer.id } }
        let focused = routes.contains { $0.monitor == model.selected }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "desktopcomputer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.blue)
                Text(computer.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Button { removeComputer(computer.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(DeskCanvasButtonStyle()).accessibilityLabel("Remove \(computer.name)")
                    .disabled(model.live?.removalIssue?(computer.id) != nil || model.group.computers.count == 1)
                    .help(model.live?.removalIssue?(computer.id) ?? "Remove this computer after confirmation.")
            }
            Text(model.online.contains(computer.id) ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 19)
            .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Color.blue.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(routes.isEmpty ? Color.secondary.opacity(0.5) : Color.blue.opacity(0.75), lineWidth: focused ? 2.5 : 1))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { slot, preset in
                        let assigned = preset.assignments.contains { assignment in
                            model.group.connections.contains { $0.id == assignment.connection && $0.computer == computer.id }
                        }
                        DeskWireSocket(id: "preset:\(computer.id.uuidString):\(slot + 1)", connected: assigned,
                                       label: "Preset \(slot + 1) from \(computer.name)", controller: wire,
                                       presetNumbers: [slot + 1], highlighted: model.presetIndex == slot && assigned,
                                       activeRouting: model.active?.id == preset.id) {
                            let menu = DeskSocketMenu()
                            for port in model.group.connections where port.computer == computer.id || port.computer == nil {
                                let monitor = model.group.monitors.first { $0.id == port.monitor }?.name ?? "Screen"
                                menu.action(monitor + " · " + port.inputName) { model.assignPresetPort(slot: slot + 1, computer: computer.id, connection: port.id) }
                            }
                            return menu
                        }.frame(width: 24, height: 20)
                            .anchorPreference(key: DeskCableAnchors.self, value: .bounds) { ["preset:\(computer.id.uuidString):\(slot + 1)": $0] }
                    }
                }.padding(.leading, 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { computerDetails(computer.id) }
            .accessibilityAction(named: "Edit computer") { computerDetails(computer.id) }
            .help("Click this computer to edit its details. Drag its connector to a monitor port to wire a cable.")
    }
}


/// Local canvas interaction only; no event posting or hardware access.
@MainActor final class DeskWireController: ObservableObject {
    private final class WeakSocket { weak var view: DeskWireSocketView?; init(_ view: DeskWireSocketView) { self.view = view } }
    private var sockets: [String: WeakSocket] = [:]
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    private var geometryPending = false
    private var lastGeometry: [String: CGRect] = [:]
    func scheduleGeometryUpdate() {
        guard gesture.source != nil, !geometryPending else { return }
        geometryPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.geometryPending = false; self.geometryDidChange()
        }
    }
    func geometryDidChange() {
        guard gesture.source != nil else { return }
        let current = sockets.compactMapValues { $0.view.map { $0.convert($0.bounds.intersection($0.visibleRect), to: nil) } }
        guard current != lastGeometry else { return }
        lastGeometry = current
        move(to: gesture.point)
    }
    private(set) var gesture = DeskWireGesture()
    private(set) var target: String?
    var connect: ((UUID, UUID) -> Void)?
    var presetConnect: ((Int, UUID, UUID) -> Void)?
    var connection: ((String) -> KVMConnection?)?
    var rewire: ((KVMConnection, KVMConnection) -> Void)?
    private var pickedUp: KVMConnection?
    var detachedPort: UUID? { gesture.dragging ? pickedUp?.id : nil }
    var cableSource: String? {
        if gesture.dragging, let computer = pickedUp?.computer { return "computer:" + computer.uuidString }
        return gesture.source
    }
    func register(_ view: DeskWireSocketView) {
        sockets[view.socketID] = WeakSocket(view)
        if gesture.source != nil { observeGeometry(of: view); scheduleGeometryUpdate() }
    }
    private func observeGeometry(of view: NSView) {
        var ancestor: NSView? = view
        while let current = ancestor {
            current.postsFrameChangedNotifications = true; current.postsBoundsChangedNotifications = true
            ancestor = current.superview
        }
    }
    func remove(_ view: DeskWireSocketView) {
        guard sockets[view.socketID]?.view === view else { return }
        sockets[view.socketID] = nil
        if gesture.source == view.socketID || cableSource == view.socketID { cancel() } else { scheduleGeometryUpdate() }
    }
    func socket(_ id: String?) -> DeskWireSocketView? { id.flatMap { sockets[$0]?.view } }
    func center(_ id: String?) -> CGPoint? {
        guard let view = socket(id), view.window != nil else { return nil }
        return view.convert(view.attachmentPoint, to: nil)
    }
    func begin(_ id: String, at point: CGPoint) {
        cancel(); gesture.begin(id, at: point)
        if let cable = connection?(id), cable.computer != nil { pickedUp = cable }
        for socket in sockets.values { if let view = socket.view { observeGeometry(of: view) } }
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleGeometryUpdate() }
            })
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancel(); return nil }; return event
        }
        if let window = socket(id)?.window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
    }
    func move(to point: CGPoint) {
        guard let source = gesture.source, let origin = socket(source) else { return }
        if let pickedUp, connection?(source) != pickedUp { cancel(); return }
        gesture.move(to: point)
        guard let effectiveSource = cableSource else { return }
        target = gesture.dragging ? sockets.keys.sorted().first { key in
            guard DeskWireGesture.compatible(effectiveSource, key), let view = socket(key), view.window === origin.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            let visible = view.bounds.intersection(view.visibleRect)
            return !visible.isEmpty && visible.insetBy(dx: -6, dy: -6).contains(view.convert(point, from: nil))
        } : nil
        refresh()
    }
    /// Return true only for a click; callers may then show their menu on mouse-up.
    func end(_ id: String, at point: CGPoint) -> Bool {
        guard gesture.source == id else { return false }
        move(to: point)
        // A geometry refresh may cancel a cable changed by another peer.
        guard gesture.source == id else { return false }
        let destination = target
        if gesture.dragging, let pickedUp {
            let targetCable = destination.flatMap { connection?($0) }
            cancel()
            if let targetCable, targetCable.id != pickedUp.id { rewire?(pickedUp, targetCable) }
            return false
        }
        let inside = socket(id).map { $0.bounds.contains($0.convert(point, from: nil)) } ?? false
        let result = gesture.finish(insideSource: inside, target: destination)
        cancel()
        if case let .connect(source, target) = result {
            let port = source.hasPrefix("port:") ? source : target
            if let p = UUID(uuidString: String(port.dropFirst(5))) {
                let computer = source.hasPrefix("computer:") ? source : target
                if computer.hasPrefix("computer:"), let c = UUID(uuidString: String(computer.dropFirst(9))) { connect?(p, c) }
                let preset = source.hasPrefix("preset:") ? source : target
                if preset.hasPrefix("preset:") {
                    let parts = preset.split(separator: ":")
                    if parts.count == 3, let c = UUID(uuidString: String(parts[1])), let slot = Int(parts[2]) { presetConnect?(slot, c, p) }
                }
            }
        }
        return result == .click
    }
    func cancel() {
        gesture = DeskWireGesture(); target = nil; pickedUp = nil
        for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
        geometryObservers = []; lastGeometry = [:]
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        refresh()
    }
    private func refresh() { objectWillChange.send(); for socket in sockets.values { socket.view?.needsDisplay = true } }
}

final class DeskSocketMenu: NSMenu {
    private final class Action: NSObject { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run }; @objc func invoke() { run() } }
    private var actions: [Action] = []
    func action(_ title: String, enabled: Bool = true, help: String? = nil, _ run: @escaping () -> Void) {
        let target = Action(run); actions.append(target)
        let item = NSMenuItem(title: title, action: #selector(Action.invoke), keyEquivalent: "")
        autoenablesItems = false
        item.target = target; item.isEnabled = enabled; item.toolTip = help; addItem(item)
    }
}

struct DeskWireSocket: NSViewRepresentable {
    let id: String
    let connected: Bool
    let label: String
    let controller: DeskWireController
    var presetNumbers: [Int] = []
    var highlighted = false
    var activeRouting = false
    var menu: (() -> DeskSocketMenu)? = nil
    func makeNSView(context: Context) -> DeskWireSocketView { DeskWireSocketView(frame: .zero) }
    func updateNSView(_ view: DeskWireSocketView, context: Context) {
        if view.socketID != id { view.controller?.remove(view) }
        view.socketID = id; view.connected = connected; view.presetNumbers = presetNumbers; view.highlighted = highlighted; view.activeRouting = activeRouting; view.controller = controller; view.makeMenu = menu
        view.setAccessibilityLabel(label)
        let routeState = (highlighted ? "; selected in editing preset" : "") + (activeRouting ? "; active now" : "")
        view.setAccessibilityValue(presetNumbers.isEmpty ? (activeRouting ? "Active now" : "No presets") : "Presets " + presetNumbers.map(String.init).joined(separator: ", ") + routeState)
        view.toolTip = label + (id.hasPrefix("preset:") ? ". Drag to a monitor input to assign this preset; click for choices." : (connected && id.hasPrefix("port:") ? ". Drag to move this cable to another input; Esc cancels. Click for the port menu." : ". Drag to another connector to draw a wire. Click for connections."))
        controller.register(view); view.needsDisplay = true
    }
    static func dismantleNSView(_ view: DeskWireSocketView, coordinator: ()) { view.controller?.remove(view) }
}
final class DeskWireSocketView: NSView {
    var socketID = ""
    var connected = false
    var presetNumbers: [Int] = []
    var highlighted = false
    var activeRouting = false
    weak var controller: DeskWireController?
    var makeMenu: (() -> DeskSocketMenu)?
    private(set) var hovered = false
    var attachmentPoint: CGPoint {
        let isComputer = socketID.hasPrefix("computer:") || socketID.hasPrefix("preset:")
        return CGPoint(x: bounds.midX, y: isComputer ? bounds.maxY : bounds.minY)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.begin(socketID, at: event.locationInWindow) }
    override func mouseDragged(with event: NSEvent) { controller?.move(to: event.locationInWindow) }
    override func mouseUp(with event: NSEvent) { if controller?.end(socketID, at: event.locationInWindow) == true { showMenu() } }
    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.cancel() }
        else if event.keyCode == 36 || event.keyCode == 49 { showMenu() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { showMenu(); return makeMenu != nil }
    private func showMenu() {
        guard let menu = makeMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        let center = attachmentPoint
        let isComputer = socketID.hasPrefix("computer:") || socketID.hasPrefix("preset:")
        let active = controller?.target == socketID
        func halfCircle(_ radius: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: isComputer ? 180 : 0, endAngle: isComputer ? 360 : 180)
            path.close(); return path
        }
        if hovered || active {
            NSColor.systemTeal.withAlphaComponent(active ? 0.25 : 0.14).setFill(); halfCircle(12).fill()
        }
        // The straight edge meets the device outline; the curved side is inside.
        let socket = halfCircle(8)
        NSColor.controlBackgroundColor.setFill(); socket.fill()
        let detached = controller?.detachedPort.map { socketID == "port:" + $0.uuidString } ?? false
        let base = isComputer ? NSColor.systemBlue : NSColor.systemIndigo
        let color = hovered || active ? NSColor.systemTeal : base
        color.setFill(); color.setStroke()
        socket.lineWidth = active || hovered ? 2.5 : 1.5
        if connected && !detached { socket.fill() } else { socket.stroke() }
        if highlighted {
            let ring = halfCircle(10.5); ring.lineWidth = 2; NSColor.systemTeal.setStroke(); ring.stroke()
        }
        if activeRouting {
            let ring = halfCircle(12); ring.lineWidth = 2; NSColor.systemGreen.setStroke(); ring.stroke()
        }
        if !presetNumbers.isEmpty {
            let text = presetNumbers.map(String.init).joined(separator: " ") as NSString
            let numberColor = highlighted ? NSColor.systemTeal : (activeRouting ? NSColor.systemGreen : base)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: numberColor]
            let size = text.size(withAttributes: attrs)
            // Membership stays visible for every preset, outside the half circle.
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: isComputer ? center.y - 9 - size.height : center.y + 9), withAttributes: attrs)
        }
        if active { let ring = halfCircle(11); ring.lineWidth = 2; ring.stroke() }

    }
}
struct DeskWireOverlay: NSViewRepresentable {
    @ObservedObject var controller: DeskWireController
    func makeNSView(context: Context) -> DeskWireOverlayView { DeskWireOverlayView(frame: .zero) }
    func updateNSView(_ view: DeskWireOverlayView, context: Context) { view.controller = controller; view.needsDisplay = true }
}
final class DeskWireOverlayView: NSView {
    weak var controller: DeskWireController?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout(); needsDisplay = true; controller?.scheduleGeometryUpdate()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let controller, controller.gesture.dragging, let start = controller.center(controller.cableSource) else { return }
        let a = convert(start, from: nil), b = convert(controller.center(controller.target) ?? controller.gesture.point, from: nil)
        let path = NSBezierPath(); path.move(to: a)
        let middle = (a.y + b.y) / 2
        path.curve(to: b, controlPoint1: CGPoint(x: a.x, y: middle), controlPoint2: CGPoint(x: b.x, y: middle))
        path.lineWidth = 2.5
        (controller.target == nil ? NSColor.secondaryLabelColor : NSColor.systemTeal).setStroke()
        if controller.target == nil { path.setLineDash([4, 4], count: 2, phase: 0) }
        path.stroke()
    }
}
