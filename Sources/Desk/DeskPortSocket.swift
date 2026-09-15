import SwiftUI

/// One monitor input on a screen tile: its label, the preset chips that use it,
/// and the socket a cable or a preset connector can be dragged to.
struct DeskPortSocket: View {
    @ObservedObject var model: DeskModel
    let port: KVMConnection
    let horizontal: Bool
    let labelHeight: CGFloat
    let wire: DeskWireController
    let cable: (UUID, UUID) -> Void
    let editPort: (UUID) -> Void

    private var presetNumbers: [Int] {
        model.group.presets.enumerated().compactMap { index, preset in preset.assignments.contains { $0.connection == port.id } ? index + 1 : nil }
    }
    private var ownerName: String? { model.group.computers.first { $0.id == port.computer }?.name }
    private var chosen: Bool { model.preset.assignments.contains { $0.connection == port.id } }
    private var active: Bool { model.active?.assignments.contains { $0.connection == port.id } == true }

    var body: some View {
        VStack(spacing: 3) {
            if horizontal {
                Text(port.inputName).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(width: 62).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(ownerName ?? "Unassigned").font(.system(size: 9)).lineLimit(1).truncationMode(.tail)
                    .frame(width: 62).foregroundStyle(ownerName == nil ? .tertiary : .secondary).accessibilityHidden(true)
            } else {
                Text(port.inputName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .frame(width: labelHeight, height: 14, alignment: .leading)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: labelHeight)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // Chips sit side by side under a horizontal label; a rotated label
            // leaves only the socket's width, so they stack.
            let chips = ForEach(presetNumbers, id: \.self) { number in
                let editing = number - 1 == model.presetIndex
                let inActive = model.active.map { $0.assignments.contains { $0.connection == port.id } && model.group.presets.firstIndex(where: { $0.id == model.active?.id }) == number - 1 } ?? false
                let color: Color = editing && inActive ? .purple : editing ? .teal : inActive ? Color(nsColor: StatusColors.success) : .secondary
                Text("\(number)").font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(color.opacity(0.14), in: Capsule())
            }
            if horizontal { HStack(spacing: 2) { chips }.frame(height: 14).accessibilityHidden(true) }
            else { VStack(spacing: 1) { chips }.accessibilityHidden(true) }
            DeskWireSocket(id: "port:" + port.id.uuidString, connected: port.computer != nil,
                           label: model.connectionLabel(port), controller: wire,
                           presetNumbers: presetNumbers, highlighted: chosen, activeRouting: active, drawsNumbers: false) {
                let menu = DeskSocketMenu()
                menu.action("Switch this monitor to \(port.inputName)", help: "Send the monitor command now, even if Perch thinks this input is already selected. Presets stay unchanged.") {
                    model.selected = port.monitor; model.backend.switchConnection(port.id)
                }
                menu.addItem(.separator())
                for (index, preset) in model.group.presets.enumerated() {
                    let used = preset.assignments.contains { $0.connection == port.id }
                    menu.action("Use in \(preset.name)", checked: used, help: used ? "This preset switches \(model.group.monitors.first { $0.id == port.monitor }?.name ?? "the screen") to \(port.inputName). Choose again to leave the screen unchanged in this preset." : "Make this preset switch the screen to \(port.inputName).") {
                        model.assign(used ? nil : port.id, preset: index, monitor: port.monitor)
                    }
                }
                menu.addItem(.separator())
                for computer in model.group.computers where computer.id != port.computer { menu.action("Connect " + computer.name) { cable(port.id, computer.id) } }
                if port.computer != nil { menu.action("Disconnect cable") { model.disconnectCable(port.id) } }
                menu.addItem(.separator())
                menu.action("Edit port…") { editPort(port.id) }
                return menu
            }.frame(width: 24, height: 20)
                .deskControl("port:" + port.id.uuidString)
                .anchorPreference(key: DeskCableAnchors.self, value: .bounds) { ["port:" + port.id.uuidString: $0] }
        }
        .frame(width: horizontal ? 62 : 24)
        .help("\(port.inputName)" + (ownerName.map { " from \($0)" } ?? " (no computer connected)") + ". Click for preset and cable options; drag to move this cable.")
    }
}
