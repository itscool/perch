import SwiftUI

/// The app's desk backend: forwards the page's actions to the runtime. It holds
/// the runtime weakly because the runtime owns the model that owns it.
final class DeskRuntimeBackend: DeskBackend {
    weak var runtime: DeskRuntime?
    let wording = DeskWording.live

    func edit(_ group: KVMGroup) throws { try runtime?.node.edit(group) }

    func activate(preset: UUID) { runtime?.activatePreset(preset) }
    func readiness(preset: UUID) -> String? {
        // A switch in progress is a neutral state on its own card, not a warning on every card.
        guard let runtime, !runtime.switching.busy else { return nil }
        return runtime.switching.readiness(preset)
    }
    func retryActive() {
        guard let runtime, let preset = runtime.switching.activePreset ?? runtime.switching.request?.preset else { return }
        runtime.activatePreset(preset)
    }
    func revertSwitch() { runtime?.switching.revert() }
    func switchConnection(_ connection: UUID) { runtime?.switchConnection(connection) }

    func mappingOptions() -> [DeskMappingOption] { runtime?.mappingOptions ?? [] }
    func map(port: UUID, option: String) { runtime?.map(port, choice: option) }
    func mapComputer(port: UUID, computer: UUID) { runtime?.mapComputer(port, computer: computer) }
    func displayStatus(computer: UUID) -> String? {
        guard let runtime else { return nil }
        if !runtime.node.online.contains(computer) { return "This computer is offline. Its saved cable will remain until it reconnects." }
        return computer == runtime.node.localID ? runtime.discoveryProblem : runtime.remoteDisplayProblem(computer)
    }
    func refreshScreens() { runtime?.refreshAllDisplays() }
    func panelAspect(monitor: UUID) -> Double? { runtime?.panelAspect(monitor) }

    func identify(monitor: UUID?) { runtime?.identify(monitor) }
    func identifyDisplay(_ display: String, computer: UUID) { runtime?.identifyDetected(display, computer: computer, name: "Is this the screen?") }
    func identifyComputer(_ computer: UUID) { runtime?.identifyComputer(computer) }
    func isIdentifying(monitor: UUID) -> Bool { runtime?.identifications.active["monitor:" + monitor.uuidString] != nil }
    func isIdentifying(display: String, computer: UUID) -> Bool { runtime?.identifications.active[computer.uuidString + "|" + display] != nil }
    func isIdentifying(computer: UUID) -> Bool { runtime?.identifications.active["computer:" + computer.uuidString] != nil }
    func peerActionReadiness(computer: UUID, action: String) -> String? { runtime?.peerActionReadiness(computer, action: action) }

    /// The runtime's own steps, by the kind its sheet view understands.
    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView? {
        let kind: String
        switch sheet {
        case .addComputer: kind = "computer"
        case .addScreen: kind = "screen"
        case .computerDetails: kind = "computerDetails"
        case .removeComputer: kind = "removeComputer"
        case .conflict: kind = "conflict"
        case .connections: kind = "connections"
        case .removeConnection: kind = "removeConnection"
        case .control: kind = "control"
        case .monitorSetup: kind = "monitorSetup"
        case .cable, .port, .removeScreen, .dimensions: return nil
        }
        guard let runtime else { return AnyView(EmptyView()) }
        return AnyView(DeskLiveSheet(runtime: runtime, kind: kind, selection: sheet.subject ?? runtime.model.selected, close: close))
    }
}
