import Foundation
import SwiftUI

func runDeskInspectionTests() throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw KVMError(message) }
    }
    func fixture(id: String = UUID().uuidString, vendor: UInt32 = 7789, serial: UInt32 = 0) -> DeskDetectedDisplay {
        DeskDetectedDisplay(id: id, name: "LG HDR 4K", vendor: vendor, model: 7706, serial: serial,
            width: 600, height: 340, canControl: true, inputs: [.init(code: 17, name: "HDMI 1"), .init(code: 210, name: "USB-C")], mode: "lg")
    }
    let generic = fixture()
    try check(generic.portOptions(choice: "").isEmpty, "Unverified seed ports were presented as monitor-reported ports")
    var detected = generic
    detected.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0x5124))
    let suggested = detected.profile(choice: "")
    try check(detected.portOptions(choice: "").contains { $0.code == 209 }, "Firmware-suggested controls disappeared from port choices")
    try check(detected.portOptions(choice: DeskDetectedDisplay.reportedInputsChoice).isEmpty, "Use reported ports silently reused guessed or profile ports")
    try check(suggested?.inputs.contains(where: { $0.code == 209 }) == true && suggested?.inputs.contains(where: { $0.code == 210 }) == false,
              "Desk lost the owner-evidenced USB-C 209 profile behind generic LG identity")
    let manual = MonitorProfiles.entries.first { $0.vendor == 7789 && $0.name != suggested?.name }!
    try check(detected.profile(choice: manual.name)?.name == manual.name && detected.profile(choice: DeskDetectedDisplay.reportedInputsChoice) == nil,
              "Asynchronous identity replaced a manual choice or explicit detected-input choice")
    try check(detected.inputs == generic.inputs, "A firmware suggestion rewrote detected inputs")
    var refreshed = generic; refreshed.retainIdentity(from: detected)
    try check(refreshed.profile(choice: "")?.name == suggested?.name, "Routine refresh erased the firmware suggestion")
    var replaced = fixture(id: generic.id, serial: 22); replaced.retainIdentity(from: detected)
    try check(replaced.firmwareFamily == nil && !replaced.sameDevice(as: detected), "A replacement device inherited another display's identity")
    var exact = generic; exact.matchedProfileName = "LG 27UP850-W"
    try check(exact.profile(choice: "")?.name == "LG 27UP850-W", "Exact model match was lost between discovery and Desk setup")
    let bytes = try JSONEncoder().encode(DeskDeviceMessage.displays([detected]))
    guard case .displays(let remote) = try JSONDecoder().decode(DeskDeviceMessage.self, from: bytes) else { throw KVMError("Missing peer display metadata") }
    try check(remote.first?.profile(choice: "")?.name == suggested?.name, "Remote setup lost firmware profile evidence")
    let monitorID = UUID(), session = UUID()
    let identificationBytes = try JSONEncoder().encode(DeskDeviceMessage.monitorIdentification(monitorID, "Shared screen", session, true))
    guard case .monitorIdentification(let receivedMonitor, let receivedName, let receivedSession, let showing) = try JSONDecoder().decode(DeskDeviceMessage.self, from: identificationBytes) else { throw KVMError("Shared monitor identification event could not be decoded") }
    try check(receivedMonitor == monitorID && receivedName == "Shared screen" && receivedSession == session && showing, "Shared monitor identification lost its monitor or session identity")
    var extended = generic; extended.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0xc000, lgExtendedIdentity: 1))
    try check(extended.profile(choice: "")?.name == "LG 27UP850-W", "Extended firmware ID not used by Desk")
    for identity in [nil, 0x0124, 0xffff] as [UInt16?] {
        var unknown = detected; unknown.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: identity))
        try check(unknown.profile(choice: "") == nil && unknown.profile(choice: manual.name)?.name == manual.name, "Unknown firmware prevented manual setup or retained an old suggestion")
    }
    var otherVendor = fixture(vendor: 1)
    otherVendor.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0x5124))
    try check(otherVendor.firmwareFamily == nil && otherVendor.profile(choice: suggested!.name) == nil, "LG identity applied to another vendor")

    // Exercise the real add-screen transaction using disposable storage; never start the node or hardware adapter.
    let previousTesting = SettingsWindow.shared.testing; SettingsWindow.shared.testing = true
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-desk-inspection-" + UUID().uuidString)
    defer { SettingsWindow.shared.testing = previousTesting; try? FileManager.default.removeItem(at: root) }
    let node = try KVMDeskNode(identity: .fresh(), name: "Inspection fixture", storage: root.appendingPathComponent("desk.json"))
    let runtime = DeskRuntime(node: node)
    defer { runtime.stop() }
    runtime.displays[node.localID] = [detected]
    try runtime.addScreen(name: "My LG", existing: nil, computer: node.localID, display: detected.id, input: 209, profile: suggested)
    try check(node.group.connections.contains { $0.inputCode == 209 && $0.computer == node.localID } && node.group.monitors.first?.control?.mode == "lg",
              "Suggested profile failed to save the chosen port and LG control protocol")
    let saved = node.group
    var second = fixture(); second.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0x5124))
    runtime.displays[node.localID] = [second]
    try check(runtime.suggestedScreens(computer: node.localID, display: second).isEmpty, "Firmware family was treated as a unique physical screen")
    try runtime.addScreen(name: "Another LG", existing: nil, computer: node.localID, display: second.id, input: 209, profile: suggested)
    try check(node.group.monitors.count == 2 && node.group.monitors.first == saved.monitors.first && node.group.connections.filter { $0.monitor == saved.monitors[0].id } == saved.connections,
              "Adding an identical model changed an existing screen or its mappings")
    print("PASS: Desk firmware profile suggestions, manual/unknown/vendor cases, peer metadata, refresh identity, persisted LG port/protocol and distinct identical screens; no hardware access")
}

