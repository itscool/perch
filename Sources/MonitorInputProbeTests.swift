import Foundation

private final class ProbeFixtureBackend: MonitorCommandBackend {
    let target = MonitorDescriptor(id: "11111111-1111-1111-1111-111111111111", displayID: 9, name: "Selected display", vendor: 1, model: 1, ddcAvailable: true)
    let other = MonitorDescriptor(id: "22222222-2222-2222-2222-222222222222", displayID: 10, name: "Other display", vendor: 1, model: 1, ddcAvailable: true)
    var current = 15
    var alwaysConnected = false
    var commands: [[String]] = []
    func run(_ arguments: [String]) throws -> Data {
        commands.append(arguments)
        switch arguments.first {
        case "list": return try JSONEncoder().encode(current == 15 || alwaysConnected ? [target, other] : [other])
        case "read": return Data("{\"current\":\(current)}".utf8)
        case "switch":
            guard arguments[1] == target.id else { throw AppError(message: "Touched another display") }
            current = Int(arguments[3])!; return Data("{\"sent\":true}".utf8)
        default: throw AppError(message: "Unexpected probe command")
        }
    }
}

func runMonitorInputProbeTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let inputs = [MonitorInput(code: 17, name: "HDMI"), MonitorInput(code: 15, name: "USB-C")]
    let backend = ProbeFixtureBackend()
    let result = MonitorInputProbe.run(display: backend.target.id, mode: "standard", inputs: inputs, returnInput: 15, reliableReadback: true,
        backend: backend, cancellation: MonitorProbeCancellation(), wait: { _ in })
    try check(result.suggested?.code == 15 && result.showing?.code == 15 && backend.current == 15, "Unique reconnect did not suggest/return to the candidate")
    try check(result.lines.contains { $0.contains("visual confirmation is still needed") }, "Reconnect was presented as proof of the Mac's input")
    try check(backend.commands.filter { $0.first == "switch" }.allSatisfy { $0[1] == backend.target.id && ["15", "17"].contains($0[3]) }, "Probe escaped selected display/known input scope")
    backend.alwaysConnected = true
    let ambiguous = MonitorInputProbe.run(display: backend.target.id, mode: "standard", inputs: inputs, returnInput: 15, reliableReadback: true,
        backend: backend, cancellation: MonitorProbeCancellation(), wait: { _ in })
    try check(ambiguous.suggested == nil && ambiguous.lines.contains { $0.contains("No unique input") }, "Constant connection plus matching readback fabricated a Mac mapping")
    let cancellation = MonitorProbeCancellation(); backend.commands = []
    let cancelled = MonitorInputProbe.run(display: backend.target.id, mode: "standard", inputs: inputs, returnInput: 15, reliableReadback: false,
        backend: backend, cancellation: cancellation, wait: { _ in cancellation.cancel() })
    try check(cancelled.cancelled && backend.commands.filter { $0.first == "switch" }.map { $0[3] } == ["17", "15"], "Cancellation continued testing or failed to attempt return")
    backend.commands = []
    _ = MonitorInputProbe.run(display: backend.target.id, mode: "standard", inputs: inputs + inputs, returnInput: nil, reliableReadback: false,
        backend: backend, cancellation: MonitorProbeCancellation(), wait: { _ in })
    try check(backend.commands.isEmpty, "Invalid input list sent commands")
    print("PASS: selected-monitor input experiment; unique reconnect as a suggestion, ambiguous persistent connection, fresh readback distinction, bounded known inputs, cancellation and return; simulated hardware only")
}
