import AppKit
import Carbon

struct MonitorDescriptor: Codable, Equatable {
    let id: String
    let displayID: UInt32
    let name: String
    let vendor: UInt32
    let model: UInt32
    let ddcAvailable: Bool
    var connection: String? = nil
}
struct MonitorInput: Codable, Equatable {
    var code: UInt16
    var name: String
    var valid: Bool { code > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 80 }
    static func name(_ code: UInt16, alternate: Bool = false) -> String {
        let names: [UInt16:String] = alternate ? [:] : [1:"VGA 1",2:"VGA 2",3:"DVI 1",4:"DVI 2",15:"DisplayPort 1",16:"DisplayPort 2",17:"HDMI 1",18:"HDMI 2"]
        return names[code] ?? "Input \(code)"
    }
}
/// Strict, bounded extraction from the VCP section. A port's presence in this
/// capability list does not mean that a second computer is connected to it.
enum MonitorCapabilities {
    static func model(_ text: String) -> String? {
        guard text.utf8.count <= 4096 else { return nil }
        if let start = text.range(of: "model(", options: .caseInsensitive),
           let end = text[start.upperBound...].firstIndex(of: ")") {
            let value = text[start.upperBound..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 80, !value.contains("("),
                  !value.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
            return value
        }
        // Some LGs put a bare model token between type(lcd) and cmds(...).
        // Parse only that bounded slot, never search arbitrary capability values.
        guard let start = text.range(of: "type(lcd)", options: .caseInsensitive),
              let end = text.range(of: "cmds(", options: .caseInsensitive, range: start.upperBound..<text.endIndex) else { return nil }
        let value = text[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 80, value.contains(where: \.isNumber),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_. ".unicodeScalars.contains($0) }) else { return nil }
        return value
    }
    static func modelSeries(_ value: String) -> String? {
        let upper = value.uppercased()
        guard let range = upper.range(of: "[A-Z]{1,3}[0-9]{3,4}", options: .regularExpression) else { return nil }
        return String(upper[range])
    }

    /// Discovery only adds unselected ports. Existing names, codes and order win.
    static func merge(_ existing: [MonitorInput], reported: [MonitorInput]) -> [MonitorInput] {
        let known = Set(existing.map { $0.code })
        return Array((existing + reported.filter { !known.contains($0.code) }).prefix(16))
    }

    static func inputs(_ text: String) -> [UInt16] {
        guard text.utf8.count <= 4096 else { return [] }
        let bytes = Array(text.lowercased().utf8)
        var i = 0
        func skip() { while i < bytes.count && (bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13) { i += 1 } }
        while i+4 <= bytes.count {
            if Array(bytes[i..<i+4]) == [118,99,112,40] { i += 4; break }; i += 1
        }
        var depth = 1
        while i < bytes.count && depth > 0 {
            skip(); guard i < bytes.count else { return [] }
            if bytes[i] == 41 { depth -= 1; i += 1; continue }
            if bytes[i] == 40 { depth += 1; i += 1; continue }
            let start = i
            while i < bytes.count && bytes[i] != 32 && bytes[i] != 40 && bytes[i] != 41 { i += 1 }
            let token = String(bytes: bytes[start..<i], encoding: .ascii) ?? ""
            skip()
            guard depth == 1 && token == "60" && i < bytes.count && bytes[i] == 40 else { continue }
            i += 1; var values: [UInt16] = []
            while i < bytes.count {
                skip(); guard i < bytes.count else { return [] }
                if bytes[i] == 41 { return values.count <= 32 ? Array(Set(values)).sorted() : [] }
                let start = i
                while i < bytes.count && bytes[i] != 32 && bytes[i] != 41 { i += 1 }
                guard let token = String(bytes: bytes[start..<i], encoding: .ascii), token.count <= 4, let value = UInt16(token, radix: 16) else { return [] }
                if value == 0 { continue } // Reserved/unspecified placeholder, not a selectable input.
                values.append(value); if values.count > 32 { return [] }
            }
            return []
        }
        return []
    }
}
struct MonitorInspection: Decodable {
    let current: UInt16?
    let capabilities: String?
    var transportInputs: [MonitorInput]? = nil
    var transportModel: String? = nil
    var lgIdentity: UInt16? = nil
    var lgExtendedIdentity: UInt16? = nil
    var lgFirmwareModel: String? {
        LGFirmwareProfiles.family(identity: lgIdentity, extended: lgExtendedIdentity)?.name
    }
}

protocol MonitorCommandBackend { func run(_ arguments: [String]) throws -> Data }

/// A cheap WindowServer snapshot, including mirrored displays. This does not
/// open a monitor transport, read its input, or launch the display adapter.
enum MonitorDisplayTopology {
    static func read() -> [String]? {
        guard let displays = DisplayIdentity.list() else { return nil }
        var result: [String] = []
        for display in displays {
            guard let uuid = display.uuid else { return nil }
            result.append("\(display.id):\(uuid)")
        }
        return result.sorted()
    }
}

final class MonitorDisplayBackend: MonitorCommandBackend {
    static let mainThreadRefusal = "Monitor commands never run on the main thread; they can take up to nine seconds."
    // Called on the controller's serial worker queue, never on a UI/input thread.
    func run(_ arguments: [String]) throws -> Data {
        // A slow monitor would freeze menus, timers and input for up to nine
        // seconds. Refuse at once so a misplaced call is found, not felt.
        guard !Thread.isMainThread else { throw AppError(message: Self.mainThreadRefusal) }
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PerchDisplay"), FileManager.default.isExecutableFile(atPath: url.path) else { throw AppError(message: "Perch’s monitor adapter is missing. Reinstall Perch.") }
        let output: Subprocess.Output
        do { output = try Subprocess.run(url.path, arguments, timeout: 9, capture: .collect(maximumBytes: 32768)) }
        catch is Subprocess.Timeout { throw AppError(message: "The monitor took too long to respond. No switch was confirmed. Check that it is awake and DDC/CI is enabled in its menu.") }
        catch is Subprocess.Oversized { throw AppError(message: "The monitor adapter returned an oversized response.") }
        if let object = try? JSONSerialization.jsonObject(with: output.data) as? [String:Any], let error = object["error"] as? String { throw AppError(message: error) }
        guard output.succeeded else { throw AppError(message: "The monitor did not respond before the request expired. Check the cable, wake the monitor, and enable DDC/CI in its menu.") }
        return output.data
    }
}
