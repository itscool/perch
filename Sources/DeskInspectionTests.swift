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
    var detected = generic
    detected.applyInspection(.init(current: nil, capabilities: nil, lgIdentity: 0x5124))
    let suggested = detected.profile(choice: "")
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
