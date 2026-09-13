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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bird.fill").font(.system(size: 26)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.group.name).font(.system(size: 27, weight: .semibold))
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
                Button { if let open = model.live?.openSettings { open() } else { draftName = model.group.name; sheet = "desk" } } label: { Label("Desk settings", systemImage: "slider.horizontal.3") }
            }.padding(24)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(model.group.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack(spacing: 8) {
                        Button { model.presetIndex = index; model.problem = nil } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(preset.name).font(.system(size: 14, weight: .semibold))
                                HStack(spacing: 6) {
                                    Text(model.presetIndex == index ? "Editing" : "\(preset.assignments.count) screens").font(.system(size: 11)).foregroundStyle(.secondary)
                                    if model.active?.id == preset.id {
                                        Label(model.changedSinceUse ? "Active · edited" : "Active", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.teal)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Edit \(preset.name)\(model.presetIndex == index ? ", selected for editing" : "")\(model.active?.id == preset.id ? ", active preset" : "")").help("Edit this preset without changing the running screens or input.")
                        VStack(spacing: 6) {
                            Button { model.activatePreset(index) } label: { Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 23) }
                                .buttonStyle(.bordered).tint(.teal).disabled(model.readinessIssue(for: index) != nil)
                                .accessibilityLabel("Switch to \(preset.name)")
                                .help(model.readinessIssue(for: index) ?? (model.live == nil ? "Switch to this preset now. The Desk Lab simulates the switch." : DeskModel.presetActivationHelp))
                            Text(preset.shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(model.presetIndex == index ? Color.teal.opacity(0.10) : Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.presetIndex == index ? Color.teal : Color(nsColor: .separatorColor), lineWidth: model.presetIndex == index ? 2 : 1))
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Editing \(model.preset.name)").font(.headline)
                            Text(model.live == nil ? "Match your desk. Touching edges let the pointer cross." : "Arrange the screens to match your desk.").font(.callout).foregroundStyle(.secondary)
                            if let issue = model.problem ?? model.readinessIssue {
                                Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button { draftName = "New screen"; draftComputer = model.group.computers.first?.id; draftScreen = nil; sheet = "screen" } label: { Label("Add screen", systemImage: "plus") }
                            .help("Identify a physical screen or add a connection to an existing shared screen. Up to 16 physical screens.")
                    }
                    DeskCanvas(model: model,
                        remove: { id in model.selected = id; sheet = "removeScreen" },
                        dimensions: { id in model.selected = id; sheet = "dimensions" },
                        cable: beginCable,
                        editPort: { id in draftConnection = id; sheet = "port" },
                        addPort: { id in model.selected = id; draftScreen = id; sheet = "connections" },
                        computerDetails: { id in draftComputer = id; draftName = model.group.computers.first { $0.id == id }?.name ?? "Computer"; sheet = "computerDetails" },
                        removeComputer: { id in draftComputer = id; sheet = "removeComputer" },
                        addComputer: { sheet = "computer" }).frame(minHeight: 380, maxHeight: .infinity)

                }.padding(24)
                inspector.frame(width: 276).padding(.leading, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25), lineWidth: 1).allowsHitTesting(false))
            }.background(Color(nsColor: .textBackgroundColor))

        }.frame(minWidth: 560, minHeight: 520)
            .onChange(of: sheet) { _, next in if next != nil { model.problem = nil; showRemove = false } }
            .sheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) { sheetView }
    }

    @ViewBuilder var inspector: some View {
        if let monitor = model.selectedMonitor {
            InspectorScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        DeskTextSetting("Screen name", saved: monitor.name) { value in
                            model.edit { group in if let i = group.monitors.firstIndex(where: { $0.id == monitor.id }) { group.monitors[i].name = value } }
                            if let problem = model.problem { throw KVMError(problem) }
                        }.id(monitor.id).font(.headline)
                        Button((model.live?.identifyingMonitor?(monitor.id) ?? (model.identifying == monitor.id)) ? "Stop identifying" : "Identify") { model.identify() }
                    }
                    if model.live != nil { Button("Monitor setup…") { sheet = "monitorSetup" } }
                    Button("Physical size & position…") { sheet = "dimensions" }
                    ForEach(model.group.connections.filter { $0.monitor == monitor.id && $0.computer != nil && $0.localDisplay == nil }) { pending in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.connectionLabel(pending)).font(.callout)
                            Button("Match display…") { if let computer = pending.computer { beginCable(pending.id, computer) } }
                        }
                    }
                    if let result = model.monitorResults[monitor.id] { Text(result).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Preset inputs").font(.system(size: 12, weight: .semibold))
                        ForEach(0..<3, id: \.self) { index in
                            let preset = model.group.presets[index]
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(preset.name).font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Text(preset.shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Picker("Input for \(preset.name)", selection: Binding<UUID?>(get: { model.group.presets[index].assignments.first { $0.monitor == monitor.id }?.connection }, set: { model.assign($0, preset: index) })) {
                                    if !preset.assignments.contains(where: { $0.monitor == monitor.id }) { Text("Choose input").tag(nil as UUID?).disabled(true) }
                                    ForEach(model.group.connections.filter { $0.monitor == monitor.id }) { connection in
                                        Text(model.connectionLabel(connection)).tag(Optional(connection.id))
                                    }
                                }.labelsHidden().frame(maxWidth: .infinity)
                                if let assignment = preset.assignments.first(where: { $0.monitor == monitor.id }), model.group.connections.contains(where: { $0.id == assignment.connection && $0.computer == nil }) {
                                    Label("Unassigned · picture only", systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange)
                                }
                            }
                        }
                        Text("Choices save immediately. Press play on a preset to switch.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) { Image(systemName: "display.2").font(.largeTitle).foregroundStyle(.teal); Text("Your desk starts here").font(.headline); Text("Add the computers and screens you want to use together. You can return and change anything later.").foregroundStyle(.secondary) }.frame(maxHeight: .infinity, alignment: .top)
        }
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
            if let problem = model.problem { Text(problem).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(25).frame(width: 440)
    }

    @ViewBuilder var sheetContents: some View {
        if let live = model.live, let sheet, ["computer", "screen", "computerDetails", "removeComputer", "conflict", "connections", "removeConnection", "desk", "control", "monitorSetup"].contains(sheet) {
            live.sheet(sheet, ["computerDetails", "removeComputer"].contains(sheet) ? draftComputer : (sheet == "removeConnection" || sheet == "correctConnection" ? draftConnection : model.selected), { self.sheet = nil })
        } else {
        switch sheet {
        case "desk":
            Text("Desk settings").font(.title2).fontWeight(.semibold)
            TextField("Desk name", text: $draftName).textFieldStyle(.roundedBorder).onChange(of: draftName) { _, value in model.edit { $0.name = value } }
            Text("Names and presets save immediately in this demo. Group synchronization is tested separately in the core; this lab does not connect to another computer.").foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { i in
                HStack {
                    TextField("Preset \(i + 1) name", text: Binding(get: { model.group.presets[i].name }, set: { name in model.edit { $0.presets[i].name = name } })).textFieldStyle(.roundedBorder)
                    Text(model.group.presets[i].shortcut.label).font(.callout).foregroundStyle(.secondary)
                }
            }
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
            Text("Physical size & position").font(.title2.bold())
            Text("Use the visible panel’s physical width and height in millimetres, before rotation. These proportions are independent of screen resolution.").foregroundStyle(.secondary)
            if let monitor = model.selectedMonitor {
                HStack {
                    Text("X"); TextField("X", value: Binding(get: { monitor.geometry.x }, set: { model.move(monitor.id, x: $0, y: monitor.geometry.y) }), format: .number).textFieldStyle(.roundedBorder)
                    Text("Y"); TextField("Y", value: Binding(get: { monitor.geometry.y }, set: { model.move(monitor.id, x: monitor.geometry.x, y: $0) }), format: .number).textFieldStyle(.roundedBorder)
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

private struct DeskCableAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
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
    let cable: (UUID, UUID) -> Void
    let editPort: (UUID) -> Void
    let addPort: (UUID) -> Void
    let computerDetails: (UUID) -> Void
    let removeComputer: (UUID) -> Void
    let addComputer: () -> Void
    @State private var drag: DeskScreenDrag?
    @StateObject private var wire = DeskWireController()
    @State private var snapBypassed = false
    @State private var modifierMonitor: Any?

    var body: some View {
        VStack(spacing: 24) {
            GeometryReader { area in
                let liveLayout = DeskCanvasLayout(rectangles: model.group.monitors.map { rectangle($0.geometry) }, viewport: area.size)
                let layout = drag?.layout ?? liveLayout
                ZStack(alignment: .topLeading) {
                    if model.group.monitors.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "display.2").font(.system(size: 40, weight: .light))
                            Text("Add a screen, then connect its ports to the computers below.").foregroundStyle(.secondary)
                        }.frame(width: area.size.width, height: area.size.height)
                    }
                    ForEach(Array(model.group.monitors.enumerated()), id: \.element.id) { index, monitor in
                        screen(monitor, index: index, layout: layout)
                    }
                    if let drag { snapPreview(drag) }

                }.frame(width: area.size.width, height: area.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "deskScreenCanvas")
            }.frame(minHeight: 230)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Computers").font(.headline)
                    Spacer()
                    Button(action: addComputer) { Label("Add computer", systemImage: "plus") }.disabled(model.group.computers.count >= 16)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) { ForEach(model.group.computers) { computer in computerCard(computer) } }
                        .padding(.top, 6).padding(.bottom, 2)
                }.frame(height: 79)
                Text("Draw a wire between a computer and a monitor port. Click a port for its menu. Esc cancels a wire.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12)
            .onChange(of: model.group.monitors.map(\.id)) { _, ids in if let current = drag, !ids.contains(current.id) { finishScreenDrag() } }
            .onAppear { wire.connect = cable }
            .onDisappear { finishScreenDrag(); wire.cancel() }
            .overlay { DeskWireOverlay(controller: wire).allowsHitTesting(false) }
            .backgroundPreferenceValue(DeskCableAnchors.self) { anchors in
                GeometryReader { area in
                    Path { path in
                        for connection in model.group.connections {
                            guard let computer = connection.computer,
                                  let start = anchors["computer:" + computer.uuidString], let end = anchors["port:" + connection.id.uuidString] else { continue }
                            let source = area[start], target = area[end]
                            let a = CGPoint(x: source.midX, y: source.midY), b = CGPoint(x: target.midX, y: target.midY)
                            path.move(to: a)
                            let middle = (a.y + b.y) / 2
                            path.addCurve(to: b, control1: CGPoint(x: a.x, y: middle), control2: CGPoint(x: b.x, y: middle))
                        }
                    }.stroke(Color.teal.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }.allowsHitTesting(false)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .underPageBackgroundColor).opacity(0.5)))
    }
    private func finishScreenDrag() {
        drag = nil; snapBypassed = false
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }; modifierMonitor = nil
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
    private func screen(_ monitor: KVMMonitor, index: Int, layout: DeskCanvasLayout) -> some View {
        let g = monitor.geometry, scale = layout.scale
        let width = max(1, g.displayedWidth * scale), height = max(1, g.displayedHeight * scale)
        let compact = width < 145 || height < 105
        let portLabelHeight = max(18, min(66, height - (compact ? 48 : 72)))
        let translation = drag?.id == monitor.id ? drag!.translation : .zero
        return ZStack(alignment: .topTrailing) {
            Button { model.selected = monitor.id } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.identifying == monitor.id || compact ? "\(index + 1)" : monitor.name)
                        .font(.system(size: model.identifying == monitor.id ? 36 : 13, weight: .semibold))
                        .lineLimit(1)
                    if !compact && !model.owner(monitor.id).isEmpty {
                        Text(model.owner(monitor.id)).font(.system(size: 11)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(.leading, 9).padding(.trailing, compact ? 9 : 52).padding(.top, 9)
                    .frame(width: width, height: height, alignment: .topLeading).clipped()
                    .background(RoundedRectangle(cornerRadius: 9).fill(model.selected == monitor.id ? Color.teal.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.selected == monitor.id ? Color.teal : Color.gray.opacity(0.65), lineWidth: model.selected == monitor.id ? 2.5 : 1.5))
            }.buttonStyle(.plain)
                .accessibilityLabel("Screen \(index + 1), \(monitor.name), \(model.owner(monitor.id)), \(g.rotation.rawValue) degrees")
                .help("Drag to arrange this physical screen. Guides preview edge and center alignment. Hold Shift to bypass snapping; gaps are allowed. Right-click for exact size in millimetres.")
                .contextMenu {
                    Button("Position & physical size…") { dimensions(monitor.id) }
                    Button("Rotate clockwise") { model.rotateScreen(monitor.id) }
                    Button("Add port…") { addPort(monitor.id) }
                    Button("Remove screen…", role: .destructive) { remove(monitor.id) }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("deskScreenCanvas"))
                    .onChanged { value in
                        if drag == nil {
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
            if !compact {
                HStack(spacing: 8) {
                    Button { model.rotateScreen(monitor.id) } label: { Image(systemName: "rotate.right") }.accessibilityLabel("Rotate \(monitor.name)")
                    Button { remove(monitor.id) } label: { Image(systemName: "xmark") }.accessibilityLabel("Remove \(monitor.name)")
                }.font(.system(size: 11, weight: .semibold)).buttonStyle(.borderless).padding(9)
            }
            VStack { Spacer(minLength: 0)
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(model.group.connections.filter { $0.monitor == monitor.id }) { port in portSocket(port, labelHeight: portLabelHeight) }
                        Button { addPort(monitor.id) } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless).help("Add a monitor port")
                    }.padding(.horizontal, 7)
                }.frame(height: portLabelHeight + 30)
            }.padding(.bottom, 3).frame(width: width, height: height)
        }.frame(width: width, height: height)
            .offset(x: layout.origin.x + (g.x - layout.bounds.minX) * scale + translation.width,
                    y: layout.origin.y + (g.y - layout.bounds.minY) * scale + translation.height)
    }
    private func portSocket(_ port: KVMConnection, labelHeight: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text(port.inputName).font(.system(size: 10)).lineLimit(1)
                .frame(width: labelHeight, height: 14, alignment: .leading)
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: labelHeight)
                .accessibilityHidden(true)
            DeskWireSocket(id: "port:" + port.id.uuidString, connected: port.computer != nil,
                           label: model.connectionLabel(port), controller: wire) {
                let menu = DeskSocketMenu()
                for computer in model.group.computers { menu.action("Connect " + computer.name) { cable(port.id, computer.id) } }
                if port.computer != nil { menu.action("Disconnect cable") { model.disconnectCable(port.id) } }
                menu.addItem(.separator())
                menu.action("Edit port…") { editPort(port.id) }
                return menu
            }.frame(width: 24, height: 22)
                .anchorPreference(key: DeskCableAnchors.self, value: .bounds) { ["port:" + port.id.uuidString: $0] }
        }
    }

    private func computerCard(_ computer: KVMComputer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                DeskWireSocket(id: "computer:" + computer.id.uuidString, connected: true,
                               label: computer.name + " cable connector", controller: wire) {
                    let menu = DeskSocketMenu()
                    for port in model.group.connections {
                        let monitor = model.group.monitors.first { $0.id == port.monitor }?.name ?? "Screen"
                        menu.action(monitor + " · " + port.inputName) { cable(port.id, computer.id) }
                    }
                    return menu
                }.frame(width: 24, height: 22)
                    .anchorPreference(key: DeskCableAnchors.self, value: .bounds) { ["computer:" + computer.id.uuidString: $0] }
                Button(computer.name) { computerDetails(computer.id) }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                Button { removeComputer(computer.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.borderless).accessibilityLabel("Remove \(computer.name)")
                    .disabled(model.live?.removalIssue?(computer.id) != nil || model.group.computers.count == 1)
                    .help(model.live?.removalIssue?(computer.id) ?? "Remove this computer after confirmation.")
            }
            Text(model.online.contains(computer.id) ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
        }.padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
            .help("Draw a wire from the connector to the monitor port its cable plugs into.")
    }
}


