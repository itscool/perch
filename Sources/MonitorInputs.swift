import AppKit
import Carbon

struct MonitorDescriptor: Codable, Equatable {
    let id: String
    let displayID: UInt32
    let name: String
    let vendor: UInt32
    let model: UInt32
    let ddcAvailable: Bool
}
struct MonitorInput: Codable, Equatable {
    var code: UInt16
    var name: String
    var valid: Bool { code > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 80 }
    static func name(_ code: UInt16, alternate: Bool = false) -> String {
        let names: [UInt16:String] = alternate ? [144:"HDMI 1",145:"HDMI 2",208:"DisplayPort 1",209:"DisplayPort 2",210:"USB-C / DisplayPort 3"] : [1:"VGA 1",2:"VGA 2",3:"DVI 1",4:"DVI 2",15:"DisplayPort 1",16:"DisplayPort 2",17:"HDMI 1",18:"HDMI 2",27:"USB-C"]
        return names[code] ?? "Input \(code)"
    }
}
struct MonitorInputPlan: Codable, Equatable {
    var display = ""
    var alternate = false
    var inputs: [MonitorInput] = []
    var allowUnconfirmedCycle = false
    var shortcut = PanicShortcut(key: UInt32(kVK_F8), modifiers: UInt32(controlKey | optionKey), enabled: false)
    var valid: Bool {
        (display.isEmpty || UUID(uuidString: display) != nil) && inputs.count <= 16 && inputs.allSatisfy { $0.valid } &&
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
struct MonitorInspection: Decodable { let current: UInt16?; let capabilities: String? }

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
    var connected: MonitorDescriptor? { displays.first { $0.id == plan.display } }
    var canCycle: Bool { !busy && plan.valid && plan.inputs.count >= 2 && connected?.ddcAvailable == true }
    var shortcutActive: Bool { hotKey.active }
    init(displays: [MonitorDescriptor] = [], backend: MonitorCommandBackend = MonitorDisplayBackend()) { self.displays = displays; self.backend = backend; super.init() }
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
                self.warning = self.plan.shortcut.enabled && (!self.hotKey.active || self.connected == nil)
                self.message = displays.isEmpty ? "No external monitor connected." : self.warning ? "The configured monitor or shortcut is unavailable." : "✓ \(displays.count) external monitor\(displays.count == 1 ? "" : "s") detected"
            case .failure(let error): self.message = error.localizedDescription; self.warning = true
            }
        }
    }
    func inspect(_ id: String, alternate: Bool, completion: @escaping (Result<MonitorInspection,Error>) -> Void) {
        guard !busy else { return }
        perform({ [backend] in try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["inspect",id,alternate ? "lg" : "standard"])) }, completion: completion)
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
        if value.display != plan.display || value.alternate != plan.alternate || value.inputs != plan.inputs { lastSent = nil }
        plan = value; message = "✓ Monitor input settings saved"; warning = false; changed()
    }
    func cycle() {
        guard canCycle else {
            message = busy ? "A monitor request is already in progress." : "Open Monitor input settings to choose a connected display and at least two inputs."
            warning = true; changed(); return
        }
        let plan = self.plan, last = self.lastSent
        perform({ [backend] () -> MonitorInput in
            let data = try backend.run(["read",plan.display,plan.alternate ? "lg" : "standard"])
            let state = try JSONDecoder().decode(MonitorInspection.self, from: data)
            let next = try plan.next(current: state.current, lastSent: last)
            let result = try backend.run(["switch",plan.display,plan.alternate ? "lg" : "standard",String(next.code)])
            guard let object = try JSONSerialization.jsonObject(with: result) as? [String:Any], object["sent"] as? Bool == true else { throw AppError(message: "The input command was not accepted.") }
            return next
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let input): self.lastSent = input.code; self.message = "Command sent: \(input.name) · monitor confirmation unavailable. If nothing changed, check the exact model’s input codes in Edit inputs."; self.warning = true
            case .failure(let error): self.message = error.localizedDescription; self.warning = true
            }
        }
    }
    deinit { pending?.cancel(); NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self) }
}
