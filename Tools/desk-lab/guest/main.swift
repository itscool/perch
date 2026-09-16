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

func edgePush(at point: CGPoint, deltaX: Int, events: Int = 14, pause: Double = 0.008, held: Bool) {
    // A real mouse pushed against the side of a screen keeps reporting motion
    // while the cursor stays clamped on the last pixel. Perch builds its canvas
    // position from those deltas, not from the clamped position, so without
    // them a crossing can never be detected however far the drag intended to
    // travel. One plausible mouse delta, repeated, is what a device produces.
    for _ in 0..<max(1, events) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: held ? .leftMouseDragged : .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { continue }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(deltaX))
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        post(event)
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
    }
}


func drag(from start: CGPoint, to end: CGPoint, steps: Int, pause: Double, held: Bool, push: Int) {
    if held { post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)) }
    for step in 1...max(1, steps) {
        let fraction = Double(step) / Double(max(1, steps))
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        if held { post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)) }
        else { move(to: point) }
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
    }
    // Keep pushing once the cursor is against the edge, which is the only
    // motion that can carry the pointer onto the other Mac.
    if push != 0 { edgePush(at: end, deltaX: push, held: held) }
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

func crossHolding(at point: CGPoint, push: Int, key: CGKeyCode, flags: CGEventFlags) {
    // A chord held across a switch: the key goes down on this Mac, control
    // moves to the other one mid-chord, then the key comes up. A modifier or
    // key left behind on either machine shows up as an unbalanced trace.
    move(to: point)
    let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
    down?.flags = flags
    post(down)
    edgePush(at: point, deltaX: push, held: false)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    up?.flags = flags
    post(up)
}


func name(of type: CGEventType) -> String {
    // Swift renders a CGEventType as "CGEventType(rawValue: 10)", which reads
    // badly in a trace and invites comparisons against names that never match.
    switch type {
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .mouseMoved: return "mouseMoved"
    case .leftMouseDragged: return "leftMouseDragged"
    case .rightMouseDragged: return "rightMouseDragged"
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .flagsChanged: return "flagsChanged"
    default: return String(describing: type)
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
        let sample = Sample(at: now(), kind: name(of: type), x: location.x, y: location.y,
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
    // The run loop timer below normally ends the recording, but a stalled tap
    // callback or a busy guest can outlast it, and a recorder that never exits
    // fails the permutation that was being measured. Leave on time regardless.
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds + 3) {
        try? file.close()
        exit(0)
    }
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
    // drive move x y | drive drag x1 y1 x2 y2 steps pause held pushDelta | drive crosshold x y pushDelta keycode flags | drive type keycodes flags repeats pause
    guard arguments.count >= 3 else { fail("usage: guest drive <move|drag|type> ...") }
    switch arguments[2] {
    case "move":
        guard arguments.count == 5, let x = Double(arguments[3]), let y = Double(arguments[4]) else { fail("usage: drive move x y") }
        move(to: CGPoint(x: x, y: y))
    case "drag":
        guard arguments.count == 11, let x1 = Double(arguments[3]), let y1 = Double(arguments[4]),
              let x2 = Double(arguments[5]), let y2 = Double(arguments[6]), let steps = Int(arguments[7]),
              let pause = Double(arguments[8]), let push = Int(arguments[10]) else {
            fail("usage: drive drag x1 y1 x2 y2 steps pause held pushDelta")
        }
        drag(from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), steps: steps, pause: pause,
             held: arguments[9] == "held", push: push)
    case "crosshold":
        guard arguments.count == 8, let x = Double(arguments[3]), let y = Double(arguments[4]),
              let push = Int(arguments[5]), let key = UInt16(arguments[6]), let flags = UInt64(arguments[7]) else {
            fail("usage: drive crosshold x y pushDelta keycode flags")
        }
        crossHolding(at: CGPoint(x: x, y: y), push: push, key: CGKeyCode(key), flags: CGEventFlags(rawValue: flags))
    case "type":
        guard arguments.count == 7, let flags = UInt64(arguments[4]), let repeats = Int(arguments[5]), let pause = Double(arguments[6]) else {
            fail("usage: drive type <comma keycodes> <flags> <repeats> <pause>")
        }
        type(arguments[3].split(separator: ",").compactMap { CGKeyCode($0) }, flags: CGEventFlags(rawValue: flags), repeats: repeats, pause: pause)
    default: fail("unknown drive verb")
    }
case "track":
    // Does this guest's own cursor still follow input posted here? When focus
    // moves to the other Mac, Perch captures local input instead of letting it
    // through, so the cursor stops tracking. That tells the lab whether focus
    // went remote without asking the product anything.
    guard arguments.count == 4, let dx = Double(arguments[2]), let dy = Double(arguments[3]) else {
        fail("usage: guest track dx dy")
    }
    let before = CGEvent(source: nil)?.location ?? .zero
    let target = CGPoint(x: before.x + dx, y: before.y + dy)
    move(to: target)
    Thread.sleep(forTimeInterval: 0.25)
    let after = CGEvent(source: nil)?.location ?? .zero
    let followed = abs(after.x - target.x) < 2 && abs(after.y - target.y) < 2
    let report: [String: Any] = ["beforeX": before.x, "beforeY": before.y,
                                 "targetX": target.x, "targetY": target.y,
                                 "afterX": after.x, "afterY": after.y, "followed": followed]
    if let data = try? JSONSerialization.data(withJSONObject: report) {
        FileHandle.standardOutput.write(data)
    }

case "displays":
    // What CoreGraphics really sees in this guest's own window session. The
    // desk scales pointer motion by a screen's physical size divided by these
    // point bounds, so empty bounds here would make that scale meaningless.
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    var listed: [[String: Any]] = []
    for identifier in ids.prefix(Int(count)) {
        let bounds = CGDisplayBounds(identifier)
        let millimetres = CGDisplayScreenSize(identifier)
        listed.append(["id": Int(identifier), "main": CGDisplayIsMain(identifier) != 0,
                       "x": bounds.origin.x, "y": bounds.origin.y,
                       "pointWidth": bounds.width, "pointHeight": bounds.height,
                       "mmWidth": millimetres.width, "mmHeight": millimetres.height])
    }
    let report: [String: Any] = ["mainDisplayID": Int(CGMainDisplayID()), "displays": listed]
    if let data = try? JSONSerialization.data(withJSONObject: report) {
        FileHandle.standardOutput.write(data)
    }

default:
    fail("unknown mode")
}
