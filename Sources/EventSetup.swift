import AppKit

// One persistent window, one next action, and observed results rather than an assumed grant.
final class EventCollectorSetup: NSObject, NSWindowDelegate {
    static let shared = EventCollectorSetup()
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let installState = NSTextField(wrappingLabelWithString: "")
    let accessState = NSTextField(wrappingLabelWithString: "")
    let readyState = NSTextField(wrappingLabelWithString: "")
    let guidance = NSTextField(wrappingLabelWithString: "")
    let primary = NSButton()
    let reveal = NSButton()
    var timer: Timer?
    var fromSettings = false
    var installing = false
    var installError: String?
    var retryUntil: Date?
    var waitingForSession = false
    var previousSession: String?
    var updateRequestedAt: Date?
    var installed: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/local.scott.perch.events.plist") && FileManager.default.fileExists(atPath: ProcessEventStream.pipePath)
    }
    var repairReason: String? {
        guard installed else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/Library/LaunchDaemons/local.scott.perch.events.plist")),
              let job = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return "The collector configuration cannot be read. Update it to restore the supported configuration." }
        if (job["ProgramArguments"] as? [String])?.first != "/usr/bin/eslogger" {
            return "The old launcher makes macOS check the shell’s permission. Updating launches Apple’s collector directly so the eslogger grant can apply."
        }
        if job["ProcessType"] as? String != "Interactive" {
            return "The collector uses macOS’s default CPU and I/O throttling. Updating removes that throttling so process events can be delivered promptly. It restarts the collector and begins a new verified observation session; earlier gaps cannot be recovered."
        }
        return nil
    }
    var needsRepair: Bool { repairReason != nil }
    override init() {
        super.init()
        panel.title = "Set up process event collection"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let intro = NSTextField(wrappingLabelWithString: "Remember agent subprocesses as they start—even if their parents exit quickly. This window checks each step automatically.")
        intro.frame = NSRect(x: 24, y: 341, width: 512, height: 46)
        panel.contentView?.addSubview(intro)
        for (index, label) in [installState, accessState, readyState].enumerated() {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.frame = NSRect(x: 24, y: 300 - index * 35, width: 512, height: 27)
            panel.contentView?.addSubview(label)
        }
        guidance.frame = NSRect(x: 24, y: 87, width: 512, height: 134)
        panel.contentView?.addSubview(guidance)
        primary.bezelStyle = .rounded; primary.target = self; primary.action = #selector(nextStep)
        primary.frame = NSRect(x: 306, y: 26, width: 230, height: 32)
        panel.contentView?.addSubview(primary)
        let drag = PermissionDragItem(title: "Drag eslogger → Settings") { URL(fileURLWithPath: "/usr/bin/eslogger") }
        drag.frame = NSRect(x: 24, y: 22, width: 245, height: 42)
        panel.contentView?.addSubview(drag)
        let openSettings = NSButton(title: "Open Full Disk Access…", target: self, action: #selector(openPrivacySettings))
        openSettings.isBordered = false
        openSettings.font = .systemFont(ofSize: 12)
        openSettings.contentTintColor = .linkColor
        openSettings.frame = NSRect(x: 20, y: 65, width: 230, height: 22)
        panel.contentView?.addSubview(openSettings)

    }
    func show(fromSettings: Bool) {
        self.fromSettings = fromSettings
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel) }
        if let content = panel.contentView {
            SettingsWindow.shared.show(.init(title: "Process event collection", detail: "Follow the steps below. Status updates automatically; you can return here at any time.", view: content, leave: { [weak self] in self?.timer?.invalidate(); self?.timer = nil }))
        }
        refresh()
    }
    func refresh() {
        let state = GuardianInstall.status
        let fresh = state?.fresh == true
        if waitingForSession, let session = state?.eventSessionID, session != previousSession { waitingForSession = false }
        let receiving = fresh && state?.eventConnected == true && (state?.eventLastSeen.map { Date().timeIntervalSince($0) < 45 } ?? false)
        let ready = fresh && !waitingForSession && state?.eventCoverage == "Process events active"
        installState.stringValue = needsRepair ? "⚠  1. Collector update needed" : installed ? "✓  1. Collector installed" : "1. Install Apple’s collector"
        accessState.stringValue = receiving ? "✓  2. Full Disk Access confirmed by received events" : "⚠  2. Live access not yet confirmed"
        readyState.stringValue = ready ? "✓  3. Ready — live event health check passed" : (receiving ? "3. Receiving events — checking stream health…" : "⚠  3. Waiting to receive events")
        installState.textColor = needsRepair ? StatusColors.warning : installed ? StatusColors.success : .labelColor
        accessState.textColor = receiving ? StatusColors.success : StatusColors.warning
        readyState.textColor = ready ? StatusColors.success : StatusColors.warning
        reveal.isHidden = !installed || ready
        primary.isEnabled = !installing
        if installing { primary.title = "Installing…"; return }
        if !installed || needsRepair {
            primary.title = needsRepair ? "Update collector…" : "Install collector…"
            guidance.stringValue = installError ?? (needsRepair
                ? (repairReason ?? "Collector update required.") + "\n\nApprove the update in Perch’s macOS prompt. Existing eslogger access is preserved. The checks above update automatically."
                : "Perch will ask for administrator approval to install Apple’s built-in eslogger as a background service. It observes process starts, forks and exits. Perch itself stays unprivileged.\n\nNext, grant eslogger Full Disk Access. Codex does not need permission.")

        } else if waitingForSession {
            let expired = Date().timeIntervalSince(updateRequestedAt ?? .distantPast) > 10
            primary.title = expired ? "Retry verification" : "Starting new observation…"
            primary.isEnabled = expired
            guidance.stringValue = expired ? "The collector update finished, but the helper has not acknowledged the new observation session. Retry verification; if it still cannot respond, repair background protection in Settings." : "The collector update finished. Waiting for Perch to start a new observation session before checking readiness."
        } else if ready {
            primary.title = "Done"
            guidance.stringValue = "Setup complete. Perch is receiving process events and its health check succeeded. You can close this window.\n\nPanic still performs a fresh sweep and verifies process identities before termination."
        } else if let until = retryUntil, until > Date() {
            primary.title = "Checking…"; primary.isEnabled = false
            guidance.stringValue = "Retry requested. Waiting for a fresh probe event (up to 10 seconds). You can still open Full Disk Access using the link below."
        } else if !fresh {
            primary.title = "Waiting for Perch…"; primary.isEnabled = false
            guidance.stringValue = "The collector is installed, but Perch’s background helper is not responding. Close this window and use Repair background protection in Settings."
        } else if (state?.processEventCount ?? 0) > 0 && state?.error != nil && state?.error != "Process events need setup. Open Agent safety settings." {
            primary.title = "Retry health check"
            readyState.stringValue = "⚠  3. Events received, but coverage is degraded"
            guidance.stringValue = (state?.error ?? "Stream verification failed.") + "\n\nEvents arrived earlier, but current readiness is not confirmed. Repeating the permission toggle may not help. Perch is using snapshot fallback."
        } else if receiving {
            primary.title = "Checking automatically…"; primary.isEnabled = false
            guidance.stringValue = "Full Disk Access is working. Perch is now checking that a known process appears in the event stream. This can take up to 45 seconds; no further clicks are needed."
        } else {
            primary.title = "Open Full Disk Access"
            guidance.stringValue = "Installation succeeded. Next:\n1. Open Full Disk Access.\n2. Drag the eslogger icon below into that list.\n3. Turn on eslogger’s switch.\n\nLeave this window open. The next two checkmarks appear automatically once events arrive (allow up to 45 seconds). Grant eslogger access, not Codex."
        }
    }
    @objc func nextStep() {
        if !installed || needsRepair {
            guard let url = Bundle.main.url(forResource: "install-event-collector", withExtension: "sh") else { installError = "The collector installer is missing. Reinstall Perch."; refresh(); return }
            installing = true; refresh()
            let command = "/bin/sh " + GuardianInstall.shellQuote(url.path) + " " + String(getuid())
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            do { _ = try script("do shell script \"\(escaped)\" with administrator privileges"); try requestNewSession(); installError = nil }
            catch { installError = "Installation did not finish: \(error.localizedDescription). You can try again." }
            installing = false; refresh()
        } else if waitingForSession {
            do { try requestNewSession(); refresh() } catch { guidance.stringValue = error.localizedDescription }
        } else if GuardianInstall.status?.eventCoverage == "Process events active" { SettingsWindow.shared.goBack() }
        else if (GuardianInstall.status?.processEventCount ?? 0) > 0 {
            do { try SafetyFiles.send("check-events"); retryUntil = Date().addingTimeInterval(10); refresh() }
            catch { guidance.stringValue = "Could not request a health check: \(error.localizedDescription)" }
        }
        else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    }
    func requestNewSession() throws {
        previousSession = GuardianInstall.status?.eventSessionID
        try SafetyFiles.send("restart-events")
        waitingForSession = true; updateRequestedAt = Date()
    }
    @objc func openPrivacySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    @objc func showFile() { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/usr/bin/eslogger")]) }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        if fromSettings { fromSettings = false; NSApp.stopModal() }
    }
}

extension AppDelegate {
    @objc func processEventSetup() { EventCollectorSetup.shared.show(fromSettings: true) }
}
