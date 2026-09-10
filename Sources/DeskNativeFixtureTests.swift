import AppKit
import Network

private enum DeskNativeFixtureState { static var retained: [AnyObject] = [] }
func runDeskNativeFixture() throws {
    guard Bundle.main.bundleIdentifier == "local.perch.functional-review", CommandLine.arguments.contains("--desk-native-fixture") else { throw KVMError("Native Desk fixture is unavailable in this app.") }
    SettingsWindow.shared.testing = true
    func wait(_ predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(8)
        while !predicate() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }
        guard predicate() else { throw KVMError("Native fixture pairing timed out.") }
    }
    let root = SafetyFiles.base.appendingPathComponent("desk-ui-" + UUID().uuidString)
    let a = try KVMDeskNode(identity: .fresh(), name: "Fixture MacBook", storage: root.appendingPathComponent("a.json"))
    let b = try KVMDeskNode(identity: .fresh(), name: "Fixture Studio", storage: root.appendingPathComponent("b.json"))
    let port = UInt16.random(in: 54000...59000)
    try a.start(localOnly: true, port: .init(rawValue: port)!); try b.start(localOnly: true, port: .init(rawValue: port + 1)!)
    a.openPairing(hosting: true); b.openPairing(hosting: false)
    b.connect(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
    try wait { a.pairings.count == 1 && b.pairings.count == 1 }
    a.approve(a.pairings[0].id); b.approve(b.pairings[0].id)
    try wait { a.hasOtherMembers && b.hasOtherMembers }
    a.closePairing(); b.closePairing()
    var group = a.group
    for i in 0..<2 {
        let localA = UUID().uuidString, localB = UUID().uuidString
        let monitor = KVMMonitor(name: i == 0 ? "Main screen" : "Side screen", geometry: .init(x: Double(i*550), y: 0, width: 550, height: 310), control: .init(computer: a.localID, localDisplay: localA))
        group.monitors.append(monitor)
        let ca = KVMConnection(monitor: monitor.id, computer: a.localID, localDisplay: localA, inputName: "HDMI 1", inputCode: 17)
        let cb = KVMConnection(monitor: monitor.id, computer: b.localID, localDisplay: localB, inputName: "DisplayPort", inputCode: 15)
        group.connections += [ca, cb]
        for p in 0..<3 { group.presets[p].assignments.append(.init(monitor: monitor.id, connection: p == 1 ? cb.id : ca.id)) }
    }
    try a.edit(group); try wait { b.group == group }
    let runtime = DeskRuntime(node: a), other = KVMMonitorSwitch(node: b)
    for c in group.computers {
        runtime.displays[c.id] = group.connections.filter { $0.computer == c.id }.map { connection in
            DeskDetectedDisplay(id: connection.localDisplay!, name: group.monitors.first { $0.id == connection.monitor }!.name, vendor: 1, model: 1, serial: 0, width: 550, height: 310, canControl: true,
                                inputs: [.init(code: 17, name: "HDMI 1"), .init(code: 15, name: "DisplayPort")], mode: "standard")
        }
    }
    for service in [runtime.switching, other] {
        service.execute = { _, valid, completion in completion(valid() ? .confirmed : .failed, "Simulated monitor readback in native UI fixture") }
        service.readForVerification = { _, completion in completion(17) }
    }
    DeskCoordinator.shared.runtime = runtime
    let app = AppDelegate(); app.buildMenu(); app.installSettingsNavigation()
    DeskNativeFixtureState.retained = [a, b, runtime, other, app]
    try DesktopTestSession.check()
    NSApp.setActivationPolicy(.regular)
    app.deskSettings()
    SettingsWindow.shared.window.center()
    SettingsWindow.shared.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
