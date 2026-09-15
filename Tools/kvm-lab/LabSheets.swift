import SwiftUI

/// The Desk Lab's own temporary steps: simulated membership, ports and
/// conflicts. The shared editors stay in the app's Desk sheets.
struct LabSheet: View {
    @ObservedObject var model: DeskModel
    let simulation: DeskSimulation
    let sheet: DeskSheet
    let close: () -> Void
    @State private var name = "New screen"
    @State private var input = "HDMI 1"
    @State private var computer: UUID?
    @State private var screen: UUID?
    @State private var confirmingRemoval = false

    private func finish() { if model.problem == nil { close() } }

    var body: some View {
        switch sheet {
        case .addComputer:
            Text("Add a computer").font(.title2).fontWeight(.semibold)
            Text("The production flow finds nearby Perches and confirms membership on both computers. Here, add a simulated member to explore a larger desk.").foregroundStyle(.secondary)
            TextField("Computer name", text: $name).textFieldStyle(.roundedBorder)
            Button("Add demo computer") { simulation.addComputer(name); finish() }.buttonStyle(.borderedProminent)
        case .addScreen:
            Text("Identify a screen").font(.title2).fontWeight(.semibold)
            Text("Identical models aren’t necessarily the same physical screen. Confirm whether this is a new screen or another connection to one already in your desk.").foregroundStyle(.secondary)
            Picker("Screen", selection: $screen) { Text("A new physical screen").tag(nil as UUID?); ForEach(model.group.monitors) { Text($0.name).tag(Optional($0.id)) } }
            if screen == nil { TextField("Screen name", text: $name).textFieldStyle(.roundedBorder) }
            Picker("Connected computer", selection: $computer) { ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) } }
                .onAppear { computer = computer ?? model.group.computers.first?.id }
            Button(screen == nil ? "Add demo screen" : "Confirm shared screen") {
                guard let computer else { return }
                if let screen { simulation.addConnection(screen: screen, computer: computer, name: "HDMI 1") } else { simulation.addScreen(name, computer: computer) }
                finish()
            }.buttonStyle(.borderedProminent)
        case .connections(let screen):
            Text("Add a monitor port").font(.title2).fontWeight(.semibold)
            Text("Add an input on this physical screen. You can leave its computer unassigned and still select the input in a preset.").foregroundStyle(.secondary)
            Picker("Computer", selection: $computer) { Text("Unassigned").tag(nil as UUID?); ForEach(model.group.computers) { Text($0.name).tag(Optional($0.id)) } }
            TextField("Input, such as HDMI 1", text: $input).textFieldStyle(.roundedBorder)
            Button("Add demo connection") { simulation.addConnection(screen: screen, computer: computer, name: input); finish() }
        case .removeConnection(let id):
            Text("Remove this port?").font(.title2).fontWeight(.semibold)
            Text("This clears its assignments from all three presets. The physical screen and other connections remain.")
            Button("Remove demo connection", role: .destructive) { model.removeConnection(id); finish() }
        case .removeComputer(let id):
            Text("Remove \(model.group.computers.first { $0.id == id }?.name ?? "computer")?").font(.title2.bold())
            Text("Its cables will be disconnected. Monitor ports and preset input choices remain.")
            Button("Remove computer", role: .destructive) { model.removeComputer(id); finish() }
        case .computerDetails(let id):
            Text(model.group.computers.first { $0.id == id }?.name ?? "Computer").font(.title2).fontWeight(.semibold)
            Text("\(model.group.connections.filter { $0.computer == id }.count) screen connections · simulated member").foregroundStyle(.secondary)
            Button(model.online.contains(id) ? "Simulate going offline" : "Simulate reconnecting") { simulation.toggleOnline(id); close() }
            if confirmingRemoval {
                Text("Remove this computer from the group? Its monitor connections remain selectable, marked Unassigned. Remote input control stops for those connections.")
                Button("Remove demo computer", role: .destructive) { model.removeComputer(id); finish() }
            } else { Button("Remove computer…", role: .destructive) { confirmingRemoval = true }.disabled(model.group.computers.count == 1) }
        case .conflict:
            Text("Review both changes").font(.title2).fontWeight(.semibold)
            Text("Two computers edited this desk while apart. Both versions are kept until you choose. This scenario changes the desk name only.").foregroundStyle(.secondary)
            Button("Keep this version: \(model.group.name)") { simulation.resolve(useOther: false); finish() }
            Button("Use other version: \(model.conflict?.name ?? "")") { simulation.resolve(useOther: true); finish() }
        case .control, .monitorSetup:
            Text("Hardware and control").font(.title2).fontWeight(.semibold)
            Text("Monitor control paths and firmware profiles are not simulated. The installed Perch configures them from detected displays.").foregroundStyle(.secondary)
        case .cable, .port, .removeScreen, .dimensions: EmptyView()
        }
    }
}
