import Foundation
import CoreGraphics

@main struct NativeInputChecks {
    static func main() throws {
        func check(_ condition: Bool, _ detail: String) throws { if !condition { throw KVMError(detail) } }
        var builder = KVMNativeEvent()
        let point = CGPoint(x: 123, y: 456)
        let source = CGEventSource(stateID: .privateState)
        let down = builder.make(.init(kind: .buttonDown, code: 0, clickCount: 2), point: point, source: source)
        try check(down?.type == .leftMouseDown && down?.location == point && down?.getIntegerValueField(.mouseEventClickState) == 2, "Double-click semantics or target position lost")
        let drag = builder.make(.init(kind: .motion), point: point, source: source)
        try check(drag?.type == .leftMouseDragged, "Held button generated a move instead of a drag")
        _ = builder.make(.init(kind: .buttonUp, code: 0), point: point, source: source)
        try check(builder.make(.init(kind: .motion), point: point, source: source)?.type == .mouseMoved, "Mouse stayed dragging after release")
        _ = builder.make(.init(kind: .buttonDown, code: 2), point: point, source: source)
        try check(builder.make(.init(kind: .motion), point: point, source: source)?.type == .otherMouseDragged, "Auxiliary mouse button drag lost")
        let key = builder.make(.init(kind: .keyDown, code: 12, flags: CGEventFlags.maskShift.rawValue, repeated: true), point: point, source: source)
        try check(key?.type == .keyDown && key?.getIntegerValueField(.keyboardEventAutorepeat) == 1 && key?.flags.contains(.maskShift) == true, "Repeat/modifiers lost")
        try check(key?.getIntegerValueField(.eventSourceUserData) == KVMNativeEvent.eventTag, "Injected event can be captured again or transformed twice")
        let wheel = builder.make(.init(kind: .scroll, x: 7, y: -13), point: point, source: source)
        try check(wheel?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -13 && wheel?.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 7, "Scroll axes or direction changed")
        try check(builder.make(.init(kind: .buttonDown, code: 99), point: point, source: source) == nil, "Invalid event reached native constructor")
        print("PASS: native event construction preserves double clicks, drag/release, auxiliary buttons, modifiers, repeat, scroll axes and loop-prevention tag. No event posted, tap created, or access requested.")
    }
}
