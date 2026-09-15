import SwiftUI

/// What the Desk page needs from whoever runs the desk: Perch's runtime in the
/// app, or the simulation in the Desk Lab. Views never ask which one they have.
/// A backend answers nil, false or a plain no-op for what it cannot do, and
/// supplies its own wording where the two genuinely differ.
protocol DeskBackend: AnyObject {
    var wording: DeskWording { get }

    /// Save a validated desk. Throwing leaves the model unchanged.
    func edit(_ group: KVMGroup) throws

    // Presets
    func activate(preset: UUID)
    /// Why a preset cannot be used right now, or nil when it can.
    func readiness(preset: UUID) -> String?
    /// Retry the preset whose switch failed.
    func retryActive()
    /// The user reports that an accepted-but-unconfirmed switch did not change
    /// the picture: forget it everywhere and look again.
    func revertSwitch()
    /// Send one monitor's command now, even if this input looks selected.
    /// Presets stay unchanged.
    func switchConnection(_ connection: UUID)

    // Cables and displays
    func mappingOptions() -> [DeskMappingOption]
    func map(port: UUID, option: String)
    /// Save a cable to a computer before its display identity is known.
    func mapComputer(port: UUID, computer: UUID)
    func displayStatus(computer: UUID) -> String?
    func refreshScreens()
    func panelAspect(monitor: UUID) -> Double?

    // Identification
    func identify(monitor: UUID?)
    func identifyDisplay(_ display: String, computer: UUID)
    func identifyComputer(_ computer: UUID)
    func isIdentifying(monitor: UUID) -> Bool
    func isIdentifying(display: String, computer: UUID) -> Bool
    func isIdentifying(computer: UUID) -> Bool
    /// Why an action on a peer cannot run right now, or nil when it can.
    func peerActionReadiness(computer: UUID, action: String) -> String?

    /// A temporary step the backend renders itself. Nil hands the step to the
    /// shared editors.
    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView?
}

/// The few strings that honestly differ between running a desk and simulating one.
struct DeskWording {
    var badge = "DESK"
    var addComputerHelp = "Find a nearby Perch and confirm membership on both computers."
    var presetActivationHelp = "Switch the physical monitor inputs. If keyboard and mouse sharing is enabled on the participating Macs, control starts automatically when the preset is ready."
    static let live = DeskWording()
}
