import CoreGraphics
import Foundation

// A stand-in for Perch's monitor adapter, for lab guests only.
//
// It fakes ONLY the monitor edge: the DDC read and write that a virtual
// display cannot answer. Every other line of Perch runs untouched, including
// the desk link, the input session and the real event taps. Installing this
// makes input sharing reachable in a VM; it proves nothing about monitors.
//
// The contract mirrors Sources/Native/PerchDisplay.m:
//   list                        -> [MonitorDescriptor]
//   inspect <id> <mode>         -> MonitorInspection
//   read <id> <mode>            -> MonitorInspection
//   switch <id> <mode> <input>  -> {"sent": true}
// Anything else prints {"error": ...} and exits non-zero, as the real one does.

let statePath = ProcessInfo.processInfo.environment["PERCH_LAB_DISPLAY_STATE"] ?? "/tmp/desk-lab-display.json"
let logPath = ProcessInfo.processInfo.environment["PERCH_LAB_DISPLAY_LOG"] ?? "/tmp/desk-lab-display.log"

func record(_ arguments: [String]) {
    // Every call Perch makes, so a run can say whether a preset was activated
    // and whether a switch was ever issued, rather than inferring it.
    let line = ISO8601DateFormatter().string(from: Date()) + " " + arguments.joined(separator: " ") + "\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile(); handle.write(data); try? handle.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
}

func emit(_ object: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
}

func failure(_ text: String) -> Never {
    emit(["error": text])
    exit(1)
}

struct State {
    var id: String
    var current: UInt16
}

func loadState() -> State {
    // The desk validates a screen's control identity as a UUID, so the
    // identifier this reports has to be one.
    let fallback = State(id: "E7A5D100-0000-4000-8000-000000000001", current: 17)
    guard let data = FileManager.default.contents(atPath: statePath),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }
    let id = object["id"] as? String ?? fallback.id
    let current = (object["current"] as? NSNumber)?.uint16Value ?? fallback.current
    return State(id: id, current: current)
}

func saveState(_ state: State) {
    let object: [String: Any] = ["id": state.id, "current": Int(state.current)]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    try? data.write(to: URL(fileURLWithPath: statePath))
}

let arguments = CommandLine.arguments
record(Array(arguments.dropFirst()))
guard arguments.count >= 2 else { failure("Invalid display command.") }
let command = arguments[1]
let state = loadState()

// The real adapter answers this; returning nothing keeps callers happy.
if command == "usb-list", arguments.count == 2 {
    emit([])
    exit(0)
}

let isList = command == "list", isInspect = command == "inspect"
let isRead = command == "read", isSwitch = command == "switch"
guard isList || isInspect || isRead || isSwitch,
      !(isList && arguments.count != 2),
      !((isInspect || isRead) && arguments.count != 4),
      !(isSwitch && arguments.count != 5) else { failure("Invalid display command.") }

if isList {
    // displayID must be this guest's real display: the app reads its bounds,
    // physical size and modes straight from CoreGraphics with it.
    let main = CGMainDisplayID()
    emit([[
        "id": state.id,
        "displayID": Int(main),
        "name": "Lab Screen",
        "vendor": 0x1E2D,
        "model": 0x4C41,
        "ddcAvailable": true,
        "connection": "Lab",
    ]])
    exit(0)
}

let identifier = arguments[2]
let mode = arguments[3]
guard mode == "standard" || mode == "lg" else { failure("Unsupported monitor mode.") }
guard identifier == state.id else { failure("That display is not connected.") }

if isSwitch {
    guard let value = Int(arguments[4]), value >= 1, value <= 65535 else { failure("Input code must be between 1 and 65535.") }
    // Perch's reconciliation compares a later read against what it wrote, so
    // the switch has to stick.
    saveState(State(id: state.id, current: UInt16(value)))
    emit(["sent": true])
    exit(0)
}

var inspection: [String: Any] = ["current": Int(state.current)]
if isInspect {
    inspection["capabilities"] = "(prot(monitor)type(lcd)cmds(01 02 03 07 0C E3 F3)vcp(60(0F 11 12)))"
}
emit(inspection)
exit(0)
