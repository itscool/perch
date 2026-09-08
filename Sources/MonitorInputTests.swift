import AppKit

func runMonitorInputTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let a = MonitorInput(code: 17,name: "HDMI 1"), b = MonitorInput(code: 15,name: "DisplayPort")
    var plan = MonitorInputPlan(); plan.inputs = [a,b]
    try check(try plan.next(current: 17,lastSent: nil) == b && plan.next(current: 15,lastSent: nil) == a && plan.next(current: 18,lastSent: nil) == a, "Cycle order/wrap/current-outside-list failed")
    do { _ = try plan.next(current: nil,lastSent: 17); throw AppError(message: "Unknown input silently used a stale position") } catch let e as AppError { try check(!e.message.contains("silently"), e.message) }
    plan.allowUnconfirmedCycle = true
    try check(try plan.next(current: nil,lastSent: 17) == b, "Explicit unconfirmed cycle fallback failed")
    do { _ = try plan.next(current:nil,lastSent:nil); throw AppError(message:"Guessed unknown starting input") } catch let e as AppError { try check(!e.message.contains("Guessed"),e.message) }
    plan.availableInputs = [a,b,.init(code:18,name:"HDMI 2")]
    let restored = try JSONDecoder().decode(MonitorInputPlan.self,from:JSONEncoder().encode(plan))
    try check(restored.availableInputs?.count == 3 && restored.inputs.count == 2,"Unchecked input discarded")
    plan.availableInputs = nil
    plan.inputs = [a,a]; try check(!plan.valid,"Duplicate input codes accepted")
    let preserved = [MonitorInput(code:145,name:"My HDMI"),MonitorInput(code:209,name:"USB-C")]
    try check(MonitorCapabilities.merge(preserved, reported: [.init(code:145,name:"HDMI 2"),.init(code:210,name:"Input 210")]) == preserved + [.init(code:210,name:"Input 210")], "Discovery overwrote a working map")
    try check(MonitorInput.name(27) == "Input 27" && MonitorInput.name(209, alternate:true) == "Input 209", "Unknown input falsely labeled USB-C")
    try check(MonitorCapabilities.model("(prot(monitor)model(27UN850-W)vcp(60(11)))") == "27UN850-W" && MonitorCapabilities.model("model(") == nil, "Bounded model extraction failed")
    let caps = "(prot(monitor)model(Test)vcp(10 12 60(0f 10 11 12 1b) 62))"
    try check(MonitorCapabilities.inputs(caps) == [15,16,17,18,27],"Capabilities input codes were not decoded as hex")
    for bad in ["", "(vcp(10 12))", "(vcp(60(0f zz)))", "(vcp(60(0f)", "(vcp(60(00000f)))", String(repeating:"x",count:5000)] {
        if bad == "(vcp(60(0f)" { continue } // Input subsection is complete; outer metadata can be truncated.
        try check(MonitorCapabilities.inputs(bad).isEmpty,"Malformed capabilities accepted: \(bad.prefix(30))")
    }
    try check(try MonitorInputPage.parse("17 = HDMI 1\n15 = DisplayPort") == [a,MonitorInput(code:15,name:"DisplayPort")],"Manual input parsing failed")
    for bad in ["17", "0 = x\n1 = y", "17 = x\n17 = y", "65536 = x\n1 = y"] {
        var refused = false; do { _ = try MonitorInputPage.parse(bad) } catch { refused = true }
        try check(refused,"Invalid manual input list accepted")
    }
    var request = [UInt8](repeating:0,count:36), payload: [UInt8] = [0x60,0,17]
    let count = perch_ddc_request(&request,0x51,0x03,&payload,payload.count)
    try check(count == 6 && request.prefix(6).reduce(UInt8(0x6e ^ 0x51),^) == 0,"DDC write packet/checksum invalid")
    var reply: [UInt8] = [0x6e,0x88,0x02,0,0x60,0,0,0x1b,0,0x11,0]
    reply[10] = reply.prefix(10).reduce(UInt8(0x50),^)
    var value: UInt16 = 0
    try check(perch_ddc_value(&reply,reply.count,0x60,&value) && value == 17,"Valid DDC response rejected")
    for i in 0..<reply.count {
        var bad = reply; bad[i] ^= 1
        try check(!perch_ddc_value(&bad,bad.count,0x60,&value),"Corrupt DDC reply accepted")
        try check(!perch_ddc_value(&reply,i,0x60,&value),"Truncated DDC reply accepted")
    }
    print("PASS: monitor cycle order/wrap; explicit unknown-state fallback; strict capabilities/manual input parsing; packet checksum, truncation and corruption; no DDC sent")
}