/// Model-only detection/control checks: no windows, runtime adapters or hardware.
func runDeskProfilePolicyTests() throws {
    try runDeskDesktopTests()
    func check(_ value: Bool, _ message: String) throws { if !value { throw KVMError(message) } }
    var group = KVMGroup.sample()
    let monitor = group.monitors[0].id, cable = group.connections[0]
    group.monitors[0].control = .init(computer: cable.computer!, localDisplay: cable.localDisplay!)
    let detected = Set(group.connections.compactMap { c in c.computer.flatMap { host in c.localDisplay.map { host.uuidString + "|" + $0 } } })
    let paths = DeskControlPaths.options(group: group, monitor: monitor, detected: detected)
    try check(paths.count == 2 && paths.contains { $0.label.contains("USB-C") } && paths.contains { $0.label.contains("DisplayPort") }, "Same-monitor paths need computer/port labels")
    try check(!paths.contains { $0.display == group.connections[3].localDisplay }, "Another physical monitor leaked into control choices")
    var offline = group
    offline.connections.removeAll { $0.monitor == monitor }
    let pending = DeskControlPaths.options(group: offline, monitor: monitor, detected: [])
    try check(pending.count == 1 && pending[0].label.contains("Port not mapped") && pending[0].label.contains("not currently detected"), "Saved control path must survive offline/missing port metadata honestly")
    var incorrect = group
    incorrect.monitors[0].control = .init(computer: group.connections[3].computer!, localDisplay: group.connections[3].localDisplay!)
    try check(DeskControlPaths.options(group: incorrect, monitor: monitor, detected: detected).count == 2, "Saved path to another monitor must not become a valid option")
    var record = DeskDetectedDisplay(id: UUID().uuidString, name: "LG HDR 4K", vendor: 7789, model: 7706, serial: 0,
                                    width: 600, height: 340, canControl: true, inputs: [], mode: "lg")
    record.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0x5124))
    guard case .profile(let profile) = record.inputDetection else { throw KVMError("Known family did not select an evidenced profile") }
    try check(profile.inputs.contains { $0.code == 209 }, "Known firmware lost its input codes")
    record.applyInspection(.init(current: nil, capabilities: "(vcp(60(11 12)))", lgIdentity: nil))
    guard case .reported(let ports) = record.inputDetection else { throw KVMError("Reported capabilities were not usable without a named profile") }
    try check(ports.map(\.code) == [17, 18], "Reported input codes changed")
    record.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: nil))
    guard case .unknown = record.inputDetection else { throw KVMError("Unknown detection reused stale ports/profile") }
    try DeskMonitorConfiguration.apply(monitor: monitor, profile: profile.name, ports: profile.inputs.map { .init(name: $0.name, code: $0.code) }, mode: "lg", to: &group)
    group.monitors[0].control?.mode = "standard"
    let restored = try JSONDecoder().decode(KVMGroup.self, from: JSONEncoder().encode(group))
    try check(restored.monitors[0].defaultControlMode == "lg" && restored.monitors[0].inputProfile == profile.name, "Override lost the monitor's original protocol/profile")
    let realCaps = "(prot(monitor)type(lcd)UP850Kcmds(01 02 03)vcp(60(11 12 0F 00)))"
    record.applyInspection(.init(current: nil, capabilities: realCaps, lgIdentity: 0xc024, lgExtendedIdentity: 116))
    try check(record.reportedModel == "UP850K" && record.identityConflict, "Observed UP850K model or conflicting firmware identity lost")
    try check(record.reportedPorts?.map(\.code) == [15, 17, 18] && record.reportedPortMode == "standard", "Reserved zero discarded usable inputs or mixed standard codes with LG protocol")
    var refreshed = DeskDetectedDisplay(id: record.id, name: record.name, vendor: record.vendor, model: record.model, serial: record.serial, width: record.width, height: record.height, canControl: true, inputs: [], mode: "standard")
    refreshed.retainIdentity(from: record)
    try check(refreshed.reportedModel == "UP850K" && refreshed.identityConflict, "Periodic refresh lost detected identity")
    try check(refreshed.displayLabel == "UP850K" && refreshed.validInspectionMetadata, "The actual model must be visible and valid")
    var malformed = refreshed; malformed.reportedModel = String(repeating: "x", count: 81)
    try check(!malformed.validInspectionMetadata, "Oversized remote model accepted")
    malformed = refreshed; malformed.reportedPortMode = "untrusted-protocol"
    try check(!malformed.validInspectionMetadata, "Invalid remote port protocol accepted")
    record.applyInspection(.init(current: nil, capabilities: "(model(27UP850-W)vcp(60(11 12)))"))
    try check(record.profile(choice: "")?.name == "LG 27UP850-W", "Capability model was ignored when choosing a profile")
    try check(MonitorCapabilities.model("(type(lcd)cmds(01)vcp(60(11)))") == nil, "Invented missing model")
    let token = UUID(), message = DeskDeviceMessage.inspectionReply(token, record, nil)
    guard case .inspectionReply(let roundTripToken, let roundTripRecord, _) = try JSONDecoder().decode(DeskDeviceMessage.self, from: JSONEncoder().encode(message)) else { throw KVMError("Detection reply lost its identity") }
    try check(roundTripToken == token && roundTripRecord == record, "Detection replies must retain the specific request and display")
    print("PASS: scoped control paths, port/offline labels, wrong-monitor exclusion, profile/capability/unknown detection, protocol default persistence and reply correlation payload")
    try runDeskPresetGraphTests()
}

