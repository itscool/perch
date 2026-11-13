import AppKit
import Darwin

/// Perch's background helper. It runs beside the menu app and does the few
/// things that must keep working if Perch quits or crashes:
///
/// - It puts back a screen the desk handed to another Mac when the Perch that
///   handed it is gone, so a crash never leaves a monitor dark.
/// - It keeps the Mac awake while Perch is asked to.
/// - It passes the input helper's request to ask for keyboard access.
/// - It reports its own health, so Perch can tell a stale or missing helper.
///
/// It was also the Agent Kill Switch's watcher. It followed every process start
/// and exit on the Mac, took a snapshot of the whole process table and every
/// running app each second, and could freeze and kill AI agents on a shortcut.
/// Scott removed that feature on November 12, 2026: it never once helped, and
/// that constant system-wide watching slowed the Mac down. What remains here is
/// only what other features need.
final class AgentGuardian {
    var config = SafetyConfiguration.load()
    var statusServer: HelperStatusServer?
    let awake = Awake()
    var responsiveness: NSObjectProtocol?
    var timer: Timer?
    var configSignal: FileChangeSignal?
    var requestSignal: FileChangeSignal?
    var configurationDirty = true
    var requestsDirty = true
    var maintenance = GuardianMaintenanceCounts()
    var statusError: String?
    /// Set while launch jobs the retired kill switch switched off could not all
    /// be switched back on. Every start tries again.
    var recoveryError: String?
    var lastStatus = Date.distantPast
    var tickQueued = false
    var singleton: Int32 = -1

    func run() {
        do { try SafetyFiles.prepare() } catch { exit(1) }
        singleton = open(SafetyFiles.base.appendingPathComponent("watcher.lock").path, O_CREAT | O_RDWR, 0o600)
        guard singleton >= 0, flock(singleton, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        recoveryError = Self.retireKillSwitch()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        responsiveness = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Put back desk screens and keep the Mac awake for Perch")
        configSignal = FileChangeSignal(SafetyFiles.config) { [weak self] in self?.configurationDirty = true; self?.queueTick() }
        requestSignal = FileChangeSignal(SafetyFiles.requests) { [weak self] in self?.requestsDirty = true; self?.queueTick() }
        let server = HelperStatusServer(service: HelperStatusIPC.guardian)
        statusServer = server; server.start()
        try? FileManager.default.removeItem(at: SafetyFiles.base.appendingPathComponent("status.json"))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
        NSApp.run()
    }

    func queueTick() {
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.tickQueued = false; self.tick()
        }
    }

    /// Undo what the Agent Kill Switch left switched off, then remove its files.
    ///
    /// Its emergency stop disabled the launch jobs of the agents it stopped and
    /// kept that list on disk for "Resume". With the feature gone nothing could
    /// ever resume them, so every start of the helper switches them back on
    /// first. The state file is deleted only once that has fully succeeded.
    /// Returns a message while some job still could not be re-enabled.
    @discardableResult
    static func retireKillSwitch(stateURL: URL = SafetyFiles.state, retired: [URL] = SafetyFiles.retired,
                                 enable: (String) -> String = { LaunchdJob.user($0).enable().description }) -> String? {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard var state = try? SafetyFiles.read(SafetyState.self, from: stateURL) else {
                // Unreadable: nothing can be recovered from it, and keeping it
                // would retry forever.
                try? FileManager.default.removeItem(at: stateURL)
                return nil
            }
            if !state.disabledJobs.isEmpty || state.locked {
                do {
                    let failed = try AgentJobRecovery.resume(state: &state, persist: { try SecureFile.writeAtomically($0, to: stateURL, durable: true) }, enable: enable)
                    if !failed.isEmpty {
                        return "Some apps the Agent Kill Switch stopped could not be allowed to start again: " + failed.joined(separator: ", ") + ". Perch will retry."
                    }
                } catch { return "Could not record putting back apps the Agent Kill Switch stopped. Perch will retry." }
            }
            try? FileManager.default.removeItem(at: stateURL)
        }
        for url in retired { try? FileManager.default.removeItem(at: url) }
        return nil
    }

    func refreshConfigurationIfNeeded() {
        guard configurationDirty else { return }
        configurationDirty = false; maintenance.configurationReads &+= 1
        config = SafetyConfiguration.load()
    }

    func pendingRequests(directory: URL = SafetyFiles.requests) -> [(URL, SafetyRequest)] {
        guard requestsDirty else { return [] }
        requestsDirty = false; maintenance.requestScans &+= 1
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { requestsDirty = true; return [] } // Retry an I/O failure on the next tick.
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, SafetyRequest)? in
            guard let request = try? SafetyFiles.read(SafetyRequest.self, from: url) else { try? FileManager.default.removeItem(at: url); return nil }
            return (url, request)
        }.sorted { $0.1.timestamp < $1.1.timestamp }
    }

    func tick() {
        DeskDesktopRecovery.recover()
        // Only compare cheap file revisions here; change notifications still
        // run the work straight away.
        if configSignal?.refresh() == true { configurationDirty = true }
        if requestSignal?.refresh() == true { requestsDirty = true }
        refreshConfigurationIfNeeded()
        // Keep awake belongs to a running Perch.
        do { try awake.set(config.keepAwake && !FileManager.default.fileExists(atPath: HelperLifecycle.closedMarker.path)) } catch { statusError = error.localizedDescription }
        let requests = pendingRequests()
        for (url, request) in requests {
            defer { try? FileManager.default.removeItem(at: url) }
            guard Date().timeIntervalSince(request.timestamp) < 30 else { continue }
            // Every other action belonged to the retired kill switch and is ignored.
            if request.action == "input-access" { try? SafetyFiles.write(Date(), to: InputHelperStatus.permissionRequest) }
        }
        if Date().timeIntervalSince(lastStatus) >= 1 || !requests.isEmpty {
            let status = SafetyStatus(inputTrusted: nil, inputActive: false, keepAwakeActive: awake.enabled,
                                      message: "Putting back desk screens and keeping the Mac awake when asked",
                                      error: recoveryError ?? statusError, maintenance: maintenance)
            statusServer?.publishSnapshot { status }
            lastStatus = Date()
        }
    }
}
