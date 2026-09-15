import SwiftUI

/// The one temporary step the Desk page shows at a time. The backend renders
/// the steps it owns; the rest are the shared editors.
struct DeskSheetRouter: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.backend.wording.badge).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { page.close() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close").help("Close this temporary step.").keyboardShortcut(.cancelAction)
            }
            ScrollView { contents }.frame(maxHeight: 560)
            if let problem = model.problem { SettingsFeedback(text: problem) }
        }.padding(25).frame(width: 440)
    }

    @ViewBuilder private var contents: some View {
        if let sheet = page.sheet {
            if let owned = model.backend.sheet(sheet, close: { page.close() }) {
                owned
            } else {
                switch sheet {
                case .cable(let port, let computer): DeskCableSheet(model: model, page: page, portID: port, computerID: computer)
                case .port(let port): DeskPortSheet(model: model, page: page, portID: port)
                case .dimensions(let monitor): DeskDimensionsSheet(model: model, page: page, monitorID: monitor)
                case .removeScreen(let id):
                    Text("Remove \(model.group.monitors.first { $0.id == id }?.name ?? "screen")?").font(.title2).fontWeight(.semibold)
                    Text("This removes the screen, its cable connections and its assignments from all three presets. Other screens stay as they are.")
                    Button("Remove screen", role: .destructive) { model.removeScreen(id); if model.problem == nil { page.close() } }
                default: Text("This step is not available here.").foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DeskCableSheet: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState
    let portID: UUID
    let computerID: UUID
    var body: some View {
        if let port = model.group.connections.first(where: { $0.id == portID }),
           let computer = model.group.computers.first(where: { $0.id == computerID }) {
            Text("Connect \(computer.name)").font(.title2.bold())
            Text("To \(model.group.monitors.first { $0.id == port.monitor }?.name ?? "screen") · \(port.inputName)").font(.headline)
            if let old = model.group.computers.first(where: { $0.id == port.computer }), old.id != computer.id {
                Text("This replaces the saved cable from \(old.name). It does not switch the monitor’s input.").foregroundStyle(.secondary)
            }
            let backend = model.backend
            Group {
                let options = model.cableOptions(for: computer.id)
                if options.isEmpty {
                    Text(port.computer == computer.id ? "Cable saved. Perch is waiting for this computer’s display identity." : "You can save this cable now and match its display when macOS reports it.").foregroundStyle(.secondary)
                    Text("If the monitor hides inactive inputs, use your preset to show this computer’s picture, then refresh here.").font(.callout).foregroundStyle(.secondary)
                    let identifyIssue = backend.peerActionReadiness(computer: computer.id, action: "Identify")
                    Button(backend.isIdentifying(computer: computer.id) ? "Stop identifying displays" : "Identify displays on \(computer.name)") { backend.identifyComputer(computer.id) }
                        .disabled(identifyIssue != nil)
                        .help(identifyIssue ?? "Show a short label on every display currently visible to \(computer.name), so you can match this cable without guessing.")
                    if let identifyIssue { Text(identifyIssue).font(.caption).foregroundStyle(.secondary) }
                    if port.computer != computer.id {
                        Button("Save cable") { backend.mapComputer(port: port.id, computer: computer.id); if model.problem == nil { page.close() } }
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
                                Button(option.display.map { backend.isIdentifying(display: $0, computer: computer.id) } == true ? "Stop identifying" : "Identify") { if let display = option.display { backend.identifyDisplay(display, computer: computer.id) } }
                                    .disabled(!model.online.contains(computer.id))
                                Button("Connect here") { backend.map(port: port.id, option: option.id); if model.problem == nil { page.close() } }
                                    .disabled(model.cableConflict(option, port: port.id) != nil)
                            }
                        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let status = backend.displayStatus(computer: computer.id) { Text(status).foregroundStyle(Color(nsColor: StatusColors.warning)) }
                Button("Refresh displays on paired Macs") { backend.refreshScreens() }
            }
        } else { Text("This computer or port was removed. Close this step and choose another port.") }
    }
}

struct DeskPortSheet: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState
    let portID: UUID
    var body: some View {
        if let port = model.group.connections.first(where: { $0.id == portID }) {
            Text("\(model.group.monitors.first { $0.id == port.monitor }?.name ?? "Screen") · \(port.inputName)").font(.title2.bold())
            DeskTextSetting("Port name", saved: port.inputName) { value in
                model.changeConnection(port.id, input: value); if let problem = model.problem { throw KVMError(problem) }
            }.id(port.id)
            Group {
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
            if port.computer != nil { Button("Disconnect cable") { model.disconnectCable(port.id); if model.problem == nil { page.close() } } }
            Button("Remove port…", role: .destructive) { page.open(.removeConnection(port.id)) }
        } else { Text("This port was removed.") }
    }
}

struct DeskDimensionsSheet: View {
    @ObservedObject var model: DeskModel
    @ObservedObject var page: DeskPageState
    let monitorID: UUID
    var body: some View {
        Text("Physical size").font(.title2.bold())
        Text("Use the visible panel’s physical width and height in millimetres, before rotation. Position is set directly in the Desk graph.").foregroundStyle(.secondary)
        if let monitor = model.group.monitors.first(where: { $0.id == monitorID }) {
            let detectedAspect = model.backend.panelAspect(monitor: monitor.id) ?? monitor.panelAspect
            let aspect = detectedAspect ?? page.fallbackAspect
            HStack {
                Text("Diagonal (inches)")
                TextField("Screen diagonal in inches", value: Binding(get: { hypot(monitor.geometry.width, monitor.geometry.height) / 25.4 }, set: { inches in
                    if let size = DeskPhysicalSize.estimate(inches: inches, aspect: aspect) { model.selected = monitor.id; model.resize(width: size.width, height: size.height) }
                    else { model.problem = "Enter a diagonal from 1 to 300 inches." }
                }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 90)
            }
            if detectedAspect != nil {
                Text("Aspect ratio detected from the display. Changing the diagonal estimates the panel’s width and height below.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Aspect ratio unavailable", selection: $page.fallbackAspect) {
                    Text("16:9").tag(16.0 / 9.0); Text("16:10").tag(1.6); Text("21:9").tag(21.0 / 9.0); Text("32:9").tag(32.0 / 9.0); Text("4:3").tag(4.0 / 3.0)
                }
                Text("No display capabilities are available yet. Choose a ratio only to estimate from a diagonal; exact millimetres remain editable.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Width (mm)"); TextField("Width in millimetres", value: Binding(get: { monitor.geometry.width }, set: { model.selected = monitor.id; model.resize(width: $0, height: monitor.geometry.height) }), format: .number).textFieldStyle(.roundedBorder)
                Text("Height (mm)"); TextField("Height in millimetres", value: Binding(get: { monitor.geometry.height }, set: { model.selected = monitor.id; model.resize(width: monitor.geometry.width, height: $0) }), format: .number).textFieldStyle(.roundedBorder)
            }
        } else { Text("This screen was removed.") }
    }
}
