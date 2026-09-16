import AppKit
import CoreGraphics
import Foundation

// Runs inside a lab guest only. Two modes:
//   drive  — post synthetic input as if a person were using this guest
//   record — observe every input event this guest receives, with timing
// Perch tags the events it injects from another Mac, so the recorder can tell
// locally posted input from input that arrived over the desk.
let perchTag: Int64 = 0x5045524348494E50

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
}

func move(to point: CGPoint) {
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
}

func drag(from start: CGPoint, to end: CGPoint, steps: Int, pause: Double, held: Bool) {
    if held { post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)) }
    for step in 1...max(1, steps) {
        let fraction = Double(step) / Double(max(1, steps))
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        if held { post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)) }
        else { move(to: point) }
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
    }
    if held { post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)) }
}

func type(_ keys: [CGKeyCode], flags: CGEventFlags, repeats: Int, pause: Double) {
    for _ in 0..<max(1, repeats) {
        for key in keys {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
            down?.flags = flags
            post(down)
            if pause > 0 { Thread.sleep(forTimeInterval: pause) }
            let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
            up?.flags = flags
            post(up)
            if pause > 0 { Thread.sleep(forTimeInterval: pause) }
        }
    }
}

struct Sample: Codable {
    let at: Double
    let kind: String
    let x: Double?
    let y: Double?
    let key: Int?
    let flags: UInt64?
    let fromPerch: Bool
}

func record(seconds: Double, path: String) {
    guard let file = FileHandle(forWritingAtPath: path) ?? {
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }() else { fail("cannot open \(path)") }
    let encoder = JSONEncoder()
    let interesting: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown, .keyUp, .flagsChanged]
    let types = interesting.reduce(into: CGEventMask(0)) { $0 |= CGEventMask(1 << $1.rawValue) }
    let started = now()
    guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                      options: .listenOnly, eventsOfInterest: types,
                                      callback: { _, type, event, context in
        let handle = Unmanaged<FileHandle>.fromOpaque(context!).takeUnretainedValue()
        let location = event.location
        let sample = Sample(at: now(), kind: String(describing: type), x: location.x, y: location.y,
                            key: type == .keyDown || type == .keyUp ? Int(event.getIntegerValueField(.keyboardEventKeycode)) : nil,
                            flags: event.flags.rawValue,
                            fromPerch: event.getIntegerValueField(.eventSourceUserData) == perchTag)
        if let line = try? JSONEncoder().encode(sample) {
            handle.write(line); handle.write(Data("\n".utf8))
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: Unmanaged.passUnretained(file).toOpaque()) else {
        fail("no event tap: grant Accessibility and Input Monitoring in this guest")
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    // Also sample the pointer, so a pointer that stops moving is still visible.
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        guard let point = CGEvent(source: nil)?.location else { return }
        let sample = Sample(at: now(), kind: "pointer", x: point.x, y: point.y, key: nil, flags: nil, fromPerch: false)
        if let line = try? encoder.encode(sample) { file.write(line); file.write(Data("\n".utf8)) }
        if now() - started >= seconds { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }
    CFRunLoopRun()
    try? file.close()
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("usage: guest <drive|record|pointer|screen> ...") }
switch arguments[1] {
case "clock":
    // Traces are stamped with this guest's uptime clock; the host needs the
    // offset to put both guests on one timeline.
    print("{\"uptime\": \(now()), \"wall\": \(Date().timeIntervalSince1970)}")
case "pointer":
    guard let point = CGEvent(source: nil)?.location else { fail("no pointer") }
    print("{\"x\": \(point.x), \"y\": \(point.y)}")
case "screen":
    let frame = NSScreen.main?.frame ?? .zero
    print("{\"width\": \(frame.width), \"height\": \(frame.height)}")
case "record":
    guard arguments.count == 4, let seconds = Double(arguments[2]) else { fail("usage: guest record <seconds> <file>") }
    record(seconds: seconds, path: arguments[3])
case "drive":
    // drive move x y | drive drag x1 y1 x2 y2 steps pause held | drive type keycodes flags repeats pause
    guard arguments.count >= 3 else { fail("usage: guest drive <move|drag|type> ...") }
    switch arguments[2] {
    case "move":
        guard arguments.count == 5, let x = Double(arguments[3]), let y = Double(arguments[4]) else { fail("usage: drive move x y") }
        move(to: CGPoint(x: x, y: y))
    case "drag":
        guard arguments.count == 10, let x1 = Double(arguments[3]), let y1 = Double(arguments[4]),
              let x2 = Double(arguments[5]), let y2 = Double(arguments[6]), let steps = Int(arguments[7]),
              let pause = Double(arguments[8]) else { fail("usage: drive drag x1 y1 x2 y2 steps pause held") }
        drag(from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), steps: steps, pause: pause, held: arguments[9] == "held")
    case "type":
        guard arguments.count == 7, let flags = UInt64(arguments[4]), let repeats = Int(arguments[5]), let pause = Double(arguments[6]) else {
            fail("usage: drive type <comma keycodes> <flags> <repeats> <pause>")
        }
        type(arguments[3].split(separator: ",").compactMap { CGKeyCode($0) }, flags: CGEventFlags(rawValue: flags), repeats: repeats, pause: pause)
    default: fail("unknown drive verb")
    }
default:
    fail("unknown mode")
}