/// Local canvas interaction only; no event posting or hardware access.
@MainActor final class DeskWireController: ObservableObject {
    private final class WeakSocket { weak var view: DeskWireSocketView?; init(_ view: DeskWireSocketView) { self.view = view } }
    private var sockets: [String: WeakSocket] = [:]
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private(set) var gesture = DeskWireGesture()
    private(set) var target: String?
    var connect: ((UUID, UUID) -> Void)?
    func register(_ view: DeskWireSocketView) { sockets[view.socketID] = WeakSocket(view) }
    func remove(_ view: DeskWireSocketView) {
        guard sockets[view.socketID]?.view === view else { return }
        sockets[view.socketID] = nil
        if gesture.source == view.socketID { cancel() }
    }
    func socket(_ id: String?) -> DeskWireSocketView? { id.flatMap { sockets[$0]?.view } }
    func center(_ id: String?) -> CGPoint? {
        guard let view = socket(id), view.window != nil else { return nil }
        return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }
    func begin(_ id: String, at point: CGPoint) {
        cancel(); gesture.begin(id, at: point)
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
        gesture.move(to: point)
        target = gesture.dragging ? sockets.keys.sorted().first { key in
            guard DeskWireGesture.compatible(source, key), let view = socket(key), view.window === origin.window, !view.isHiddenOrHasHiddenAncestor else { return false }
            return view.bounds.insetBy(dx: -6, dy: -6).contains(view.convert(point, from: nil))
        } : nil
        refresh()
    }
    /// Return true only for a click; callers may then show their menu on mouse-up.
    func end(_ id: String, at point: CGPoint) -> Bool {
        guard gesture.source == id else { return false }
        move(to: point)
        let destination = target
        let inside = socket(id).map { $0.bounds.contains($0.convert(point, from: nil)) } ?? false
        let result = gesture.finish(insideSource: inside, target: destination)
        cancel()
        if case let .connect(source, target) = result {
            let port = source.hasPrefix("port:") ? source : target
            let computer = source.hasPrefix("computer:") ? source : target
            if let p = UUID(uuidString: String(port.dropFirst(5))), let c = UUID(uuidString: String(computer.dropFirst(9))) { connect?(p, c) }
        }
        return result == .click
    }
    func cancel() {
        gesture = DeskWireGesture(); target = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        refresh()
    }
    private func refresh() { objectWillChange.send(); for socket in sockets.values { socket.view?.needsDisplay = true } }
}

