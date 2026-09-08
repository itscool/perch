import AppKit

private final class GroupTestBackend: MonitorCommandBackend {
    var displays: [MonitorDescriptor] = []
    var current: [String: UInt16] = [:]
    var failed: Set<String> = []
    var unreadable: Set<String> = []
    var commands: [[String]] = []
    func run(_ arguments: [String]) throws -> Data {
        commands.append(arguments)
        if arguments[0] == "list" { return try JSONEncoder().encode(displays) }
        let id = arguments[1]
        if failed.contains(id) { throw AppError(message: "Fixture monitor disconnected") }
        if arguments[0] == "read" { return Data("{\"current\":\(unreadable.contains(id) ? "null" : current[id].map(String.init) ?? "null")}".utf8) }
        if arguments[0] == "switch" { current[id] = UInt16(arguments[3]); return Data("{\"sent\":true}".utf8) }
        throw AppError(message: "Unexpected fixture command")
    }
}

func runMonitorGroupTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let backend = GroupTestBackend(), suite = "local.perch.group-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let ids = (0..<3).map { _ in UUID().uuidString }
    backend.displays = ids.enumerated().map { .init(id: $0.element, displayID: UInt32($0.offset+10), name: "Studio Display", vendor: 1, model: 1, ddcAvailable: true) }
    let monitor = MonitorInputController(displays: backend.displays, backend: backend, defaults: defaults)
    for (i, id) in ids.enumerated() {
        var plan = MonitorInputPlan(); plan.display = id
        plan.inputs = [.init(code: UInt16(15+i), name: "Laptop"), .init(code: UInt16(21+i), name: "Desktop")]
        try monitor.save(plan); backend.current[id] = UInt16(15+i)
    }
    var group = MonitorGroup(); group.members = Array(backend.displays.prefix(2)).map { .init(display: $0.id, name: $0.name) }
    group.destinations = [.init(name: "MacBook", inputs: [ids[0]: 15, ids[1]: 16]), .init(name: "Mac mini", inputs: [ids[0]: 21, ids[1]: 22])]
    try monitor.groups.save(.init(groups: [group], activeID: group.id))
    try check(backend.commands.isEmpty && monitor.groups.active?.members.count == 2, "Saving or detecting displays switched or silently included one")
    func finish() throws {
        let until = Date().addingTimeInterval(3)
        while (monitor.busy || monitor.groups.busy) && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try check(!monitor.busy && !monitor.groups.busy, "Mock group operation did not finish")
    }
    monitor.groups.cycle(); try finish()
    try check(backend.current[ids[0]] == 21 && backend.current[ids[1]] == 22 && backend.current[ids[2]] == 17, "Group cycle diverged across different port mappings or touched unselected display")
    try check(monitor.groups.results.allSatisfy { $0.state == .confirmed }, "Per-monitor confirmation is missing")
    backend.current[ids[0]] = 15; backend.current[ids[1]] = 22; backend.commands = []
    monitor.groups.checkInputs(group); try finish()
    try check(monitor.groups.cycleNeedsChoice && !backend.commands.contains { $0[0] == "switch" }, "Checking current inputs guessed a destination or sent a command")
    monitor.groups.cycle(); try finish()
    try check(monitor.groups.cycleNeedsChoice && !backend.commands.contains { $0[0] == "switch" }, "Mixed state independently cycled monitors")
    backend.failed = [ids[1]]; backend.commands = []
    monitor.groups.choose(group, destination: group.destinations[1]); try finish()
    try check(monitor.groups.results.first { $0.display == ids[0] }?.state == .confirmed && monitor.groups.results.first { $0.display == ids[1] }?.state == .failed, "Partial failure appeared successful or was omitted")
    backend.failed = []; backend.current[ids[1]] = 16; backend.commands = []
    monitor.groups.retry(); try finish()
    try check(backend.commands.allSatisfy { $0[1] == ids[1] } && backend.current[ids[1]] == 22, "Retry repeated confirmed members or lost the requested destination")
    backend.unreadable = [ids[1]]; backend.commands = []
    monitor.groups.choose(group, destination: group.destinations[0]); try finish()
    try check(monitor.groups.results.first { $0.display == ids[1] }?.state == .unverified, "Accepted write without readback was called confirmed")
    backend.displays.removeAll { $0.id == ids[1] }; monitor.refresh(); try finish()
    monitor.groups.choose(group, destination: group.destinations[1]); try finish()
    try check(monitor.groups.results.count == 2 && monitor.groups.results.first { $0.display == ids[1] }?.detail.contains("disconnected") == true, "Disconnected selected display silently fell out of scope")
    backend.displays.append(.init(id: ids[1], displayID: 11, name: "Studio Display", vendor: 1, model: 1, ddcAvailable: true)); backend.unreadable = []
    monitor.refresh(); try finish(); backend.commands = []
    monitor.groups.retry(); try finish()
    try check(monitor.groups.results.allSatisfy { $0.state == .confirmed } && backend.commands.allSatisfy { $0[1] == ids[1] }, "Reconnecting prevented retry or expanded its scope")
    for selected in ids.prefix(2) {
        var single = group; single.id = UUID().uuidString; single.members = group.members.filter { $0.display == selected }
        for i in single.destinations.indices { single.destinations[i].inputs = single.destinations[i].inputs.filter { $0.key == selected } }
        let requests = monitor.groups.requests(single, destination: single.destinations[0]); backend.commands = []
        _ = MonitorGroupEngine.execute(requests, backend: backend, pause: {}) { _ in }
        try check(backend.commands.allSatisfy { $0[1] == selected }, "Either-monitor selection touched another display")
    }
    let before = defaults.data(forKey: MonitorGroupController.preferenceKey), beforeCommands = backend.commands
    let host = SettingsWindow.shared; host.testing = true; host.pages = []
    defer { host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window)) }
    MonitorGroupsPage(monitor).show(); let editor = MonitorGroupEditor(monitor, group: group); editor.show()
    let name = host.pages.last!.view.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    name.stringValue = "My desk draft"
    host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Set up individual display inputs…" }!.performClick(nil)
    try check(host.pages.last?.title != "Edit switching group", "Missing inputs have no reachable setup page")
    host.goBack()
    try check(editor.draft.name == "My desk draft" && host.pages.last?.title == "Edit switching group", "Reviewing an individual display lost the group draft")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-monitor-group-editor.png")
    host.goBack()
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-monitor-group-results.png")
    try check(defaults.data(forKey: MonitorGroupController.preferenceKey) == before && backend.commands == beforeCommands, "Opening/closing group editor changed saved setup or hardware")
    defaults.set(Data("broken".utf8), forKey: MonitorGroupController.preferenceKey)
    let corrupt = MonitorInputController(backend: backend, defaults: defaults)
    do { try corrupt.groups.save(.init()); throw AppError(message: "Corrupt store was overwritten") }
    catch { try check(defaults.data(forKey: MonitorGroupController.preferenceKey) == Data("broken".utf8), "Corrupt group settings were replaced") }
    print("PASS: one/either/both displays, distinct ports, mixed-state refusal, external input changes, partial results, unverified writes, reconnect retry, stable duplicate identities and draft cancellation; mock hardware only")
}
