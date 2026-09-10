import SwiftUI

struct DeskView: View {
    @ObservedObject var model: DeskModel
    @State private var sheet: String?
    @State private var draftName = ""
    @State private var draftInput = "HDMI 1"
    @State private var draftComputer: UUID?
    @State private var draftScreen: UUID?
    @State private var draftConnection: UUID?
    @State private var expandedConnection: UUID?
    @State private var rename = ""
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
                Button { draftName = model.group.name; sheet = "desk" } label: { Label("Desk settings", systemImage: "slider.horizontal.3") }
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
                    DeskCanvas(model: model, remove: { id in model.selected = id; sheet = "removeScreen" }, dimensions: { id in model.selected = id; sheet = "dimensions" }).frame(minHeight: 270, maxHeight: .infinity)

                }.padding(24)
                Divider()
                inspector.frame(width: 276).padding(.leading, 16).padding(.vertical, 12)
            }.background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("COMPUTERS IN THIS DESK").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(model.group.computers) { computer in
                                Button { draftComputer = computer.id; draftName = computer.name; sheet = "computerDetails" } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "desktopcomputer")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(computer.name).font(.system(size: 12, weight: .medium))
                                            Text(model.online.contains(computer.id) ? (model.live == nil ? "Online · demo" : "Online") : (model.live == nil ? "Offline · demo" : "Offline")).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                    }.padding(9)
                                }.buttonStyle(.bordered).help("View this computer and its screen connections.")
                            }
                        }
                    }.frame(height: 55)
                }
                Button { draftName = "Mac mini"; sheet = "computer" } label: { Label("Add computer", systemImage: "plus") }.disabled(model.group.computers.count >= 16)
            }.padding(.horizontal, 24).padding(.vertical, 16)

        }.frame(minWidth: 960, minHeight: 620)
            .onChange(of: model.selected) { _, _ in rename = model.selectedMonitor?.name ?? "" }
            .onAppear { rename = model.selectedMonitor?.name ?? "" }
            .onChange(of: sheet) { _, next in if next != nil { model.problem = nil; showRemove = false } }
            .sheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) { sheetView }
    }

    @ViewBuilder var inspector: some View {
        if let monitor = model.selectedMonitor {
            InspectorScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Screen name", text: $rename).textFieldStyle(.roundedBorder).font(.headline).accessibilityLabel("Screen name")
                            .onChange(of: rename) { _, value in if value != model.selectedMonitor?.name { model.renameMonitor(value) } }
                        Button("Identify") { model.identify() }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connections").font(.system(size: 12, weight: .semibold))
                        ForEach(model.group.connections.filter { $0.monitor == monitor.id }) { connection in
                            VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Text(connection.inputName).font(.system(size: 11, weight: .medium)).frame(width: 63, alignment: .leading)
                                if let live = model.live {
                                    Picker("Computer for \(connection.inputName)", selection: Binding(get: { connection.computer.map { $0.uuidString + "|" + (connection.localDisplay ?? "") } ?? "" }, set: { live.map(connection.id, $0) })) {
                                        Text("Unassigned").tag("")
                                        ForEach(live.mappingOptions()) { Text($0.label).tag($0.id) }
                                    }.labelsHidden().frame(maxWidth: .infinity)
                                } else {
                                Picker("Computer for \(connection.inputName)", selection: Binding<UUID?>(get: { connection.computer }, set: { model.mapConnection(connection.id, computer: $0) })) {
                                    Text("Unassigned").tag(nil as UUID?); ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) }
                                }.labelsHidden().frame(maxWidth: .infinity)
                                }
                                    Button { expandedConnection = expandedConnection == connection.id ? nil : connection.id } label: { Image(systemName: expandedConnection == connection.id ? "chevron.up" : "pencil") }
                                    .accessibilityLabel("\(expandedConnection == connection.id ? "Collapse" : "Edit") \(connection.inputName) connection").help("Change the input name or correct its physical screen.")
                            }
                            if expandedConnection == connection.id {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Input name", text: Binding(get: { connection.inputName }, set: { model.changeConnection(connection.id, input: $0) })).textFieldStyle(.roundedBorder).accessibilityLabel("Input name")
                                    if model.live != nil {
                                        TextField("Input code", text: Binding(get: { connection.inputCode.map(String.init) ?? "" }, set: { value in
                                            if let code = UInt16(value), code > 0 { model.edit { group in if let i = group.connections.firstIndex(where: { $0.id == connection.id }) { group.connections[i].inputCode = code } } }
                                        })).textFieldStyle(.roundedBorder).accessibilityLabel("Monitor input code")
                                        Button("Monitor control…") { sheet = "control" }
                                    }
                                    Button("Correct physical screen…") { draftConnection = connection.id; draftScreen = connection.monitor; sheet = "correctConnection" }
                                    Button("Remove connection…", role: .destructive) { draftConnection = connection.id; sheet = "removeConnection" }
                                }.padding(.vertical, 6)
                            }
                            }.padding(expandedConnection == connection.id ? 8 : 0)
                                .background(RoundedRectangle(cornerRadius: 8).fill(expandedConnection == connection.id ? Color.teal.opacity(0.10) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(expandedConnection == connection.id ? Color.secondary.opacity(0.5) : .clear, lineWidth: 1))
                        }
                        Button("Add connection…") { draftScreen = monitor.id; draftComputer = nil; draftInput = "HDMI 1"; sheet = "connections" }
                    }
                    if let result = model.monitorResults[monitor.id] { Text(result).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Preset connections").font(.system(size: 12, weight: .semibold))
                        ForEach(0..<3, id: \.self) { index in
                            let preset = model.group.presets[index]
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(preset.name).font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Text(preset.shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Picker("Connection for \(preset.name)", selection: Binding<UUID?>(get: { model.group.presets[index].assignments.first { $0.monitor == monitor.id }?.connection }, set: { model.assign($0, preset: index) })) {
                                    if !preset.assignments.contains(where: { $0.monitor == monitor.id }) { Text("Choose connection").tag(nil as UUID?).disabled(true) }
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

    var sheetView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(model.live == nil ? "DESK LAB" : "DESK").font(.caption).foregroundStyle(.secondary); Spacer(); Button { sheet = nil; showRemove = false } label: { Image(systemName: "xmark") }.accessibilityLabel("Close").help("Close this temporary step.").keyboardShortcut(.cancelAction) }
            ScrollView { sheetContents }.frame(maxHeight: 560)
            if let problem = model.problem { Text(problem).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(25).frame(width: 440)
    }

    @ViewBuilder var sheetContents: some View {
        if let live = model.live, let sheet, ["computer", "screen", "computerDetails", "conflict", "connections", "correctConnection", "removeConnection", "desk", "control"].contains(sheet) {
            live.sheet(sheet, sheet == "computerDetails" ? draftComputer : (sheet == "removeConnection" || sheet == "correctConnection" ? draftConnection : model.selected), { self.sheet = nil })
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
            Text("Add a connection").font(.title2).fontWeight(.semibold)
            Text("Add an input on this physical screen. You can leave its computer unassigned and still select the input in a preset.").foregroundStyle(.secondary)
            Picker("Computer", selection: $draftComputer) { Text("Unassigned").tag(nil as UUID?); ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) } }
            TextField("Input, such as HDMI 1", text: $draftInput).textFieldStyle(.roundedBorder)
            Button("Add demo connection") { if let screen = draftScreen { model.addConnection(screen: screen, computer: draftComputer, name: draftInput); if model.problem == nil { sheet = nil } } }
        case "correctConnection":
            Text("Correct the physical screen").font(.title2).fontWeight(.semibold)
            Text("This moves only the selected cable connection. Its preset assignments are cleared so you can choose them again. Other cables and screens stay as they are.").foregroundStyle(.secondary)
            Picker("Actually connected to", selection: $draftScreen) {
                Text("A separate physical screen").tag(nil as UUID?)
                ForEach(model.group.monitors) { Text($0.name).tag(Optional($0.id)) }
            }
            Button("Correct screen match") { if let id = draftConnection { model.correctConnection(id, physicalScreen: draftScreen); if model.problem == nil { sheet = nil } } }.buttonStyle(.borderedProminent)
        case "removeConnection":
            Text("Remove this connection?").font(.title2).fontWeight(.semibold)
            Text("This clears its assignments from all three presets. The physical screen and other connections remain.")
            Button("Remove demo connection", role: .destructive) { if let id = draftConnection { model.removeConnection(id); if model.problem == nil { sheet = nil } } }
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
            Text("Screen position & size").font(.title2).fontWeight(.semibold)
            Text("Drag the screen to move it, or enter exact millimetres here. Size is the panel before rotation. Valid changes save immediately.").foregroundStyle(.secondary)
            if let monitor = model.selectedMonitor {
                HStack {
                    Text("X"); TextField("X", value: Binding(get: { monitor.geometry.x }, set: { model.move(monitor.id, x: $0, y: monitor.geometry.y) }), format: .number).textFieldStyle(.roundedBorder)
                    Text("Y"); TextField("Y", value: Binding(get: { monitor.geometry.y }, set: { model.move(monitor.id, x: monitor.geometry.x, y: $0) }), format: .number).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Width"); TextField("Width", value: Binding(get: { monitor.geometry.width }, set: { model.resize(width: $0, height: monitor.geometry.height) }), format: .number).textFieldStyle(.roundedBorder)
                    Text("Height"); TextField("Height", value: Binding(get: { monitor.geometry.height }, set: { model.resize(width: monitor.geometry.width, height: $0) }), format: .number).textFieldStyle(.roundedBorder)
                }
            }
        default: EmptyView()
        }
        }
    }
}

