import AppKit
import SwiftUI
import Carbon

/// Records every call the Desk page makes, so page actions are proven to
/// reach whoever runs the desk instead of silently doing nothing.
private final class RecordingDeskBackend: DeskBackend {
    let wording = DeskWording.live
    var calls: [String] = []
    var options: [DeskMappingOption] = []
    var editError: Error?
    func edit(_ group: KVMGroup) throws { calls.append("edit"); if let editError { throw editError } }
    func activate(preset: UUID) { calls.append("activate \(preset)") }
    func readiness(preset: UUID) -> String? { nil }
    func retryActive() { calls.append("retry") }
    func revertSwitch() { calls.append("revert") }
    func switchConnection(_ connection: UUID) { calls.append("switch \(connection)") }
    func mappingOptions() -> [DeskMappingOption] { options }
    func map(port: UUID, option: String) { calls.append("map \(port) \(option)") }
    func mapComputer(port: UUID, computer: UUID) { calls.append("mapComputer \(port) \(computer)") }
    func displayStatus(computer: UUID) -> String? { nil }
    func refreshScreens() { calls.append("refresh") }
    func panelAspect(monitor: UUID) -> Double? { nil }
    func identify(monitor: UUID?) { calls.append("identify \(monitor?.uuidString ?? "none")") }
    func identifyDisplay(_ display: String, computer: UUID) { calls.append("identifyDisplay") }
    func identifyComputer(_ computer: UUID) { calls.append("identifyComputer") }
    func isIdentifying(monitor: UUID) -> Bool { false }
    func isIdentifying(display: String, computer: UUID) -> Bool { false }
    func isIdentifying(computer: UUID) -> Bool { false }
    func peerActionReadiness(computer: UUID, action: String) -> String? { nil }
    func sheet(_ sheet: DeskSheet, close: @escaping () -> Void) -> AnyView? { nil }
}

