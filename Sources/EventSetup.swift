import AppKit

// One persistent window, one next action, and observed results rather than an assumed grant.
final class EventCollectorSetup: NSObject {
    static let shared = EventCollectorSetup()
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 450))
    let installState = SettingsStatusField(wrappingLabelWithString: "")
    let accessState = SettingsStatusField(wrappingLabelWithString: "")
    let readyState = SettingsStatusField(wrappingLabelWithString: "")
    let guidance = SettingsStatusField(wrappingLabelWithString: "")
    let primary = NSButton()
    var permissionDrag: PermissionDragItem!
    var launcherDrag: PermissionDragItem!
    let intro = NSTextField(wrappingLabelWithString: "")
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
        if !Self.supportedArguments(job["ProgramArguments"] as? [String]) {
            return "The collector uses an unsupported launcher or command. Update it to restore the fixed collector command."
        }
        if job["ProcessType"] as? String != "Interactive" {
            return "The collector uses macOS’s default CPU and I/O throttling. Updating removes that throttling so process events can be delivered promptly. It restarts the collector and begins a new verified observation session; earlier gaps cannot be recovered."
        }
        return nil
    }
    var needsRepair: Bool { repairReason != nil }
    static func supportedArguments(_ arguments: [String]?) -> Bool {
        arguments == [CollectorIdentity.launcher]
    }
    override init() {
        super.init()
        intro.stringValue = "Remember agent subprocesses as they start—even if their parents exit quickly. Setup and health are checked automatically."
        intro.frame = NSRect(x: 24, y: 381, width: 512, height: 46)
        content.addSubview(intro)
        for (index, label) in [installState, accessState, readyState].enumerated() {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.frame = NSRect(x: 24, y: 340 - index * 35, width: 512, height: 27)
            content.addSubview(label)
        }
        guidance.frame = NSRect(x: 24, y: 110, width: 512, height: 154)
        content.addSubview(guidance)
        primary.bezelStyle = .rounded; primary.target = self; primary.action = #selector(nextStep)
        primary.frame = NSRect(x: 306, y: 26, width: 230, height: 32)
        content.addSubview(primary)
        let drag = PermissionDragItem(title: "eslogger · drag / copy path") { URL(fileURLWithPath: "/usr/bin/eslogger") }
        permissionDrag = drag
        drag.frame = NSRect(x: 24, y: 22, width: 245, height: 42)
        content.addSubview(drag)
        launcherDrag = PermissionDragItem(title: "Collector · drag / copy path") { URL(fileURLWithPath: CollectorIdentity.launcher) }
        launcherDrag.frame = NSRect(x: 276, y: 65, width: 260, height: 32)
        content.addSubview(launcherDrag)
        let openSettings = NSButton(title: "Open Full Disk Access…", target: self, action: #selector(openPrivacySettings))
        openSettings.isBordered = false
        openSettings.font = .systemFont(ofSize: 12)
        openSettings.contentTintColor = .linkColor
        openSettings.frame = NSRect(x: 20, y: 65, width: 230, height: 22)
        content.addSubview(openSettings)

    }
    func show(fromSettings: Bool) {
        self.fromSettings = fromSettings
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel) }
        SettingsWindow.shared.show(.init(title: "Process event collection", detail: "See current collection health or complete any missing setup. Status updates automatically; you can return here at any time.", view: content, leave: { [weak self] in self?.timer?.invalidate(); self?.timer = nil }))
        refresh()
    }
    static func collectionReady(_ state: SafetyStatus?, installed: Bool, needsRepair: Bool, waitingForSession: Bool, now: Date = Date()) -> Bool {
        guard installed, !needsRepair, !waitingForSession, state?.fresh == true,
              state?.eventCoverage == "Process events active", state?.eventConnected == true,
              let last = state?.eventLastSeen else { return false }
        return now.timeIntervalSince(last) >= 0 && now.timeIntervalSince(last) < 45
    }
    func refresh() {
        let state = GuardianInstall.status
        let fresh = state?.fresh == true
        if waitingForSession, let session = state?.eventSessionID, session != previousSession { waitingForSession = false }
        let receiving = fresh && state?.eventConnected == true && (state?.eventLastSeen.map { Date().timeIntervalSince($0) < 45 } ?? false)
        let ready = Self.collectionReady(state, installed: installed, needsRepair: needsRepair, waitingForSession: waitingForSession)
        permissionDrag.isHidden = ready || receiving || !installed
        launcherDrag.isHidden = permissionDrag.isHidden || !FileManager.default.fileExists(atPath: CollectorIdentity.launcher)
        intro.stringValue = ready ? "Process event collection is ready. No further setup is needed." : "Remember agent subprocesses as they start—even if their parents exit quickly. Complete the missing step below."
        installState.stringValue = needsRepair ? "⚠  1. Collector update needed" : installed ? "✓  1. Collector installed" : "1. Install Apple’s collector"
        accessState.stringValue = receiving ? "✓  2. Full Disk Access confirmed by received events" : "⚠  2. Live access not yet confirmed"
        readyState.stringValue = ready ? "✓  3. Ready — live event health check passed" : (receiving ? "3. Receiving events — checking stream health…" : "⚠  3. Waiting to receive events")
        installState.textColor = needsRepair ? StatusColors.warning : installed ? StatusColors.success : .labelColor
        accessState.textColor = receiving ? StatusColors.success : StatusColors.warning
        readyState.textColor = ready ? StatusColors.success : StatusColors.warning
        primary.isHidden = false
        primary.isEnabled = !installing
        if installing { primary.title = "Installing…"; return }
        if !installed || needsRepair {
            primary.title = needsRepair ? "Update collector…" : "Install collector…"
            guidance.stringValue = installError ?? (needsRepair
                ? (repairReason ?? "Collector update required.") + "\n\nApprove the update in Perch’s macOS prompt. The update does not reset permissions; macOS may require access for the new launcher. The checks above verify event delivery again."
                : "Perch will ask for administrator approval to install Apple’s built-in eslogger as a background service. It observes process starts, forks and exits. A small Perch launcher records its process identity, then becomes Apple’s collector.\n\nNext, review Full Disk Access. macOS may require access for the native Perch collector launcher; received events confirm whether access is working.")

        } else if waitingForSession {
            let expired = Date().timeIntervalSince(updateRequestedAt ?? .distantPast) > 10
            primary.title = expired ? "Retry verification" : "Starting new observation…"
            primary.isEnabled = expired
            guidance.stringValue = expired ? "The collector update finished, but the helper has not acknowledged the new observation session. Retry verification; if it still cannot respond, repair background protection in Settings." : "The collector update finished. Waiting for Perch to start a new observation session before checking readiness."
        } else if ready {
            primary.isHidden = true
            guidance.stringValue = "Setup complete. Perch is receiving process events and its health check succeeded. Choose another settings category, or close the window.\n\nPanic still performs a fresh sweep and verifies process identities before termination."
        } else if let until = retryUntil, until > Date() {
            primary.title = "Checking…"; primary.isEnabled = false
            guidance.stringValue = "Retry requested. Waiting for a fresh probe event (up to 10 seconds). You can still open Full Disk Access using the link below."
        } else if !fresh {
            primary.title = "Repair background helper…"; primary.isEnabled = true
            guidance.stringValue = installError ?? "The collector is installed, but Perch’s background helper is not responding. Repair it below; this page will recheck collection automatically."
        } else if (state?.processEventCount ?? 0) > 0 && state?.error != nil && state?.error != "Process events need setup. Open Agent Kill Switch settings." {
            primary.title = "Retry health check"
            readyState.stringValue = "⚠  3. Events received, but coverage is degraded"
            guidance.stringValue = (state?.error ?? "Stream verification failed.") + "\n\nEvents arrived earlier, but current readiness is not confirmed. Repeating the permission toggle may not help. Perch is using snapshot fallback."
        } else if receiving {
            primary.title = "Checking automatically…"; primary.isEnabled = false
            guidance.stringValue = "Full Disk Access is working. Perch is now checking that a known process appears in the event stream. This can take up to 45 seconds; no further clicks are needed."
        } else {
            primary.title = "Open Full Disk Access"
            guidance.stringValue = "1. Open Full Disk Access.\n2. Drag eslogger below into the list and enable it.\n\nWith a keyboard: focus its icon and press Space to copy the path. In System Settings, choose +, press ⌘⇧G, paste, then Open.\n\nPerch checks incoming events automatically (allow up to 45 seconds). If none arrive, add and enable the Collector launcher below in the same list."
        }
    }
    @objc func nextStep() {
        if !installed || needsRepair {
            installCollector()
        } else if GuardianInstall.status?.fresh != true {
            do { try GuardianInstall.install(); installError = nil }
            catch { installError = error.localizedDescription }
            refresh()
        } else if waitingForSession {
            do { try requestNewSession(); refresh() } catch { guidance.stringValue = error.localizedDescription }
        } else if Self.collectionReady(GuardianInstall.status, installed: installed, needsRepair: needsRepair, waitingForSession: waitingForSession) { refresh() }
        else if (GuardianInstall.status?.processEventCount ?? 0) > 0 {
            do { try SafetyFiles.send("check-events"); retryUntil = Date().addingTimeInterval(10); refresh() }
            catch { guidance.stringValue = "Could not request a health check: \(error.localizedDescription)" }
        }
        else { SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) } }
    }
    private func installCollector() {
        guard !installing else { return }
        guard !SettingsWindow.shared.testing else { installError = "Collector installation is blocked in tests."; return }
        guard let url = Bundle.main.url(forResource: "install-event-collector", withExtension: "sh"),
              let requirement = HelperStatusIPC.requirement,
              requirement.contains("identifier \"local.scott.perch\"") else {
            installError = "The signed collector installer is unavailable. Reinstall Perch."; refresh(); return
        }
        let launcher = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PerchEventLauncher")
        let launcherRequirement = requirement.replacingOccurrences(of: "identifier \"local.scott.perch\"", with: "identifier \"local.scott.perch.event-launcher\"")
        installing = true; refresh()
        let command = "/bin/sh " + GuardianInstall.shellQuote(url.path) + " " + String(getuid()) + " " + GuardianInstall.shellQuote(launcher.path) + " " + GuardianInstall.shellQuote(launcherRequirement)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        do { _ = try script("do shell script \"\(escaped)\" with administrator privileges"); try requestNewSession(); installError = nil }
        catch { installError = "Installation did not finish: \(error.localizedDescription). You can try again." }
        installing = false; refresh()
    }
    func requestNewSession() throws {
        previousSession = GuardianInstall.status?.eventSessionID
        try SafetyFiles.send("restart-events")
        waitingForSession = true; updateRequestedAt = Date()
    }
    @objc func openPrivacySettings() { SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) } }
    @objc func showFile() { SettingsWindow.shared.handoffToExternalApp { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/usr/bin/eslogger")]); return true } }
}

extension AppDelegate {
    @objc func processEventSetup() { EventCollectorSetup.shared.show(fromSettings: true) }
}
