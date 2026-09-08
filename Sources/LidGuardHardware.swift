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
    func observe() -> LidObservation {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var closed: Bool?, allowed: Bool?
        if root != 0 {
            closed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            allowed = IORegistryEntryCreateCFProperty(root, "AppleClamshellCausesSleep" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            IOObjectRelease(root)
        }
        var power = LidPower.unknown
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            if source == kIOPSACPowerValue { power = .external }
            else if source == kIOPSBatteryPowerValue { power = .battery }
        }
        return .init(closed: closed, power: power, lidSleepAllowed: allowed)
    }
    func preventLidSleep(_ enabled: Bool) throws {
        guard geteuid() == 0 else { throw AppError(message: "The authorized lid helper is required.") }
        let connection = IOPMFindPowerManagement(mach_task_self_)
        guard connection != 0 else { throw AppError(message: "macOS power control is unavailable.") }
        defer { IOServiceClose(connection) }
        var value: UInt64 = enabled ? 1 : 0
        let result = IOConnectCallScalarMethod(connection, 12, &value, 1, nil, nil)
        guard result == kIOReturnSuccess else { throw AppError(message: "This Mac did not accept supervised lid control (\(result)). Lid mode is unavailable.") }
        guard !enabled || observe().lidSleepAllowed == false else { throw AppError(message: "macOS did not confirm lid-sleep prevention. This mode is unavailable on this Mac.") }
    }
    func requestSleep() throws {
        let connection = IOPMFindPowerManagement(mach_task_self_)
        guard connection != 0 else { throw AppError(message: "Could not connect to macOS to request sleep.") }
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
    init(_ hardware: LidGuardHardware) { self.hardware = hardware }
    func apply(_ decision: LidGuardDecision, now: Double, forceRelease: Bool = false) throws {
        if preventing != decision.preventLidSleep || forceRelease {
            do { try hardware.preventLidSleep(decision.preventLidSleep) }
            catch {
                // A control call can write successfully and then fail readback.
                // Always attempt cleanup even before our local flag was set.
                if decision.preventLidSleep { try? hardware.preventLidSleep(false) }
                throw error
            }
            preventing = decision.preventLidSleep
        }
        if decision.requestSleep && now - lastSleep >= 5 {
            try hardware.requestSleep(); lastSleep = now
        }
    }
}
