import AppKit

/// The Core services that replaced per-feature copies: shell quoting, launchd
/// targets, System Settings links, code identity and display/HID enumeration.
/// Nothing here prompts, opens a device or changes the system.
func runCoreServiceTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw AppError(message: message) }
    }
    // Shell words survive the shell exactly, whatever they contain.
    let awkward = ["plain", "with space", "it's", "\"double\"", "back\\slash", "new\nline", "$HOME `id` ; rm", "'''"]
    for word in awkward {
        let output = try Subprocess.run("/bin/sh", ["-c", "printf %s " + AdminShell.quote(word)], timeout: 5, capture: .collect(maximumBytes: 4096))
        try check(output.succeeded && output.text == word, "Shell quoting changed \(word.debugDescription)")
    }
    // AppleScript literals: the escaped text evaluates back to the original.
    for word in awkward {
        let result = try AppleScript.run("\"" + AdminShell.literal(word) + "\"")
        try check(result.stringValue == word, "AppleScript literal changed \(word.debugDescription)")
    }
    let source = AdminShell.privilegedSource("/bin/echo 'a b'")
    try check(source == "do shell script \"/bin/echo 'a b'\" with administrator privileges", "Privileged source is malformed: \(source)")
    try check(source.contains(AdminShell.privilegedSuffix), "Privileged source is not recognised as privileged")
    // launchd targets and outcome wording match what callers embed in messages.
    try check(LaunchdJob.user("a.b", uid: 501).target == "gui/501/a.b" && LaunchdJob.system("c").target == "system/c", "launchd target is malformed")
    try check(LaunchdJob.Outcome.ok.description == "ok" && LaunchdJob.Outcome.failed(3).description == "failed (3)" &&
              LaunchdJob.Outcome.timedOut.description == "timed out" && LaunchdJob.Outcome.error("x").description == "failed: x", "Outcome wording changed")
    try check(LaunchdJob.Outcome.ok.succeeded && !LaunchdJob.Outcome.failed(1).succeeded, "Outcome success is wrong")
    try check(!LaunchdJob.user("local.scott.perch.never-installed-\(UUID().uuidString)").isLoaded(), "An unknown job reported loaded")
    try check(LaunchdJob.run(["print", "system/com.apple.launchd.never-\(UUID().uuidString)"]) != .ok, "print of a missing job succeeded")
    // Replacement waits for a still-unloading job, then retries bootstrap.
    do {
        let job = LaunchdJob.user("a.b", uid: 501), plist = URL(fileURLWithPath: "/fixture/a.b.plist")
        var calls: [String] = [], pauses: [TimeInterval] = [], prints = 0, bootstraps = 0
        let result = job.replace(with: plist, run: { arguments in
            calls.append(arguments[0])
            switch arguments[0] {
            case "print": prints += 1; return prints <= 2 ? .ok : .failed(113)
            case "bootstrap": bootstraps += 1; return bootstraps == 1 ? .failed(5) : .ok
            default: return .ok
            }
        }, pause: { pauses.append($0) })
        try check(result == .ok && calls == ["bootout", "print", "print", "print", "bootstrap", "bootstrap"] && pauses == [0.1, 0.1, 0.25],
                  "Replacement did not wait for unload and retry bootstrap: \(calls) \(pauses)")
        var attempts = 0, clock = 0.0
        let failed = job.replace(with: plist, unloadDeadline: 0.3, run: { arguments in
            if arguments[0] == "bootstrap" { attempts += 1; return .failed(37) }
            return arguments[0] == "print" ? .ok : .ok
        }, pause: { clock += $0 }, now: { clock })
        try check(failed == .failed(37) && attempts == 3, "Replacement did not bound its unload wait and bootstrap attempts")
    }
    // System Settings links stay well-formed deep links.
    for pane in SystemSettingsPane.allCases {
        try check(pane.url.scheme == "x-apple.systempreferences" && pane.url.absoluteString.hasSuffix(pane.rawValue), "Bad settings link for \(pane)")
    }
    try check(SystemSettingsPane.accessibility.rawValue.hasSuffix("Privacy_Accessibility") && SystemSettingsPane.inputMonitoring.rawValue.hasSuffix("Privacy_ListenEvent") && SystemSettingsPane.fullDiskAccess.rawValue.hasSuffix("Privacy_AllFiles"), "Privacy pane identifiers changed")
    // Code identity: hex encoding and the running code's own facts agree.
    try check(CodeIdentity.hex(Data([0, 15, 255])) == "000fff", "Hex encoding is wrong")
    if let current = CodeIdentity.current { try check(current.count == 40 && current.allSatisfy { "0123456789abcdef".contains($0) }, "cdhash is not 40 hex characters") }
    try check(CodeIdentity.designatedRequirement.map { $0.contains("identifier") } ?? true, "Designated requirement lacks an identifier clause")
    do { _ = try CodeIdentity.verifiedHash(of: URL(fileURLWithPath: "/nonexistent/Perch.app"), requirement: "identifier \"x\""); try check(false, "Missing app verified") } catch let error as AppError { try check(error.localizedDescription.contains("signature"), "Unexpected verification message") }
    // Display and HID enumeration are read-only and never fail on a headless run.
    let displays = DisplayIdentity.online()
    try check(displays.allSatisfy { $0.isOnline }, "An online display reported offline")
    try check(displays.count == Set(displays).count, "Display identities are not unique")
    let services = HIDDevices.withAll { $0.count }
    try check(services != nil, "HID enumeration failed")
    try check(IOServices.withMatching("IOAccelerator") { $0.count } != nil, "IOAccelerator enumeration failed")
    // The attachment observer arms, disarms and can be released without a callback firing.
    var fired = 0
    var observer: HIDAttachmentObserver? = HIDAttachmentObserver()
    observer?.changed = { fired += 1 }
    try check(observer?.start() == true && observer?.active == true, "Attachment observer did not start")
    try check(observer?.start() == true, "Restarting an active observer failed")
    observer?.stop()
    try check(observer?.active == false, "Attachment observer did not stop")
    try check(observer?.start() == true, "Observer did not restart after stop")
    observer = nil
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    try check(fired == 0, "Arming the attachment observer reported existing devices as changes")
    print("PASS: shell quoting/AppleScript literals, launchd targets and outcomes, settings links, code identity, display/HID enumeration and attachment observer lifecycle")
}