/// Records what the page asks of the desk, so claiming an input after a drawn
/// wire is proven to reach the backend.
private final class WiringBackend: DeskBackend {
    let wording = DeskWording.live
    var claimed: [(UUID, UUID)] = []
    func edit(_ group: KVMGroup) throws {}
    func activate(preset: UUID) {}
    func readiness(preset: UUID) -> String? { nil }
    func retryActive() {}
    func revertSwitch() {}
    func switchConnection(_ connection: UUID) {}
    func mappingOptions() -> [DeskMappingOption] { [] }
    func map(port: UUID, option: String) {}
    func mapComputer(port: UUID, computer: UUID) { claimed.append((port, computer)) }
    func displayStatus(computer: UUID) -> String? { nil }
    func refreshScreens() {}
    func panelAspect(monitor: UUID) -> Double? { nil }
    func identify(monitor: UUID?) {}
    func identifyDisplay(_ display: String, computer: UUID) {}
    func identifyComputer(_ computer: UUID) {}
    func isIdentifying(monitor: UUID) -> Bool { false }
    func isIdentifying(display: String, computer: UUID) -> Bool { false }
    func isIdentifying(computer: UUID) -> Bool { false }
    func peerActionReadiness(computer: UUID, action: String) -> String? { nil }
    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView? { nil }
}

