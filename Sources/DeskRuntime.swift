import AppKit
import SwiftUI
import Combine
import Carbon
import IOKit.graphics

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
    var panelAspect: Double? = nil
    var pointWidth: Double? = nil
    var pointHeight: Double? = nil
    var lgIdentity: UInt16? = nil
    var lgExtendedIdentity: UInt16? = nil
    var matchedProfileName: String? = nil
    var inspected: Bool? = nil
    var inspectionProblem: String? = nil
    var reportedPorts: [MonitorInput]? = nil
    var reportedModel: String? = nil
    var reportedPortMode: String? = nil
    var displayLabel: String { reportedModel ?? name }
    var validInspectionMetadata: Bool {
        (reportedModel.map { !$0.isEmpty && $0.utf8.count <= 80 } ?? true) &&
        (reportedPortMode.map { ["standard", "lg"].contains($0) } ?? true) &&
        (reportedPorts?.count ?? 0) <= 16 && reportedPorts?.allSatisfy(\.valid) != false
    }
    static let reportedInputsChoice = "__reported_inputs__"
    var firmwareFamily: String? {
        vendor == 7789 ? LGFirmwareProfiles.family(identity: lgIdentity, extended: lgExtendedIdentity)?.name : nil
    }
    var identityConflict: Bool {
        guard let reportedModel, let firmwareFamily,
              let reported = MonitorCapabilities.modelSeries(reportedModel),
              let family = MonitorCapabilities.modelSeries(firmwareFamily) else { return false }
        return reported != family
    }
    func profile(choice: String) -> MonitorProfile? {
        if choice == Self.reportedInputsChoice { return nil }
        if !choice.isEmpty { return MonitorProfiles.entries.first { $0.vendor == vendor && $0.name == choice } }
        if let matchedProfileName, let profile = MonitorProfiles.entries.first(where: { $0.name == matchedProfileName && $0.vendor == vendor }) { return profile }
        return vendor == 7789 && !identityConflict ? LGFirmwareProfiles.inputs(identity: lgIdentity, extended: lgExtendedIdentity) : nil
    }
    func portOptions(choice: String) -> [MonitorInput] { profile(choice: choice)?.inputs ?? reportedPorts ?? [] }
    enum InputDetection { case profile(MonitorProfile), reported([MonitorInput]), unknown }
    var inputDetection: InputDetection {
        if let profile = profile(choice: ""), profile.confidence != "suggested" { return .profile(profile) }
        if let ports = reportedPorts, !ports.isEmpty, ports.count <= 16, ports.allSatisfy(\.valid) { return .reported(ports) }
        return .unknown
    }
    func sameDevice(as other: Self) -> Bool {
        id == other.id && vendor == other.vendor && model == other.model && serial == other.serial && name == other.name
    }
    mutating func retainIdentity(from old: Self?) {
        guard let old, sameDevice(as: old) else { return }
        lgIdentity = old.lgIdentity; lgExtendedIdentity = old.lgExtendedIdentity
        inspected = old.inspected; inspectionProblem = old.inspectionProblem; reportedPorts = old.reportedPorts
        reportedModel = old.reportedModel; reportedPortMode = old.reportedPortMode
        matchedProfileName = old.matchedProfileName ?? matchedProfileName
        if let reportedPorts { inputs = MonitorCapabilities.merge(inputs, reported: reportedPorts) }
    }
    mutating func applyInspection(_ result: MonitorInspection) {
        inspected = true; inspectionProblem = nil
        lgIdentity = vendor == 7789 ? result.lgIdentity : nil
        lgExtendedIdentity = vendor == 7789 ? result.lgExtendedIdentity : nil
        reportedModel = result.transportModel ?? MonitorCapabilities.model(result.capabilities ?? "")
        let descriptor = MonitorDescriptor(id: id, displayID: 0, name: name, vendor: vendor, model: model, ddcAvailable: canControl)
        matchedProfileName = MonitorProfiles.match(descriptor, reportedModel: reportedModel)?.name
        reportedPortMode = result.transportInputs == nil ? "standard" : mode
        let reported = result.transportInputs ?? MonitorCapabilities.inputs(result.capabilities ?? "").map {
            MonitorInput(code: $0, name: MonitorInput.name($0))
        }
        reportedPorts = reported
        inputs = MonitorCapabilities.merge(inputs, reported: reported)
    }
}
enum DeskDeviceMessage: Codable {
    case displays([DeskDetectedDisplay])
    case refresh
    case displayProblem(String)
    case inspect(String)
    case inspectRequest(UUID, String)
    case inspectionReply(UUID, DeskDetectedDisplay?, String?)
    case identify(String, String)
    case identification(String, String, UUID, Bool)
}
enum DeskShortcutKey {
    // Carbon virtual key codes are not consecutive. Keep this independent of
    // the smaller set of keys offered by the emergency shortcut picker.
    static let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    static let names = codes.indices.map { "F\($0 + 1)" }
    static func code(_ name: String) -> UInt32? {
        names.firstIndex(of: name).map { UInt32(codes[$0]) }
    }
}
final class DeskRuntime: ObservableObject {
    let node: KVMDeskNode
    let switching: KVMMonitorSwitch
    let input: KVMInputSession
    let inputAdapter: DeskInputAdapter
    let model: DeskModel
    @Published var displays: [UUID: [DeskDetectedDisplay]] = [:]
    @Published var discoveryProblem: String?
    private var remoteDisplayProblems: [UUID: String] = [:]
    @Published var discovering = false
    @Published var usbDevices: [MonitorUSBDevice] = []
    @Published var shortcutProblem: String?
    private var subscriptions: Set<AnyCancellable> = []
    private var queues: [String: DispatchQueue] = [:]
    private var refreshTimer: Timer?
    private struct PendingInspection {
        let computer: UUID
        let before: DeskDetectedDisplay
        let completion: (Result<DeskDetectedDisplay, Error>) -> Void
    }
    private var pendingInspections: [UUID: PendingInspection] = [:]
    private var hotKeys: [PanicHotKey] = []
    private var registeredShortcuts: [KVMShortcut] = []
    private var registeredPanic: PanicShortcut?
    private var identifyWindows: [String: (UUID, NSWindow)] = [:]
    private(set) var identifications = DeskIdentificationState()
    private var inputAfterSwitch: (UUID, UUID)?
    init(node: KVMDeskNode) {
        self.node = node
        let switching = KVMMonitorSwitch(node: node)
        self.switching = switching
        let input = KVMInputSession(node: node)
        input.optimisticMonitorInput = { [weak switching] monitor in switching?.optimisticInputs[monitor] }
        self.input = input; inputAdapter = DeskInputAdapter(session: input)
        model = DeskModel(store: node.storage.deletingLastPathComponent().appendingPathComponent("unused-preview.json"))
        model.group = node.group; model.selected = node.group.monitors.first?.id
        model.live = DeskLiveActions(edit: { [weak node] in try node?.edit($0) }, activate: { [weak self] in self?.activatePreset($0) }, readiness: { [weak self] in self?.switching.readiness($0) },
            mappingOptions: { [weak self] in self?.mappingOptions ?? [] }, map: { [weak self] in self?.map($0, choice: $1) },
            identify: { [weak self] in self?.identify($0) }, sheet: { [weak self] kind, selection, close in
                guard let self else { return AnyView(EmptyView()) }; return AnyView(DeskLiveSheet(runtime: self, kind: kind, selection: selection, close: close))
            },
            identifyDisplay: { [weak self] computer, display in self?.identifyDetected(display, computer: computer, name: "Is this the screen?") },
            identifyingDisplay: { [weak self] computer, display in self?.identifications.active[computer.uuidString + "|" + display] != nil },
            identifyingMonitor: { [weak self] monitor in self?.identifications.active["monitor:" + monitor.uuidString] != nil },
            refreshScreens: { [weak self] in self?.refreshAllDisplays() },
            removalIssue: { [weak node] id in
                guard let node else { return "Desk is unavailable." }
                if id == node.localID { return "This is the Mac you are using." }
                return node.isOwner ? nil : "Remove computers from \(node.ownerName), which owns this desk."
            }, mapComputer: { [weak self] port, computer in
                guard let self else { return }
                self.model.edit { try DeskCableBinding.apply(connection: port, computer: computer, display: nil, to: &$0) }
                self.resolvePendingDisplays(); self.refreshAllDisplays()
            }, displayStatus: { [weak self] computer in
                guard let self else { return nil }
                if !self.node.online.contains(computer) { return "This computer is offline. Its saved cable will remain until it reconnects." }
                return computer == self.node.localID ? self.discoveryProblem : self.remoteDisplayProblems[computer]
            })
        model.live?.inputControls = { [weak self] preset, monitor in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(DeskSharingControls(input: self.input, adapter: self.inputAdapter,
                                               node: self.node, preset: preset, monitor: monitor))
        }
        model.live?.refreshMonitorStatus = { [weak self] in self?.switching.refreshObservations() }
        model.live?.retryMonitorConnection = { [weak self] monitor in self?.switching.retryConnection(for: monitor) }
        model.live?.connectionReadiness = { [weak self] connection in
            guard let self else { return "Desk is unavailable." }
            return self.switching.connectionReadiness(connection)
        }
        model.live?.switchConnection = { [weak self] connection in
            guard let self else { return }
            if self.switching.connectionReadiness(connection) == nil {
                self.inputAfterSwitch = nil
                self.input.stop()
            }
            self.switching.activateConnection(connection)
        }
        model.live?.forceSwitchConnection = { [weak self] connection in
            guard let self else { return }
            self.inputAfterSwitch = nil
            self.input.stop()
            self.switching.forceActivateConnection(connection)
        }
        node.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        switching.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        switching.execute = { [weak self] route, valid, completion in self?.execute(route, valid: valid, completion: completion) }
        switching.readForVerification = { [weak self] monitor, completion in self?.read(monitor, completion: completion) }
        input.readMonitor = { [weak self] monitor, completion in self?.read(monitor, completion: completion) }
        input.motionScale = { [weak self] focus in
            guard let self, let geometry = self.node.group.monitors.first(where: { $0.id == focus.monitor })?.geometry,
                  let connection = self.node.group.connections.first(where: { $0.monitor == focus.monitor && $0.computer == focus.computer }),
                  let computer = connection.computer,
                  let display = self.displays[computer]?.first(where: { $0.id == connection.localDisplay }),
                  let width = display.pointWidth, let height = display.pointHeight, width > 0, height > 0 else { return .init(x: 0.25, y: 0.25) }
            return .init(x: geometry.displayedWidth / width, y: geometry.displayedHeight / height)
        }
        switching.otherMessage = { [weak self] peer, data in
            guard let self else { return }
            if !self.input.receive(data, peer: peer) { self.receiveDevices(data, peer: peer) }
        }
        model.live?.panelAspect = { [weak self] id in
            guard let self else { return nil }
            let ratios = self.node.group.connections.filter { $0.monitor == id }.compactMap { cable -> Double? in
                guard let computer = cable.computer, let display = cable.localDisplay else { return nil }
                return self.displays[computer]?.first { $0.id == display }?.panelAspect
            }
            // Reports for the same physical monitor must agree before choosing automatically.
            guard let first = ratios.first, ratios.allSatisfy({ abs($0-first) < 0.02 }) else { return nil }
            return first
        }
        node.peersChanged = { [weak self] in self?.refreshAllDisplays(); self?.updateModel() }
        inputAdapter.presetShortcut = { [weak self] in self?.activatePreset($0) }
        updateModel()
    }
    deinit { refreshTimer?.invalidate() }
    func stop() {
        desktopHandoff.stop()
        for (_, window) in identifyWindows.values { window.orderOut(nil) }; identifyWindows = [:]
        inputAdapter.stop()
        refreshTimer?.invalidate(); refreshTimer = nil
        hotKeys.forEach { $0.unregister() }; hotKeys = []; registeredShortcuts = []
        node.stop()
    }
    func start() throws {
        try node.start()
        guard node.isMember else { return }
        desktopHandoff.start()
        refreshDisplays()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refreshDisplays() }
        timer.tolerance = 3; refreshTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func updateModel() {
        if let (preset, monitor) = inputAfterSwitch, !switching.busy {
            inputAfterSwitch = nil
            if switching.activePreset == preset || switching.optimisticInputs[monitor] != nil {
                input.resumeAfterPreset(preset, monitor: monitor)
            }
        }
        registerShortcuts()
        model.group = node.group; model.online = node.online
        model.conflict = node.conflicts.first ?? node.recoveredDraft
        model.problem = switching.problem ?? desktopHandoff.problem ?? node.displayProblem ?? discoveryProblem ?? shortcutProblem
        model.active = node.group.presets.first { $0.id == switching.activePreset }
        model.activeGroup = switching.activeGroup
        if !switching.busy, let active = model.active,
           let index = node.group.presets.firstIndex(where: { $0.id == active.id }), model.presetIndex != index {
            model.presetIndex = index
        }
        model.monitorResults = switching.results.mapValues { $0.state.rawValue.capitalized + ": " + $0.detail }
        model.monitorProblems = Set(switching.results.values.filter { $0.state != .confirmed }.map(\.monitor))
        if let selected = model.selected, !node.group.monitors.contains(where: { $0.id == selected }) { model.selected = node.group.monitors.first?.id }
        if model.selected == nil { model.selected = node.group.monitors.first?.id }
        objectWillChange.send()
    }
    func activatePreset(_ preset: UUID) {
        if switching.busy && switching.request?.preset == preset { return }
        guard switching.readiness(preset) == nil else { switching.activate(preset); return }
        let included = node.group.presets.first { $0.id == preset }?.assignments.map(\.monitor) ?? []
        let preferred = input.focus?.monitor ?? model.selected
        let monitor = preferred.flatMap { included.contains($0) ? $0 : nil } ?? included.first
        input.stop()
        switching.activate(preset)
        if input.enabled, switching.busy, let monitor { inputAfterSwitch = (preset, monitor) }
    }
    func controlOptions(for monitor: UUID) -> [DeskMappingOption] {
        let detected = Set(displays.flatMap { computer, displays in displays.map { computer.uuidString + "|" + $0.id } })
        return DeskControlPaths.options(group: node.group, monitor: monitor, detected: detected)
    }
    func defaultControlMode(for monitor: UUID) -> String? {
        guard let screen = node.group.monitors.first(where: { $0.id == monitor }) else { return nil }
        if let mode = screen.defaultControlMode { return mode }
        if let name = screen.inputProfile, let profile = MonitorProfiles.entries.first(where: { $0.name == name }) {
            return profile.alternate ? "lg" : "standard"
        }
        return screen.control.flatMap { control in displays[control.computer]?.first { $0.id == control.localDisplay }?.mode }
    }
    var mappingOptions: [DeskMappingOption] {
        node.group.computers.flatMap { computer in
            var options = (displays[computer.id] ?? []).enumerated().map { index, display in
                let serial = display.serial == 0 ? "" : " · Serial \(display.serial)"
                return DeskMappingOption(id: computer.id.uuidString + "|" + display.id,
                    label: "Display \(index + 1): \(display.name)" + serial)
            }
            for c in node.group.connections where c.computer == computer.id {
                if let id = c.localDisplay, !options.contains(where: { $0.id == computer.id.uuidString + "|" + id }) {
                    options.append(.init(id: computer.id.uuidString + "|" + id, label: (node.group.monitors.first { $0.id == c.monitor }?.name ?? "Screen") + " · " + c.inputName + " (not currently detected)"))
                }
            }
            return options
        }
    }
    func suggestedScreens(computer: UUID, display: DeskDetectedDisplay) -> [KVMMonitor] {
        let observations = displays.flatMap { computer, values in values.map {
            KVMDisplayObservation(computer: computer, localDisplay: $0.id, vendor: $0.vendor, model: $0.model,
                                  numericSerial: $0.serial, textSerial: nil)
        } }
        let detected = KVMDisplayObservation(computer: computer, localDisplay: display.id, vendor: display.vendor,
                                            model: display.model, numericSerial: display.serial, textSerial: nil)
        let matches = detected.suggestedMatches(in: observations)
        let ids = Set(node.group.connections.filter { connection in
            matches.contains { $0.computer == connection.computer && $0.localDisplay == connection.localDisplay }
        }.map(\.monitor))
        // More than one saved physical identity is a conflict to inspect, not a
        // useful automatic suggestion. The explicit picker remains available.
        return ids.count == 1 ? node.group.monitors.filter { ids.contains($0.id) } : []
    }
    func map(_ connection: UUID, choice: String) {
        model.edit { group in
            guard group.connections.contains(where: { $0.id == connection }) else { throw KVMError("This port was removed.") }
            if choice.isEmpty { try DeskCableBinding.apply(connection: connection, computer: nil, display: nil, to: &group); return }
            let parts = choice.split(separator: "|")
            guard parts.count == 2, let computer = UUID(uuidString: String(parts[0])), self.mappingOptions.contains(where: { $0.id == choice }) else { throw KVMError("Choose a detected display on a grouped computer.") }
            try DeskCableBinding.apply(connection: connection, computer: computer, display: String(parts[1]), to: &group)
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
                    let retained = (self.displays[self.node.localID] ?? []).filter { old in self.desktopHandoff.disconnected.contains(old.id) && !values.contains(where: { $0.id == old.id }) }
                    self.displays[self.node.localID] = values.map { display in
                        let profile = MonitorProfiles.match(display)
                        let size = CGDisplayScreenSize(display.displayID)
                        var detected = DeskDetectedDisplay(id: display.id, name: display.name, vendor: display.vendor, model: display.model,
                            serial: CGDisplaySerialNumber(display.displayID), width: max(1, size.width), height: max(1, size.height), canControl: display.ddcAvailable,
                            inputs: profile?.inputs ?? [], mode: profile?.alternate == true ? "lg" : "standard",
                            pointWidth: CGDisplayBounds(display.displayID).width, pointHeight: CGDisplayBounds(display.displayID).height)
                        let modes = CGDisplayCopyAllDisplayModes(display.displayID, nil) as? [CGDisplayMode] ?? []
                        let native = modes.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
                        let largest = modes.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
                        if let mode = native, mode.pixelWidth > 0, mode.pixelHeight > 0 {
                            detected.panelAspect = Double(mode.pixelWidth) / Double(mode.pixelHeight)
                        } else if size.width > 1 && size.height > 1 {
                            detected.panelAspect = size.width / size.height
                        } else if let mode = largest, mode.pixelWidth > 0, mode.pixelHeight > 0 {
                            detected.panelAspect = Double(mode.pixelWidth) / Double(mode.pixelHeight)
                        }
                        detected.matchedProfileName = profile?.name
                        detected.retainIdentity(from: self.displays[self.node.localID]?.first { $0.id == display.id })
                        return detected
                    }
                    self.displays[self.node.localID, default: []].append(contentsOf: retained)
                    self.resolvePendingDisplays(); self.publishDisplays()
                case .failure(let error):
                    self.discoveryProblem = "Could not refresh connected screens. " + error.localizedDescription
                    if let data = try? JSONEncoder().encode(DeskDeviceMessage.displayProblem(String(self.discoveryProblem!.prefix(800)))) {
                        for peer in self.node.online where peer != self.node.localID { self.node.sendApplication(data, peer: peer) }
                    }
                }
                self.updateModel()
            }
        }
    }
    func inspect(_ display: String, computer: UUID, completion: ((Result<DeskDetectedDisplay, Error>) -> Void)? = nil) {
        guard let d = displays[computer]?.first(where: { $0.id == display }) else {
            completion?(.failure(KVMError("This display is no longer reported. Reconnect it and try again."))); return
        }
        if computer != node.localID {
            guard node.online.contains(computer) else { completion?(.failure(KVMError("The control computer is offline. Reconnect it and try again."))); return }
            let message: DeskDeviceMessage
            if let completion {
                let token = UUID()
                pendingInspections[token] = .init(computer: computer, before: d, completion: completion)
                message = .inspectRequest(token, display)
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let pending = self?.pendingInspections.removeValue(forKey: token) else { return }
                    pending.completion(.failure(KVMError("The control computer did not finish detection. Check its connection and Perch version, then retry.")))
                }
            } else { message = .inspect(display) }
            if let data = try? JSONEncoder().encode(message) { node.sendApplication(data, peer: computer) }
            return
        }
        queue(display).async { [weak self] in
            let result = Result { try JSONDecoder().decode(MonitorInspection.self, from: MonitorDisplayBackend().run(["inspect", display, d.mode])) }
            DispatchQueue.main.async {
                guard let self, let i = self.displays[computer]?.firstIndex(where: { $0.id == display }),
                      self.displays[computer]?[i].sameDevice(as: d) == true else {
                    completion?(.failure(KVMError("The display changed during detection. Try again."))); return
                }
                switch result {
                case .success(let inspection): self.displays[computer]?[i].applyInspection(inspection)
                case .failure(let error): self.displays[computer]?[i].inspectionProblem = error.localizedDescription; self.displays[computer]?[i].inspected = true
                }
                self.publishDisplays(); self.updateModel()
                switch result {
                case .success: if let updated = self.displays[computer]?[i] { completion?(.success(updated)) }
                case .failure(let error): completion?(.failure(error))
                }
            }
        }
    }
    func detectInputProfile(_ monitor: UUID, completion: @escaping (Result<String, Error>) -> Void) {
        guard let screen = node.group.monitors.first(where: { $0.id == monitor }), let control = screen.control else {
            completion(.failure(KVMError("Choose this monitor’s control connection first."))); return
        }
        guard controlOptions(for: monitor).contains(where: { $0.computer == control.computer && $0.display == control.localDisplay }) else {
            completion(.failure(KVMError("The saved path points to another monitor. Choose a matched control connection for this screen before detecting its profile."))); return
        }
        let originalPorts = node.group.connections.filter { $0.monitor == monitor }
        inspect(control.localDisplay, computer: control.computer) { [weak self] result in
            guard let self else { return }
            do {
                let detected = try result.get()
                guard self.node.group.monitors.first(where: { $0.id == monitor }) == screen,
                      self.node.group.connections.filter({ $0.monitor == monitor }) == originalPorts else {
                    throw KVMError("This monitor’s setup changed during detection. Your changes were kept; try again.")
                }
                switch detected.inputDetection {
                case .profile(let profile):
                    try self.configureMonitor(monitor, profile: profile)
                    completion(.success("Detected " + profile.name)); return
                case .reported:
                    try self.configureReportedInputs(monitor, detected: detected)
                    completion(.success("Using the monitor’s reported inputs.")); return
                case .unknown: break
                }
                let family = detected.firmwareFamily.map { "Recognized firmware family: " + $0 + ". " } ?? ""
                completion(.success(family + "No verified input profile or reported ports were found. Your current setup is unchanged."))
            } catch { completion(.failure(error)) }
        }
    }
    func configureReportedInputs(_ monitor: UUID, detected: DeskDetectedDisplay) throws {
        guard let inputs = detected.reportedPorts, !inputs.isEmpty, inputs.count <= 16, inputs.allSatisfy(\.valid) else { throw KVMError("This monitor has not reported a usable input list.") }
        var group = node.group
        try DeskMonitorConfiguration.apply(monitor: monitor, profile: DeskDetectedDisplay.reportedInputsChoice,
                                           ports: inputs.map { .init(name: $0.name, code: $0.code) }, mode: detected.reportedPortMode ?? detected.mode, to: &group)
        try node.edit(group)
    }
    func discoverUSB() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = (try? JSONDecoder().decode([MonitorUSBDevice].self, from: MonitorDisplayBackend().run(["usb-list"]))) ?? []
            DispatchQueue.main.async { self?.usbDevices = devices }
        }
    }
    private func resolvePendingDisplays() {
        guard node.canEdit, !switching.busy else { return }
        let observations = displays.flatMap { computer, values in values.map {
            KVMDisplayObservation(computer: computer, localDisplay: $0.id, vendor: $0.vendor, model: $0.model, numericSerial: $0.serial, textSerial: nil)
        } }
        let resolved = DeskPendingCableResolver.resolve(node.group, observations: observations)
        guard resolved != node.group else { return }
        do { try node.edit(resolved) } catch { model.problem = error.localizedDescription }
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
            guard values.allSatisfy(\.validInspectionMetadata) else { return }
            guard values.count <= 16, Set(values.map(\.id)).count == values.count,
                  values.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.name.isEmpty && $0.name.utf8.count <= 100 && $0.inputs.count <= 16 && $0.inputs.allSatisfy(\.valid) && $0.width.isFinite && $0.height.isFinite && (1...10000).contains($0.width) && (1...10000).contains($0.height) && ["standard", "lg"].contains($0.mode) }) else { return }
            guard values.allSatisfy({ $0.panelAspect.map { $0.isFinite && (0.1...10).contains($0) } ?? true }) else { return }
            guard values.allSatisfy({ value in [value.pointWidth, value.pointHeight].allSatisfy { $0.map { $0.isFinite && (1...100_000).contains($0) } ?? true } }) else { return }
            displays[peer] = values; remoteDisplayProblems[peer] = nil; resolvePendingDisplays(); updateModel()
        case .displayProblem(let problem):
            remoteDisplayProblems[peer] = String(problem.prefix(800)); updateModel()
        case .refresh: refreshDisplays()
        case .inspect(let display): inspect(display, computer: node.localID)
        case .inspectRequest(let token, let display):
            inspect(display, computer: node.localID) { [weak self] result in
                guard let self else { return }
                let reply: DeskDeviceMessage
                switch result {
                case .success(let detected): reply = .inspectionReply(token, detected, nil)
                case .failure(let error): reply = .inspectionReply(token, nil, String(error.localizedDescription.prefix(800)))
                }
                if let data = try? JSONEncoder().encode(reply) { self.node.sendApplication(data, peer: peer) }
            }
        case .inspectionReply(let token, let value, let error):
            guard let pending = pendingInspections[token], pending.computer == peer else { return }
            pendingInspections[token] = nil
            if let error { pending.completion(.failure(KVMError(String(error.prefix(800))))); return }
            guard let value, value.sameDevice(as: pending.before), value.inspectionProblem == nil,
                  let i = displays[peer]?.firstIndex(where: { $0.sameDevice(as: pending.before) }),
                  value.validInspectionMetadata else {
                pending.completion(.failure(KVMError("The display changed or returned invalid detection details. Try again."))); return
            }
            // Only inspection fields come from the reply; retain validated device metadata.
            displays[peer]?[i].lgIdentity = value.lgIdentity; displays[peer]?[i].lgExtendedIdentity = value.lgExtendedIdentity
            displays[peer]?[i].reportedModel = value.reportedModel; displays[peer]?[i].reportedPortMode = value.reportedPortMode
            let descriptor = MonitorDescriptor(id: value.id, displayID: 0, name: value.name, vendor: value.vendor, model: value.model, ddcAvailable: value.canControl)
            displays[peer]?[i].matchedProfileName = MonitorProfiles.match(descriptor, reportedModel: value.reportedModel)?.name
            displays[peer]?[i].reportedPorts = value.reportedPorts; displays[peer]?[i].inspected = true; displays[peer]?[i].inspectionProblem = nil
            if let updated = displays[peer]?[i] { pending.completion(.success(updated)) }
            updateModel()
        case .identify(let display, let name): showIdentification(display, name: String(name.prefix(100)), token: UUID(), showing: true)
        case .identification(let display, let name, let token, let showing): showIdentification(display, name: String(name.prefix(100)), token: token, showing: showing)
        }
    }
    func addScreen(name: String, existing: UUID?, computer: UUID, display: String, input: UInt16, profile: MonitorProfile? = nil, custom: MonitorInput? = nil) throws {
        guard var detected = displays[computer]?.first(where: { $0.id == display }) else { throw KVMError("Choose a detected screen.") }
        detected.inputs = profile?.inputs ?? detected.reportedPorts ?? []
        if let profile { detected.mode = profile.alternate ? "lg" : "standard" }
        else if let reportedMode = detected.reportedPortMode { detected.mode = reportedMode }
        if let custom, custom.valid { detected.inputs.removeAll { $0.code == custom.code }; detected.inputs.append(custom) }
        guard detected.inputs.contains(where: { $0.code == input }) else { throw KVMError("Choose this cable’s connected input.") }
        var group = node.group
        let monitor: UUID
        if let existing { monitor = existing }
        else {
            let screen = KVMMonitor(name: name, geometry: .init(x: group.monitors.map { $0.geometry.right }.max() ?? 0, y: 0, width: detected.width > 1 ? detected.width : 550, height: detected.height > 1 ? detected.height : 310), control: .init(computer: computer, localDisplay: display, mode: detected.mode))
            monitor = screen.id; group.monitors.append(screen)
            group.monitors[group.monitors.count - 1].panelAspect = detected.panelAspect
            group.monitors[group.monitors.count - 1].defaultControlMode = detected.mode
            group.monitors[group.monitors.count - 1].inputProfile = profile?.name ?? detected.matchedProfileName
        }
        for port in detected.inputs where !group.connections.contains(where: { $0.monitor == monitor && $0.inputCode == port.code }) {
            group.connections.append(.init(monitor: monitor, computer: nil, localDisplay: nil, inputName: port.name, inputCode: port.code))
        }
        guard let i = group.connections.firstIndex(where: { $0.monitor == monitor && $0.inputCode == input }) else { throw KVMError("This input is not configured.") }
        guard group.connections[i].computer == nil || group.connections[i].computer == computer && group.connections[i].localDisplay == display else { throw KVMError("That input is already mapped. Correct its existing mapping first.") }
        group.connections[i].computer = computer; group.connections[i].localDisplay = display
        try node.edit(group); model.selected = monitor; node.problem = nil
    }
    private lazy var desktopHandoff = DeskDesktopHandoff(local: node.localID, group: { [unowned self] in self.node.group }, inputs: { [weak self] in self?.switching.desktopInputs ?? [:] }, optimisticInputs: { [weak self] in self?.switching.optimisticInputs ?? [:] }, online: { [weak self] in self?.node.online ?? [] }, suspended: { [weak self] in self?.node.canEdit != true })
    private func execute(_ route: KVMMonitorRoute, valid: @escaping () -> Bool, completion: @escaping (KVMMonitorOutcome.State, String) -> Void) {
        guard desktopHandoff.prepareCommand(route.control.localDisplay) else { completion(.failed, desktopHandoff.problem ?? "The display could not reconnect."); return }
        queue(route.control.localDisplay).async {
            let backend = MonitorDisplayBackend()
            let args = [route.control.localDisplay, route.control.mode]
            func allowed() -> Bool { DispatchQueue.main.sync { valid() } }
            func read() throws -> UInt16? { try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["read"] + args)).current }
            var state = KVMMonitorOutcome.State.failed, detail = "The switch was cancelled before its monitor command."
            do {
                let outcome = try DeskMonitorCommand.run(input: route.input, permitted: allowed, read: read, write: {
                    let data = try backend.run(["switch"] + args + [String(route.input)])
                    guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["sent"] as? Bool == true else { throw KVMError("The monitor did not accept the input command.") }
                }, settle: { Thread.sleep(forTimeInterval: 0.2) })
                switch outcome {
                case .alreadySelected: state = .confirmed; detail = "Already on this input; confirmed without sending a switch command."
                case .switched: state = .confirmed; detail = "Monitor reports the requested input."
                case .unverified: state = .unverified; detail = "Command sent. Checking the picture from another paired computer…"
                }
            } catch { detail = error.localizedDescription }
            DispatchQueue.main.async { self.desktopHandoff.finishCommand(route.control.localDisplay); completion(state, detail) }
        }
    }
    private func read(_ monitor: UUID, completion: @escaping (UInt16?) -> Void) {
        guard let control = node.group.monitors.first(where: { $0.id == monitor })?.control else { completion(nil); return }
        let id: String, mode: String
        if control.computer == node.localID { id = control.localDisplay; mode = control.mode }
        else {
            guard let connection = node.group.connections.first(where: { $0.monitor == monitor && $0.computer == node.localID }),
                  let local = connection.localDisplay, let display = displays[node.localID]?.first(where: { $0.id == local }),
                  control.mode == "standard" || control.mode == "lg" && display.vendor == 7789 else { completion(nil); return }
            id = local; mode = display.mode
        }
        guard !desktopHandoff.disconnected.contains(id) else { completion(nil); return }
        queue(id).async {
            let input = try? JSONDecoder().decode(MonitorInspection.self, from: MonitorDisplayBackend().run(["read", id, mode])).current
            DispatchQueue.main.async { completion(input ?? nil) }
        }
    }

    func identify(_ monitor: UUID?) {
        guard let monitor, let screen = node.group.monitors.first(where: { $0.id == monitor }) else { return }
        var targets = node.group.connections.filter { $0.monitor == monitor }.compactMap { c -> (UUID, String)? in
            guard let peer = c.computer, let display = c.localDisplay else { return nil }; return (peer, display)
        }
        // A monitor can have a control computer even while none of its input
        // ports is mapped to that computer. Identification follows the control
        // route too, so a screen owned by another Perch can still be identified
        // from this Desk view.
        if let control = screen.control, !targets.contains(where: { $0.0 == control.computer && $0.1 == control.localDisplay }) {
            targets.append((control.computer, control.localDisplay))
        }
        toggleIdentification(key: "monitor:" + monitor.uuidString, targets: targets, name: screen.name)
    }
    func identifyDetected(_ display: String, computer: UUID, name: String) {
        guard displays[computer]?.contains(where: { $0.id == display }) == true else { return }
        toggleIdentification(key: computer.uuidString + "|" + display, targets: [(computer, display)], name: name)
    }
    private func toggleIdentification(key: String, targets: [(UUID, String)], name: String) {
        let change = identifications.toggle(key)
        for (peer, display) in targets { sendIdentification(display, peer: peer, name: name, token: change.token, showing: change.showing) }
        model.objectWillChange.send(); objectWillChange.send()
        if change.showing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.identifications.expire(key, token: change.token) else { return }
                for (peer, display) in targets { self.sendIdentification(display, peer: peer, name: name, token: change.token, showing: false) }
                self.model.objectWillChange.send(); self.objectWillChange.send()
            }
        }
    }
    private func sendIdentification(_ display: String, peer: UUID, name: String, token: UUID, showing: Bool) {
        if peer == node.localID { showIdentification(display, name: name, token: token, showing: showing) }
        else if let bytes = try? JSONEncoder().encode(DeskDeviceMessage.identification(display, name, token, showing)) { node.sendApplication(bytes, peer: peer) }
    }
    private func showIdentification(_ display: String, name: String, token: UUID, showing: Bool) {
        if !showing {
            if let (current, window) = identifyWindows[display], current == token { window.orderOut(nil); identifyWindows[display] = nil }
            return
        }
        guard !SettingsWindow.shared.testing, let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == display
        }) else { return }
        identifyWindows[display]?.1.orderOut(nil)
        let window = NSWindow(contentRect: NSRect(x: screen.frame.midX-160, y: screen.frame.midY-60, width: 320, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear; window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text(name).font(.largeTitle.bold()).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)))
        identifyWindows[display] = (token, window); window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.identifyWindows[display]?.0 == token else { return }
            self.identifyWindows[display]?.1.orderOut(nil); self.identifyWindows[display] = nil
        }
    }
    func configureMonitor(_ monitor: UUID, profile: MonitorProfile) throws {
        guard let screen = node.group.monitors.first(where: { $0.id == monitor }), let control = screen.control,
              let detected = displays[control.computer]?.first(where: { $0.id == control.localDisplay }), detected.vendor == profile.vendor else { throw KVMError("Reconnect this monitor’s control computer so Perch can check its manufacturer before changing the profile.") }
        var group = node.group
        try DeskMonitorConfiguration.apply(monitor: monitor, profile: profile.name, ports: profile.inputs.map { .init(name: $0.name, code: $0.code) }, mode: profile.alternate ? "lg" : "standard", to: &group)
        try node.edit(group)
    }
    func registerShortcuts() {
        guard !SettingsWindow.shared.testing else { return }
        let shortcuts = node.group.presets.map(\.shortcut)
        let panic = SafetyConfiguration.load().shortcut
        guard registeredShortcuts != shortcuts || registeredPanic != panic else { return }
        registeredPanic = panic
        hotKeys.forEach { try? $0.register(PanicShortcut(enabled: false)) }; hotKeys = []; registeredShortcuts = shortcuts
        do {
            for (i, shortcut) in shortcuts.enumerated() {
                let key = DeskShortcutKey.code(shortcut.key)
                guard let key else { throw KVMError("This Mac cannot register \(shortcut.label). Change the shortcut in App settings → Hotkeys.") }
                let hotkey = PanicHotKey(signature: UInt32(0x50444B30 + i))
                var modifiers: UInt32 = 0
                if shortcut.control { modifiers |= UInt32(controlKey) }; if shortcut.option { modifiers |= UInt32(optionKey) }
                if shortcut.command { modifiers |= UInt32(cmdKey) }; if shortcut.shift { modifiers |= UInt32(shiftKey) }
                let chosen = PanicShortcut(key: key, modifiers: modifiers, enabled: true)
                guard !panic.enabled || panic.key != key || panic.modifiers != modifiers else { throw KVMError("\(shortcut.label) is already the Agent Kill Switch shortcut. Choose another Desk shortcut.") }
                try hotkey.register(chosen)
                hotkey.action = { [weak self] in guard let self else { return }; self.activatePreset(self.node.group.presets[i].id) }
                hotKeys.append(hotkey)
            }
            shortcutProblem = nil
        } catch {
            // A failed set must not leave only some presets registered.
            hotKeys.forEach { $0.unregister() }; hotKeys = []
            shortcutProblem = error.localizedDescription
        }
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
            if DeskInputAdapter.sharingEnabledByDefault { runtime.inputAdapter.enable(true) }
        } catch { problem = error.localizedDescription }
    }
}


extension KVMShortcut {
    func matches(_ shortcut: PanicShortcut) -> Bool {
        guard shortcut.enabled, DeskShortcutKey.code(key) == shortcut.key else { return false }
        return self.control == (shortcut.modifiers & UInt32(controlKey) != 0) &&
            self.option == (shortcut.modifiers & UInt32(optionKey) != 0) &&
            self.command == (shortcut.modifiers & UInt32(cmdKey) != 0) &&
            self.shift == (shortcut.modifiers & UInt32(shiftKey) != 0)
    }
}