/// Fast regression tests from the September 15 focused review: Desk (KVM) and input handling.
func runDeskInputReviewTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let group = KVMGroup.sample()

    // Page actions reach the desk, and a refused edit leaves the desk unchanged with its reason shown.
    let backend = RecordingDeskBackend()
    let model = DeskModel(backend: backend, group: group)
    model.activatePreset(2)
    try check(backend.calls == ["activate \(group.presets[2].id)"] && model.presetIndex == 2, "Playing a preset did not reach the desk: \(backend.calls)")
    backend.calls = []; model.selected = group.monitors[1].id; model.identify()
    try check(backend.calls == ["identify \(group.monitors[1].id.uuidString)"], "Identify did not reach the desk: \(backend.calls)")
    backend.calls = []; backend.editError = KVMError("Fixture refusal")
    model.renameMonitor("Renamed")
    try check(backend.calls == ["edit"] && model.problem == "Fixture refusal" && model.group == group, "A refused edit changed the desk or hid its reason")
    backend.editError = nil; model.problem = nil

    // Drawing a cable: an unassigned port with no detected display saves the computer;
    // exactly one detected display maps directly without opening a step.
    let page = DeskPageState()
    let port = group.connections.first { $0.computer == nil }!, mac = group.computers[0].id
    backend.calls = []
    page.beginCable(port.id, mac, model: model)
    try check(backend.calls == ["refresh", "mapComputer \(port.id) \(mac)"] && page.sheet == nil, "A new cable without a detected display did not save its computer: \(backend.calls)")
    backend.calls = []; backend.options = [DeskMappingOption(id: mac.uuidString + "|fixture-display", label: "Fixture display")]
    page.beginCable(port.id, mac, model: model)
    try check(backend.calls == ["refresh", "map \(port.id) \(mac.uuidString)|fixture-display"] && page.sheet == nil, "A single detected display was not mapped directly: \(backend.calls)")

    // A page that outlives its runtime refuses visibly instead of pretending to save.
    let orphan = DeskRuntimeBackend()
    var refused = false
    do { try orphan.edit(group) } catch { refused = error.localizedDescription == DeskRuntimeBackend.stopped }
    try check(refused && orphan.readiness(preset: group.presets[0].id) == DeskRuntimeBackend.stopped, "A Desk page without a running desk silently accepted edits or Play")
    let orphanModel = DeskModel(backend: orphan, group: group)
    orphanModel.renameMonitor("Lost")
    try check(orphanModel.problem == DeskRuntimeBackend.stopped && orphanModel.group == group, "An edit without a running desk looked saved")

    // Retry repeats the most recent switch, including a single port switch.
    func request(preset: UUID?, connection: UUID?) -> KVMMonitorRequest {
        KVMMonitorRequest(id: UUID(), epoch: UUID(), revision: "fixture", preset: preset, routes: [], connection: connection)
    }
    let presetID = group.presets[0].id, otherPreset = group.presets[1].id
    try check(DeskRetryTarget.target(activePreset: otherPreset, request: request(preset: presetID, connection: nil)) == .preset(presetID), "Retry did not repeat the failed preset")
    try check(DeskRetryTarget.target(activePreset: nil, request: request(preset: nil, connection: port.id)) == .connection(port.id), "Retry after a failed port switch did nothing")
    try check(DeskRetryTarget.target(activePreset: presetID, request: nil) == .preset(presetID) && DeskRetryTarget.target(activePreset: nil, request: nil) == nil, "Retry without a recent switch is wrong")

    // Hotkey problems are shown on the shortcut that has them, and failed passes are retried.
    var presets = group.presets
    let sharing = Shortcut(key: UInt32(kVK_ANSI_S))
    let free: (Shortcut, String) -> String? = { _, _ in nil }
    let ready = DeskShortcutPlan.make(presets: presets, sharing: sharing, problem: free)
    try check(ready.presets.map(\.preset) == presets.map(\.id) && ready.presetProblem == nil && ready.sharingProblem == nil, "A free desk did not plan every preset hotkey")
    let presetRegistry = ShortcutRegistry()
    presetRegistry.provide("fixture") { [ShortcutClaim(owner: "a fixture action", shortcut: presets[0].shortcut.local!)] }
    let presetClash = DeskShortcutPlan.make(presets: presets, sharing: sharing) { presetRegistry.problem(with: $0, excluding: $1) }
    try check(presetClash.presetProblem?.contains("a fixture action") == true && presetClash.sharingProblem == nil && presetClash.presets.isEmpty,
              "A preset hotkey problem was shown under Share on this Mac instead of the preset")
    let sharingRegistry = ShortcutRegistry()
    sharingRegistry.provide("fixture") { [ShortcutClaim(owner: "a fixture action", shortcut: sharing)] }
    let sharingClash = DeskShortcutPlan.make(presets: presets, sharing: sharing) { sharingRegistry.problem(with: $0, excluding: $1) }
    try check(sharingClash.sharingProblem != nil && sharingClash.presetProblem == nil && sharingClash.presets.count == presets.count, "A sharing hotkey problem blocked or was shown on the presets")
    presets[1].shortcut.key = "Esc"
    try check(DeskShortcutPlan.make(presets: presets, sharing: sharing, problem: free).presetProblem?.contains("cannot register") == true, "A preset key this Mac cannot register was accepted")
    var memory = DeskShortcutRegistrationMemory()
    let claims = [ShortcutClaim(owner: "fixture", shortcut: sharing)]
    try check(memory.needsRegistration(claims: claims, presets: group.presets), "First hotkey registration was skipped")
    memory.finished(claims: claims, presets: group.presets, succeeded: false)
    try check(memory.needsRegistration(claims: claims, presets: group.presets), "A failed hotkey registration was never retried")
    memory.finished(claims: claims, presets: group.presets, succeeded: true)
    try check(!memory.needsRegistration(claims: claims, presets: group.presets), "An unchanged, registered desk re-registered its hotkeys")
    memory.reset()
    try check(memory.needsRegistration(claims: claims, presets: group.presets), "Stopping the desk did not forget its hotkey registration")

    // Key routing in the input tap: emergency, preset, Perch's own shortcuts stay local, ordinary keys are sent.
    var router = DeskKeyRouter()
    let f1 = Int64(kVK_F1), s = Int64(kVK_ANSI_S), a = Int64(kVK_ANSI_A)
    let chord: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    let perchOwned: (Int64, CGEventFlags) -> Bool = { code, flags in code == s && flags.contains(chord) }
    func route(_ type: CGEventType, _ code: Int64, _ flags: CGEventFlags = [], repeating: Bool = false, sharingOn: Bool = true) -> DeskKeyDisposition {
        router.route(type: type, keyCode: code, flags: flags, autorepeat: repeating, sharing: sharingOn, presets: group.presets, localShortcut: perchOwned)
    }
    try check(route(.keyDown, 53, [.maskControl, .maskAlternate]) == .emergencyStop, "Control-Option-Escape did not return local control")
    try check(route(.keyDown, f1, chord) == .activatePreset(group.presets[0].id), "A preset shortcut did not switch the preset")
    try check(route(.keyDown, f1, chord, repeating: true) == .consumed && route(.keyUp, f1, chord) == .consumed, "A held preset shortcut repeated or leaked its release")
    try check(route(.keyDown, s, chord) == .local && route(.keyUp, s) == .local, "Share on this Mac's shortcut was sent to the other Mac")
    try check(route(.keyDown, a) == .forward && route(.keyUp, a) == .forward, "Ordinary keys were not sent while sharing")
    try check(route(.keyDown, f1, chord, sharingOn: false) == .forward, "The tap claimed a preset shortcut while sharing is off")
    _ = route(.keyDown, s, chord)
    try check(route(.keyDown, s) == .forward && route(.keyUp, s) == .forward, "A missed release left a later ordinary key stuck on the other Mac")
    try check(router.consumedKeys.isEmpty && router.localKeys.isEmpty, "Key routing kept stale held keys")

    // Monitor commands can take nine seconds: on the main thread they refuse at once.
    let started = Date()
    var mainRefusal = ""
    do { _ = try MonitorDisplayBackend().run(["list"]) } catch { mainRefusal = error.localizedDescription }
    try check(mainRefusal == MonitorDisplayBackend.mainThreadRefusal && Date().timeIntervalSince(started) < 0.2, "A monitor command could block the main thread")

    // A worker asking the main thread gets a prompt answer when it is free, and a
    // bounded nil while the main queue is busy inside another block.
    var idleAnswer: Bool?, busyAnswer: Bool? = true, busyWait = 0.0, finished = 0
    DispatchQueue.global().async {
        idleAnswer = DeskMainThreadGate.ask(timeout: 1) { true }
        DispatchQueue.main.async {
            // Occupy the main queue, as a modal loop inside a main-queue block does.
            let hold = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                let asked = Date()
                busyAnswer = DeskMainThreadGate.ask(timeout: 0.1) { true }
                busyWait = Date().timeIntervalSince(asked)
                hold.signal()
            }
            _ = hold.wait(timeout: .now() + 1)
            finished = 1
        }
    }
    let gateDeadline = Date().addingTimeInterval(3)
    while finished == 0, Date() < gateDeadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    try check(idleAnswer == true, "A worker's main-thread check was not answered while the main thread was free")
    try check(finished == 1 && busyAnswer == nil && busyWait < 0.5, "A worker waited on a busy main thread instead of giving up (\(busyWait)s)")

    print("PASS: Desk page actions reach the desk, orphaned pages refuse visibly, retry covers port switches, hotkey problems land on their own shortcut and failed registrations retry, Perch's shortcuts never reach the other Mac, and monitor commands never block or wait forever on the main thread")
}
