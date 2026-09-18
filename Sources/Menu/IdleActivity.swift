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
    /// Whether the last attempt was refused by macOS, so a lock report can say
    /// that Perch tried and could not, instead of implying it held the lock off.
    private(set) var lastSignalRefused = false
    private func fire() {
        if signal.declare(reason: "Perch: prevent idle lock") { lastSignalled = Date(); lastSignalRefused = false }
        else { lastSignalRefused = true }
    }
    deinit { timer?.invalidate() }
}


/// How long this Mac has been without input, as macOS counts it for the screen
/// saver and the idle lock. Read-only: it touches no setting and moves nothing.
enum IdleClock {
    static func seconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any],
              let nanoseconds = values["HIDIdleTime"] as? UInt64 else { return nil }
        return Double(nanoseconds) / 1_000_000_000
    }
}

/// Records every screen lock and unlock next to the facts that explain it, so
/// "my Mac keeps locking" is answered from the log instead of guesswork: how
/// long the Mac had actually been idle, whether Perch was holding the idle lock
/// off and when it last managed to, and whether a desk session was running.
final class ScreenLockLog {
    /// A lock while the Mac had been idle for less than this cannot be an idle
    /// timeout: the shortest idle lock macOS offers is a minute.
    static let idleLockFloor: Double = 55
    private var observers: [Any] = []
    private var lockedAt: Date?
    var idle: () -> Double? = { IdleClock.seconds() }
    var preventing: () -> Bool = { false }
    var lastSignal: () -> Date? = { nil }
    var signalRefused: () -> Bool = { false }
    var sharing: () -> Bool = { false }
    var clock: () -> Date = { Date() }
    func start() {
        guard observers.isEmpty, !SettingsWindow.shared.testing else { return }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.record(locked: locked)
            })
        }
    }
    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
    }
    deinit { stop() }
    private func record(locked: Bool) {
        let now = clock()
        if locked {
            lockedAt = now
            PerchLog.record("screen.lock", Self.lockSummary(idle: idle(), preventing: preventing(),
                                                            sinceSignal: lastSignal().map { now.timeIntervalSince($0) },
                                                            signalRefused: signalRefused(), sharing: sharing()))
        } else {
            let held = lockedAt.map { now.timeIntervalSince($0) }
            lockedAt = nil
            PerchLog.record("screen.unlock", Self.unlockSummary(lockedFor: held))
        }
    }
    static func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole) s" }
        let minutes = whole / 60
        return minutes < 60 ? "\(minutes) min \(whole % 60) s" : "\(minutes / 60) h \(minutes % 60) min"
    }
    /// One line of facts. It never claims a cause it cannot see; it states how
    /// long the Mac was idle and what Perch was doing, and it says plainly when
    /// the Mac was not idle long enough for this to have been an idle lock.
    static func lockSummary(idle: Double?, preventing: Bool, sinceSignal: TimeInterval?, signalRefused: Bool, sharing: Bool) -> String {
        var parts = ["Screen locked."]
        if let idle {
            parts.append("The Mac had been idle \(duration(idle)).")
            if idle < idleLockFloor { parts.append("That is too short to be an idle lock, so something else locked it.") }
        } else {
            parts.append("This Mac's idle time could not be read.")
        }
        if !preventing {
            parts.append("Prevent idle lock is off.")
        } else if signalRefused {
            parts.append("Prevent idle lock is on, but macOS refused its last signal.")
        } else if let sinceSignal {
            parts.append("Prevent idle lock is on; it last reported activity \(duration(sinceSignal)) ago.")
        } else {
            parts.append("Prevent idle lock is on but has not reported activity yet.")
        }
        if sharing { parts.append("A desk session was running, so keyboard and mouse sharing stops until this Mac is unlocked.") }
        return parts.joined(separator: " ")
    }
    static func unlockSummary(lockedFor: TimeInterval?) -> String {
        guard let lockedFor else { return "Screen unlocked." }
        return "Screen unlocked after \(duration(lockedFor))."
    }
}
