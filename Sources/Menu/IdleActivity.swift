import AppKit
import IOKit
import IOKit.pwr_mgt

/// One "the user is here" signal that the screen saver and the lock really see.
///
/// On current macOS, loginwindow starts the screen saver, and the lock that
/// follows it, from the session's idle clock: the time since the last input
/// event in this login session (`IdleClock.sessionSeconds`). Perch used to post
/// a null HID event and declare user activity. The null event resets only the
/// HID idle clock and the declaration only display sleep, so neither held off a
/// single lock: on November 13 to 16, 2026, 23 locks came at exactly 20 idle
/// minutes while Perch was signalling every 30 seconds.
///
/// What works, and what this does:
/// 1. A zero-distance mouse move, tagged so Perch's own taps ignore it, posted
///    into the HID stream: it counts as session input and resets that clock. It
///    is posted only once the session has been idle a while (never while you
///    are using the Mac), never during a drag or on the lock screen, and each
///    one reads the clock before and after to say whether it really worked.
/// 2. A display-sleep assertion, renewed with every signal and released by
///    itself a little after the last one: loginwindow checks it before starting
///    the screen saver, and the screens stay on.
/// 3. The user-activity declaration, kept for display sleep, now updating one
///    assertion instead of creating a new one every time (120 had piled up).
/// None of it unlocks a screen already locked, or stops a lock asked for:
/// closing the lid, Ctrl-Cmd-Q, a hot corner, an MDM lock command.
final class IdleActivitySignal {
    private var activity: IOPMAssertionID = 0
    private var display: IOPMAssertionID = 0
    private lazy var eventSource = CGEventSource(stateID: .privateState)
    /// The last signal's outcome, for the log and the lock report.
    private(set) var lastOutcome: IdleNudge.Outcome?
    init() {}
    deinit { close() }
    /// Signal now. Returns false only when the signal could not be given at all.
    @discardableResult func declare(reason: String) -> Bool {
        guard !SettingsWindow.shared.testing else { return false }
        let name = reason as CFString
        if IOPMAssertionDeclareUserActivity(name, kIOPMUserActiveLocal, &activity) != kIOReturnSuccess { activity = 0 }
        holdDisplay(name)
        let before = IdleClock.sessionSeconds()
        let decision = IdleNudge.decide(sessionIdle: before, buttonHeld: Self.buttonHeld, locked: Self.screenLocked, canPost: CGPreflightPostEventAccess())
        guard decision == .nudge else {
            lastOutcome = decision
            if decision == .cannotPost { PerchLog.note("idle.signal", "Cannot hold off the idle lock: Perch needs Accessibility to post its signal") }
            return decision != .cannotPost
        }
        guard let location = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) else {
            lastOutcome = .cannotPost; return false
        }
        event.setIntegerValueField(.eventSourceUserData, value: KVMNativeEvent.eventTag)
        event.post(tap: .cghidEventTap)
        // The clock is read again a moment later: posted events reach the
        // session on their own schedule.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            let after = IdleClock.sessionSeconds()
            let outcome = IdleNudge.judge(before: before, after: after)
            self?.lastOutcome = outcome
            PerchLog.note("idle.signal", outcome.summary(before: before, after: after))
        }
        return true
    }
    /// Keep the screens from sleeping until a little after the last signal.
    private func holdDisplay(_ name: CFString) {
        if display != 0 { IOPMAssertionRelease(display); display = 0 }
        let properties: [String: Any] = [kIOPMAssertionTypeKey as String: kIOPMAssertPreventUserIdleDisplaySleep as String,
                                         kIOPMAssertionNameKey as String: name as String,
                                         kIOPMAssertionTimeoutKey as String: IdleNudge.displayHold,
                                         kIOPMAssertionTimeoutActionKey as String: kIOPMAssertionTimeoutActionRelease as String]
        if IOPMAssertionCreateWithProperties(properties as CFDictionary, &display) != kIOReturnSuccess { display = 0 }
    }
    func close() {
        if display != 0 { IOPMAssertionRelease(display); display = 0 }
        if activity != 0 { IOPMAssertionRelease(activity); activity = 0 }
    }
    private static var buttonHeld: Bool {
        (0...2).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
    }
    private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }
}

/// When to post the idle signal and whether it worked, as logic only, pinned by
/// fast tests.
enum IdleNudge {
    /// Only once the session has been idle this long: never while someone is
    /// using the Mac. With a signal every 30 s, the session clock then never
    /// passes about 45 s, under the shortest screen saver time macOS offers (1 min).
    static let after: Double = 15
    /// How long the screens are held on after a signal, in seconds.
    static let displayHold = 75
    enum Outcome: Equatable {
        case nudge, notNeeded, busy, locked, cannotPost, worked, failed
        func summary(before: Double?, after: Double?) -> String {
            func seconds(_ value: Double?) -> String { value.map { String(format: "%.1f s", $0) } ?? "unreadable" }
            switch self {
            case .worked: return "The idle signal reset the session idle clock (" + seconds(before) + " → " + seconds(after) + ")"
            case .failed: return "The idle signal did not reset the session idle clock (" + seconds(before) + " → " + seconds(after) + "); the screen saver may still start"
            default: return "Idle signal: \(self)"
            }
        }
    }
    static func decide(sessionIdle: Double?, buttonHeld: Bool, locked: Bool, canPost: Bool) -> Outcome {
        if locked { return .locked }
        if buttonHeld { return .busy }
        guard let sessionIdle, sessionIdle >= after else { return .notNeeded }
        return canPost ? .nudge : .cannotPost
    }
    static func judge(before: Double?, after: Double?) -> Outcome {
        guard let after, after.isFinite else { return .failed }
        return after < 1 && (before ?? .infinity) >= 1 ? .worked : .failed
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
        if signal.declare(reason: "Perch: prevent idle lock") { lastSignalled = Date() }
        // Refused: it could not be given, or it was given and the clock the
        // screen saver uses did not move.
        lastSignalRefused = signal.lastOutcome == .cannotPost || signal.lastOutcome == .failed
    }
    deinit { timer?.invalidate() }
}


/// How long this Mac has been without input. Read-only: it touches no setting
/// and moves nothing.
enum IdleClock {
    /// The session's idle clock: what loginwindow's screen saver and idle lock
    /// go by on current macOS.
    static func sessionSeconds() -> Double? {
        guard let any = CGEventType(rawValue: ~0) else { return nil }
        let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        return value.isFinite && value >= 0 ? value : nil
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
    /// The session clock, which is the one the screen saver and lock go by.
    var idle: () -> Double? = { IdleClock.sessionSeconds() }
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
