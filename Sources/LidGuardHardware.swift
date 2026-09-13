import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// The macOS adapter is deliberately separate from the deterministic policy.
/// The guarded persistent override is independent of powerd's shared clamshell
/// flag. A durable ownership journal and independent recovery must exist first.
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
        try LidSleepOverride.set(enabled)
    }
    func verifyLidSleepPrevention() throws {
        guard LidSleepOverride.owned else { throw AppError(message: "The lid recovery record is missing. Protection has stopped.") }
        try LidSleepOverride.verify(true)
    }
    func requestSleep() throws {
        let connection = try Self.openPowerConnection()
        defer { IOServiceClose(connection) }
        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else { throw AppError(message: "macOS rejected the sleep request (\(result)). Open the lid and check the Mac.") }
    }
}
