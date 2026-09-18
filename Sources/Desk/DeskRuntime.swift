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
    static let wirePrefix = Data("Perch devices v1\0".utf8)
    var wire: Data? { (try? JSONEncoder().encode(self)).map { Self.wirePrefix + $0 } }
    case displays([DeskDetectedDisplay])
    case refresh
    case displayProblem(String)
    case inspect(String)
    case inspectRequest(UUID, String)
    case inspectionReply(UUID, DeskDetectedDisplay?, String?)
    case identify(String, String)
    case identification(String, String, UUID, Bool)
    /// A monitor identification session is shared by the whole desk. The
    /// monitor ID, rather than the currently selected input, is the stable
    /// identity so any paired Mac can stop it.
    case monitorIdentification(UUID, String, UUID, Bool)
    /// Identify every display currently visible to a peer. This lets a user
    /// match a new cable before its host display identity is saved locally.
    case identifyAll(String, UUID, Bool)
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
    func remoteDisplayProblem(_ computer: UUID) -> String? { remoteDisplayProblems[computer] }
    @Published var discovering = false
    @Published var usbDevices: [MonitorUSBDevice] = []
    @Published var shortcutProblem: String?
    @Published var sharingShortcutError: String?
    private var subscriptions: Set<AnyCancellable> = []
    private var queues: [String: DispatchQueue] = [:]
    private var refreshTimer: Timer?
    private struct PendingInspection {
        let computer: UUID
        let before: DeskDetectedDisplay
        let completion: (Result<DeskDetectedDisplay, Error>) -> Void
    }
    private var pendingInspections: [UUID: PendingInspection] = [:]
    private var presetHotKeys: [UUID: HotKey] = [:]
    private let sharingHotKey = HotKey()
    private var shortcutMemory = DeskShortcutRegistrationMemory()
    private var identifyWindows: [String: (UUID, NSWindow)] = [:]
    private(set) var identifications = DeskIdentificationState()
    private var inputAfterSwitch: (UUID, UUID)?
    private var lastInputPreset: UUID?
    /// Avoid repeated focus requests while the owner prepares a grant. A
    /// failed request can be retried after the short backoff when readiness
    /// changes.
    private var automaticInputStart: (preset: UUID, monitor: UUID, at: TimeInterval)?
    init(node: KVMDeskNode) {
        self.node = node
        let switching = KVMMonitorSwitch(node: node)
        self.switching = switching
        let input = KVMInputSession(node: node)
        input.optimisticMonitorInput = { [weak switching] monitor in switching?.optimisticInputs[monitor] }
        self.input = input; inputAdapter = DeskInputAdapter(session: input)
        let backend = DeskRuntimeBackend()
        model = DeskModel(backend: backend, group: node.group)
        backend.runtime = self
        node.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        switching.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateModel() } }.store(in: &subscriptions)
        // Readiness arrives over the input session's polling channel. Retry
        // automatic focus when a peer becomes ready instead of making the
        // user reopen Desk or press a hidden test button.
        input.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.startInputForActivePresetIfNeeded() }
        }.store(in: &subscriptions)
        switching.execute = { [weak self] route, valid, completion in self?.execute(route, valid: valid, completion: completion) }
        switching.prepareDestination = { [weak self] request in
            guard let self else { return }
            for route in request.routes {
                guard let connection = self.node.group.connections.first(where: { $0.monitor == route.monitor && $0.inputCode == route.input }),
                      connection.computer == self.node.localID, let display = connection.localDisplay else { continue }
                self.desktopHandoff.prepareDestination(display)
            }
        }
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
        node.peersChanged = { [weak self] in
            self?.refreshAllDisplays()
            self?.syncActiveMonitorIdentifications()
            self?.updateModel()
        }
        inputAdapter.presetShortcut = { [weak self] in self?.activatePreset($0) }
        // Other Perch shortcuts stay with this Mac's own tap owners.
        inputAdapter.localShortcut = { key, flags in ShortcutRegistry.perch.owns(keyCode: key, flags: flags, excluding: ShortcutRegistry.Source.deskPresets) }
        updateModel()
    }
    deinit { refreshTimer?.invalidate() }
    func stop() {
        // Input first: the session tells the owner it is releasing its lease
        // and posts held-key releases while the link is still open.
        input.stop()
        desktopHandoff.stop()
        for (_, window) in identifyWindows.values { window.orderOut(nil) }; identifyWindows = [:]
        inputAdapter.stop()
        refreshTimer?.invalidate(); refreshTimer = nil
        presetHotKeys = [:]; sharingHotKey.unregister(); shortcutMemory.reset()
        node.stop()
    }
    func start() throws {
        try node.start()
        guard node.isMember else { return }
        desktopHandoff.start()
        refreshDisplays()
        let timer = MainTimer.every(20) { [weak self] in self?.refreshDisplays() }
        timer.tolerance = 3; refreshTimer = timer
    }
    private func updateModel() {
        if inputAfterSwitch != nil, !switching.busy {
            inputAfterSwitch = nil
            automaticInputStart = nil
        }
        registerShortcuts()
        model.group = node.group; model.online = node.online
        model.conflict = node.conflicts.first ?? node.recoveredDraft
        model.problem = switching.problem ?? desktopHandoff.problem ?? node.displayProblem ?? discoveryProblem ?? shortcutProblem ?? inputAdapter.accessProblem
        model.caution = switching.caution ?? inputAdapter.note ?? pendingMatchCaution()
        model.status = inputStatus()
        model.switchingPreset = switching.busy ? switching.request?.preset : nil
        model.activeUnconfirmed = switching.activePreset != nil && switching.results.values.contains { $0.state == .unverified }
        model.active = node.group.presets.first { $0.id == switching.activePreset }
        model.activeGroup = switching.activeGroup
        if let activePreset = switching.activePreset, activePreset != lastInputPreset {
            // activatePreset already stopped the old lease before beginning a
            // monitor switch. Only tear down here when an externally received
            // preset changed while a lease is still live; preserve the
            // bounded resume request queued for a local activation.
            if lastInputPreset != nil && (input.focus != nil || input.active || input.preparing) {
                inputAfterSwitch = nil
                automaticInputStart = nil
                input.stop()
            }
            lastInputPreset = activePreset
        }
        if !switching.busy, let active = model.active,
           let index = node.group.presets.firstIndex(where: { $0.id == active.id }), model.presetIndex != index {
            model.presetIndex = index
        }
        model.monitorResults = switching.results.mapValues { $0.state.rawValue.capitalized + ": " + $0.detail }
        model.monitorProblems = Set(switching.results.values.filter { $0.state == .failed }.map(\.monitor))
        if let selected = model.selected, !node.group.monitors.contains(where: { $0.id == selected }) { model.selected = node.group.monitors.first?.id }
        if model.selected == nil { model.selected = node.group.monitors.first?.id }
        startInputForActivePresetIfNeeded()
        objectWillChange.send()
    }
    /// One sentence of fact about keyboard and mouse control, never an instruction.
    private func inputStatus() -> String? {
        guard input.enabled else { return "Keyboard and mouse sharing is off on this Mac." }
        if let focus = input.focus, input.active {
            if focus.computer == node.localID { return "Control is on this Mac." }
            let screen = node.group.monitors.first { $0.id == focus.monitor }?.name ?? "a screen"
            let computer = node.group.computers.first { $0.id == focus.computer }?.name ?? "another Mac"
            return "Controlling \(screen) on \(computer)."
        }
        if input.preparing || input.settling { return "Handing off control…" }
        if let problem = input.problem { return problem }
        return "Sharing is on. Control is local."
    }
    private func pendingMatchCaution() -> String? {
        guard let active = switching.activePreset, let preset = node.group.presets.first(where: { $0.id == active }) else { return nil }
        let pending = preset.assignments.compactMap { assignment -> String? in
            guard let connection = node.group.connections.first(where: { $0.id == assignment.connection }), connection.computer != nil, connection.localDisplay == nil else { return nil }
            return node.group.monitors.first { $0.id == assignment.monitor }?.name
        }
        guard !pending.isEmpty else { return nil }
        return pending.joined(separator: ", ") + ": Perch has not seen this screen from that Mac yet, so the keyboard and mouse cannot follow the picture there. Switch to this input once and Perch will pick it up."
    }
    func activatePreset(_ preset: UUID) {
        if switching.busy && switching.request?.preset == preset { return }
        // Replaying the preset that is already active is an explicit request
        // to resend every input, even when cached state says nothing changed.
        let force = switching.activePreset == preset
        let included = node.group.presets.first { $0.id == preset }?.assignments.map(\.monitor) ?? []
        let preferred = input.focus?.monitor ?? model.selected
        // Release any current lease even when the new preset is not ready;
        // otherwise an invalid target leaves the old KVM route capturing input.
        automaticInputStart = nil
        input.allowAutomaticStart()
        input.stop()
        guard switching.readiness(preset) == nil else { switching.activate(preset, force: force); return }
        let monitor = preferred.flatMap { included.contains($0) ? $0 : nil } ?? included.first
        switching.activate(preset, force: force)
        if input.enabled, switching.busy, let monitor { inputAfterSwitch = (preset, monitor) }
    }
    func toggleInputSharing() {
        let enabled = !input.enabled
        inputAdapter.enable(enabled)
        if enabled { startInputForActivePreset() }
        DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.refreshDeskSharingMenu() }
    }
    var sharingShortcut: Shortcut { DeskSharingShortcut.load() }
    func saveSharingShortcut(_ value: Shortcut) {
        let previous = DeskSharingShortcut.load()
        do {
            try DeskSharingShortcut.save(value)
            registerShortcuts()
            guard sharingShortcutError == nil else { throw KVMError(sharingShortcutError!) }
        } catch {
            try? DeskSharingShortcut.save(previous)
            registerShortcuts()
            sharingShortcutError = error.localizedDescription
        }
    }
    /// The Share on this Mac menu item is the user's consent. Once a preset
    /// with a remote route is active, establish focus automatically instead
    /// of requiring a second hidden "Test remote control" action.
    func startInputForActivePreset() {
        startInputForActivePresetIfNeeded(force: true)
    }
    private func startInputForActivePresetIfNeeded(force: Bool = false) {
        // Each refusal is named: silence here is what made a two-VM run
        // impossible to diagnose. PerchLog.note repeats nothing, so this
        // stays quiet until the answer actually changes.
        guard input.enabled else { PerchLog.note("input.start", "keyboard and mouse sharing is off on this Mac"); return }
        guard !input.automaticStartSuppressed else { PerchLog.note("input.start", "automatic start is suppressed after a local-control exit"); return }
        guard !switching.busy else { PerchLog.note("input.start", "a monitor switch is still running"); return }
        guard let preset = switching.activePreset else { PerchLog.note("input.start", "no preset is active"); return }
        guard let saved = node.group.presets.first(where: { $0.id == preset }) else { PerchLog.note("input.start", "the active preset is not part of this desk"); return }
        let assignments = saved.assignments.compactMap { assignment -> (KVMAssignment, KVMConnection)? in
            guard let connection = node.group.connections.first(where: { $0.id == assignment.connection }) else { return nil }
            return (assignment, connection)
        }
        // Local-only presets should not capture and re-inject every event.
        guard assignments.contains(where: { $0.1.computer != nil && $0.1.computer != node.localID }) else {
            PerchLog.note("input.start", "the active preset has no other Mac in it"); return
        }
        // An automatic start never follows the editing selection: the screen
        // being edited is not where the user's hands are. Start on this Mac's
        // own screen, or wherever focus already is.
        let local = assignments.first(where: { $0.1.computer == node.localID })?.0.monitor
        let candidates = [input.focus?.monitor, local] + assignments.map { $0.0.monitor }
        // A handoff that is still settling is not "no focus"; requesting focus
        // again during it is what pulled the pointer back to a screen centre.
        guard input.focus == nil || !input.active else { PerchLog.note("input.start", "control is already active"); return }
        guard !input.settling else { PerchLog.note("input.start", "a handoff is still settling"); return }
        let offered = candidates.compactMap { $0 }
        guard let monitor = offered.first(where: { inputReadiness(preset: preset, monitor: $0) == nil }) else {
            let reason = offered.first.flatMap { inputReadiness(preset: preset, monitor: $0) } ?? "this preset has no screen to start on"
            PerchLog.note("input.start", "no screen is ready: " + reason); return
        }
        if let automaticInputStart,
           automaticInputStart.preset == preset,
           !force,
           ProcessInfo.processInfo.systemUptime - automaticInputStart.at < 2 { return }
        automaticInputStart = (preset, monitor, ProcessInfo.processInfo.systemUptime)
        PerchLog.note("input.start", "starting control on screen \(monitor)")
        input.start(preset: preset, monitor: monitor, automatic: !force)
    }
    func inputReadiness(preset: UUID, monitor: UUID) -> String? {
        guard node.group.monitors.contains(where: { $0.id == monitor }) else { return "Select a screen in Desk." }
        guard node.group.presets.first(where: { $0.id == preset })?.assignments.contains(where: { $0.monitor == monitor }) == true else {
            return "This screen is not included in the selected preset."
        }
        return input.readinessIssue(preset: preset, monitor: monitor)
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
    /// Send one monitor's command now, even if this input looks selected.
    /// Any input lease ends first: a route change must not keep capturing.
    func switchConnection(_ connection: UUID) {
        inputAfterSwitch = nil
        automaticInputStart = nil
        input.stop()
        switching.forceActivateConnection(connection)
    }
    /// Save a cable to a computer before its display identity is known, then
    /// try to complete it from what the desk already knows.
    func mapComputer(_ port: UUID, computer: UUID) {
        model.edit { try DeskCableBinding.apply(connection: port, computer: computer, display: nil, to: &$0) }
        resolvePendingDisplays(); refreshAllDisplays()
    }
    /// The panel aspect ratio every cable on this monitor agrees on, or nil.
    func panelAspect(_ monitor: UUID) -> Double? {
        let ratios = node.group.connections.filter { $0.monitor == monitor }.compactMap { cable -> Double? in
            guard let computer = cable.computer, let display = cable.localDisplay else { return nil }
            return displays[computer]?.first { $0.id == display }?.panelAspect
        }
        // Reports for the same physical monitor must agree before choosing automatically.
        guard let first = ratios.first, ratios.allSatisfy({ abs($0-first) < 0.02 }) else { return nil }
        return first
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
                    self.logDisplays(self.node.localID, self.displays[self.node.localID] ?? [])
                    self.resolvePendingDisplays(); self.publishDisplays()
                case .failure(let error):
                    self.discoveryProblem = "Could not refresh connected screens. " + error.localizedDescription
                    if let data = DeskDeviceMessage.displayProblem(String(self.discoveryProblem!.prefix(800))).wire {
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
            if let issue = peerActionReadiness(computer, action: "read monitor details") {
                completion?(.failure(KVMError(issue))); return
            }
            let message: DeskDeviceMessage
            var pendingToken: UUID?
            if let completion {
                let token = UUID()
                pendingToken = token
                pendingInspections[token] = .init(computer: computer, before: d, completion: completion)
                message = .inspectRequest(token, display)
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let pending = self?.pendingInspections.removeValue(forKey: token) else { return }
                    pending.completion(.failure(KVMError("The control computer did not finish detection. Check its connection and Perch version, then retry.")))
                }
            } else { message = .inspect(display) }
            if let data = message.wire, !node.sendApplication(data, peer: computer) {
                if let pendingToken { pendingInspections.removeValue(forKey: pendingToken) }
                completion?(.failure(KVMError("Perch could not reach this Mac. Reconnect it, then retry monitor details.")))
            }
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
        var resolved = DeskIdentityCableResolver.resolve(node.group, displays: displays.mapValues { values in
            values.map { .init(id: $0.id, vendor: $0.vendor, model: $0.model, serial: $0.serial) }
        })
        resolved = DeskPendingCableResolver.resolve(resolved, observations: observations)
        // Then the input each screen is actually showing, which is the only
        // evidence available for a cable no other Mac can see at the same time.
        resolved = DeskShowingCableResolver.resolve(resolved, showing: switching.effectiveInputs,
                                                    displays: displays.mapValues { $0.map(\.id) })
        guard resolved != node.group else { return }
        do { try node.edit(resolved) } catch { model.problem = error.localizedDescription }
    }
    /// What each Mac sees, written to the log whenever it changes. Every Mac
    /// already sends the others its display list; this makes it readable from
    /// any one Mac, so diagnosing a screen never needs a command run on another.
    private func logDisplays(_ computer: UUID, _ values: [DeskDetectedDisplay]) {
        let name = computer == node.localID ? "This Mac" : (node.group.computers.first { $0.id == computer }?.name ?? String(computer.uuidString.prefix(8)))
        let seen = values.isEmpty ? "no external displays" : values.map { display in
            "\(display.id.prefix(8)) \(display.name) (maker \(display.vendor), model \(display.model), serial \(display.serial), " +
            (display.canControl ? "takes monitor commands)" : "cannot take monitor commands)")
        }.joined(separator: "; ")
        PerchLog.note("desk.displays." + computer.uuidString.prefix(8), name + " sees: " + seen)
    }
    private func publishDisplays() {
        guard let data = DeskDeviceMessage.displays(displays[node.localID] ?? []).wire else { return }
        for peer in node.online where peer != node.localID { node.sendApplication(data, peer: peer) }
    }
    func refreshAllDisplays() {
        refreshDisplays()
        if let data = DeskDeviceMessage.refresh.wire { for peer in node.online where peer != node.localID { node.sendApplication(data, peer: peer) } }
    }
    private func receiveDevices(_ data: Data, peer: UUID) {
        guard data.count <= 64 * 1024, data.starts(with: DeskDeviceMessage.wirePrefix),
              let message = try? JSONDecoder().decode(DeskDeviceMessage.self, from: data.dropFirst(DeskDeviceMessage.wirePrefix.count)) else { return }
        switch message {
        case .displays(let values):
            guard values.allSatisfy(\.validInspectionMetadata) else { return }
            guard values.count <= 16, Set(values.map(\.id)).count == values.count,
                  values.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.name.isEmpty && $0.name.utf8.count <= 100 && $0.inputs.count <= 16 && $0.inputs.allSatisfy(\.valid) && $0.width.isFinite && $0.height.isFinite && (1...10000).contains($0.width) && (1...10000).contains($0.height) && ["standard", "lg"].contains($0.mode) }) else { return }
            guard values.allSatisfy({ $0.panelAspect.map { $0.isFinite && (0.1...10).contains($0) } ?? true }) else { return }
            guard values.allSatisfy({ value in [value.pointWidth, value.pointHeight].allSatisfy { $0.map { $0.isFinite && (1...100_000).contains($0) } ?? true } }) else { return }
            displays[peer] = values; remoteDisplayProblems[peer] = nil; logDisplays(peer, values); resolvePendingDisplays(); updateModel()
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
                if let data = reply.wire { self.node.sendApplication(data, peer: peer) }
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
        case .monitorIdentification(let monitor, let name, let token, let showing):
            applyMonitorIdentification(monitor, name: String(name.prefix(100)), token: token, showing: showing, broadcast: false)
        case .identifyAll(let name, let token, let showing): showAllIdentifications(name: String(name.prefix(100)), token: token, showing: showing)
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
            group.connections.append(.init(monitor: monitor, computer: nil, localDisplay: nil, inputName: port.name, inputCode: port.code, inputProtocol: port.command))
        }
        guard let i = group.connections.firstIndex(where: { $0.monitor == monitor && $0.inputCode == input }) else { throw KVMError("This input is not configured.") }
        guard group.connections[i].computer == nil || group.connections[i].computer == computer && group.connections[i].localDisplay == display else { throw KVMError("That input is already mapped. Correct its existing mapping first.") }
        group.connections[i].computer = computer; group.connections[i].localDisplay = display
        try node.edit(group); model.selected = monitor; node.problem = nil
    }
    private lazy var desktopHandoff = DeskDesktopHandoff(local: node.localID, group: { [unowned self] in self.node.group }, inputs: { [weak self] in self?.switching.desktopInputs ?? [:] }, optimisticInputs: { [weak self] in self?.switching.optimisticInputs ?? [:] }, online: { [weak self] in self?.node.online ?? [] }, suspended: { [weak self] in self?.node.canEdit != true })
    private func execute(_ recorded: KVMMonitorRoute, valid: @escaping () -> Bool, completion: @escaping (KVMMonitorOutcome.State, String) -> Void) {
        // The recorded display is only a hint. macOS renames displays, and a Mac
        // handed a monitor may never have had one recorded for it, so look at
        // this Mac's own displays right now and find the monitor by what it is.
        let identity = node.group.monitors.first { $0.id == recorded.monitor }?.identity
        var route = recorded
        if let identity {
            let seen = DeskLiveDisplays.current()
            if !seen.contains(where: { $0.id == recorded.control.localDisplay }),
               let found = DeskIdentityCableResolver.display(for: identity, among: seen) {
                PerchLog.record("switch.write", "Monitor \(recorded.monitor.uuidString.prefix(8)) found as display \(found.prefix(8)) on this Mac; its record said \(recorded.control.localDisplay.prefix(8))")
                route = KVMMonitorRoute(monitor: recorded.monitor, control: .init(computer: recorded.control.computer, localDisplay: found, mode: recorded.control.mode), input: recorded.input, force: recorded.force)
            }
        }
        desktopHandoff.hold(route.control.localDisplay)
        queue(route.control.localDisplay).async {
            // Reconnecting a handed-away display is a display transaction that
            // can block for seconds; it belongs here, not on the main thread.
            do { try self.desktopHandoff.restoreHeld(route.control.localDisplay) }
            catch {
                DispatchQueue.main.async { self.desktopHandoff.finishCommand(route.control.localDisplay); completion(.failed, error.localizedDescription) }
                return
            }
            let backend = MonitorDisplayBackend()
            let args = [route.control.localDisplay, route.control.mode]
            // An unanswered check cancels the write rather than stalling the switch.
            func allowed() -> Bool { DeskMainThreadGate.ask(timeout: 3) { valid() } ?? false }
            func read() throws -> UInt16? { try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["read"] + args)).current }
            var state = KVMMonitorOutcome.State.failed, detail = "The switch was cancelled before its monitor command."
            do {
                let outcome = try DeskMonitorCommand.run(input: route.input, permitted: allowed, read: read, write: {
                    let data = try backend.run(["switch"] + args + [String(route.input)])
                    guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["sent"] as? Bool == true else { throw KVMError("The monitor did not accept the input command.") }
                }, settle: { Thread.sleep(forTimeInterval: 0.2) }, pause: { Thread.sleep(forTimeInterval: 1.2) }, force: route.force)
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
        let targets = monitorIdentificationTargets(monitor)
        // A newly added cable can have no matched localDisplay yet. The
        // shared event still goes to every Perch; the control computer will
        // identify all of its visible displays so the user can establish the
        // match. Do not make stop/cancel depend on the current input owner.
        if targets.isEmpty && screen.control == nil {
            model.problem = "Choose this monitor’s control computer in Hardware before identifying it."
            return
        }
        let key = monitorIdentificationKey(monitor)
        let change = identifications.toggle(key)
        applyMonitorIdentification(monitor, name: screen.name, token: change.token, showing: change.showing, broadcast: true)
    }

    private func monitorIdentificationKey(_ monitor: UUID) -> String { "monitor:" + monitor.uuidString }

    /// Return every saved display route for this physical monitor. This is
    /// deliberately independent of the input currently selected on the
    /// monitor: identification is a group operation, not an input-owner
    /// operation.
    private func monitorIdentificationTargets(_ monitor: UUID) -> [(UUID, String)] {
        guard let screen = node.group.monitors.first(where: { $0.id == monitor }) else { return [] }
        var targets = node.group.connections.filter { $0.monitor == monitor }.compactMap { connection -> (UUID, String)? in
            guard let computer = connection.computer, let display = connection.localDisplay else { return nil }
            return (computer, display)
        }
        if let control = screen.control, !targets.contains(where: { $0.0 == control.computer && $0.1 == control.localDisplay }) {
            targets.append((control.computer, control.localDisplay))
        }
        return targets
    }

    /// Render a monitor identification locally and propagate the same token
    /// to every connected Perch. A peer receiving the event only renders it;
    /// it never rebroadcasts, so a stop from any Mac is one shared stop.
    private func applyMonitorIdentification(_ monitor: UUID, name: String, token: UUID, showing: Bool, broadcast: Bool) {
        let key = monitorIdentificationKey(monitor)
        identifications.apply(key, token: token, showing: showing)
        let targets = monitorIdentificationTargets(monitor)
        for (computer, display) in targets where computer == node.localID {
            showIdentification(display, name: name, token: token, showing: showing)
        }
        // If the control path is known but its cable has not been matched,
        // preserve the existing "identify all displays" behavior on that Mac.
        if let control = node.group.monitors.first(where: { $0.id == monitor })?.control,
           control.computer == node.localID, targets.isEmpty {
            showAllIdentifications(name: name, token: token, showing: showing)
        }
        if !showing {
            // A stop may arrive after a cable was edited. Close every window
            // carrying this shared token, even if its route is no longer in
            // the current graph or the monitor has a new current input.
            let displaysToHide = identifyWindows.compactMap { display, current in current.0 == token ? display : nil }
            for display in displaysToHide { showIdentification(display, name: name, token: token, showing: false) }
        }
        if broadcast, let bytes = DeskDeviceMessage.monitorIdentification(monitor, name, token, showing).wire {
            for peer in node.online where peer != node.localID { _ = node.sendApplication(bytes, peer: peer) }
        }
        model.objectWillChange.send(); objectWillChange.send()
        if showing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.identifications.expire(key, token: token) else { return }
                self.applyMonitorIdentification(monitor, name: name, token: token, showing: false, broadcast: true)
            }
        }
    }

    /// Re-send active monitor sessions to a peer after it reconnects. This
    /// keeps the settings UI and the stop action in sync even when a Mac was
    /// offline when the original start event was sent.
    private func syncActiveMonitorIdentifications() {
        for (key, token) in identifications.active {
            guard key.hasPrefix("monitor:"), let monitor = UUID(uuidString: String(key.dropFirst("monitor:".count))),
                  let screen = node.group.monitors.first(where: { $0.id == monitor }),
                  let bytes = DeskDeviceMessage.monitorIdentification(monitor, screen.name, token, true).wire else { continue }
            for peer in node.online where peer != node.localID { _ = node.sendApplication(bytes, peer: peer) }
        }
    }
    func identifyDetected(_ display: String, computer: UUID, name: String) {
        if let issue = peerActionReadiness(computer, action: "identify") {
            model.problem = issue
            return
        }
        if computer == node.localID && displays[computer]?.contains(where: { $0.id == display }) != true {
            model.problem = "This display is no longer connected to this Mac. Refresh connected screens, then identify it again."
            return
        }
        let key = computer.uuidString + "|" + display
        let change = identifications.toggle(key)
        if !sendIdentification(display, peer: computer, name: name, token: change.token, showing: change.showing) {
            _ = identifications.expire(key, token: change.token)
            let computerName = node.group.computers.first { $0.id == computer }?.name ?? "that Mac"
            model.problem = "Perch could not reach \(computerName). Reconnect it, then try Identify again."
            return
        }
        model.objectWillChange.send(); objectWillChange.send()
        if change.showing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.identifications.expire(key, token: change.token) else { return }
                _ = self.sendIdentification(display, peer: computer, name: name, token: change.token, showing: false)
                self.model.objectWillChange.send(); self.objectWillChange.send()
            }
        }
    }
    /// Shared readiness for actions relayed to another Perch. Membership can
    /// remain valid after a transport drops, so every caller checks the live
    /// trusted link rather than silently treating a send as successful.
    func peerActionReadiness(_ computer: UUID, action: String = "action") -> String? {
        guard node.group.computers.contains(where: { $0.id == computer }) else { return "That computer is no longer part of this desk." }
        if computer == node.localID { return nil }
        guard node.online.contains(computer), node.hasApplicationLink(to: computer) else {
            let name = node.group.computers.first { $0.id == computer }?.name ?? "that Mac"
            return "\(name) is not connected to this desk. Reconnect it, then try \(action) again."
        }
        return nil
    }
    func identifyComputer(_ computer: UUID, name: String? = nil) {
        if let issue = peerActionReadiness(computer, action: "Identify") {
            model.problem = issue
            return
        }
        let key = "computer:" + computer.uuidString
        let change = identifications.toggle(key)
        let label = name ?? (node.group.computers.first { $0.id == computer }?.name ?? "Which screen is this?")
        if !sendIdentifyAll(computer, name: label, token: change.token, showing: change.showing) {
            _ = identifications.expire(key, token: change.token)
            let computerName = node.group.computers.first { $0.id == computer }?.name ?? "that Mac"
            model.problem = "Perch could not reach \(computerName). Reconnect it, then try Identify again."
            return
        }
        model.objectWillChange.send(); objectWillChange.send()
        if change.showing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.identifications.expire(key, token: change.token) else { return }
                _ = self.sendIdentifyAll(computer, name: label, token: change.token, showing: false)
                self.model.objectWillChange.send(); self.objectWillChange.send()
            }
        }
    }
    @discardableResult private func sendIdentification(_ display: String, peer: UUID, name: String, token: UUID, showing: Bool) -> Bool {
        if peer == node.localID { showIdentification(display, name: name, token: token, showing: showing); return true }
        else if let bytes = DeskDeviceMessage.identification(display, name, token, showing).wire { return node.sendApplication(bytes, peer: peer) }
        return peer == node.localID
    }
    private func sendIdentifyAll(_ computer: UUID, name: String, token: UUID, showing: Bool) -> Bool {
        if computer == node.localID { showAllIdentifications(name: name, token: token, showing: showing); return true }
        guard let bytes = DeskDeviceMessage.identifyAll(name, token, showing).wire else { return false }
        return node.sendApplication(bytes, peer: computer)
    }
    private func showAllIdentifications(name: String, token: UUID, showing: Bool) {
        if !showing {
            let displaysToHide = identifyWindows.compactMap { display, current in current.0 == token ? display : nil }
            for display in displaysToHide {
                identifyWindows[display]?.1.orderOut(nil); identifyWindows[display] = nil
            }
            return
        }
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let display = displayID(for: screen) else { continue }
            let screenName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            showIdentification(display, name: "\(name) · \(screenName)", token: token, showing: true)
        }
    }
    private func displayID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    private func showIdentification(_ display: String, name: String, token: UUID, showing: Bool) {
        if !showing {
            if let (current, window) = identifyWindows[display], current == token { window.orderOut(nil); identifyWindows[display] = nil }
            return
        }
        guard !SettingsWindow.shared.testing, let screen = NSScreen.screens.first(where: { displayID(for: $0) == display }) else { return }
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
        try DeskMonitorConfiguration.apply(monitor: monitor, profile: profile.name, ports: profile.inputs.map { .init(name: $0.name, code: $0.code, command: $0.command) }, mode: profile.alternate ? "lg" : "standard", to: &group)
        try node.edit(group)
    }
    /// Register every Desk shortcut this Mac owns as one change. A shortcut
    /// another Perch action already uses, or one macOS refuses, is reported
    /// and the previously working set stays registered.
    func registerShortcuts() {
        guard !SettingsWindow.shared.testing else { return }
        let registry = ShortcutRegistry.perch
        let claims = registry.claims(excluding: ShortcutRegistry.Source.deskPresets)
        let presets = node.group.presets
        guard shortcutMemory.needsRegistration(claims: claims, presets: presets) else { return }
        let plan = DeskShortcutPlan.make(presets: presets, sharing: DeskSharingShortcut.load()) { registry.problem(with: $0, excluding: $1) }
        presetHotKeys = presetHotKeys.filter { id, _ in presets.contains { $0.id == id } }
        var presetProblem = plan.presetProblem, sharingProblem = plan.sharingProblem
        // Presets and sharing register separately so each problem is shown on
        // its own shortcut; each set keeps its previous registration on failure.
        if presetProblem == nil {
            let changes = plan.presets.map { binding -> (hotKey: HotKey, shortcut: Shortcut) in
                let hotKey = presetHotKeys[binding.preset] ?? HotKey()
                presetHotKeys[binding.preset] = hotKey
                let preset = binding.preset
                hotKey.action = { [weak self] in
                    let name = self?.node.group.presets.first { $0.id == preset }?.name ?? "a preset"
                    PerchLog.record("switch.hotkey", "Shortcut for \(name) pressed on this Mac")
                    self?.activatePreset(preset)
                }
                return (hotKey, binding.shortcut)
            }
            do { try HotKey.register(changes) } catch { presetProblem = error.localizedDescription }
        }
        if sharingProblem == nil {
            sharingHotKey.action = { [weak self] in self?.toggleInputSharing() }
            do { try HotKey.register([(sharingHotKey, plan.sharing)]) } catch { sharingProblem = error.localizedDescription }
        }
        shortcutProblem = presetProblem
        sharingShortcutError = sharingProblem
        PerchLog.note("shortcut.register", presetProblem.map { "Preset shortcuts not registered: " + $0 } ?? "Preset shortcuts registered: " + plan.presets.map { $0.shortcut.title }.joined(separator: ", "))
        shortcutMemory.finished(claims: claims, presets: presets, succeeded: presetProblem == nil && sharingProblem == nil)
    }
}

final class DeskCoordinator: ObservableObject {
    static let shared = DeskCoordinator()
    static var storage: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Desk/desk.json") }
    @Published var runtime: DeskRuntime?
    @Published var problem: String?
    /// Deliberate process exit: stop input sharing and the transport so peers
    /// receive a "Perch stopped" close and the activity log is flushed.
    func shutdown() {
        guard let runtime else { return }
        runtime.stop(); self.runtime = nil
    }
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
            if DeskInputAdapter.sharingEnabledByDefault {
                runtime.inputAdapter.enable(true)
                runtime.startInputForActivePreset()
            }
        } catch { problem = error.localizedDescription }
    }
}


/// This Mac's external displays as macOS sees them this instant, read in-process
/// from CoreGraphics: fast enough for the main thread, and never a stored ID.
enum DeskLiveDisplays {
    static func current() -> [DeskIdentityCableResolver.Display] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return .init(id: CFUUIDCreateString(nil, uuid) as String, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
    }
}