/// The Desk graph's wiring rules, as Scott set them: a drag from a computer always
/// creates a connection and claims the input; an unconnected input draws toward a
/// computer; a connected input detaches to be rewired; a detached end dropped in
/// empty space disappears. Also clearing one preset and resetting the desk.
func runDeskPresetGraphTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw KVMError(message) } }
    let portID = UUID(), otherID = UUID(), computerID = UUID()
    let connector = "preset:\(computerID.uuidString):2", socket = "port:\(portID.uuidString)", otherSocket = "port:\(otherID.uuidString)"
    func outcome(_ source: String, _ target: String?, dragging: Bool = true, inside: Bool = false, detached: UUID? = nil) -> DeskWireOutcome {
        DeskWireOutcome.resolve(source: source, target: target, dragging: dragging, insideSource: inside, detached: detached)
    }
    try check(outcome(connector, socket) == .draw(slot: 2, computer: computerID, port: portID), "A drag from a computer did not create a connection")
    try check(outcome(socket, connector) == .draw(slot: 2, computer: computerID, port: portID), "An unconnected input could not draw a wire to a computer")
    try check(outcome(connector, nil) == .nothing && outcome(socket, nil) == .nothing, "A new wire dropped in empty space was kept")
    try check(outcome(socket, otherSocket, detached: portID) == .move(from: portID, to: otherID), "A detached connection did not move to another input")
    try check(outcome(socket, nil, detached: portID) == .remove(port: portID), "A detached connection dropped in empty space did not disappear")
    try check(outcome(socket, socket, inside: true, detached: portID) == .nothing, "Dropping a connection back on its own input changed it")
    try check(outcome(socket, nil, dragging: false, inside: true, detached: portID) == .click && outcome(connector, nil, dragging: false, inside: true) == .click,
              "A click on a connector or input did not open its menu")
    try check(outcome("preset:\(computerID.uuidString):4", socket) == .nothing, "A connector outside the three preset slots drew a wire")

    let sample = KVMGroup.sample()
    let mac = sample.computers[0].id, studio = sample.computers[1].id
    let left = sample.monitors[0].id, main = sample.monitors[1].id, side = sample.monitors[2].id
    func port(_ group: KVMGroup, _ monitor: UUID, _ computer: UUID?) -> KVMConnection {
        group.connections.first { $0.monitor == monitor && $0.computer == computer }!
    }
    func routes(_ group: KVMGroup, to id: UUID) -> [Int] {
        group.presets.indices.filter { index in group.presets[index].assignments.contains { $0.connection == id } }
    }

    // Drawing onto a free input routes it; the page then claims it for that computer.
    let backend = WiringBackend(), model = DeskModel(backend: backend, group: sample)
    let free = port(sample, left, nil)
    model.drawWire(slot: 2, computer: mac, port: free.id)
    try check(model.problem == nil && model.group.presets[1].assignments.contains { $0.monitor == left && $0.connection == free.id } && routes(model.group, to: free.id) == [1],
              "A wire onto a free input did not route it in that preset: \(model.problem ?? "")")
    DeskPageState().beginCable(free.id, mac, model: model)
    try check(backend.claimed.count == 1 && backend.claimed[0] == (free.id, mac), "The drawn input was not claimed for its computer, so the wire would stay invisible")

    // Drawing onto another computer's input replaces that connection and its routes.
    let taken = port(sample, main, studio)
    try check(routes(sample, to: taken.id) == [0, 2], "Fixture changed: the Studio's main input should be in presets 1 and 3")
    model.drawWire(slot: 2, computer: mac, port: taken.id)
    let replaced = model.group.connections.first { $0.id == taken.id }!
    try check(replaced.computer == nil && replaced.localDisplay == nil && routes(model.group, to: taken.id) == [1],
              "A new connection did not replace the other computer's connection and routes")

    // Moving a wire onto an input with nothing plugged into it moves the cable,
    // so the presets that used that cable follow it instead of pointing at an
    // empty input. The preset being edited uses the input it was dropped on.
    let moving = DeskModel(backend: WiringBackend(), group: sample)
    moving.presetIndex = 1
    let from = port(sample, left, studio), to = port(sample, left, nil)
    try check(routes(sample, to: from.id) == [0, 2], "Fixture changed: the Studio's left input should be in presets 1 and 3")
    moving.moveWire(from: from.id, to: to.id)
    let moved = moving.group.connections.first { $0.id == to.id }!, emptied = moving.group.connections.first { $0.id == from.id }!
    try check(moving.problem == nil && moved.computer == studio && emptied.computer == nil &&
              routes(moving.group, to: to.id) == [0, 1, 2] && routes(moving.group, to: from.id).isEmpty,
              "A moved cable did not take the preset being edited and the presets that used it: \(moving.problem ?? "")")

    // When that computer is already connected to the input it is dropped on,
    // no cable moves, so only the preset being edited changes.
    var second = sample
    let spare = second.connections.firstIndex { $0.id == to.id }!
    second.connections[spare].computer = studio
    let inPlace = DeskModel(backend: WiringBackend(), group: second)
    inPlace.presetIndex = 1
    inPlace.moveWire(from: from.id, to: to.id)
    try check(inPlace.problem == nil && inPlace.group.connections.first { $0.id == from.id }?.computer == studio &&
              routes(inPlace.group, to: to.id) == [1] && routes(inPlace.group, to: from.id) == [0, 2],
              "Moving between two inputs the same computer is plugged into changed other presets: \(inPlace.problem ?? "")")

    // A wire dropped in empty space leaves the preset being edited. The cable is
    // unplugged only once no preset uses that input.
    let removing = DeskModel(backend: WiringBackend(), group: sample)
    let gone = port(sample, side, mac)
    try check(routes(sample, to: gone.id) == [0, 1], "Fixture changed: the MacBook's portrait input should be in presets 1 and 2")
    removing.presetIndex = 0
    removing.removeWire(gone.id)
    try check(removing.problem == nil && routes(removing.group, to: gone.id) == [1] && removing.group.connections.first { $0.id == gone.id }?.computer == mac,
              "Dropping a wire in space cleared a preset that was not being edited, or unplugged a cable still in use")
    removing.presetIndex = 1
    removing.removeWire(gone.id)
    try check(removing.group.connections.first { $0.id == gone.id }?.computer == nil && routes(removing.group, to: gone.id).isEmpty,
              "The last preset using an input left its cable plugged in")

    // Clearing one preset leaves the others and every input alone.
    let clearing = DeskModel(backend: WiringBackend(), group: sample)
    clearing.clearPreset(1)
    try check(clearing.group.presets[1].assignments.isEmpty && clearing.group.presets[0] == sample.presets[0] && clearing.group.presets[2] == sample.presets[2] && clearing.group.connections == sample.connections,
              "Clearing a preset changed something other than that preset")

    // Resetting the desk starts screens, inputs and routes over but keeps the paired Macs.
    let resetting = DeskModel(backend: WiringBackend(), group: sample)
    resetting.resetLayout()
    try check(resetting.problem == nil && resetting.group.monitors.isEmpty && resetting.group.connections.isEmpty && resetting.group.presets.allSatisfy { $0.assignments.isEmpty } &&
              resetting.group.computers == sample.computers && resetting.group.presets.map(\.name) == sample.presets.map(\.name),
              "Resetting the desk did not start the layout over while keeping paired Macs: \(resetting.problem ?? "")")
    print("PASS: desk wiring rules: computer drags always connect and claim the input, free inputs draw to a computer, connected inputs detach and change the preset being edited, cables move only when they must; clear preset and reset desk")
    try runDeskInputListTests()
}

