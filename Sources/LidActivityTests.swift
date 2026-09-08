import AppKit
import Darwin

func runLidActivityTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let many = (0..<1100).map { LidActivityEntry(date: now.addingTimeInterval(Double($0-1100)), source: "Fixture", message: "Event \($0)") }
    let expired = LidActivityEntry(date: now.addingTimeInterval(-86_400), source: "Fixture", message: "Expired")
    let future = LidActivityEntry(date: now.addingTimeInterval(1), source: "Fixture", message: "Future")
    let kept = LidActivityStore.retained([expired] + many + [future], now: now)
    try check(kept.count == 1024 && kept.first?.message == "Event 76" && kept.last?.message == "Event 1099", "Lid log age/count retention failed")
    try check(LidActivityEntry(source: "Fixture", message: String(repeating: "x", count: 1000)).message.count == 512, "Lid event size is unbounded")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("perch-lid-log-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LidActivityStore(directory: directory.path, owner: getuid())
    try store.append(many, now: now)
    try check(try store.read(now: now) == kept, "Persisted log differs from bounded history")
    let reopened = LidActivityStore(directory: directory.path, owner: getuid())
    try check(try reopened.read(now: now).count == 1024, "Log did not survive a new store instance")
    try reopened.append([], now: now.addingTimeInterval(86_400))
    try check(try store.read(now: now.addingTimeInterval(86_400)).isEmpty, "Quiet log was not pruned on disk")
    let group = DispatchGroup(), resultLock = NSLock()
    var errors: [String] = []
    for source in ["Helper", "Watchdog"] {
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                let other = LidActivityStore(directory: directory.path, owner: getuid())
                try other.append((0..<50).map { LidActivityEntry(date: now, source: source, message: "\($0)") }, now: now)
            } catch { resultLock.lock(); errors.append(error.localizedDescription); resultLock.unlock() }
        }
    }
    try check(group.wait(timeout: .now()+5) == .success, "Concurrent log writers stalled")
    try check(errors.isEmpty && (try store.read(now: now)).count == 100, "Concurrent writers lost log events")
    let events = directory.appendingPathComponent("events.json"), target = directory.appendingPathComponent("unrelated")
    try Data("leave me".utf8).write(to: target)
    try FileManager.default.removeItem(at: events)
    try FileManager.default.createSymbolicLink(at: events, withDestinationURL: target)
    var refused = false
    do { try store.append([.init(date: now, source: "Fixture", message: "Must not write")], now: now) } catch { refused = true }
    try check(refused && (try String(contentsOf: target, encoding: .utf8)) == "leave me", "Log writer followed a symlink")

    var tracker = LidActivityTracker(), policy = LidGuardPolicy()
    var messages: [String] = []
    func sample(_ closed: Bool?, _ power: LidPower, _ time: Double) {
        let observation = LidObservation(closed: closed, power: power)
        messages += tracker.observe(observation, now: time)
        let decision = policy.step(observation, now: time, authorized: true)
        messages += tracker.decision(decision, observation: observation, deadline: policy.deadline, now: time)
    }
    sample(false, .external, 0); sample(true, .external, 10); sample(true, .battery, 20)
    let count = messages.count
    for tick in 1...80 { sample(true, .battery, 20+Double(tick)/4) }
    try check(messages.count == count, "Every countdown tick produced a log entry")
    sample(true, .external, 45); sample(true, .battery, 46)
    try check(messages.contains { $0.contains("Plugged in after 25.0 seconds") } && messages.contains { $0.contains("continuing the original interval") }, "Power reconnection timing/flap logs are wrong")
    sample(false, .battery, 50)
    try check(messages.contains { $0.contains("Lid opened after 40.0 seconds closed") } && messages.contains { $0.contains("30.0 seconds of the battery interval. Countdown cancelled") }, "Lid-open elapsed times are wrong")
    sample(true, .battery, 60); sample(true, .battery, 120)
    try check(messages.filter { $0.contains("within 60 seconds. Releasing") }.count == 1, "Expiry was not recorded once")
    sample(true, .battery, 121)
    try check(messages.filter { $0.contains("within 60 seconds. Releasing") }.count == 1, "Stopped policy floods expiry events")
    tracker = LidActivityTracker(); policy = LidGuardPolicy(); messages = []
    sample(false, .battery, 0); sample(true, .battery, 1); sample(true, .external, 20); sample(true, .external, 25)
    try check(messages.contains { $0.contains("five seconds. Battery interval cleared") }, "Stable-power countdown reset missing")
    tracker = LidActivityTracker(); messages = tracker.observe(.init(closed: true, power: .battery), now: 0)
    messages += tracker.observe(.init(closed: false, power: .external), now: 20)
    try check(messages.contains { $0.contains("time closed was not observed") } && !messages.contains { $0.contains("20.0 seconds") }, "Initial unknown durations were fabricated")
    print("PASS: lid activity 24-hour/1,024-entry retention, restart persistence, concurrent helper/watchdog writes, symlink refusal, elapsed transitions, quiet countdowns, cancellation, power flapping and expiry; fixture storage only")
}

