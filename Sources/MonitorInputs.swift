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
struct MonitorInputPlan: Codable, Equatable {
    var display = ""
    var alternate = false
    var profileName: String? = nil
    var controlConnection: MonitorConnection? = nil
    var commandMode: String { controlConnection?.argument ?? (alternate ? "lg" : "standard") }
    var inputs: [MonitorInput] = []
    var allowUnconfirmedCycle = false
    var shortcut = PanicShortcut(key: UInt32(kVK_F8), modifiers: UInt32(controlKey | optionKey), enabled: false)
    var valid: Bool {
        (controlConnection?.valid ?? true) && (display.isEmpty || UUID(uuidString: display) != nil) && inputs.count <= 16 && inputs.allSatisfy { $0.valid } &&
        Set(inputs.map { $0.code }).count == inputs.count &&
        (!shortcut.enabled || (!display.isEmpty && inputs.count >= 2 && shortcut.modifiers.nonzeroBitCount >= 2 && PanicShortcut.keys.contains { $0.1 == shortcut.key }))
    }
    func next(current: UInt16?, lastSent: UInt16?) throws -> MonitorInput {
        guard inputs.count >= 2 else { throw AppError(message: "Choose at least two inputs in Monitor input settings.") }
        let current = current == 0 ? nil : current
        let position = current ?? (allowUnconfirmedCycle ? lastSent : nil)
        guard current != nil || allowUnconfirmedCycle else { throw AppError(message: "The monitor did not report its current input. In Monitor input settings, you can explicitly allow cycling from the last command sent.") }
        if let position, let index = inputs.firstIndex(where: { $0.code == position }) { return inputs[(index+1)%inputs.count] }
        return inputs[0]
    }
}

