import AppKit

/// Perch's publisher changed from a local certificate to Developer ID, and the
/// old Privacy & Security entries stayed behind looking granted. These checks
/// pin when Perch clears them, that it only ever clears its own two services,
/// and that Setup explains it until access is granted again.
func runPublisherChangeTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let suite = "perch.publisher." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { throw AppError(message: "Isolated defaults are unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    let developerID = "identifier \"local.scott.perch\" and certificate leaf[subject.OU] = \"S42F8BV6J2\""
    let localCertificate = "identifier \"local.scott.perch\" and certificate leaf = H\"0f0f\""
    var calls: [[String]] = []
    let accepting: PermissionRecovery.Run = { calls.append($0); return Subprocess.Output(status: 0, data: Data()) }
    func stored() -> PublisherRecord? { defaults.codable(PublisherRecord.self, forKey: PublisherChange.key) }
    func forget() { defaults.removeObject(forKey: PublisherChange.key); calls = [] }
    func store(publisher: String, cleared: String? = nil, services: [PermissionService] = []) {
        try? defaults.setCodable(PublisherRecord(publisher: publisher, seen: Date(), cleared: cleared, clearedServices: services), forKey: PublisherChange.key)
        calls = []
    }

    // A launch with access working records the publisher and touches nothing.
    forget()
    var outcome = PermissionRecovery.perform(current: developerID, failing: [], defaults: defaults, run: accepting)
    try check(outcome == .init() && calls.isEmpty, "A launch with working access cleared a permission")
    try check(stored()?.publisher == developerID && stored()?.cleared == nil, "A healthy launch did not record its publisher")

    // First run under a publisher Perch has not seen, with one failing check.
    forget()
    outcome = PermissionRecovery.perform(current: developerID, failing: [.accessibility], defaults: defaults, run: accepting)
    try check(calls == [["reset", "Accessibility", "local.scott.perch"]], "The stale Accessibility entry was not removed for Perch alone: \(calls)")
    try check(outcome.cleared == [.accessibility] && outcome.failure == nil, "Clearing one service did not report itself")
    try check(stored()?.cleared == developerID && stored()?.clearedServices == [.accessibility], "The clear was not recorded against the publisher")

    // A changed publisher with both failing: both cleared, once.
    store(publisher: localCertificate, cleared: localCertificate, services: [.accessibility])
    outcome = PermissionRecovery.perform(current: developerID, failing: [.accessibility, .inputMonitoring], defaults: defaults, run: accepting)
    try check(calls == [["reset", "Accessibility", "local.scott.perch"], ["reset", "ListenEvent", "local.scott.perch"]], "A new publisher did not clear both permissions: \(calls)")
    try check(outcome.cleared == [.accessibility, .inputMonitoring], "Both cleared services were not reported")
    calls = []
    outcome = PermissionRecovery.perform(current: developerID, failing: [.accessibility, .inputMonitoring], defaults: defaults, run: accepting)
    try check(calls.isEmpty && outcome == .init(), "The next launch cleared the same publisher's permissions again")
    try check(stored()?.cleared == developerID && stored()?.clearedServices == [.accessibility, .inputMonitoring], "The recorded clear was lost on a later launch")

    // The same publisher as last time is an ordinary not-yet-granted permission.
    store(publisher: developerID)
    outcome = PermissionRecovery.perform(current: developerID, failing: [.accessibility, .inputMonitoring], defaults: defaults, run: accepting)
    try check(calls.isEmpty && outcome == .init(), "An ungranted permission under the same publisher was cleared")

    // Never "All", never global, never another app's id.
    forget()
    _ = PermissionRecovery.perform(current: developerID, failing: PermissionService.allCases, defaults: defaults, run: accepting)
    for call in calls {
        try check(call.count == 3 && call[0] == "reset" && call[2] == "local.scott.perch", "A permission reset was not scoped to Perch: \(call)")
        try check(PermissionService(rawValue: call[1]) != nil, "A permission reset named an unexpected service: \(call)")
    }
    try check(!calls.isEmpty && !calls.contains { $0.contains("All") }, "A permission reset cleared every service")

    // A refused or slow reset reports the failure and leaves a retry possible.
    let refusing: PermissionRecovery.Run = { calls.append($0); return Subprocess.Output(status: 1, data: Data()) }
    let timing: PermissionRecovery.Run = { calls.append($0); throw Subprocess.Timeout(executable: PermissionRecovery.tccutil, seconds: 20) }
    for runner in [refusing, timing] {
        store(publisher: localCertificate, cleared: localCertificate)
        outcome = PermissionRecovery.perform(current: developerID, failing: [.accessibility], defaults: defaults, run: runner)
        try check(outcome.cleared.isEmpty && outcome.failure != nil, "A refused permission reset claimed success")
        try check(stored()?.publisher == localCertificate, "A refused permission reset recorded the new publisher, so no later launch retries")
    }

    // Setup explains it while the permissions are missing, and stops when granted.
    try check(PublisherChange.restoreNeeded(current: developerID,
        stored: PublisherRecord(publisher: developerID, seen: Date(), cleared: developerID, clearedServices: [.accessibility, .inputMonitoring]),
        failing: [.inputMonitoring]) == [.inputMonitoring], "Setup named a permission that already works")
    try check(PublisherChange.restoreNeeded(current: developerID,
        stored: PublisherRecord(publisher: developerID, seen: Date(), cleared: developerID, clearedServices: [.accessibility]),
        failing: []) == [], "Setup still asked for access after it was granted")
    try check(PublisherChange.restoreNeeded(current: developerID,
        stored: PublisherRecord(publisher: localCertificate, seen: Date(), cleared: localCertificate, clearedServices: [.accessibility]),
        failing: [.accessibility]) == [], "Setup explained a removal that was not made for this copy")

    var snapshot = SetupSnapshot(config: SafetyConfiguration())
    snapshot.accessRestoreNeeded = [.accessibility, .inputMonitoring]
    let row = snapshot.checks.first { $0.id == "access" }
    try check(row?.state == .attention && row?.route == .inputAccess, "Setup does not show Perch's access as needing attention")
    try check(row?.detail == "Perch removed permission entries that no longer work for this copy. macOS needs Accessibility and Input Monitoring granted again for Perch.",
              "The Perch access explanation changed: \(row?.detail ?? "missing")")
    snapshot.accessRestoreNeeded = []
    try check(snapshot.checks.first { $0.id == "access" } == nil, "Setup explains a removal when nothing was removed")
    print("PASS: a new publisher's dead Accessibility and Input Monitoring entries are removed once, only for Perch, never as All or globally; refusals keep a retry; Setup explains it until access is granted")
}
