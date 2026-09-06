import AppKit

func runInputTests() throws {
    func check(_ ok: Bool, _ message: String) throws {
        if !ok { throw AppError(message: message) }
    }
    for phased in [false, true] {
        for trackpad in [false, true] {
            for wheel in [false, true] {
                let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 9, wheel2: -4, wheel3: 0)!
                e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phased ? 2 : 0)
                e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 11)
                e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 2.25)
                let y = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let py = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let fy = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                let x = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                let px = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                let fx = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                InputTransform.apply(e, type: .scrollWheel, trackpad: trackpad, wheel: wheel, swap: false)
                let sign: Int64 = (phased ? trackpad : wheel) ? -1 : 1
                try check(e.getIntegerValueField(.scrollWheelEventDeltaAxis1) == y * sign, "Vertical scroll direction")
                try check(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == py * sign, "Pixel scroll direction")
                try check(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == fy * Double(sign), "Fractional scroll direction")
                try check(e.getIntegerValueField(.scrollWheelEventDeltaAxis2) == x && e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == px && e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == fx, "Horizontal scroll changed")
            }
        }
    }
    let momentum = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 7, wheel2: 0, wheel3: 0)!
    momentum.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
    let originalMomentum = momentum.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    InputTransform.apply(momentum, type: .scrollWheel, trackpad: true, wheel: false, swap: false)
    try check(momentum.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -originalMomentum, "Trackpad momentum direction")
    let pairs: [(Int64, Int64, UInt64, UInt64)] = [(59,55,0x1,0x8),(55,59,0x8,0x1),(62,54,0x2000,0x10),(54,62,0x10,0x2000)]
    for (from,to,flag,targetFlag) in pairs {
        for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(from), keyDown: true)!
            let aggregate: CGEventFlags = from == 59 || from == 62 ? .maskControl : .maskCommand
            let destination: CGEventFlags = aggregate == .maskControl ? .maskCommand : .maskControl
            e.flags = CGEventFlags(rawValue: aggregate.rawValue | flag | CGEventFlags.maskShift.rawValue)
            let original = e.flags
            InputTransform.apply(e, type: type, trackpad: false, wheel: false, swap: true)
            try check(e.getIntegerValueField(.keyboardEventKeycode) == to, "Modifier keycode swap")
            try check(e.flags.rawValue == destination.rawValue | targetFlag | CGEventFlags.maskShift.rawValue, "Modifier flags swap")
            InputTransform.apply(e, type: type, trackpad: false, wheel: false, swap: true)
            try check(e.flags == original && e.getIntegerValueField(.keyboardEventKeycode) == from, "Modifier swap roundtrip")
        }
    }
    print("PASS: independent vertical scroll, horizontal preservation, momentum, both modifier sides and key transitions")
}
