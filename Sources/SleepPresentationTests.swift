import AppKit
import IOKit.pwr_mgt

func runSleepPresentationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var assertion: [String: Any] = [kIOPMAssertionLevelKey: 1, kIOPMAssertionTypeKey: "UserIsActive", kIOPMAssertionNameKey: "Perch: keep Mac awake"]
    try check(!SleepStatus.isPerchKeepAwake(assertion), "Transient activity became a keep-awake request")
    assertion[kIOPMAssertionTypeKey] = kIOPMAssertionTypePreventUserIdleSystemSleep
    try check(SleepStatus.isPerchKeepAwake(assertion), "Explicit Perch assertion was missed")
    assertion[kIOPMAssertionNameKey] = "AppKit activity"
    try check(!SleepStatus.isPerchKeepAwake(assertion), "Unrelated same-process assertion became Keep awake")
    assertion[kIOPMAssertionNameKey] = "Perch: keep Mac awake"; assertion[kIOPMAssertionLevelKey] = 0
    try check(!SleepStatus.isPerchKeepAwake(assertion), "Released assertion stayed active")
    let off = SleepStatus(perchActive: false, caffeinateProcesses: [])
    for master in [false, true] {
        let stopped = SleepPresentation(ordinary: off, actualLid: .off, savedLid: true, masterWanted: master, legacy: false, changing: false, remaining: nil)
        try check(stopped.lid == .on && stopped.lidEnabled && stopped.awake == .off, "Stopped preference unchecked, locked or claimed active")
        try check(stopped.lidHint.contains(master ? "protection stopped" : "Applies when"), "Saved choice has no inactive explanation")
    }
    let unknown = SleepPresentation(ordinary: off, actualLid: .mixed, savedLid: true, masterWanted: true, legacy: false, changing: false, remaining: nil)
    try check(unknown.lid == .on && !unknown.lidEnabled && unknown.lidHint.contains("unknown"), "Unknown session lost intent or allowed unsafe write")
    let active = SleepPresentation(ordinary: off, actualLid: .on, savedLid: true, masterWanted: true, legacy: false, changing: false, remaining: 42)
    try check(active.awake == .on && active.awakeHint == "Lid mode requested" && active.lidHint.contains("42"), "Final snapshot lost lid state/countdown")
    let app = AppDelegate(); app.buildMenu(); app.observedSleep = off; app.observedLidDisabled = false
    app.applyLidSleepPresentation()
    let before = (app.awakeItem.view as! MenuRowView).text
    app.applyLidSleepPresentation()
    try check((app.awakeItem.view as! MenuRowView).text === before, "Unchanged sleep poll replaced rendered title")

    var startup = StartupKeyboardAccessNotice()
    try check(!startup.shouldShow(blocked: false, connected: true, busy: false), "Healthy launch warned")
    try check(!startup.shouldShow(blocked: true, connected: false, busy: false), "Unused optional keyboard feature warned")
    try check(!startup.shouldShow(blocked: true, connected: true, busy: true), "Pending discovery warned")
    try check(startup.shouldShow(blocked: true, connected: true, busy: false), "Blocked connected keyboard did not warn")
    try check(!startup.shouldShow(blocked: true, connected: true, busy: false), "Startup warning repeated")
    try check(LaunchAccessRecovery.automationFailure("Cancelled", code: -128) == "Cancelled", "Cancellation blamed launch context")
    try check(LaunchAccessRecovery.automationFailure("Denied", code: -1743).contains("separate from keyboard"), "Automation failure confused permission scopes")
    let now = Date()
    for wanted in [false, true] {
        for lid: Bool? in [false, true, nil] {
            let incident = LidSleepIncident.capture(wanted: wanted, observation: .init(closed: lid, power: .battery), active: true, now: now)
            try check((incident != nil) == (wanted && lid == true), "Sleep notice captured ordinary/off/unknown-lid sleep")
        }
    }
    let incident = LidSleepIncident.capture(wanted: true, observation: .init(closed: true, power: .external), active: true, now: now)!
    let expiry = LidActivityEntry(date: now.addingTimeInterval(-1), source: "Helper", message: "Lid not opened and external power not restored within 60 seconds. Releasing lid protection and requesting sleep.")
    try check(incident.explanation(events: [expiry]).contains("60-second interval expired"), "Expiry explanation missing")
    let stale = LidActivityEntry(date: now.addingTimeInterval(-121), source: "Helper", message: expiry.message)
    try check(!incident.explanation(events: [stale]).contains("interval expired"), "Stale expiry falsely explains a later sleep")
    let wake = LidActivityEntry(date: now.addingTimeInterval(-0.5), source: "Helper", message: "macOS notification: wake completed")
    try check(!incident.explanation(events: [expiry, wake]).contains("interval expired"), "Earlier sleep interval falsely explains current sleep")
    try check(incident.explanation(events: []).contains("does not identify the cause"), "Missing evidence invented a cause")
    let sleepEvent = LidActivityEntry(date: now, source: "Helper", message: "macOS notification: system sleep is beginning.")
    let wakeEvent = LidActivityEntry(date: now.addingTimeInterval(5), source: "Helper", message: "macOS notification: wake completed, 5 seconds after sleep began.")
    let cancelEvent = LidActivityEntry(date: now.addingTimeInterval(1), source: "Helper", message: "macOS notification: the pending idle-sleep attempt was cancelled.")
    try check(!incident.hasWakeEvidence(events: []) && !incident.hasWakeEvidence(events: [sleepEvent]), "Restart treated sleep intent as completed sleep")
    try check(incident.hasWakeEvidence(events: [sleepEvent, wakeEvent]), "Restart lost corroborated wake")
    try check(!incident.hasWakeEvidence(events: [sleepEvent, cancelEvent, wakeEvent]), "Cancelled attempt borrowed a later wake")
    let unknownIncident = LidSleepIncident.capture(wanted: true, observation: .init(closed: true, power: .unknown), active: nil, now: now)!
    try check(unknownIncident.explanation(events: []).contains("could not be confirmed"), "Stale helper status was presented as definitely inactive")
    let domain = "perch.sleep-notice-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let first = LidSleepNotice(defaults: defaults); first.pending = incident
    let reopened = LidSleepNotice(defaults: defaults)
    try check(reopened.pending == incident, "Pending sleep context did not survive process/store restart")
    reopened.pending = nil
    try check(first.pending == nil, "Acknowledged sleep notice remained pending")
    var delivered = 0
    var acknowledge: (() -> Void)?
    let delivery = LidSleepNotice(defaults: defaults, readEvents: { [sleepEvent, wakeEvent] })
    delivery.show = { _, _, done in delivered += 1; acknowledge = done }
    delivery.pending = incident
    delivery.deliver(); delivery.deliver()
    let deadline = Date().addingTimeInterval(2)
    while delivered == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    try check(delivered == 1, "Pending wake notice was lost or duplicated during delivery")
    delivery.deliver(); try check(delivered == 1, "An open wake notice was presented again")
    acknowledge?(); delivery.deliver()
    try check(delivery.pending == nil && delivered == 1, "Acknowledged notice repeated")
    let host = SettingsWindow.shared
    host.testing = true
    app.configureSettings(); app.keyboardAccessRecovery()
    try check(host.pages.last?.title == "Keyboard access" && host.detail.stringValue.contains("already enabled"), "Access recovery omitted the existing-grant journey")
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "Show Perch in Finder" }, "Access recovery has no route to the installed copy")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-launch-access-recovery.png")
    host.goBack()
    let previousPreference = UserDefaults.standard.object(forKey: SleepMasterChange.lidPreferenceKey)
    let previousConfig = SafetyConfiguration.load()
    defer {
        if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: SleepMasterChange.lidPreferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: SleepMasterChange.lidPreferenceKey) }
        try? previousConfig.save()
    }
    var config = previousConfig; config.keepAwake = false; try config.save()
    UserDefaults.standard.set(true, forKey: SleepMasterChange.lidPreferenceKey)
    app.observedLidDisabled = false; app.observedSleep = off; app.keepAwakeSettings()
    let lidBox = host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Including with the lid closed" }!
    try check(lidBox.state == .on && lidBox.isEnabled, "Settings lost or locked a stopped saved lid choice")
    try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-saved-lid-choice.png")
    app.changeLidChoice(readSleep: { (off, false) })
    try check(!UserDefaults.standard.bool(forKey: SleepMasterChange.lidPreferenceKey) && !SafetyConfiguration.load().keepAwake, "Clicking checked inactive lid choice enabled protection/master instead of clearing intent")
    host.goBack(); app.observedLidDisabled = false; app.observedSleep = off; app.keepAwakeSettings()
    try check(host.pages.last!.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Including with the lid closed" }?.state == .off, "Cleared lid choice did not survive Back/reopen")
    host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: host.window))
    print("PASS: transient sleep assertions, stable polling, saved lid intent/inactive/unknown states, conditional sleep notices, temporal evidence and durable acknowledgement")
}
