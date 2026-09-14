import Foundation

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
    var group = DeskModel.sample()
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

/// The Desk graph is the single preset-editing path: numbered computer sockets
/// assign monitor ports, while physical cable ownership remains independent.
func runDeskPresetGraphTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw KVMError(message) } }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-desk-graph-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = DeskModel(store: root.appendingPathComponent("desk.json"))
    let first = model.group.computers[0], second = model.group.computers[1]
    let unassigned = model.group.connections.first { $0.computer == nil }!
    model.assignPresetPort(slot: 2, computer: first.id, connection: unassigned.id)
    try check(model.group.presets[1].assignments.contains { $0.monitor == unassigned.monitor && $0.connection == unassigned.id },
              "Numbered preset socket did not assign an unassigned monitor input")
    let before = model.group.presets[0].assignments
    let foreign = model.group.connections.first { $0.computer == second.id }!
    model.assignPresetPort(slot: 1, computer: first.id, connection: foreign.id)
    try check(model.problem?.contains("belongs to another computer") == true && model.group.presets[0].assignments == before,
              "Preset graph allowed a computer to claim another computer's physical input")
    var gesture = DeskWireGesture()
    gesture.begin("preset:\(first.id.uuidString):3", at: .zero)
    gesture.move(to: CGPoint(x: 8, y: 0))
    let result = gesture.finish(insideSource: false, target: "port:\(unassigned.id.uuidString)")
    try check(result == .connect("preset:\(first.id.uuidString):3", "port:\(unassigned.id.uuidString)"),
              "Preset socket drag did not produce a compatible graph connection")
    print("PASS: numbered preset graph assignment, ownership guard and preset wire gesture")
}
