import CoreGraphics
import Foundation

/// Constructs sanitized native events without posting them. Tests exercise this
/// boundary without a tap, privileges, windows, or desktop input injection.
struct KVMNativeEvent {
    static let eventTag: Int64 = 0x5045524348494E50
    private var pressedButtons: Set<UInt16> = []
    /// Sub-pixel scroll remainders, so gentle trackpad scrolling still moves.
    private var scrollRemainder = (x: 0.0, y: 0.0)
    /// `localFlags`: modifiers held on the posting Mac's own keyboard, added to
    /// the sender's.
    mutating func make(_ value: KVMInputEvent, point: CGPoint, source: CGEventSource?, localFlags: UInt64 = 0) -> CGEvent? {
        guard value.valid else { return nil }
        let event: CGEvent?
        switch value.kind {
        case .keyDown, .keyUp, .modifiers:
            event = CGEvent(keyboardEventSource: source, virtualKey: value.code, keyDown: value.kind == .keyDown)
            if value.kind == .modifiers { event?.type = .flagsChanged }
            event?.setIntegerValueField(.keyboardEventAutorepeat, value: value.repeated ? 1 : 0)
        case .motion:
            let button = pressedButtons.sorted().first
            let type: CGEventType = button == nil ? .mouseMoved : button == 0 ? .leftMouseDragged : button == 1 ? .rightMouseDragged : .otherMouseDragged
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: CGMouseButton(rawValue: UInt32(button ?? 0))!)
            // Apps and games that read relative movement see the values the
            // hardware produced, not only a new position.
            event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(value.x.rounded()))
            event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(value.y.rounded()))
        case .buttonDown, .buttonUp:
            let down = value.kind == .buttonDown
            if down { pressedButtons.insert(value.code) } else { pressedButtons.remove(value.code) }
            let type: CGEventType = value.code == 0 ? (down ? .leftMouseDown : .leftMouseUp) : value.code == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: CGMouseButton(rawValue: UInt32(value.code))!)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(value.clickCount))
        case .mediaDown, .mediaUp:
            // Posted as a system-defined event by the adapter (`DeskMediaKey`).
            return nil
        case .scroll:
            if value.continuous {
                let y = value.y + scrollRemainder.y, x = value.x + scrollRemainder.x
                let wholeY = y.rounded(.towardZero), wholeX = x.rounded(.towardZero)
                scrollRemainder = (x - wholeX, y - wholeY)
                event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(clamping: Int(wholeY)), wheel2: Int32(clamping: Int(wholeX)), wheel3: 0)
                event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(value.phase))
                event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(value.momentum))
            } else {
                scrollRemainder = (0, 0)
                event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: Int32(clamping: Int(value.y.rounded())), wheel2: Int32(clamping: Int(value.x.rounded())), wheel3: 0)
            }
        }
        // This Mac's own modifiers join mouse events only. Keys carry exactly
        // what the sender held, so a release really releases.
        let mouse = value.kind != .keyDown && value.kind != .keyUp && value.kind != .modifiers
        event?.flags = CGEventFlags(rawValue: value.flags | (mouse ? localFlags & KVMInputEvent.flagMask : 0))
        event?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        // Gesture recognisers and drag thresholds compare event times.
        event?.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        return event
    }
}

/// Counts clicks on the Mac showing the pointer, from where its cursor really
/// is: a second press of the same button, soon enough and close enough, is a
/// double-click; a third, a triple.
struct DeskClickCounter {
    static let slop: CGFloat = 4
    private var last: (button: UInt16, at: Double, point: CGPoint, count: Int)?
    mutating func down(_ button: UInt16, at time: Double, point: CGPoint, interval: Double) -> Int {
        var count = 1
        if let last, last.button == button, time >= last.at, time - last.at <= interval,
           hypot(point.x - last.point.x, point.y - last.point.y) <= Self.slop { count = min(3, last.count + 1) }
        last = (button, time, point, count)
        return count
    }
    /// The count a release carries: the same as its press.
    func count(_ button: UInt16) -> Int { last.map { $0.button == button ? $0.count : 1 } ?? 1 }
}

/// A trackpad scroll in progress on this Mac, so it can be ended when control
/// moves away mid-gesture instead of leaving an app rubber-banding.
struct DeskScrollGesture {
    private(set) var phaseOpen = false
    private(set) var momentumOpen = false
    mutating func posted(_ value: KVMInputEvent) {
        guard value.kind == .scroll, value.continuous else { return }
        switch value.phase { case 1, 2: phaseOpen = true; case 4, 8: phaseOpen = false; default: break }
        switch value.momentum { case 1, 2: momentumOpen = true; case 3: momentumOpen = false; default: break }
    }
    mutating func endings() -> [KVMInputEvent] {
        var out: [KVMInputEvent] = []
        if phaseOpen { var end = KVMInputEvent(kind: .scroll); end.phase = 4; out.append(end) }
        if momentumOpen { var end = KVMInputEvent(kind: .scroll); end.momentum = 3; out.append(end) }
        phaseOpen = false; momentumOpen = false
        return out
    }
}
