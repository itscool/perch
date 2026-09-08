import Foundation
import IOKit
import IOKit.pwr_mgt

/// OS notifications are separate evidence from command return codes. They say
/// sleep is beginning / wake completed, not why sleep happened or time asleep.
/// Always acknowledge promptly; logging never vetoes or delays system sleep.
final class LidPowerNotifications {
    private let activity: LidActivityRecorder
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var connection: io_connect_t = 0
    private var sleepBegan: Double?
    private let observe: () -> Void
    init(activity: LidActivityRecorder, observe: @escaping () -> Void = {}) { self.activity = activity; self.observe = observe }
    func start() {
        connection = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &port, { context, _, type, argument in
            guard let context else { return }
            Unmanaged<LidPowerNotifications>.fromOpaque(context).takeUnretainedValue().receive(type, argument: argument)
        }, &notifier)
        guard connection != 0, let port, let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            activity.record("macOS sleep/wake notifications are unavailable. Command results alone cannot confirm sleep."); return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        activity.record("Listening for macOS sleep/wake notifications.")
    }
    private func receive(_ type: UInt32, argument: UnsafeMutableRawPointer?) {
        switch type {
        case UInt32(PerchCanSystemSleep):
            IOAllowPowerChange(connection, Int(bitPattern: argument))
        case UInt32(PerchSystemWillSleep):
            observe()
            sleepBegan = LidGuardClock.now
            activity.record("macOS notification: system sleep is beginning.")
            IOAllowPowerChange(connection, Int(bitPattern: argument))
        case UInt32(PerchSystemHasPoweredOn):
            activity.record(sleepBegan.map { "macOS notification: wake completed, \(LidActivityTracker.seconds(LidGuardClock.now - $0)) after sleep began." } ?? "macOS notification: wake completed; the preceding sleep was not observed.")
            sleepBegan = nil
            observe()
        case UInt32(PerchSystemWillNotSleep):
            activity.record("macOS notification: the pending idle-sleep attempt was cancelled.")
        default: break
        }
    }
    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if connection != 0 { IOServiceClose(connection) }
        if let port { IONotificationPortDestroy(port) }
    }
}
