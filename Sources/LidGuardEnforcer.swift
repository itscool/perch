import Foundation

protocol LidGuardHardware: AnyObject {
    func observe() -> LidObservation
    func preventLidSleep(_ enabled: Bool) throws
    func requestSleep() throws
    func verifyLidSleepPrevention() throws
}
extension LidGuardHardware { func verifyLidSleepPrevention() throws {} }

/// All power mutations, including failure cleanup, cross this injectable edge.
/// Removing clamshell prevention always precedes an actual system-sleep request.
final class LidGuardEnforcer {
    let hardware: LidGuardHardware
    private(set) var preventing = false
    private var lastSleep: Double = -.infinity
    private let log: (String) -> Void
    init(_ hardware: LidGuardHardware, log: @escaping (String) -> Void = { _ in }) { self.hardware = hardware; self.log = log }
    func apply(_ decision: LidGuardDecision, now: Double, forceRelease: Bool = false) throws {
        if preventing != decision.preventLidSleep || forceRelease {
            do {
                log(decision.preventLidSleep ? "Requesting lid-sleep prevention." : "Releasing lid-sleep prevention.")
                try hardware.preventLidSleep(decision.preventLidSleep)
                log(decision.preventLidSleep ? "macOS accepted lid-sleep prevention." : "macOS accepted release of lid-sleep prevention.")
            }
            catch {
                log("Lid-control command failed: \(error.localizedDescription)")
                // An uncertain command still needs cleanup before our local flag is set.
                if decision.preventLidSleep {
                    do { try hardware.preventLidSleep(false); log("macOS accepted cleanup after the failed lid command.") }
                    catch { log("Lid cleanup also failed: \(error.localizedDescription)") }
                }
                throw error
            }
            preventing = decision.preventLidSleep
        }
        if decision.preventLidSleep { try hardware.verifyLidSleepPrevention() }
        if decision.requestSleep && now - lastSleep >= 5 {
            log("Sending a system sleep request to macOS.")
            do { try hardware.requestSleep(); lastSleep = now; log("macOS accepted the sleep request. See sleep/wake notifications for the observed transition.") }
            catch { log("macOS sleep request failed: \(error.localizedDescription)"); throw error }
        }
    }
}
