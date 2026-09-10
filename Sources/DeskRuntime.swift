import AppKit
import SwiftUI
import Combine
import Carbon

struct DeskDetectedDisplay: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let width: Double
    let height: Double
    let canControl: Bool
    var inputs: [MonitorInput]
    var mode: String
}
enum DeskDeviceMessage: Codable {
    case displays([DeskDetectedDisplay])
    case refresh
    case inspect(String)
    case identify(String, String)
}
final class DeskRuntime: ObservableObject {
    let node: KVMDeskNode
    let switching: KVMMonitorSwitch
    let model: DeskModel
    @Published var displays: [UUID: [DeskDetectedDisplay]] = [:]
    @Published var discoveryProblem: String?
    @Published var discovering = false
    @Published var usbDevices: [MonitorUSBDevice] = []
    @Published var shortcutProblem: String?
    private var subscriptions: Set<AnyCancellable> = []
    private var queues: [String: DispatchQueue] = [:]
    private var refreshTimer: Timer?
    private var hotKeys: [PanicHotKey] = []
    private var registeredShortcuts: [KVMShortcut] = []
    private var identifyWindows: [NSWindow] = []
    init(node: KVMDeskNode) {
        self.node = node; switching = KVMMonitorSwitch(node: node)
        model = DeskModel(store: node.storage.deletingLastPathComponent().appendingPathComponent("unused-preview.json"))
        model.group = node.group; model.selected = node.group.monitors.first?.id
        model.live = DeskLiveActions(edit: { [weak node] in try node?.edit($0) }, activate: { [weak self] in self?.switching.activate($0) }, readiness: { [weak self] in self?.switching.readiness($0) },
            mappingOptions: { [weak self] in self?.mappingOptions ?? [] }, map: { [weak self] in self?.map($0, choice: $1) },
            identify: { [weak self] in self?.identify($0) }, sheet: { [weak self] kind, selection, close in
                guard let self else { return AnyView(EmptyView()) }; return AnyView(DeskLiveSheet(runtime: self, kind: kind, selection: selection, close: close))
            })
        node.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        switching.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        switching.execute = { [weak self] route, valid, completion in self?.execute(route, valid: valid, completion: completion) }
        switching.readForVerification = { [weak self] monitor, completion in self?.read(monitor, completion: completion) }
        switching.otherMessage = { [weak self] peer, data in self?.receiveDevices(data, peer: peer) }
        node.peersChanged = { [weak self] in self?.publishDisplays(); self?.updateModel() }
        updateModel()
    }
    deinit { refreshTimer?.invalidate() }
    func stop() {
        refreshTimer?.invalidate(); refreshTimer = nil
        hotKeys.forEach { try? $0.register(PanicShortcut(enabled: false)) }; hotKeys = []
        node.stop()
    }
    func start() throws {
        try node.start()
        guard node.isMember else { return }
        refreshDisplays()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refreshDisplays() }
        timer.tolerance = 3; refreshTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func updateModel() {
        model.group = node.group; model.online = node.online
        model.conflict = node.conflicts.first ?? node.recoveredDraft
        model.problem = switching.problem ?? node.problem ?? discoveryProblem ?? shortcutProblem
        model.active = node.group.presets.first { $0.id == switching.activePreset }
        model.activeGroup = switching.activeGroup
        model.monitorResults = switching.results.mapValues { $0.state.rawValue.capitalized + ": " + $0.detail }
        if let selected = model.selected, !node.group.monitors.contains(where: { $0.id == selected }) { model.selected = node.group.monitors.first?.id }
        if model.selected == nil { model.selected = node.group.monitors.first?.id }
        registerShortcuts()
        objectWillChange.send()
    }
    var mappingOptions: [DeskMappingOption] {
        node.group.computers.flatMap { computer in
            var options = (displays[computer.id] ?? []).map { DeskMappingOption(id: computer.id.uuidString + "|" + $0.id, label: computer.name + " · " + $0.name) }
            for c in node.group.connections where c.computer == computer.id {
                if let id = c.localDisplay, !options.contains(where: { $0.id == computer.id.uuidString + "|" + id }) {
                    options.append(.init(id: computer.id.uuidString + "|" + id, label: computer.name + " · saved display (not detected)"))
                }
            }
            return options
        }
    }
    func map(_ connection: UUID, choice: String) {
        model.edit { group in
            guard let i = group.connections.firstIndex(where: { $0.id == connection }) else { return }
            if choice.isEmpty { group.connections[i].computer = nil; group.connections[i].localDisplay = nil; return }
            let parts = choice.split(separator: "|")
            guard parts.count == 2, let computer = UUID(uuidString: String(parts[0])), self.mappingOptions.contains(where: { $0.id == choice }) else { throw KVMError("Choose a detected display on a grouped computer.") }
            group.connections[i].computer = computer; group.connections[i].localDisplay = String(parts[1])
        }
    }
    private func queue(_ id: String) -> DispatchQueue {
        if let queue = queues[id] { return queue }
        let queue = DispatchQueue(label: "local.perch.desk.monitor." + id, qos: .userInitiated); queues[id] = queue; return queue
    }
    func refreshDisplays() {
        guard !discovering else { return }; discovering = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try JSONDecoder().decode([MonitorDescriptor].self, from: MonitorDisplayBackend().run(["list"])) }
            DispatchQueue.main.async {
                guard let self else { return }; self.discovering = false
                switch result {
                case .success(let values):
                    self.discoveryProblem = nil
                    self.displays[self.node.localID] = values.map { display in
                        let profile = MonitorProfiles.match(display)
                        let size = CGDisplayScreenSize(display.displayID)
                        return DeskDetectedDisplay(id: display.id, name: display.name, vendor: display.vendor, model: display.model,
                            serial: CGDisplaySerialNumber(display.displayID), width: max(1, size.width), height: max(1, size.height), canControl: display.ddcAvailable,
                            inputs: profile?.inputs ?? [15, 16, 17, 18].map { MonitorInput(code: $0, name: MonitorInput.name($0)) }, mode: profile?.alternate == true ? "lg" : "standard")
                    }
                    self.publishDisplays()
                case .failure(let error): self.discoveryProblem = "Could not refresh connected screens. " + error.localizedDescription
                }
                self.updateModel()
            }
        }
    }
    func inspect(_ display: String, computer: UUID) {
        if computer != node.localID {
            if let data = try? JSONEncoder().encode(DeskDeviceMessage.inspect(display)) { node.sendApplication(data, peer: computer) }
            return
        }
        guard let d = displays[computer]?.first(where: { $0.id == display }) else { return }
        queue(display).async { [weak self] in
            let result = try? JSONDecoder().decode(MonitorInspection.self, from: MonitorDisplayBackend().run(["inspect", display, d.mode]))
            DispatchQueue.main.async {
                guard let self, let result, let i = self.displays[computer]?.firstIndex(where: { $0.id == display }) else { return }
                let reported = result.transportInputs ?? MonitorCapabilities.inputs(result.capabilities ?? "").map { MonitorInput(code: $0, name: MonitorInput.name($0, alternate: d.mode == "lg")) }
                self.displays[computer]?[i].inputs = MonitorCapabilities.merge(d.inputs, reported: reported)
                self.publishDisplays()
            }
        }
    }
    func discoverUSB() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = (try? JSONDecoder().decode([MonitorUSBDevice].self, from: MonitorDisplayBackend().run(["usb-list"]))) ?? []
            DispatchQueue.main.async { self?.usbDevices = devices }
        }
    }
    private func publishDisplays() {
        guard let data = try? JSONEncoder().encode(DeskDeviceMessage.displays(displays[node.localID] ?? [])) else { return }
        for peer in node.online where peer != node.localID { node.sendApplication(data, peer: peer) }
    }
    func refreshAllDisplays() {
        refreshDisplays()
        if let data = try? JSONEncoder().encode(DeskDeviceMessage.refresh) { for peer in node.online where peer != node.localID { node.sendApplication(data, peer: peer) } }
    }
    private func receiveDevices(_ data: Data, peer: UUID) {
        guard data.count <= 64 * 1024, let message = try? JSONDecoder().decode(DeskDeviceMessage.self, from: data) else { return }
        switch message {
        case .displays(let values):
            guard values.count <= 16, Set(values.map(\.id)).count == values.count,
                  values.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.name.isEmpty && $0.name.utf8.count <= 100 && $0.inputs.count <= 16 && $0.inputs.allSatisfy(\.valid) && $0.width.isFinite && $0.height.isFinite && (1...10000).contains($0.width) && (1...10000).contains($0.height) && ["standard", "lg"].contains($0.mode) }) else { return }
            displays[peer] = values; updateModel()
        case .refresh: refreshDisplays()
        case .inspect(let display): inspect(display, computer: node.localID)
        case .identify(let display, let name): showIdentification(display, name: String(name.prefix(100)))
        }
    }
    func addScreen(name: String, existing: UUID?, computer: UUID, display: String, input: UInt16, profile: MonitorProfile? = nil, custom: MonitorInput? = nil) throws {
        guard var detected = displays[computer]?.first(where: { $0.id == display }) else { throw KVMError("Choose a detected screen.") }
        if let profile { detected.inputs = profile.inputs; detected.mode = profile.alternate ? "lg" : "standard" }
        if let custom, custom.valid { detected.inputs.removeAll { $0.code == custom.code }; detected.inputs.append(custom) }
        guard detected.inputs.contains(where: { $0.code == input }) else { throw KVMError("Choose this cable’s connected input.") }
        var group = node.group
        let monitor: UUID
        if let existing { monitor = existing }
        else {
            let screen = KVMMonitor(name: name, geometry: .init(x: group.monitors.map { $0.geometry.right }.max() ?? 0, y: 0, width: detected.width > 1 ? detected.width : 550, height: detected.height > 1 ? detected.height : 310), control: .init(computer: computer, localDisplay: display, mode: detected.mode))
            monitor = screen.id; group.monitors.append(screen)
        }
        for port in detected.inputs where !group.connections.contains(where: { $0.monitor == monitor && $0.inputCode == port.code }) {
            group.connections.append(.init(monitor: monitor, computer: nil, localDisplay: nil, inputName: port.name, inputCode: port.code))
        }
        guard let i = group.connections.firstIndex(where: { $0.monitor == monitor && $0.inputCode == input }) else { throw KVMError("This input is not configured.") }
        guard group.connections[i].computer == nil || group.connections[i].computer == computer && group.connections[i].localDisplay == display else { throw KVMError("That input is already mapped. Correct its existing mapping first.") }
        group.connections[i].computer = computer; group.connections[i].localDisplay = display
        try node.edit(group); model.selected = monitor; node.problem = nil
    }
    private func execute(_ route: KVMMonitorRoute, valid: @escaping () -> Bool, completion: @escaping (KVMMonitorOutcome.State, String) -> Void) {
        queue(route.control.localDisplay).async {
            let backend = MonitorDisplayBackend()
            let args = [route.control.localDisplay, route.control.mode]
            func allowed() -> Bool { DispatchQueue.main.sync { valid() } }
            func read() throws -> UInt16? { try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["read"] + args)).current }
            var state = KVMMonitorOutcome.State.failed, detail = "The switch was cancelled before its monitor command."
            do {
                guard allowed() else { throw KVMError(detail) }
                if (try? read()) == route.input { state = .confirmed; detail = "A fresh monitor read confirms this input." }
                else {
                    guard allowed() else { throw KVMError(detail) }
                    let data = try backend.run(["switch"] + args + [String(route.input)])
                    guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["sent"] as? Bool == true else { throw KVMError("The monitor did not accept the input command.") }
                    Thread.sleep(forTimeInterval: 0.2)
                    if allowed(), (try? read()) == route.input { state = .confirmed; detail = "Monitor reports the requested input." }
                    else { state = .unverified; detail = "Command sent. Checking the picture from another paired computer…" }
                }
            } catch { detail = error.localizedDescription }
            DispatchQueue.main.async { completion(state, detail) }
        }
    }
    private func read(_ monitor: UUID, completion: @escaping (UInt16?) -> Void) {
        guard let control = node.group.monitors.first(where: { $0.id == monitor })?.control else { completion(nil); return }
        let id: String, mode: String
        if control.computer == node.localID { id = control.localDisplay; mode = control.mode }
        else {
            guard let connection = node.group.connections.first(where: { $0.monitor == monitor && $0.computer == node.localID }),
                  let local = connection.localDisplay, let display = displays[node.localID]?.first(where: { $0.id == local }), display.mode == control.mode else { completion(nil); return }
            id = local; mode = display.mode
        }
        queue(id).async {
            let input = try? JSONDecoder().decode(MonitorInspection.self, from: MonitorDisplayBackend().run(["read", id, mode])).current
            DispatchQueue.main.async { completion(input ?? nil) }
        }
    }

    func identify(_ monitor: UUID?) {
        guard let monitor, let screen = node.group.monitors.first(where: { $0.id == monitor }) else { return }
        for c in node.group.connections where c.monitor == monitor {
            guard let peer = c.computer, let display = c.localDisplay else { continue }
            if peer == node.localID { showIdentification(display, name: screen.name) }
            else if let bytes = try? JSONEncoder().encode(DeskDeviceMessage.identify(display, screen.name)) { node.sendApplication(bytes, peer: peer) }
        }
    }
    private func showIdentification(_ display: String, name: String) {
        guard !SettingsWindow.shared.testing, let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == display
        }) else { return }
        let window = NSWindow(contentRect: NSRect(x: screen.frame.midX-160, y: screen.frame.midY-60, width: 320, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear; window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text(name).font(.largeTitle.bold()).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)))
        identifyWindows.append(window); window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak window] in window?.orderOut(nil); self?.identifyWindows.removeAll { $0 === window } }
    }
    private func registerShortcuts() {
        guard !SettingsWindow.shared.testing else { return }
        let shortcuts = node.group.presets.map(\.shortcut)
        guard registeredShortcuts != shortcuts else { return }
        hotKeys.forEach { try? $0.register(PanicShortcut(enabled: false)) }; hotKeys = []; registeredShortcuts = shortcuts
        do {
            for (i, shortcut) in shortcuts.enumerated() {
                let key = PanicShortcut.keys.first { $0.0 == shortcut.key }?.1
                guard let key else { throw KVMError("This Mac cannot register \(shortcut.label). Change the shortcut in Desk settings.") }
                let hotkey = PanicHotKey(signature: UInt32(0x50444B30 + i))
                var modifiers: UInt32 = 0
                if shortcut.control { modifiers |= UInt32(controlKey) }; if shortcut.option { modifiers |= UInt32(optionKey) }
                if shortcut.command { modifiers |= UInt32(cmdKey) }; if shortcut.shift { modifiers |= UInt32(shiftKey) }
                let chosen = PanicShortcut(key: key, modifiers: modifiers, enabled: true)
                let panic = SafetyConfiguration.load().shortcut
                guard !panic.enabled || panic.key != key || panic.modifiers != modifiers else { throw KVMError("\(shortcut.label) is already the Agent Kill Switch shortcut. Choose another Desk shortcut.") }
                try hotkey.register(chosen)
                hotkey.action = { [weak self] in guard let self else { return }; self.switching.activate(self.node.group.presets[i].id) }
                hotKeys.append(hotkey)
            }
            shortcutProblem = nil
        } catch { shortcutProblem = error.localizedDescription }
    }
}

final class DeskCoordinator: ObservableObject {
    static let shared = DeskCoordinator()
    static var storage: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Desk/desk.json") }
    @Published var runtime: DeskRuntime?
    @Published var problem: String?
    func startAfterRemoval() {
        guard let runtime else { return }
        do { try runtime.node.archiveRemovedDesk(); runtime.stop(); self.runtime = nil; enable() }
        catch { problem = error.localizedDescription }
    }
    func resumeIfConfigured() { if FileManager.default.fileExists(atPath: Self.storage.path) { enable() } }
    func enable() {
        guard runtime == nil, !SettingsWindow.shared.testing else { return }
        do {
            let identity = try KVMPeerIdentity.load()
            let node = try KVMDeskNode(identity: identity, name: Host.current().localizedName ?? "This Mac", storage: Self.storage)
            let runtime = DeskRuntime(node: node); try runtime.start(); self.runtime = runtime; problem = nil
        } catch { problem = error.localizedDescription }
    }
}
