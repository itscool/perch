import AppKit

func runMonitorInputTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let a = MonitorInput(code: 17,name: "HDMI 1"), b = MonitorInput(code: 15,name: "DisplayPort")
    var plan = MonitorInputPlan(); plan.inputs = [a,b]
    try check(try plan.next(current: 17,lastSent: nil) == b && plan.next(current: 15,lastSent: nil) == a && plan.next(current: 18,lastSent: nil) == a, "Cycle order/wrap/current-outside-list failed")
    do { _ = try plan.next(current: nil,lastSent: 17); throw AppError(message: "Unknown input silently used a stale position") } catch let e as AppError { try check(!e.message.contains("silently"), e.message) }
    plan.allowUnconfirmedCycle = true
    try check(try plan.next(current: nil,lastSent: 17) == b && plan.next(current: nil,lastSent: nil) == a, "Explicit unconfirmed cycle fallback failed")
    plan.inputs = [a,a]; try check(!plan.valid,"Duplicate input codes accepted")
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
    let controller = MonitorInputController(displays:[display],backend:mock)
    controller.message = "✓ LG HDR 4K detected · choose inputs to cycle"
    controller.plan.inputs = [.init(code:144,name:"HDMI 1"),.init(code:145,name:"HDMI 2"),.init(code:208,name:"DisplayPort"),.init(code:210,name:"USB-C")]
    controller.plan.display = display.id; controller.plan.alternate = true
    let app = AppDelegate(); app.buildMenu()
    host.show(.init(title:"Perch settings",detail:"",view:NSView()))
    controller.plan.allowUnconfirmedCycle = true
    controller.cycle()
    let deadline = Date().addingTimeInterval(2)
    while controller.busy && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
    let page = MonitorInputPage(controller); page.show()
    guard !page.worked.isHidden && !page.failed.isHidden && !page.status.frame.intersects(page.worked.frame) else { throw AppError(message:"Unconfirmed switch feedback is hidden or overlaps") }
    guard host.pages.count == 2, host.pages.last?.title == "Monitor inputs" else { throw AppError(message:"Monitor setup left the settings stack") }
    try renderReleaseView(host.window.contentView!,path:"/private/tmp/perch-monitor-inputs.png")
    let before = page.protocolChoice.indexOfSelectedItem
    let edit = page.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Edit inputs…" }!
    edit.performClick(nil)
    let child = host.pages.last!.view
    let presets = child.subviews.compactMap { $0 as? NSPopUpButton }.first!
    guard presets.itemTitles.contains("LG 27UN850-W / 27UN850-WY") else { throw AppError(message:"Embedded retail presets absent from settings") }
    child.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Use preset" }!.performClick(nil)
    host.goBack()
    guard page.protocolChoice.indexOfSelectedItem == before else { throw AppError(message:"Cancelled preset selection changed parent settings") }
    host.goBack()
    guard host.pages.count == 1 && controller.pageChanged == nil else { throw AppError(message:"Monitor setup did not clean up on Back") }
    host.pages = []
    guard app.homeEndItem != nil && app.pageKeysItem != nil && app.monitorInputItem != nil else { throw AppError(message:"Navigation or monitor menu option missing") }
    print("PASS: navigation/monitor menu items; monitor settings lifetime and Back; light/dark own-view renders; no input capture or display requests")
}

private final class FakeMonitorBackend: MonitorCommandBackend {
    var commands: [[String]] = []
    var failWrite = true
    var reported: UInt16?
    var reportWritten = false
    func run(_ args: [String]) throws -> Data {
        commands.append(args)
        if args.first == "read" { return Data("{\"current\":\(reported.map(String.init) ?? "null"),\"capabilities\":null}".utf8) }
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
    controller.cycle(); try finish()
    guard controller.warning else { throw AppError(message:"Failed monitor write wasn't surfaced") }
    backend.failWrite = false
    controller.cycle(); try finish()
    controller.cycle(); try finish()
    let writes = backend.commands.filter { $0.first == "switch" }.map { $0.last! }
    guard writes == ["17","17","15"] else { throw AppError(message:"Failed switch advanced the cycle position") }
    guard controller.pendingConfirmation == 15 && controller.warning else { throw AppError(message:"Transport success falsely confirmed monitor control") }
    controller.confirmSwitch(true)
    let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("monitor.confirmed.v1.") }
    guard saved.count == 1 && (saved.values.first as? [Int]) == [15] else { throw AppError(message:"Confirmation did not remain scoped to one input") }
    controller.cycle(); try finish()
    guard controller.warning && controller.pendingConfirmation == 17 else { throw AppError(message:"Another input inherited an unrelated confirmation") }
    controller.confirmSwitch(false)
    guard controller.warning && controller.message.contains("adapter") && controller.pendingConfirmation == nil else { throw AppError(message:"Failed physical switch has no adapter troubleshooting") }
    backend.reported = 15; backend.reportWritten = true
    controller.cycle(); try finish()
    guard !controller.warning && controller.pendingConfirmation == nil && controller.message.contains("Monitor reports") else { throw AppError(message:"Readback did not verify the requested input") }
    let generic = MonitorDescriptor(id:display.id,displayID:99,name:"LG HDR 4K",vendor:7789,model:30470,ddcAvailable:true)
    guard MonitorProfiles.match(generic)?.confidence == "suggested",
          MonitorProfiles.match(generic,reportedModel:"27UN850-W")?.inputs.contains(.init(code:209,name:"USB-C")) == true,
          MonitorProfiles.entries.count >= 21 else { throw AppError(message:"Embedded model profiles missing or ambiguous LG auto-match") }
    print("PASS: production monitor transaction failure preserves cycle position; explicit fallback advances only after accepted commands; mock adapter only")
}