func runMonitorInputUITests() throws {
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    let display = MonitorDescriptor(id: "11111111-1111-1111-1111-111111111111",displayID: 99,name:"LG HDR 4K",vendor:0x1e6d,model:0x7706,ddcAvailable:true)
    let mock = FakeMonitorBackend(); mock.failWrite = false
    let fixtureSuite = "perch-menu-fixture." + UUID().uuidString
    let fixtureDefaults = UserDefaults(suiteName:fixtureSuite)!
    defer { fixtureDefaults.removePersistentDomain(forName:fixtureSuite) }
    let controller = MonitorInputController(displays:[display],backend:mock,defaults:fixtureDefaults)
    controller.message = "✓ LG HDR 4K detected · choose inputs to cycle"
    controller.plan.inputs = [.init(code:144,name:"HDMI 1"),.init(code:145,name:"HDMI 2"),.init(code:208,name:"DisplayPort"),.init(code:210,name:"USB-C")]
    controller.plan.display = display.id; controller.plan.alternate = true
    let app = AppDelegate(); app.buildMenu()
    host.show(.init(title:"Perch settings",detail:"",view:NSView()))
    controller.plan.allowUnconfirmedCycle = true
    controller.useCurrentInput(210)
    controller.cycle()
    let deadline = Date().addingTimeInterval(2)
    while controller.busy && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    let page = MonitorInputPage(controller); page.show()
    guard !page.worked.isHidden && !page.failed.isHidden && !page.status.frame.intersects(page.worked.frame) else { throw AppError(message:"Unconfirmed switch feedback is hidden or overlaps") }
    guard host.pages.count == 2, host.pages.last?.title == "Monitor inputs" else { throw AppError(message:"Monitor setup left the settings stack") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-inputs.png")
    guard page.protocolChoice.isHidden && page.detect.isHidden && !page.view.subviews.compactMap({ $0 as? NSButton }).contains(where: { !$0.isHidden && ($0.title == "Save" || $0.title.contains("Apply")) }) else { throw AppError(message: "Ordinary monitor settings mixes immediate changes with Apply") }
    let setup = page.editSetup()
    guard host.pages.last?.title == "Monitor connection & inputs" && host.back.title == "Cancel" && setup.save.title == "Save" else { throw AppError(message: "Monitor setup does not have an explicit Save/Cancel boundary") }
    guard !setup.status.stringValue.contains("Confirm below") && setup.save.keyEquivalent == "\r" else { throw AppError(message: "Setup inherited unrelated switch confirmation or lost Save keyboard access") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-setup.png")
    let original = setup.candidates, selected = setup.selectedCodes
    setup.detect.performClick(nil)
    let scanEnd = Date().addingTimeInterval(2)
    while controller.busy && Date() < scanEnd { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    guard setup.candidates == original && setup.selectedCodes == selected else { throw AppError(message:"Detect replaced saved input codes or selection") }
    let before = setup.protocolChoice.indexOfSelectedItem
    let edit = setup.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Model & inputs…" }!
    edit.performClick(nil)
    let child = host.pages.last!.view
    let presets = child.subviews.compactMap { $0 as? NSPopUpButton }.first!
    guard presets.itemTitles.contains("LG 27UN850-W / 27UN850-WY") else { throw AppError(message:"Embedded retail presets absent from settings") }
    presets.selectItem(withTitle: "LG 27UN850-W / 27UN850-WY")
    child.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Use preset" }!.performClick(nil)
    let compatibility = child.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Compatibility test…" }!
    let beforeCommands = mock.commands.count
    compatibility.performClick(nil)
    guard host.pages.last?.title == "Monitor compatibility test", mock.commands.count == beforeCommands else { throw AppError(message:"Opening compatibility setup sent a command") }
    host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Test selected command" }!.performClick(nil)
    guard mock.commands.count == beforeCommands else { throw AppError(message:"Compatibility command sent without explicit prerequisite and candidate") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-compatibility.png")
    host.goBack()
    host.goBack()
    guard setup.protocolChoice.indexOfSelectedItem == before else { throw AppError(message:"Cancelled preset selection changed parent settings") }
    setup.protocolChoice.selectItem(at:2)
    _ = NSApp.sendAction(setup.protocolChoice.action!,to:setup.protocolChoice.target,from:setup.protocolChoice)
    guard host.pages.last?.title == "Monitor control connection" && mock.commands.count == beforeCommands else { throw AppError(message:"Opening connection setup caused hardware IO") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-connection.png")
    host.goBack()
    guard setup.protocolChoice.indexOfSelectedItem == before else { throw AppError(message:"Connection cancel changed protocol") }
    host.goBack()
    host.goBack()
    guard host.pages.count == 1 && controller.pageChanged == nil else { throw AppError(message:"Monitor setup did not clean up on Back") }
    host.pages = []
    guard app.homeEndItem != nil && app.pageKeysItem != nil && app.monitorInputItem != nil else { throw AppError(message:"Navigation or monitor menu option missing") }
    print("PASS: navigation/monitor menu items; monitor settings lifetime and Back; light/dark own-view renders; no input capture or display requests")
}

private final class FakeMonitorBackend: MonitorCommandBackend {
    var commands: [[String]] = []
    var firmwareIdentity: UInt16? = nil
    var failWrite = true
    var reported: UInt16?
    var reportWritten = false
    func run(_ args: [String]) throws -> Data {
        commands.append(args)
        if args.first == "read" || args.first == "inspect" { return Data("{\"current\":\(reported.map(String.init) ?? "null"),\"capabilities\":null,\"lgIdentity\":\(firmwareIdentity.map(String.init) ?? "null")}".utf8) }
        if failWrite { throw AppError(message:"Mock disconnected monitor") }
        if reportWritten { reported = args.last.flatMap(UInt16.init) }
        return Data("{\"sent\":true}".utf8)
    }
}
func runMonitorTransactionTests() throws {
    let display = MonitorDescriptor(id:"11111111-1111-1111-1111-111111111111",displayID:99,name:"Fixture",vendor:1,model:1,ddcAvailable:true,connection:"fixture-route")
    let backend = FakeMonitorBackend()
    let suite = "local.scott.perch.monitor-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let controller = MonitorInputController(displays:[display],backend:backend,defaults:defaults)
    controller.plan.display = display.id
    controller.plan.inputs = [.init(code:17,name:"HDMI"),.init(code:15,name:"DP")]
    controller.plan.allowUnconfirmedCycle = true
    func finish() throws {
        let until = Date().addingTimeInterval(2)
        while controller.busy && Date() < until { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        if controller.busy { throw AppError(message:"Mock monitor request did not finish") }
    }
    controller.useCurrentInput(15)
    controller.cycle(); try finish()
    guard controller.warning else { throw AppError(message:"Failed monitor write wasn't surfaced") }
    backend.failWrite = false
    controller.useCurrentInput(15)
    controller.cycle(); try finish()
    let beforeUnknown = backend.commands.filter { $0.first == "switch" }.count
    controller.cycle(); try finish()
    guard backend.commands.filter({ $0.first == "switch" }).count == beforeUnknown && controller.currentSummary.contains("unknown") else { throw AppError(message:"Shared monitor cycled from a stale last command") }
    controller.useCurrentInput(17)
    controller.cycle(); try finish()
    let writes = backend.commands.filter { $0.first == "switch" }.map { $0.last! }
    guard writes == ["17","17","15"] else { throw AppError(message:"Failed switch advanced the cycle position") }
    guard controller.pendingConfirmation == 15 && controller.warning else { throw AppError(message:"Transport success falsely confirmed monitor control") }
    controller.confirmSwitch(true)
    let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("monitor.confirmed.v1.") }
    guard saved.count == 1 && (saved.values.first as? [Int]) == [15] else { throw AppError(message:"Confirmation did not remain scoped to one input") }
    controller.useCurrentInput(15)
    controller.cycle(); try finish()
    guard controller.warning && controller.pendingConfirmation == 17 else { throw AppError(message:"Another input inherited an unrelated confirmation") }
    controller.confirmSwitch(false)
    guard controller.warning && controller.message.contains("adapter") && controller.pendingConfirmation == nil else { throw AppError(message:"Failed physical switch has no adapter troubleshooting") }
    backend.reported = 15; backend.reportWritten = true
    controller.cycle(); try finish()
    guard !controller.warning && controller.pendingConfirmation == nil && controller.message.contains("Monitor reports") else { throw AppError(message:"Readback did not verify the requested input") }
    // Another computer changes the monitor after our previous command.
    backend.reported = 15
    controller.cycle(); try finish()
    guard backend.commands.last?.first == "read" && backend.commands.filter({ $0.first == "switch" }).last?.last == "17" else { throw AppError(message:"External input change did not determine the next destination") }
    backend.reported = nil; backend.reportWritten = false
    controller.cycle(destination: controller.plan.inputs[1]); try finish()
    guard backend.commands.filter({ $0.first == "switch" }).last?.last == "15" && controller.currentSummary.contains("unknown") else { throw AppError(message:"Explicit destination required a guessed current input or claimed confirmation") }
    let generic = MonitorDescriptor(id:display.id,displayID:99,name:"LG HDR 4K",vendor:7789,model:30470,ddcAvailable:true)
    guard MonitorProfiles.match(generic)?.confidence == "suggested",
          MonitorProfiles.match(generic,reportedModel:"27UN850-W")?.inputs.contains(.init(code:209,name:"USB-C")) == true,
          MonitorProfiles.entries.count >= 21 else { throw AppError(message:"Embedded model profiles missing or ambiguous LG auto-match") }
    let samsung = MonitorDescriptor(id:display.id,displayID:99,name:"C49RG9x",vendor:19501,model:0x0f9c,ddcAvailable:true)
    guard MonitorProfiles.match(samsung)?.inputs.contains(.init(code:6,name:"HDMI")) == true,
          Set(MonitorProfiles.entries.map { $0.vendor }).count >= 12 else { throw AppError(message:"Multi-vendor or Samsung write-code profiles missing") }
    let writeOnlyBackend = FakeMonitorBackend(); writeOnlyBackend.failWrite = false; writeOnlyBackend.reportWritten = true
    let writeOnly = MonitorInputController(displays:[samsung],backend:writeOnlyBackend,defaults:defaults)
    writeOnly.plan.display = samsung.id; writeOnly.plan.inputs = MonitorProfiles.match(samsung)!.inputs; writeOnly.plan.allowUnconfirmedCycle = true
    writeOnly.useCurrentInput(writeOnly.plan.inputs.last!.code)
    writeOnly.cycle()
    let done = Date().addingTimeInterval(2)
    while writeOnly.busy && Date() < done { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    guard !writeOnly.busy && writeOnly.pendingConfirmation != nil && !writeOnlyBackend.commands.contains(where: { $0.first == "read" }) else { throw AppError(message:"Write-only monitor relied on misleading readback") }
    var rejectedRead = false
    writeOnly.readInput(samsung.id, mode: writeOnly.plan.commandMode) { if case .failure = $0 { rejectedRead = true } }
    guard rejectedRead && writeOnly.currentSummary.contains("unknown") && !writeOnlyBackend.commands.contains(where: { $0.first == "read" }) else { throw AppError(message: "Manual read trusted an unreliable monitor report") }
    let beforeTest = controller.plan
    var testAccepted = false
    controller.testInput(.init(code:18,name:"HDMI 2"),display:display.id,alternate:false) { testAccepted = $0 }
    try finish()
    guard testAccepted && controller.plan == beforeTest else { throw AppError(message:"Single candidate test changed the saved cycle") }
    print("PASS: fresh monitor readback after another computer switches; one-use manual observation; stale commands refused; direct destination without readback; per-input confirmation; mock adapter only")
}

func runMonitorConnectionTests() throws {
    let old = Data(#"{"display":"11111111-1111-1111-1111-111111111111","alternate":true,"inputs":[],"allowUnconfirmedCycle":false,"shortcut":{"key":100,"modifiers":0,"enabled":false}}"#.utf8)
    let legacy = try JSONDecoder().decode(MonitorInputPlan.self,from:old)
    guard legacy.controlConnection == nil && legacy.commandMode == "lg" else { throw AppError(message:"Legacy DDC preferences changed") }
    var plan = legacy; plan.controlConnection = .init(kind:"msi-usb",endpoint:"fixture:serial:1")
    plan.inputs = [.init(code:1,name:"HDMI 1"),.init(code:2,name:"HDMI 2")]
    let roundtrip = try JSONDecoder().decode(MonitorInputPlan.self,from:JSONEncoder().encode(plan))
    guard roundtrip == plan && plan.commandMode.hasPrefix("route:") else { throw AppError(message:"Control connection not preserved") }
    var bad = plan; bad.controlConnection?.kind = "arbitrary"; guard !bad.valid else { throw AppError(message:"Unknown transport accepted") }
    let backend = FakeMonitorBackend(); backend.failWrite = false; backend.reported = 1; backend.reportWritten = true
    let controller = MonitorInputController(displays:[],backend:backend)
    controller.plan = plan
    guard controller.canCycle else { throw AppError(message:"USB route unavailable after video switched away") }
    controller.cycle()
    let end = Date().addingTimeInterval(2)
    while controller.busy && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    guard !controller.busy && backend.commands.contains(where: { $0.first == "switch" && $0[2] == plan.commandMode && $0.last == "2" }) else { throw AppError(message:"Cycle lost its USB route") }
    _ = try MonitorDisplayBackend().run(["transport-self-test"])
    print("PASS: monitor transport packet integrity; backward-compatible preferences; invalid routes rejected; USB cycling after video disappears through mock backend only")
}

func runMonitorDraftTests() throws {
    let host = SettingsWindow.shared; host.testing = true; host.pages = []
    let suite = "perch-monitor-draft-test." + UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite); host.pages = [] }
    let display = MonitorDescriptor(id:"11111111-1111-1111-1111-111111111111",displayID:99,name:"LG HDR 4K",vendor:7789,model:30470,ddcAvailable:true)
    let backend = FakeMonitorBackend(); backend.firmwareIdentity = 0x5124
    let controller = MonitorInputController(displays:[display],backend:backend,defaults:defaults)
    controller.plan.display = display.id; controller.plan.alternate = true
    controller.plan.inputs = [.init(code:145,name:"My HDMI"),.init(code:209,name:"My USB"),.init(code:210,name:"Old candidate")]
    host.show(.init(title:"Perch settings",detail:"",view:NSView()))
    let page = MonitorInputPage(controller); page.show(); page.inputList.documentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Old candidate" }!.performClick(nil); host.goBack()
    guard controller.plan.availableInputs?.count == 3 && controller.plan.inputs.count == 2 else { throw AppError(message:"Saving unchecked inputs deleted them") }
    let saved = defaults.data(forKey:MonitorInputController.preferenceKey)
    let fresh = MonitorInputPage(controller); fresh.show()
    guard fresh.candidates.count == 3 && !fresh.selectedCodes.contains(210) && host.back.title == "Back" else { throw AppError(message:"Reopening lost unchecked inputs or cancellation label") }
    func finish() throws {
        let end = Date().addingTimeInterval(2)
        while controller.busy && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard !controller.busy else { throw AppError(message: "Mock monitor check timed out") }
    }
    func chooseProtocol(_ editor: MonitorInputPage, _ index: Int) throws {
        editor.protocolChoice.selectItem(at: index)
        _ = NSApp.sendAction(editor.protocolChoice.action!, to: editor.protocolChoice.target, from: editor.protocolChoice)
        try finish()
    }
    func undo() {
        fresh.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Undo setup change" }!.performClick(nil)
    }
    let working = controller.plan
    let detected = fresh.editSetup()
    detected.detect.performClick(nil); try finish()
    guard detected.candidates.map({ $0.code }) == [144,145,208,209], detected.selectedCodes == [145,209],
          controller.plan == working, defaults.data(forKey: MonitorInputController.preferenceKey) == saved else { throw AppError(message: "Detection committed or lost the working setup before Save") }
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-monitor-fresh-draft.png")
    detected.save.performClick(nil)
    guard controller.plan.availableInputs?.count == 4 && controller.plan.inputs.count == 2 && host.pages.last?.title == "Monitor inputs" else { throw AppError(message: "Save did not keep the whole setup and return to the monitor") }
    undo()
    guard controller.plan == working else { throw AppError(message: "Undo setup did not restore the previous input list") }

    let beforeTrialData = defaults.data(forKey: MonitorInputController.preferenceKey)
    let canceled = fresh.editSetup()
    try chooseProtocol(canceled, 0)
    canceled.selectedCodes.remove(145)
    guard controller.plan == working && defaults.data(forKey: MonitorInputController.preferenceKey) == beforeTrialData else { throw AppError(message: "A draft protocol or selection changed persisted settings") }
    let draftCycle = canceled.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Cycle input now" }!
    let destinations = canceled.inputList.documentView!.subviews.compactMap { $0 as? NSButton }.filter { $0.title == "Show this input" }
    guard draftCycle.isHidden && destinations.allSatisfy({ $0.isHidden }) else { throw AppError(message: "Setup editor exposes a switch using its working setup") }
    host.goBack()
    guard controller.plan == working && fresh.selectedCodes == [145,209] && host.back.title == "Back" else { throw AppError(message: "Cancel lost the working setup or ordinary monitor state") }

    let accepted = fresh.editSetup()
    try chooseProtocol(accepted, 0)
    accepted.save.performClick(nil)
    guard !controller.plan.alternate && controller.plan.inputs == working.inputs else { throw AppError(message: "Saving a connection changed unrelated selected inputs") }
    undo()
    guard controller.plan == working else { throw AppError(message: "Undo did not restore the previous connection") }

    let invalid = fresh.editSetup()
    invalid.candidates = [.init(code: 0, name: "Invalid fixture")]
    invalid.selectedCodes = [0]
    invalid.save.performClick(nil)
    guard host.pages.last?.title == "Monitor connection & inputs", controller.plan == working,
          invalid.candidates.first?.code == 0, invalid.status.stringValue.contains("Not saved") else { throw AppError(message: "Rejected Save lost its setup draft or closed the editor") }
    guard !controller.message.contains("Not saved") else { throw AppError(message: "A draft error replaced the working monitor’s status") }
    host.goBack()

    let connection = fresh.editSetup()
    try chooseProtocol(connection, 2)
    let connectionView = host.pages.last!.view as! MonitorConnectionView
    let type = connectionView.subviews.compactMap { $0 as? NSPopUpButton }.first!
    type.selectItem(at: 2); connectionView.updateSelection()
    let endpoint = connectionView.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    endpoint.stringValue = "192.0.2.10"
    let check = connectionView.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Check connection" }!
    let use = connectionView.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Use this connection" }!
    check.performClick(nil); try finish()
    guard use.isEnabled && controller.plan == working && connection.candidates == working.availableInputs else { throw AppError(message: "Checking a connection saved it or cleared input mappings") }
    endpoint.stringValue = "192.0.2.11"; use.performClick(nil)
    guard host.pages.last?.title == "Monitor control connection" && controller.plan == working else { throw AppError(message: "Changed endpoint used an earlier check result") }
    check.performClick(nil); try finish()
    use.performClick(nil)
    guard host.pages.last?.title == "Monitor connection & inputs", controller.plan == working, connection.candidates == working.availableInputs else { throw AppError(message: "Accepting a checked connection bypassed setup Save or lost mappings") }
    connection.save.performClick(nil)
    guard controller.plan.controlConnection?.endpoint == "192.0.2.11" && controller.plan.availableInputs == working.availableInputs else { throw AppError(message: "Saved connection differs from the reviewed one") }
    undo()
    guard controller.plan == working else { throw AppError(message: "Connection Undo lost previous setup") }
    var second = MonitorInputPlan(); second.display = "22222222-2222-2222-2222-222222222222"
    second.inputs = [.init(code:17,name:"Second display HDMI"),.init(code:15,name:"Second display DP")]
    try controller.save(second)
    guard controller.savedPlan(for: display.id) == working else { throw AppError(message:"Selecting a second display discarded the first setup") }
    try controller.save(working)
    guard controller.savedPlan(for: second.display) == second else { throw AppError(message:"Returning to the first display discarded the second setup") }
    let identify = fresh.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Identify input…" }!
    let readCurrent = fresh.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Read current input" }!
    backend.reported = 145; readCurrent.performClick(nil)
    let readEnd = Date().addingTimeInterval(2)
    while controller.busy && Date()<readEnd { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    guard identify.isHidden else { throw AppError(message:"Identification offered despite working automatic detection") }
    backend.reported = nil; readCurrent.performClick(nil)
    let unavailableEnd = Date().addingTimeInterval(2)
    while controller.busy && Date()<unavailableEnd { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    guard !identify.isHidden else { throw AppError(message:"Identification unavailable after failed detection") }
    let beforeIdentification = backend.commands.count
    identify.performClick(nil)
    guard host.pages.last?.title == "Identify this Mac’s input", backend.commands.count == beforeIdentification else { throw AppError(message:"Identification opening sent a switch") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-identification.png")
    host.goBack()
    host.goBack()
    print("PASS: ordinary monitor changes save immediately; setup Save/Cancel isolates protocol, mapping and connection drafts; checks do not save; stale checks refused; failed Save retains draft; Undo and per-display storage; mock monitor only")
}
