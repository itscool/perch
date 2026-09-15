import SwiftUI

/// A member Mac: name, connection state and its three numbered preset
/// connectors. Removal lives in the details sheet, not on the card.
struct DeskComputerCard: View {
    @ObservedObject var model: DeskModel
    let computer: KVMComputer
    let wire: DeskWireController
    let details: (UUID) -> Void

    var body: some View {
        let routes = model.preset.assignments.filter { a in model.group.connections.contains { $0.id == a.connection && $0.computer == computer.id } }
        let focused = routes.contains { $0.monitor == model.selected }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "desktopcomputer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.blue)
                Text(computer.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
            }
            Text(model.online.contains(computer.id) ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 21)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .onTapGesture { details(computer.id) }
            .deskControl("region:computer:" + computer.id.uuidString)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(computer.name), \(model.online.contains(computer.id) ? "online" : "offline")")
            .accessibilityAction(named: "Edit computer") { details(computer.id) }
            .help("Click for this computer’s details. Drag a numbered connector to a monitor input to use that input in that preset.")
    }
}