func runLidActivityUITests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared; host.testing = true
    let app = AppDelegate(); app.configureSettings(); app.keepAwakeSettings()
    let button = host.pages.last!.view.subviews.compactMap { $0 as? SettingsActionButton }.first { $0.title == "Lid activity…" }
    try check(button != nil, "Keep awake does not offer lid history")
    button!.callback()
    try check(host.pages.last?.title == "Lid activity", "Lid activity action did not navigate")
    host.goBack()
    let date = Date()
    let entries: [LidActivityEntry] = [
        .init(date: date.addingTimeInterval(-80), source: "Lid helper", message: "Unplugged; now on battery."),
        .init(date: date.addingTimeInterval(-79), source: "Lid helper", message: "Lid closed on battery. Starting 60 seconds to open the lid or reconnect power."),
        .init(date: date.addingTimeInterval(-19), source: "Lid helper", message: "Lid not opened and external power not restored within 60 seconds. Releasing lid protection and requesting sleep."),
        .init(date: date.addingTimeInterval(-18), source: "Lid helper", message: "macOS accepted the sleep request. See sleep/wake notifications for the observed transition."),
        .init(date: date.addingTimeInterval(-17), source: "Lid helper", message: "macOS notification: system sleep is beginning."),
        .init(date: date, source: "Lid helper", message: "macOS notification: wake completed, 17.0 seconds after sleep began.")
    ]
    let page = LidActivityPage(read: { $0(.success(entries)) }, helperStatus: { .init(updatedAt: LidGuardClock.now, armed: false, detail: "Off") })
    page.show()
    try check(page.text.string.hasPrefix(LidActivityPage.formatted([entries.last!])) && page.copyText.contains("system sleep is beginning"), "History order or copy contents are wrong")
    try check(page.text.isSelectable && !page.text.isEditable && page.timer != nil, "Log reading controls are not ready")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-lid-activity.png")
    host.goBack()
    try check(page.timer == nil && host.pages.last?.title == "Keep awake", "Lid log Back did not stop polling or return to Keep awake")
    var callback: ((Result<[LidActivityEntry], Error>) -> Void)?
    let delayed = LidActivityPage(read: { callback = $0 }); delayed.show(); host.goBack()
    callback?(.success(entries))
    try check(delayed.text.string.isEmpty && delayed.timer == nil, "A departed log page accepted a delayed result")
    let offline = LidActivityPage(read: { $0(.success(entries)) }, helperStatus: { nil }); offline.show()
    try check(offline.status.stringValue.contains("not currently confirmed") && offline.text.string.contains("wake completed"), "Offline helper hides saved history or appears live")
    host.goBack(); host.goBack()
    print("PASS: live lid history, newest-first readable/copyable entries, saved history with helper offline, Back/close lifecycle and ignored late replies; light/dark renders with fixtures")
}
