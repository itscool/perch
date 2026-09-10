import CoreGraphics

/// Constructs sanitized native events without posting them. Tests exercise this
/// boundary without a tap, privileges, windows, or desktop input injection.
struct KVMNativeEvent {
    static let eventTag: Int64 = 0x5045524348494E50
    private var pressedButtons: Set<UInt16> = []
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
        case .buttonDown, .buttonUp:
            let down = value.kind == .buttonDown
            if down { pressedButtons.insert(value.code) } else { pressedButtons.remove(value.code) }
            let type: CGEventType = value.code == 0 ? (down ? .leftMouseDown : .leftMouseUp) : value.code == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: CGMouseButton(rawValue: UInt32(value.code))!)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(value.clickCount))
        case .scroll:
            event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(value.y), wheel2: Int32(value.x), wheel3: 0)
        }
        event?.flags = CGEventFlags(rawValue: value.flags)
        event?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        return event
    }
}