/// Changing a screen's input list replaces it rather than stacking ports. This
/// replays Scott's Home LG New: set up with the LG profile, then switched to the
/// monitor's reported inputs, which left two DisplayPorts and a USB-C input
/// still carrying its LG code under the standard protocol.
func runDeskInputListTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw KVMError(message) } }
    let lg: [DeskPortDefinition] = [.init(name: "HDMI 1", code: 144), .init(name: "HDMI 2", code: 145), .init(name: "DisplayPort", code: 208), .init(name: "USB-C", code: 209)]
    let reported: [DeskPortDefinition] = [.init(name: "HDMI 1", code: 17), .init(name: "HDMI 2", code: 18), .init(name: "DisplayPort 1", code: 15)]
    var group = KVMGroup.sample()
    let mac = group.computers[0].id, studio = group.computers[1].id, screen = group.monitors[0].id
    let usb = group.connections.first { $0.monitor == screen && $0.computer == mac }!
    let displayPort = group.connections.first { $0.monitor == screen && $0.computer == studio }!
    group.monitors[0].control = .init(computer: mac, localDisplay: usb.localDisplay!)
    func inputs(_ g: KVMGroup) -> [String: UInt16?] {
        Dictionary(uniqueKeysWithValues: g.connections.filter { $0.monitor == screen }.map { ($0.inputName, $0.inputCode) })
    }

    try DeskMonitorConfiguration.apply(monitor: screen, profile: "LG", ports: lg, mode: "lg", to: &group)
    try check(inputs(group) == ["HDMI 1": 144, "HDMI 2": 145, "DisplayPort": 208, "USB-C": 209] && group.connections.first { $0.id == usb.id }?.computer == mac,
              "The LG profile did not become the screen's inputs while keeping its cables: \(inputs(group))")

    // Reported inputs have no USB-C and use the other protocol, so the Mac's cable would stop switching.
    let lgSetup = group
    do {
        try DeskMonitorConfiguration.apply(monitor: screen, profile: "Reported", ports: reported, mode: "standard", to: &group)
        throw KVMError("Switching protocol stranded the USB-C input the MacBook uses")
    } catch let error as KVMError where error.localizedDescription.contains("USB-C") && error.localizedDescription.contains("MacBook Pro") {}
    try check(group == lgSetup, "A refused input list partly changed the screen")

    // Without that cable, the change goes through: DisplayPort carries over to DisplayPort 1 with its cable and routes, and nothing is left behind.
    for p in group.presets.indices { group.presets[p].assignments.removeAll { $0.connection == usb.id } }
    try DeskCableBinding.apply(connection: usb.id, computer: nil, display: nil, to: &group)
    let routesBefore = group.presets.map { $0.assignments.filter { $0.connection == displayPort.id } }
    try DeskMonitorConfiguration.apply(monitor: screen, profile: "Reported", ports: reported, mode: "standard", to: &group)
    let carried = group.connections.first { $0.id == displayPort.id }
    try check(inputs(group) == ["HDMI 1": 17, "HDMI 2": 18, "DisplayPort 1": 15], "Changing the input list stacked or kept old inputs: \(inputs(group))")
    try check(carried?.computer == studio && carried?.localDisplay == displayPort.localDisplay && group.presets.map { $0.assignments.filter { $0.connection == displayPort.id } } == routesBefore,
              "DisplayPort did not carry its cable and preset routes over to DisplayPort 1")

    // Scott's saved state repairs by choosing the LG profile again.
    var saved = lgSetup
    saved.monitors[0].control?.mode = "standard"; saved.monitors[0].defaultControlMode = "standard"
    saved.connections.removeAll { $0.monitor == screen }
    saved.connections += [.init(monitor: screen, computer: nil, localDisplay: nil, inputName: "HDMI 1", inputCode: 17),
                          .init(monitor: screen, computer: nil, localDisplay: nil, inputName: "HDMI 2", inputCode: 18),
                          .init(monitor: screen, computer: nil, localDisplay: nil, inputName: "DisplayPort", inputCode: 208),
                          .init(id: usb.id, monitor: screen, computer: mac, localDisplay: usb.localDisplay, inputName: "USB-C", inputCode: 209),
                          .init(monitor: screen, computer: nil, localDisplay: nil, inputName: "DisplayPort 1", inputCode: 15)]
    for p in saved.presets.indices { saved.presets[p].assignments.removeAll { $0.monitor == screen } }
    saved.presets[1].assignments.append(.init(monitor: screen, connection: usb.id))
    try DeskMonitorConfiguration.apply(monitor: screen, profile: "LG", ports: lg, mode: "lg", to: &saved)
    try check(inputs(saved) == ["HDMI 1": 144, "HDMI 2": 145, "DisplayPort": 208, "USB-C": 209] && saved.monitors[0].control?.mode == "lg" &&
              saved.connections.first { $0.id == usb.id }?.computer == mac && saved.presets[1].assignments.contains { $0.connection == usb.id },
              "Choosing the LG profile again did not repair the stacked inputs: \(inputs(saved))")
    // Matching the cable Perch can see showing. Scott's desk: the Studio feeds
    // Home screen 2 on HDMI 2, the MacBook cannot see that monitor while it is
    // showing the Studio, so no cross-Mac comparison can ever match it.
    var desk = KVMGroup.sample()
    let studioMac = desk.computers[1].id, showingScreen = desk.monitors[1].id
    let studioPort = desk.connections.first { $0.monitor == showingScreen && $0.computer == studioMac }!
    let portIndex = desk.connections.firstIndex { $0.id == studioPort.id }!
    desk.connections[portIndex].localDisplay = nil
    desk.connections[portIndex].inputCode = 145
    let showing = [showingScreen: UInt16(145)]
    let matchedDesk = DeskShowingCableResolver.resolve(desk, showing: showing, displays: [studioMac: ["studio-hdmi-2"]])
    try check(matchedDesk.connections.first { $0.id == studioPort.id }?.localDisplay == "studio-hdmi-2",
              "The one display the showing computer reports was not matched to the input it is showing")
    // Perch never guesses between two unused displays, and never steals one
    // that another input on that Mac already uses.
    let ambiguous = DeskShowingCableResolver.resolve(desk, showing: showing, displays: [studioMac: ["one", "two"]])
    try check(ambiguous == desk, "Two possible displays were guessed between")
    var taken = desk
    let otherIndex = taken.connections.firstIndex { $0.computer == studioMac && $0.id != studioPort.id }!
    taken.connections[otherIndex].localDisplay = "studio-hdmi-2"
    try check(DeskShowingCableResolver.resolve(taken, showing: showing, displays: [studioMac: ["studio-hdmi-2"]]) == taken,
              "A display another input already uses was matched again")
    // A recorded display that Mac no longer has is replaced by the one it does,
    // which is how a USB-C-to-HDMI adapter's re-enumerated display heals even
    // when the adapter hides the monitor's own model.
    var stale = desk
    stale.connections[portIndex].localDisplay = "adapter-before-sleep"
    let restored = DeskShowingCableResolver.resolve(stale, showing: showing, displays: [studioMac: ["adapter-after-wake"]])
    try check(restored.connections.first { $0.id == studioPort.id }?.localDisplay == "adapter-after-wake",
              "A display renamed behind an adapter was not replaced while its screen showed that Mac")
    try check(DeskShowingCableResolver.resolve(stale, showing: showing, displays: [studioMac: ["adapter-before-sleep"]]) == stale,
              "A recorded display that Mac still has was replaced")
    try check(DeskShowingCableResolver.resolve(stale, showing: showing, displays: [:]) == stale,
              "A Mac with no display report had its record replaced")
    // A screen showing an input with no computer stays as it is.
    let unassigned = desk.connections.first { $0.computer == nil }!
    try check(DeskShowingCableResolver.resolve(desk, showing: [unassigned.monitor: unassigned.inputCode ?? 0], displays: [studioMac: ["studio-hdmi-2"]]) == desk,
              "An input with no computer was given a display")

    // The two screens on this desk, identified by their EDID products and set up
    // with the LG codes proven on them, so a fresh setup needs no hand editing.
    let lgCodes: [String: UInt16] = ["HDMI 1": 144, "HDMI 2": 145, "DisplayPort": 208, "USB-C": 209]
    for (model, token, name) in [(UInt32(23741), "UP850K", "LG 27UP850-W · UP850K firmware"), (UInt32(30471), "UL850", "LG 27UL850-W · UL850 firmware")] {
        let screen = MonitorDescriptor(id: UUID().uuidString, displayID: 0, name: "LG", vendor: 7789, model: model, ddcAvailable: true)
        let byProduct = MonitorProfiles.match(screen), byToken = MonitorProfiles.match(screen, reportedModel: token)
        try check(byProduct?.name == name && byToken?.name == name, "\(name) was not chosen for its screen: \(byProduct?.name ?? "none")")
        guard let tested = byProduct else { continue }
        try check(tested.confidence == "locally-tested" && tested.alternate && tested.readbackUnavailable == true,
                  "\(name) is not the tested LG-command profile without readback")
        try check(Dictionary(uniqueKeysWithValues: tested.inputs.map { ($0.name, $0.code) }) == lgCodes && tested.inputs.allSatisfy { $0.command == nil },
                  "\(name) lost the LG codes proven on this desk")
        var fresh = KVMGroup.sample()
        fresh.monitors[0].control = .init(computer: fresh.computers[0].id, localDisplay: fresh.connections[0].localDisplay!, mode: "standard")
        try DeskMonitorConfiguration.apply(monitor: fresh.monitors[0].id, profile: tested.name,
                                           ports: tested.inputs.map { .init(name: $0.name, code: $0.code, command: $0.command) },
                                           mode: tested.alternate ? "lg" : "standard", to: &fresh)
        let dp = fresh.connections.first { $0.monitor == fresh.monitors[0].id && $0.inputName == "DisplayPort" }
        try check(fresh.monitors[0].control?.mode == "lg" && dp?.inputCode == 208 && dp?.inputProtocol == nil,
                  "Setting up \(name) did not give DisplayPort LG's code")
    }

    // Scott's desk after the Studio renamed Home screen 2: the recorded ID is gone
    // from its list, so control handed to it was handed straight back. The screen
    // is found again by what it is.
    let macbook = KVMComputer(name: "MacBook Pro"), macStudio = KVMComputer(name: "Mac Studio")
    let homeOne = KVMMonitor(name: "Home Screen 1", geometry: .init(x: 0, y: 0, width: 599.3, height: 340.2))
    let homeTwo = KVMMonitor(name: "Home screen 2", geometry: .init(x: 599.3, y: 0, width: 599.3, height: 340.2))
    var drifted = KVMGroup(name: "Home", computers: [macbook, macStudio], monitors: [homeOne, homeTwo])
    let oneUSB = KVMConnection(monitor: homeOne.id, computer: macbook.id, localDisplay: "mb-one", inputName: "USB-C", inputCode: 209)
    let twoUSB = KVMConnection(monitor: homeTwo.id, computer: macbook.id, localDisplay: "mb-two", inputName: "USB-C", inputCode: 209)
    let oneDP = KVMConnection(monitor: homeOne.id, computer: macStudio.id, localDisplay: "studio-one", inputName: "DisplayPort", inputCode: 208)
    let twoHDMI = KVMConnection(monitor: homeTwo.id, computer: macStudio.id, localDisplay: "studio-two-old", inputName: "HDMI 2", inputCode: 145)
    drifted.connections = [oneUSB, twoUSB, oneDP, twoHDMI]
    typealias Seen = DeskIdentityCableResolver.Display
    let reports: [UUID: [Seen]] = [
        macbook.id: [.init(id: "mb-one", vendor: 7789, model: 23741, serial: 0), .init(id: "mb-two", vendor: 7789, model: 30471, serial: 0)],
        macStudio.id: [.init(id: "studio-two-new", vendor: 7789, model: 30471, serial: 0)]
    ]
    let healed = DeskIdentityCableResolver.resolve(drifted, displays: reports)
    try check(healed.monitors.first { $0.id == homeOne.id }?.identity == .init(vendor: 7789, model: 23741) &&
              healed.monitors.first { $0.id == homeTwo.id }?.identity == .init(vendor: 7789, model: 30471),
              "Screens did not learn what they are from the Mac that can see them")
    try check(healed.connections.first { $0.id == twoHDMI.id }?.localDisplay == "studio-two-new",
              "A screen the Studio renamed was not found again by its model")
    // A screen that Mac cannot see right now keeps its record; absence is not evidence.
    try check(healed.connections.first { $0.id == oneDP.id }?.localDisplay == "studio-one",
              "A screen the Studio could not currently see lost its record")
    // This desk as the Studio saw it: its one display, through a USB-C-to-HDMI
    // adapter, is screen 2 (serial 353740, model 30470 over HDMI where USB-C says
    // 30471), but it was recorded against screen 1's DisplayPort, and screen 2's
    // HDMI record had gone stale. The serial proves the first record wrong and
    // finds the right one.
    var crossed = drifted
    crossed.monitors[crossed.monitors.firstIndex { $0.id == homeOne.id }!].identity = .init(vendor: 7789, model: 23741, serial: 175682)
    crossed.monitors[crossed.monitors.firstIndex { $0.id == homeTwo.id }!].identity = .init(vendor: 7789, model: 30471, serial: 353740)
    crossed.connections[crossed.connections.firstIndex { $0.id == oneDP.id }!].localDisplay = "1DAE75B3"
    crossed.connections[crossed.connections.firstIndex { $0.id == twoHDMI.id }!].localDisplay = "CD3AF695"
    let studioView: [UUID: [Seen]] = [macStudio.id: [.init(id: "1DAE75B3", vendor: 7789, model: 30470, serial: 353740)]]
    let uncrossed = DeskIdentityCableResolver.resolve(crossed, displays: studioView)
    try check(uncrossed.connections.first { $0.id == twoHDMI.id }?.localDisplay == "1DAE75B3",
              "The Studio's view of screen 2 was not moved to screen 2's HDMI input")
    try check(uncrossed.connections.first { $0.id == oneDP.id }?.localDisplay == nil,
              "Screen 1 kept a record the serial proves belongs to screen 2")
    try check(KVMScreenIdentity(vendor: 7789, model: 30471, serial: 353740).matches(vendor: 7789, model: 30470, serial: 353740),
              "The same monitor reporting another model number on another input was not recognised")
    // Hearing that another Mac runs a newer Perch is worth one look for the
    // published update, and only one per build heard about.
    try check(DeskUpdateNudge.shouldCheck(peerBuild: 265, ownBuild: 262, alreadyCheckedFor: 0), "A newer Mac did not prompt a look for the update")
    try check(!DeskUpdateNudge.shouldCheck(peerBuild: 265, ownBuild: 262, alreadyCheckedFor: 265), "The same newer build was looked for twice")
    try check(DeskUpdateNudge.shouldCheck(peerBuild: 266, ownBuild: 262, alreadyCheckedFor: 265), "A further newer build was not looked for")
    try check(!DeskUpdateNudge.shouldCheck(peerBuild: 262, ownBuild: 262, alreadyCheckedFor: 0) &&
              !DeskUpdateNudge.shouldCheck(peerBuild: 200, ownBuild: 262, alreadyCheckedFor: 0),
              "A Mac that is not newer prompted a look for an update")

    // At the moment of a command, the Mac looks at its own displays and finds the
    // monitor by what it is, never trusting a stored ID.
    let screenTwo = KVMScreenIdentity(vendor: 7789, model: 30471, serial: 353740)
    try check(DeskIdentityCableResolver.display(for: screenTwo, among: [.init(id: "adapter", vendor: 7789, model: 30470, serial: 353740)]) == "adapter",
              "The monitor was not found among this Mac's live displays through an adapter")
    try check(DeskIdentityCableResolver.display(for: screenTwo, among: [.init(id: "other", vendor: 7789, model: 23741, serial: 175682)]) == nil,
              "Another monitor was taken for this one")
    try check(DeskIdentityCableResolver.display(for: nil, among: [.init(id: "any", vendor: 7789, model: 30471, serial: 353740)]) == nil,
              "A screen with no known identity was matched")
    // Learning what a screen is must not change the sharing fingerprint: an older
    // Perch cannot see that field, and a difference refuses every handoff.
    try check(KVMInputConfiguration.revision(healed) == KVMInputConfiguration.revision({ var g = healed; for i in g.monitors.indices { g.monitors[i].identity = nil }; return g }()),
              "A screen's identity changed the sharing fingerprint")
    // Two identical monitors without serials cannot be told apart, so nothing is guessed.
    var twins = healed
    twins.connections[twins.connections.firstIndex { $0.id == twoHDMI.id }!].localDisplay = "gone"
    let twinReports: [UUID: [Seen]] = [macStudio.id: [.init(id: "a", vendor: 7789, model: 30471, serial: 0), .init(id: "b", vendor: 7789, model: 30471, serial: 0)]]
    try check(DeskIdentityCableResolver.resolve(twins, displays: twinReports).connections == twins.connections,
              "Two identical monitors were guessed between")
    // A serial tells identical models apart.
    var serials = twins
    serials.monitors[serials.monitors.firstIndex { $0.id == homeTwo.id }!].identity = .init(vendor: 7789, model: 30471, serial: 42)
    let serialReports: [UUID: [Seen]] = [macStudio.id: [.init(id: "a", vendor: 7789, model: 30471, serial: 41), .init(id: "b", vendor: 7789, model: 30471, serial: 42)]]
    try check(DeskIdentityCableResolver.resolve(serials, displays: serialReports).connections.first { $0.id == twoHDMI.id }?.localDisplay == "b",
              "A serial did not pick the right one of two identical monitors")

    // One input can be selected a different way from the rest of its screen.
    var mixed = KVMGroup.sample()
    let mixedScreen = mixed.monitors[0]
    let mixedUSB = mixed.connections.first { $0.monitor == mixedScreen.id && $0.inputName.contains("USB-C") }!
    mixed.monitors[0].control = .init(computer: mixedUSB.computer!, localDisplay: mixedUSB.localDisplay!, mode: "standard")
    let mixedUSBIndex = mixed.connections.firstIndex { $0.id == mixedUSB.id }!
    mixed.connections[mixedUSBIndex].inputCode = 209
    mixed.connections[mixedUSBIndex].inputProtocol = "lg"
    try check((try? mixed.validated()) != nil, "A per-input command was refused by validation")
    // Only this screen is in the preset, so the request is about it alone.
    for index in mixed.presets.indices {
        mixed.presets[index].assignments = [.init(monitor: mixedScreen.id, connection: mixedUSB.id)]
    }
    let mixedRequest = try KVMMonitorRequest.make(group: mixed, preset: mixed.presets[0].id, epoch: UUID(), revision: "r")
    try check(mixedRequest.routes.first { $0.monitor == mixedScreen.id }?.control.mode == "lg",
              "A switch ignored the command that input needs and used the screen's")
    let direct = try KVMMonitorRequest.makeConnection(group: mixed, connection: mixedUSB.id, epoch: UUID(), revision: "r")
    try check(direct.routes[0].control.mode == "lg", "A one-off switch ignored the command that input needs")
    let other = mixed.connections.first { $0.monitor == mixedScreen.id && $0.id != mixedUSB.id && $0.inputCode != nil }!
    let standard = try KVMMonitorRequest.makeConnection(group: mixed, connection: other.id, epoch: UUID(), revision: "r")
    try check(standard.routes[0].control.mode == "standard", "Another input on the same screen lost the screen's own command")
    var invalid = mixed
    invalid.connections[mixedUSBIndex].inputProtocol = "something else"
    try check((try? invalid.validated()) == nil, "An unknown input command was accepted")

    print("PASS: changing a screen's input list replaces it: same-name and same-kind inputs keep their cables and routes, unused leftovers go, an input in use is never stranded by a protocol change; the input a screen is showing matches that cable's display; one input can be switched a different way from its screen; a screen a Mac renamed is found again by what it is")
}
