import CoreGraphics
import Foundation

/// Constructs sanitized native events without posting them. Tests exercise this
/// boundary without a tap, privileges, windows, or desktop input injection.
struct KVMNativeEvent {
    static let eventTag: Int64 = 0x5045524348494E50
    private var pressedButtons: Set<UInt16> = []
    /// Sub-pixel scroll remainders, so gentle trackpad scrolling still moves.
    private var scrollRemainder = (x: 0.0, y: 0.0)
    mutating func make(_ value: KVMInputEvent, point: CGPoint, source: CGEventSource?) -> CGEvent? {
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
        event?.flags = CGEventFlags(rawValue: value.flags)
        event?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        // Gesture recognisers and drag thresholds compare event times.
        event?.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        return event
    }
}