struct DeskCanvas: View {
    @ObservedObject var model: DeskModel
    let remove: (UUID) -> Void
    let dimensions: (UUID) -> Void
    @State private var dragging: UUID?
    @State private var translation = CGSize.zero
    var body: some View {
        GeometryReader { area in
            let minX = model.group.monitors.map { $0.geometry.x }.min() ?? 0
            let minY = model.group.monitors.map { $0.geometry.y }.min() ?? 0
            let width = max(700, (model.group.monitors.map { $0.geometry.right }.max() ?? 700) - minX)
            let height = max(500, (model.group.monitors.map { $0.geometry.bottom }.max() ?? 500) - minY)
            // A large desk scrolls instead of shrinking names and controls into
            // unreadable marks. Geometry remains proportional at the same scale.
            let scale = max(0.32, min((area.size.width - 40) / width, (area.size.height - 60) / height))
            let canvasWidth = max(area.size.width, width * scale + 40)
            let canvasHeight = max(area.size.height, height * scale + 60)
            let originX = (canvasWidth - width * scale) / 2
            let originY = (canvasHeight - height * scale) / 2
            ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
                if model.group.monitors.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "display.2").font(.system(size: 40, weight: .light)); Text("Make room for your screens").font(.headline); Text("Add a screen to begin arranging your desk.").foregroundStyle(.secondary) }.frame(width: area.size.width, height: area.size.height)
                }
                ForEach(Array(model.group.monitors.enumerated()), id: \.element.id) { index, monitor in
                    let g = monitor.geometry
                    ZStack(alignment: .topTrailing) {
                    Button { model.selected = monitor.id } label: {
                        VStack(spacing: 7) {
                            Text(model.identifying == monitor.id ? "\(index + 1)" : monitor.name).font(.system(size: model.identifying == monitor.id ? 36 : 13, weight: .semibold))
                            Text(model.owner(monitor.id)).font(.system(size: 11)).multilineTextAlignment(.center)
                            if model.selected == monitor.id { Text("Selected").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                        }.padding(8).padding(.top, 20).frame(width: max(35, g.displayedWidth * scale), height: max(35, g.displayedHeight * scale))
                            .background(RoundedRectangle(cornerRadius: 9).fill(model.selected == monitor.id ? Color.teal.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.selected == monitor.id ? Color.teal : Color.gray.opacity(0.65), lineWidth: model.selected == monitor.id ? 2.5 : 1.5))
                    }.buttonStyle(.plain).accessibilityLabel("Screen \(index + 1), \(monitor.name), \(model.owner(monitor.id)), \(g.rotation.rawValue) degrees")
                        .help("Drag to move. Right-click for exact position and size.")
                        .contextMenu { Button("Position & size…") { dimensions(monitor.id) }; Button("Rotate clockwise") { model.rotateScreen(monitor.id) }; Button("Remove screen…", role: .destructive) { remove(monitor.id) } }
                        .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { value in dragging = monitor.id; model.selected = monitor.id; translation = value.translation }.onEnded { value in
                            var x = g.x + value.translation.width / scale, y = g.y + value.translation.height / scale
                            // Snap near edges; do not jump gaps while routing input.
                            for other in model.group.monitors where other.id != monitor.id {
                                let h = other.geometry
                                for candidate in [h.x, h.right, h.x - g.displayedWidth] { if abs(candidate - x) < 18 / scale { x = candidate } }
                                for candidate in [h.y, h.bottom, h.y - g.displayedHeight] { if abs(candidate - y) < 18 / scale { y = candidate } }
                            }
                            dragging = nil; translation = .zero; model.move(monitor.id, x: x, y: y)
                        })
                        HStack(spacing: 8) {
                            Button { model.rotateScreen(monitor.id) } label: { Image(systemName: "rotate.right").font(.system(size: 11, weight: .semibold)) }
                                .accessibilityLabel("Rotate \(monitor.name) clockwise").help("Rotate this screen 90° clockwise.")
                            Button { remove(monitor.id) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                                .accessibilityLabel("Remove \(monitor.name)").help("Remove this screen after confirmation.")
                        }.buttonStyle(.borderless).padding(10)
                    }.offset(x: originX + (g.x - minX) * scale + (dragging == monitor.id ? translation.width : 0), y: originY + (g.y - minY) * scale + (dragging == monitor.id ? translation.height : 0))
                }
            }.frame(width: canvasWidth, height: canvasHeight)
            }
        }
    }
}