/// Strict, bounded extraction from the VCP section. A port's presence in this
/// capability list does not mean that a second computer is connected to it.
enum MonitorCapabilities {
    static func model(_ text: String) -> String? {
        guard text.utf8.count <= 4096,
              let start = text.range(of: "model(", options: .caseInsensitive),
              let end = text[start.upperBound...].firstIndex(of: ")") else { return nil }
        let value = text[start.upperBound..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 80, !value.contains("("),
              !value.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        return value
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
                guard let token = String(bytes: bytes[start..<i], encoding: .ascii), token.count <= 4, let value = UInt16(token, radix: 16), value > 0 else { return [] }
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

final class MonitorDisplayBackend: MonitorCommandBackend {
    private var process: Process?
    // Called on the controller's serial worker queue, never on a UI/input thread.
    func run(_ arguments: [String]) throws -> Data {
        guard process?.isRunning != true else { throw AppError(message: "The previous monitor request is still finishing. Wait before retrying.") }
        let p = Process(), pipe = Pipe(), ended = DispatchSemaphore(value: 0)
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PerchDisplay"), FileManager.default.isExecutableFile(atPath: url.path) else { throw AppError(message: "Perch’s monitor adapter is missing. Reinstall Perch.") }
        p.executableURL = url; p.arguments = arguments; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in ended.signal() }
        try p.run(); process = p
        // Child emits at most 16 descriptors / 4096 capability bytes. This is
        // below pipe capacity, so waiting here cannot deadlock on a full pipe.
        guard ended.wait(timeout: .now()+9) == .success else {
            if p.isRunning { p.terminate() }
            throw AppError(message: "The monitor took too long to respond. No switch was confirmed. Check that it is awake and DDC/CI is enabled in its menu.")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 32768 else { throw AppError(message: "The monitor adapter returned an oversized response.") }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let error = object["error"] as? String { throw AppError(message: error) }
        guard p.terminationStatus == 0 else { throw AppError(message: "The monitor did not respond before the request expired. Check the cable, wake the monitor, and enable DDC/CI in its menu.") }
        return data
    }
}

final class MonitorInputController: NSObject {
    static let preferenceKey = "monitor.inputCycle.v1"
    var plan = MonitorInputPlan()
    private(set) var displays: [MonitorDescriptor] = []
    private(set) var busy = false
    var message = "Detecting monitors…"
    var warning = false
    var onChange: (() -> Void)?
    var pageChanged: (() -> Void)?
    private let worker = DispatchQueue(label: "local.scott.perch.monitor-input", qos: .utility)
    private let backend: MonitorCommandBackend
    private let hotKey = PanicHotKey(signature: 0x504d4f4e)
    private var pending: DispatchWorkItem?
    private var lastSent: UInt16?
    private var refreshPending = false
    private let confirmationDefaults: UserDefaults
    private(set) var pendingConfirmation: UInt16?
    private var pendingConnection: String?
    private var pendingPlan: MonitorInputPlan?
    static let connectionAdvice = "If nothing changed, try a direct connection without a dock or USB-C/HDMI adapter. Some adapters pass video but block monitor commands. Also check DDC/CI and the selected input profile."
    private func confirmationKey(_ plan: MonitorInputPlan, _ connection: String) -> String {
        "monitor.confirmed.v1." + plan.display + "." + connection + "." + plan.commandMode + "." + plan.inputs.map { String($0.code) }.joined(separator: "-")
    }
    func confirmSwitch(_ worked: Bool) {
        guard !busy, let code = pendingConfirmation, let tested = pendingPlan else { return }
        if worked {
            if let route = pendingConnection, (plan.controlConnection?.argument ?? connected?.connection) == route {
                let key = confirmationKey(tested, route)
                var codes = confirmationDefaults.array(forKey: key) as? [Int] ?? []
                if !codes.contains(Int(code)) { codes.append(Int(code)); confirmationDefaults.set(codes, forKey: key) }
            }
            message = "✓ \(tested.inputs.first { $0.code == code }?.name ?? "Input") confirmed by you. Other inputs still need their own confirmation."; warning = false
        } else {
            if let route = pendingConnection { confirmationDefaults.removeObject(forKey: confirmationKey(tested, route)) }
            message = "⚠ Switch did not work. " + Self.connectionAdvice; warning = true
        }
        pendingConfirmation = nil; pendingPlan = nil; pendingConnection = nil; changed()
    }
    var connected: MonitorDescriptor? { displays.first { $0.id == plan.display } }
    var canCycle: Bool { !busy && plan.valid && !plan.display.isEmpty && plan.inputs.count >= 2 && (plan.controlConnection != nil || connected?.ddcAvailable == true) }
    var shortcutActive: Bool { hotKey.active }
    init(displays: [MonitorDescriptor] = [], backend: MonitorCommandBackend = MonitorDisplayBackend(), defaults: UserDefaults = .standard) { self.displays = displays; self.backend = backend; self.confirmationDefaults = defaults; super.init() }
    func start() {
        if let data = UserDefaults.standard.data(forKey: Self.preferenceKey), data.count <= 32768,
           let value = try? JSONDecoder().decode(MonitorInputPlan.self, from: data), value.valid { plan = value }
        hotKey.action = { [weak self] in self?.cycle() }
        do { try hotKey.register(plan.shortcut) } catch { message = error.localizedDescription; warning = true }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
    }
    private func changed() { onChange?(); pageChanged?() }
    @objc private func screensChanged() {
        pending?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = job; DispatchQueue.main.asyncAfter(deadline: .now()+0.5, execute: job)
    }
    func refresh() {
        guard !busy else { refreshPending = true; return }
        perform({ [backend] in try JSONDecoder().decode([MonitorDescriptor].self, from: backend.run(["list"])) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let displays):
                self.displays = displays
                if self.warning && self.connected != nil { return } // Preserve the last actionable result during metadata refresh.
                self.warning = self.plan.shortcut.enabled && (!self.hotKey.active || (self.connected == nil && self.plan.controlConnection == nil))
                self.message = displays.isEmpty ? (self.plan.controlConnection == nil ? "No external monitor connected." : "Video input inactive · saved control connection retained") : self.warning ? "The configured monitor or shortcut is unavailable." : "\(displays.count) external monitor\(displays.count == 1 ? "" : "s") detected · control not yet checked"
            case .failure(let error): self.message = error.localizedDescription; self.warning = true
            }
        }
    }
    func inspect(_ id: String, alternate: Bool, connection: MonitorConnection? = nil, completion: @escaping (Result<MonitorInspection,Error>) -> Void) {
        guard !busy else { return }
        perform({ [backend] in try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["inspect",id,connection?.argument ?? (alternate ? "lg" : "standard")])) }, completion: completion)
    }
    func usbDevices(completion: @escaping (Result<[MonitorUSBDevice],Error>) -> Void) {
        guard !busy else { return }
        perform({ [backend] in try JSONDecoder().decode([MonitorUSBDevice].self, from: backend.run(["usb-list"])) }, completion:completion)
    }
    private func perform<T>(_ job: @escaping () throws -> T, completion: @escaping (Result<T,Error>) -> Void) {
        busy = true; changed()
        worker.async {
            let result = Result { try job() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false; completion(result); self.changed()
                if self.refreshPending { self.refreshPending = false; self.refresh() }
            }
        }
    }
    func save(_ value: MonitorInputPlan) throws {
        guard value.valid else { throw AppError(message: "Choose unique input codes, a monitor, and at least two inputs and two modifiers for an enabled shortcut.") }
        let panic = SafetyConfiguration.load().shortcut
        guard !value.shortcut.enabled || !panic.enabled || value.shortcut.key != panic.key || value.shortcut.modifiers != panic.modifiers else { throw AppError(message: "Choose a different shortcut from Immediate Kill.") }
        do { try hotKey.register(value.shortcut) }
        catch { try? hotKey.register(plan.shortcut); throw error }
        let data = try JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: Self.preferenceKey)
        if value.controlConnection != plan.controlConnection || value.display != plan.display || value.alternate != plan.alternate || value.inputs != plan.inputs { lastSent = nil; pendingConfirmation = nil; pendingPlan = nil; pendingConnection = nil }
        plan = value; message = "✓ Monitor input settings saved"; warning = false; changed()
    }
    func testInput(_ input: MonitorInput, display: String, alternate: Bool,
                   completion: @escaping (Bool) -> Void) {
        guard !busy, input.valid, let monitor = displays.first(where: { $0.id == display }), monitor.ddcAvailable,
              !alternate || monitor.vendor == 0x1e6d else { completion(false); return }
        // Explicit, single candidate test; no preference or cycle-position mutation.
        perform({ [backend] () -> Bool in
            let data = try backend.run(["switch", display, alternate ? "lg" : "standard", String(input.code)])
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String:Any], value["sent"] as? Bool == true else {
                throw AppError(message: "The input command was not accepted.")
            }
            return true
        }) { [weak self] result in
            switch result {
            case .success: completion(true)
            case .failure(let error): self?.message = error.localizedDescription; self?.warning = true; completion(false)
            }
        }
    }
    func cycle() {
        guard canCycle else {
            message = busy ? "A monitor request is already in progress." : "Open Monitor input settings to choose a connected display and at least two inputs."
            warning = true; changed(); return
        }
        let plan = self.plan, last = self.lastSent, route = plan.controlConnection?.argument ?? connected?.connection
        let writeOnly = plan.controlConnection == nil && connected.flatMap { display in
            MonitorProfiles.entries.first { $0.name == plan.profileName && $0.vendor == display.vendor } ?? MonitorProfiles.match(display)
        }?.readbackUnavailable == true
        pendingConfirmation = nil; pendingPlan = nil
        perform({ [backend] () -> (MonitorInput, UInt16?) in
            let state: MonitorInspection
            if writeOnly { state = MonitorInspection(current:nil, capabilities:nil) }
            else { state = try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["read",plan.display,plan.commandMode])) }
            let next = try plan.next(current: state.current, lastSent: last)
            let result = try backend.run(["switch",plan.display,plan.commandMode,String(next.code)])
            guard let object = try JSONSerialization.jsonObject(with: result) as? [String:Any], object["sent"] as? Bool == true else { throw AppError(message: "The input command was not accepted.") }
            // A transport acknowledgment is not monitor confirmation. Read back only
            // after explicit user action; failures here leave the result unconfirmed.
            Thread.sleep(forTimeInterval: 0.2)
            let reply = writeOnly ? nil : try? backend.run(["read",plan.display,plan.commandMode])
            let reported = reply.flatMap { try? JSONDecoder().decode(MonitorInspection.self, from: $0) }.flatMap { $0.current }
            return (next, reported)
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let (input, reported)):
                self.lastSent = input.code
                if reported == input.code {
                    self.message = "✓ Monitor reports \(input.name) active"; self.warning = false
                } else {
                    self.pendingConfirmation = input.code; self.pendingPlan = plan; self.pendingConnection = route
                    let previous = route.map { self.confirmationDefaults.array(forKey: self.confirmationKey(plan, $0)) as? [Int] ?? [] } ?? []
                    if let reported, reported > 0 {
                        self.message = "⚠ Monitor still reports input \(reported); the switch is not confirmed. " + Self.connectionAdvice
                        self.warning = true
                    } else if previous.contains(Int(input.code)) {
                        self.message = "Sent: \(input.name) · previously confirmed by you on this connection; current input unreadable."
                        self.warning = false
                    } else {
                        self.message = "Sent: \(input.name) · did the monitor switch? Confirm below. " + Self.connectionAdvice
                        self.warning = true
                    }
                }
            case .failure(let error): self.message = error.localizedDescription + " " + Self.connectionAdvice; self.warning = true
            }
        }
    }
    deinit { pending?.cancel(); NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self) }
}
