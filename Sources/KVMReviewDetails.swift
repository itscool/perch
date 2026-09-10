import Foundation

extension KVMGroup {
    /// Include every user-editable shared value before replacing a whole version.
    var reviewDetails: [String] {
        func computer(_ id: UUID?) -> String {
            guard let id else { return "Unassigned" }
            return (computers.first { $0.id == id }?.name ?? "Unknown computer") + " [\(id.uuidString.prefix(8))]"
        }
        func screen(_ id: UUID) -> String {
            (monitors.first { $0.id == id }?.name ?? "Unknown screen") + " [\(id.uuidString.prefix(8))]"
        }
        var lines = ["Desk: \(name)", "Computers: " + computers.map { computer($0.id) + " · " + $0.platform }.joined(separator: "; ")]
        if monitors.isEmpty { lines.append("No screens") }
        for monitor in monitors {
            let g = monitor.geometry
            lines.append("Screen: \(screen(monitor.id))\nPosition: \(g.x), \(g.y) mm · Panel: \(g.width) × \(g.height) mm · Rotation: \(g.rotation.rawValue)°")
            if let control = monitor.control {
                var mode = control.mode
                if mode.hasPrefix("route:"), let data = Data(base64Encoded: String(mode.dropFirst(6))),
                   let route = try? JSONDecoder().decode(MonitorConnection.self, from: data) {
                    mode = "\(route.kind) · \(route.endpoint) · address \(route.address)" + (route.model.map { " · Model " + $0 } ?? "")
                }
                lines.append("Monitor control: \(computer(control.computer)) · Display \(control.localDisplay) · \(mode)")
            } else { lines.append("Monitor control: not configured") }
            for connection in connections.filter({ $0.monitor == monitor.id }) {
                lines.append("Input: \(connection.inputName) [\(connection.id.uuidString.prefix(8))] · Code \(connection.inputCode.map(String.init) ?? "not configured")\nConnected to: \(computer(connection.computer)) · Display \(connection.localDisplay ?? "unassigned")")
            }
        }
        for preset in presets.sorted(by: { $0.slot < $1.slot }) {
            lines.append("Preset \(preset.slot): \(preset.name) · \(preset.shortcut.label)")
            for monitor in monitors {
                let assignment = preset.assignments.first { $0.monitor == monitor.id }
                let connection = connections.first { $0.id == assignment?.connection }
                lines.append("\(screen(monitor.id)) → " + (connection.map { "\($0.inputName) [\($0.id.uuidString.prefix(8))] · \(computer($0.computer))" } ?? "No input selected"))
            }
        }
        if (sharedKeyboards ?? []).isEmpty { lines.append("Shared keyboards: none") }
        for keyboard in sharedKeyboards ?? [] {
            lines.append("Keyboard: \(keyboard.name) [\(keyboard.id.uuidString.prefix(8))] · Follow \(keyboard.follow ? "on" : "off")")
            for host in computers {
                lines.append("\(computer(host.id)) → \(keyboard.bindings[host.id] ?? "No attachment confirmed")")
            }
        }
        return lines
    }
}
