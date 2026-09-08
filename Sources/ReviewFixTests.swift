import AppKit
import Carbon

/// Regression journeys use synthetic process identities, mock monitor transport,
/// temporary preference domains, and canceled/injected forms. No live mutations.
func runReviewFixTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    for runtime in ["node", "bun"] {
        for (tool, package) in [("codex", "@openai/codex"), ("claude", "@anthropic-ai/claude-code")] {
            let script = "/fixture/node_modules/\(package)/" + (tool == "codex" ? "bin/codex.js" : "cli.js")
            for (args, expected) in [([runtime, script], true), ([runtime, "/fixture/indexer.js", script], false), ([script, "/fixture/indexer.js"], false), ([runtime, "--eval", script], false), ([runtime, "--require=" + script, "/fixture/indexer.js"], false), ([runtime, script.replacingOccurrences(of: package, with: package + "-tools")], false), ([runtime, "/fixture/node_modules/\(package)/README.md"], false), ([runtime, "/fixture/node_modules/\(package)/diagnostics.js"], false)] {
                func process(_ pid: Int, path: String) -> [String: Any] {
                    ["audit_token": ["pid": pid, "pidversion": 1, "auid": getuid(), "euid": getuid(), "ruid": getuid(), "egid": getgid(), "rgid": getgid(), "asid": 7], "executable": ["path": path]]
                }
                let data = try JSONSerialization.data(withJSONObject: ["global_seq_num": 1, "process": process(400010, path: "/bin/zsh"), "event": ["exec": ["target": process(400011, path: "/fixture/" + runtime), "args": args]]])
                let guardian = AgentGuardian()
                guardian.config.targets = [.init(id: "fixture", name: "Fixture", kind: "cli", match: tool)]
                try data.withUnsafeBytes { try BorrowedProcessEvent.withBytes($0) { event in
                    guardian.consumeEvent(event)
                    try check((guardian.ancestry.targets[event.subject.token] != nil) == expected, "Runtime data argument became an agent identity")
                } }
            }
        }
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-build-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root.appendingPathComponent("Helper.app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let executable = contents.appendingPathComponent("MacOS/Perch")
    let expected = ["CFBundleVersion": "41", "CFBundleIdentifier": "fixture.perch"]
    for (version, id, matches) in [("12", "fixture.perch", false), ("41", "fixture.perch", true), ("41", "wrong.app", false)] {
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": version, "CFBundleIdentifier": id], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try check(GuardianInstall.buildMatches(executable: executable, appInfo: expected) == matches, "Helper build/identity mismatch was accepted")
    }

    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    defer { host.modalTestDriver = nil; host.pages = []; host.window.defaultButtonCell = nil }
    let app = AppDelegate(); app.configureSettings(); app.configurePanic(); app.configureSettings()
    try check(host.pages.count == 1 && host.back.title == "Close", "Reopening Settings created a second home")
    let previousLevel = host.window.level
    let restore = host.beginAuthorization()
    try check(host.authorizing && host.window.level == .normal, "Settings can cover the system authorization prompt")
    restore()
    try check(!host.authorizing && host.window.level == previousLevel, "Authorization did not restore the settings window")
    let alert = NSAlert()
    alert.messageText = "Review all changes"
    alert.informativeText = (1...35).map { "Agent \($0): changed recognition rule" }.joined(separator: "\n") + "\nApprove every change?"
    alert.addButton(withTitle: "Apply Updates"); alert.addButton(withTitle: "Cancel")
    alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = "\u{1b}"
    var readable = false, keys = false, renderError: Error?
    host.modalTestDriver = { _ in
        readable = host.detailScroll.documentView === host.detail && host.detail.frame.height > host.detailScroll.contentSize.height && host.detail.stringValue.hasSuffix("Approve every change?") && host.detailScroll.contentView.bounds.minY == 0 && host.detailScroll.verticalScroller?.isHidden == false
        host.detailScroll.contentView.scroll(to: NSPoint(x: 0, y: host.detail.frame.height-host.detailScroll.contentSize.height))
        readable = readable && host.detail.visibleRect.maxY >= host.detail.bounds.maxY - 1 && !host.detailHint.isHidden
        host.detailScroll.contentView.scroll(to: .zero)
        let buttons = host.container.subviews.first!.subviews.compactMap { $0 as? NSButton }
        keys = buttons.contains { $0.title == "Apply Updates" && $0.keyEquivalent == "\r" } && buttons.contains { $0.title == "Cancel" && $0.keyEquivalent == "\u{1b}" }
        do { try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-review-approval.png") }
        catch { renderError = error }
        return .alertSecondButtonReturn
    }
    _ = host.run(alert)
    if let renderError { throw renderError }
    try check(readable && keys, "Approval text clipped or Return/Escape lost")
    var attempts = 0, retained = false, saved: SafetyConfiguration?
    host.modalTestDriver = { alert in
        attempts += 1
        let view = alert.accessoryView!
        let boxes = view.subviews.compactMap { $0 as? NSButton }
        let enabled = boxes.first { $0.title.hasPrefix("Enable shortcut") }!
        let modifiers = boxes.filter { ["Control", "Option", "Shift", "Command"].contains($0.title) }
        if attempts == 1 {
            enabled.state = .on; modifiers.forEach { $0.state = .off }
            return .alertFirstButtonReturn
        }
        retained = enabled.state == .on && modifiers.allSatisfy { $0.state == .off } && view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Choose at least two") }
        do { try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-review-invalid-draft.png") }
        catch { renderError = error }
        enabled.state = .off
        return attempts == 2 ? .alertFirstButtonReturn : .alertSecondButtonReturn
    }
    app.editSafetyForm(save: { saved = $0 })
    if let renderError { throw renderError }
    try check(attempts == 2 && retained && saved?.shortcut.enabled == false, "Invalid Save lost the draft or disabled shortcut required modifiers")
    host.modalTestDriver = nil
    app.buildMenu(); app.refreshMonitorInputItem()
    try check(app.monitorInputItem.isEnabled && app.monitorInputItem.action == #selector(AppDelegate.monitorInputSettings), "Monitor setup hint does not navigate")
    app.keyboardModes.results = [.init(name: "Fixture", detail: "Needs setup", verified: false)]
    app.refreshExternalFunctionKeyItem()
    try check(app.externalFnItem.isEnabled && app.externalFnItem.action == #selector(AppDelegate.keyboardSettings), "Keyboard setup hint still toggles")
    try check(app.validateMenuItem(app.externalFnItem), "Menu validation blocks the keyboard setup route")
    let keyboard = NavigationKeyboardIdentity(vendor: 1234, product: 123, version: 1, name: "Saved keyboard", transport: "USB", usages: NavigationLearning.usages.sorted())
    var profiles = [NavigationKeyboardProfile(identity: keyboard, keys: [0x68,0x69,nil,nil])]
    let offline = NavigationProbePage(enumerate: { [] }, hasAccess: { false }, saveProfile: { _ in }, readProfiles: { profiles }, resetProfiles: { identity in profiles.removeAll { $0.identity == identity } })
    offline.show()
    try check(offline.picker.titleOfSelectedItem?.contains("disconnected") == true && offline.picker.isEnabled, "Saved disconnected keyboard cannot be selected")
    host.modalTestDriver = { _ in .alertFirstButtonReturn }
    offline.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Reset saved layout…" }!.performClick(nil)
    try check(profiles.isEmpty, "Offline keyboard removal did not target the selected saved layout")
    host.goBack()
    print("PASS: runtime argument identity; helper build migration; stable Settings home; scrollable approvals; Return/Escape; retained invalid draft; disabled shortcut save; setup action routes")
}
