import SwiftUI

/// The Desk Lab window: the production Desk page plus the lab's own controls
/// for staging events that the simulation cannot observe by itself.
struct LabView: View {
    @ObservedObject var model: DeskModel
    let simulation: DeskSimulation
    @State private var failNextSwitch = false
    @State private var newDeskName = "My new desk"
    @State private var creatingDesk = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DESK LAB").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Text("Simulated devices only — no network or hardware actions").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Fail next switch", isOn: $failNextSwitch).toggleStyle(.checkbox)
                    .onChange(of: failNextSwitch) { _, value in simulation.failNextSwitch = value }
                Button("Simulate concurrent edit") { simulation.simulateConflict() }
                Button("First-use desk…") { creatingDesk = true }
            }.padding(.horizontal, 24).padding(.vertical, 8).background(.bar)
            DeskView(model: model)
        }
        .sheet(isPresented: $creatingDesk) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Start a first-use demo").font(.title2).fontWeight(.semibold)
                Text("This replaces this lab’s saved example with an empty desk. It doesn’t change your installed Perch.")
                TextField("Desk name", text: $newDeskName).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { creatingDesk = false }.keyboardShortcut(.cancelAction)
                    Button("Create empty demo desk") { simulation.newDesk(newDeskName); if model.problem == nil { creatingDesk = false } }.buttonStyle(.borderedProminent)
                }
                if let problem = model.problem { Text(problem).foregroundStyle(.red) }
            }.padding(25).frame(width: 440)
        }
    }
}
