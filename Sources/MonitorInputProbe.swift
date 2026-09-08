import Foundation

final class MonitorProbeCancellation {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

struct MonitorProbeResult {
    var lines: [String] = []
    var suggested: MonitorInput?
    var showing: MonitorInput?
    var cancelled = false
}

/// Explicit experiment over known ports of one stable display identity. A macOS
/// display connection and monitor input readback are independent observations:
/// neither a constant display count nor a write acknowledgment identifies a Mac.
enum MonitorInputProbe {
    static func run(display: String, mode: String, inputs: [MonitorInput], returnInput: UInt16?, reliableReadback: Bool,
                    backend: MonitorCommandBackend, cancellation: MonitorProbeCancellation,
                    wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                    progress: (String) -> Void = { _ in }) -> MonitorProbeResult {
        var result = MonitorProbeResult()
        func note(_ line: String) { result.lines.append(line); progress(result.lines.joined(separator: "\n")) }
        guard !inputs.isEmpty, inputs.count <= 16, inputs.allSatisfy(\.valid), Set(inputs.map(\.code)).count == inputs.count else {
            note("Choose a known input list before testing."); return result
        }
        func connected() -> Bool? {
            guard let data = try? backend.run(["list"]), let list = try? JSONDecoder().decode([MonitorDescriptor].self, from: data) else { return nil }
            return list.contains { $0.id == display }
        }
        func readInput() -> UInt16? {
            guard reliableReadback, let data = try? backend.run(["read", display, mode]), let value = try? JSONDecoder().decode(MonitorInspection.self, from: data).current, value > 0 else { return nil }
            return value
        }
        func send(_ code: UInt16) throws {
            let data = try backend.run(["switch", display, mode, String(code)])
            guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["sent"] as? Bool == true else { throw AppError(message: "Input command was not accepted.") }
        }
        let original = returnInput ?? readInput()
        var previous = connected(), candidates: [MonitorInput] = []
        note("Testing only the selected monitor. Other displays are excluded from the observations.")
        for (index, input) in inputs.enumerated() {
            if cancellation.cancelled { break }
            note("\(index+1)/\(inputs.count): selecting \(input.name)…")
            do { try send(input.code) }
            catch { note("\(input.name): command failed — \(error.localizedDescription)"); continue }
            var observations: [Bool?] = [], seconds: TimeInterval = 0
            while seconds < 4 && !cancellation.cancelled {
                wait(0.5); seconds += 0.5; observations.append(connected())
            }
            if cancellation.cancelled { break }
            let stablePresent = observations.suffix(2).count == 2 && observations.suffix(2).allSatisfy { $0 == true }
            let stableAbsent = observations.suffix(2).count == 2 && observations.suffix(2).allSatisfy { $0 == false }
            if stablePresent && (previous == false || observations.contains { $0 == false }) {
                candidates.append(input)
                note("\(input.name): this display reappeared in macOS. Possible input for this Mac; visual confirmation is still needed.")
            } else { note("\(input.name): \(stablePresent ? "display stayed connected to macOS; this does not identify its active video source" : stableAbsent ? "display is absent from macOS" : "display detection was unstable or unavailable").") }
            if let reported = readInput() { note("Monitor input readback: \(reported == input.code ? input.name : "code \(reported)"). This confirms the selected port, not which computer owns it.") }
            previous = stablePresent ? true : stableAbsent ? false : nil
        }
        result.cancelled = cancellation.cancelled
        result.suggested = !result.cancelled && candidates.count == 1 ? candidates[0] : nil
        let restore = result.suggested?.code ?? original
        if let restore {
            do {
                try send(restore)
                result.showing = inputs.first { $0.code == restore }
                note("\(result.cancelled ? "Stopped. " : "")Requested \(result.showing?.name ?? "the original input") to finish. Check the monitor before confirming.")
            } catch { note("Could not return the monitor to its finishing input. Use the monitor’s Input button to restore this Mac. \(error.localizedDescription)") }
        } else { note("The original input was unknown. Use the monitor’s Input button to restore this Mac if needed.") }
        if result.suggested == nil && !result.cancelled { note("No unique input identified. A connection that stays present cannot distinguish ports; test a selected input and confirm its picture below.") }
        return result
    }
}

extension MonitorInputController {
    func probeInputs(_ inputs: [MonitorInput], display: String, mode: String, returnInput: UInt16?,
                     cancellation: MonitorProbeCancellation, progress: @escaping (String) -> Void,
                     completion: @escaping (MonitorProbeResult) -> Void) {
        guard !busy else { return }
        let reliable = !readbackUnavailable
        perform({ [backend] in MonitorInputProbe.run(display: display, mode: mode, inputs: inputs, returnInput: returnInput,
            reliableReadback: reliable, backend: backend, cancellation: cancellation,
            progress: { value in DispatchQueue.main.async { progress(value) } }) }) { result in
                switch result { case .success(let value): completion(value)
                case .failure(let error): completion(MonitorProbeResult(lines: [error.localizedDescription])) }
            }
    }
}