final class DeskSocketMenu: NSMenu {
    private final class Action: NSObject { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run }; @objc func invoke() { run() } }
    private var actions: [Action] = []
    func action(_ title: String, _ run: @escaping () -> Void) {
        let target = Action(run); actions.append(target)
        let item = NSMenuItem(title: title, action: #selector(Action.invoke), keyEquivalent: "")
        item.target = target; addItem(item)
    }
}

struct DeskWireSocket: NSViewRepresentable {
    let id: String
    let connected: Bool
    let label: String
    let controller: DeskWireController
    var menu: (() -> DeskSocketMenu)? = nil
    func makeNSView(context: Context) -> DeskWireSocketView { DeskWireSocketView(frame: .zero) }
    func updateNSView(_ view: DeskWireSocketView, context: Context) {
        if view.socketID != id { view.controller?.remove(view) }
        view.socketID = id; view.connected = connected; view.controller = controller; view.makeMenu = menu
        view.setAccessibilityLabel(label); view.toolTip = label + ". Drag to another connector to draw a wire."
        controller.register(view); view.needsDisplay = true
    }
    static func dismantleNSView(_ view: DeskWireSocketView, coordinator: ()) { view.controller?.remove(view) }
}
final class DeskWireSocketView: NSView {
    var socketID = ""
    var connected = false
    weak var controller: DeskWireController?
    var makeMenu: (() -> DeskSocketMenu)?
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
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let circle = NSBezierPath(ovalIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        NSColor.systemTeal.setStroke(); NSColor.systemTeal.setFill(); circle.lineWidth = 1.5
        if connected { circle.fill() } else { circle.stroke() }
        if controller?.target == socketID {
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
            ring.lineWidth = 2.5; ring.stroke()
        }
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
    override func draw(_ dirtyRect: NSRect) {
        guard let controller, controller.gesture.dragging, let start = controller.center(controller.gesture.source) else { return }
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
