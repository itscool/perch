import AppKit
import IOKit
import IOKit.hidsystem
import IOKit.pwr_mgt

/// One "the user is here" signal for both of macOS's idle clocks.
///
/// Power management (display and system sleep) is reset by a user-activity
/// assertion. The screen saver and the idle lock, including an MDM maximum-
/// inactivity policy, watch the HID idle clock, which only an event through the
/// HID system resets. A null HID event is exactly "nothing happened": it moves
/// no cursor, presses no button and types no key. Fallback when the null event
/// is refused: a zero-delta mouse move at the current position, tagged so
/// Perch's own event taps ignore it. Neither unlocks a screen that is already
/// locked nor prevents an explicit lock (Ctrl-Cmd-Q, hot corner, lid, MDM lock).
final class IdleActivitySignal {
    private var hidSystem: io_connect_t = 0
    private lazy var eventSource = CGEventSource(stateID: .privateState)
    init() {}
    deinit { close() }
    /// Declare activity now. Returns false only when every path failed.
    @discardableResult func declare(reason: String) -> Bool {
        guard !SettingsWindow.shared.testing else { return false }
        var assertion: IOPMAssertionID = 0
        _ = IOPMAssertionDeclareUserActivity(reason as CFString, kIOPMUserActiveLocal, &assertion)
        if hidSystem == 0 {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                var connect: io_connect_t = 0
                if IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS { hidSystem = connect }
            }
        }
        if hidSystem != 0 {
            var data = NXEventData()
            if IOHIDPostEvent(hidSystem, UInt32(NX_NULLEVENT), IOGPoint(x: 0, y: 0), &data, UInt32(kNXEventDataVersion), 0, 0) == KERN_SUCCESS { return true }
            IOServiceClose(hidSystem); hidSystem = 0
        }
        guard let location = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) else { return false }
        event.setIntegerValueField(.eventSourceUserData, value: KVMNativeEvent.eventTag)
        event.post(tap: .cghidEventTap)
        return true
    }
    func close() {
        if hidSystem != 0 { IOServiceClose(hidSystem); hidSystem = 0 }
    }
}

/// Sleep menu option, off by default: keep the idle screen saver and idle lock
/// from starting by declaring presence every 30 seconds. It does not keep the
/// Mac awake by itself; Keep awake owns that.
final class IdleLockPreventer {
    static let interval: TimeInterval = 30
    /// What the menu row says beside the title. People want to know how long
    /// their Mac stays unlocked, not how often Perch signals: there is no time
    /// limit, so it lasts until they turn it off.
    static func rowHint(enabled: Bool) -> String { enabled ? "Until you turn it off" : "" }
    private var timer: Timer?
    private let signal = IdleActivitySignal()
    private(set) var lastSignalled: Date?
    var enabled: Bool { timer != nil }
    func set(_ enabled: Bool) {
        guard enabled != self.enabled else { return }
        timer?.invalidate(); timer = nil
        guard enabled else { lastSignalled = nil; signal.close(); return }
        let timer = MainTimer.every(Self.interval) { [weak self] in self?.fire() }
        timer.tolerance = 2
        self.timer = timer
        fire()
    }
    private func fire() {
        if signal.declare(reason: "Perch: prevent idle lock") { lastSignalled = Date() }
    }
    deinit { timer?.invalidate() }
}
