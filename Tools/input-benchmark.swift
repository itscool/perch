import AppKit
struct AppError: Error { let message: String }
@main struct InputBenchmark {
    static func main() {
        // Construct private events once; never post them or install an event tap.
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 9, wheel2: -4, wheel3: 0)!
        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let originalY = scroll.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let originalX = scroll.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true)!
        key.flags = [.maskControl, .maskShift]
        for (name, event, type) in [("vertical scroll",scroll,CGEventType.scrollWheel),("modifier swap",key,CGEventType.flagsChanged)] {
            var batches: [Double] = []
            for _ in 0..<100 {
                let began = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<2000 { InputTransform.apply(event, type: type, trackpad: true, wheel: true, swap: true) }
                batches.append(Double(DispatchTime.now().uptimeNanoseconds - began) / 2000 / 1000)
            }
            batches.sort()
            print(String(format: "%@: median batch mean %.3f microseconds/event; slowest batch mean %.3f; 200,000 private events", name,batches[50],batches.last!))
        }
        precondition(scroll.getIntegerValueField(.scrollWheelEventDeltaAxis1) == originalY)
        precondition(scroll.getIntegerValueField(.scrollWheelEventDeltaAxis2) == originalX)
        precondition(key.getIntegerValueField(.keyboardEventKeycode) == 59)
        print("These are transform-only timings, not OS event delivery or end-to-end input latency.")
    }
}
