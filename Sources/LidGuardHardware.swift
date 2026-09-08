import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

protocol LidGuardHardware: AnyObject {
    func observe() -> LidObservation
    func preventLidSleep(_ enabled: Bool) throws
    func requestSleep() throws
}

/// The macOS adapter is deliberately separate from the deterministic policy.
/// kPMSetClamshellSleepState (12) is an Apple XNU private interface, not a
/// public power assertion. Keep it isolated and fail on unsupported hardware.
/// It changes the clamshell bit, never the persistent pmset SleepDisabled key.
/// See Apple XNU IOPMLibDefs.h and RootDomainUserClient::externalMethodDispatched.
final class MacLidGuardHardware: LidGuardHardware {
    /// IOPMFindPowerManagement takes the IOKit main port, not a task port.
    /// Opening/closing this connection alone does not change power settings.
    static func openPowerConnection() throws -> io_connect_t {
        let connection = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connection != 0 else { throw AppError(message: "macOS power control is unavailable.") }
        return connection
    }
    func observe() -> LidObservation {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var closed: Bool?
        if root != 0 {
            closed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            IOObjectRelease(root)
        }
        var power = LidPower.unknown
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            if source == kIOPSACPowerValue { power = .external }
            else if source == kIOPSBatteryPowerValue { power = .battery }
        }
        return .init(closed: closed, power: power)
    }
    func preventLidSleep(_ enabled: Bool) throws {
        guard geteuid() == 0 else { throw AppError(message: "The authorized lid helper is required.") }
        let connection = try Self.openPowerConnection()
        defer { IOServiceClose(connection) }
        var value: UInt64 = enabled ? 1 : 0
        let result = IOConnectCallScalarMethod(connection, 12, &value, 1, nil, nil)
        guard result == kIOReturnSuccess else { throw AppError(message: "This Mac did not accept supervised lid control (\(result)). Lid mode is unavailable.") }
        // AppleClamshellCausesSleep is a cached notification property. XNU's
        // setter changes its internal mask without refreshing that property.
        // A successful command is acknowledgment, not physical sleep proof;
        // the cached property cannot establish success or failure of this call.
    }
    func requestSleep() throws {
        let connection = try Self.openPowerConnection()
        defer { IOServiceClose(connection) }
        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else { throw AppError(message: "macOS rejected the sleep request (\(result)). Open the lid and check the Mac.") }
    }
}

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
        if decision.requestSleep && now - lastSleep >= 5 {
            log("Sending a system sleep request to macOS.")
            do { try hardware.requestSleep(); lastSleep = now; log("macOS accepted the sleep request. See sleep/wake notifications for the observed transition.") }
            catch { log("macOS sleep request failed: \(error.localizedDescription)"); throw error }
        }
    }
}
