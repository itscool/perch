import SwiftUI

/// A three-screen, two-computer desk used by tests, the Desk Lab and renders.
extension KVMGroup {
    static func sample() -> KVMGroup {
        let mac = KVMComputer(name: "MacBook Pro"), studio = KVMComputer(name: "Mac Studio")
        let left = KVMMonitor(name: "Left screen", geometry: .init(x: 0, y: 30, width: 550, height: 310))
        let main = KVMMonitor(name: "Main screen", geometry: .init(x: 550, y: 0, width: 610, height: 343))
        let side = KVMMonitor(name: "Portrait screen", geometry: .init(x: 1160, y: 0, width: 530, height: 300, rotation: .clockwise))
        var g = KVMGroup(name: "My desk", computers: [mac, studio], monitors: [left, main, side])
        for screen in g.monitors {
            g.connections += [KVMConnection(monitor: screen.id, computer: mac.id, localDisplay: screen.id.uuidString, inputName: "USB-C"),
                              KVMConnection(monitor: screen.id, computer: studio.id, localDisplay: screen.id.uuidString, inputName: "DisplayPort", inputCode: 15)]
        }
        g.connections.append(KVMConnection(monitor: left.id, computer: nil, localDisplay: nil, inputName: "HDMI 1", inputCode: 17))
        g.presets[0].name = "Together"; g.presets[1].name = "All on MacBook"; g.presets[2].name = "All on Studio"
        for i in 0..<3 {
            for (n, screen) in g.monitors.enumerated() {
                let computer = i == 1 || (i == 0 && n == 2) ? mac : studio
                let route = g.connections.first { $0.monitor == screen.id && $0.computer == computer.id }!
                g.presets[i].assignments.append(.init(monitor: screen.id, connection: route.id))
            }
        }
        return g
    }
}

/// A backend that accepts every edit and does nothing else, for tests of the
/// model's own editing rules.
final class DeskFixtureBackend: DeskBackend {
    let wording = DeskWording.live
    private(set) var saved: [KVMGroup] = []
    func edit(_ group: KVMGroup) throws { saved.append(group) }
    func activate(preset: UUID) {}
    func readiness(preset: UUID) -> String? { nil }
    func retryActive() {}
    func revertSwitch() {}
    func switchConnection(_ connection: UUID) {}
    func mappingOptions() -> [DeskMappingOption] { [] }
    func map(port: UUID, option: String) {}
    func mapComputer(port: UUID, computer: UUID) {}
    func displayStatus(computer: UUID) -> String? { nil }
    func refreshScreens() {}
    func panelAspect(monitor: UUID) -> Double? { nil }
    func identify(monitor: UUID?) {}
    func identifyDisplay(_ display: String, computer: UUID) {}
    func identifyComputer(_ computer: UUID) {}
    func isIdentifying(monitor: UUID) -> Bool { false }
    func isIdentifying(display: String, computer: UUID) -> Bool { false }
    func isIdentifying(computer: UUID) -> Bool { false }
    func peerActionReadiness(computer: UUID, action: String) -> String? { nil }
    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView? { nil }
}
