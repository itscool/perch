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
    let token = UUID(), message = DeskDeviceMessage.inspectionReply(token, record, nil)
    guard case .inspectionReply(let roundTripToken, let roundTripRecord, _) = try JSONDecoder().decode(DeskDeviceMessage.self, from: JSONEncoder().encode(message)) else { throw KVMError("Detection reply lost its identity") }
    try check(roundTripToken == token && roundTripRecord == record, "Detection replies must retain the specific request and display")
    print("PASS: scoped control paths, port/offline labels, wrong-monitor exclusion, profile/capability/unknown detection, protocol default persistence and reply correlation payload")
}
