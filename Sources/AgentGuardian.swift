import AppKit
import Darwin

final class AgentGuardian {
    var config = SafetyConfiguration.load()
    var state = (try? SafetyFiles.read(SafetyState.self, from: SafetyFiles.state)) ?? SafetyState()
    var tracker = AgentTracker()
    let events = ProcessEventStream()
    var statusServer: HelperStatusServer?
    var ancestry = EventAncestry()
    var eventIdentities: [EventToken: ProcessIdentity] = [:]
    var observedActors: Set<EventToken> = []
    var snapshotTrackedByPID: [UInt32: ProcessIdentity] = [:]
    var eventAppPrefixes: [String: String] = [:]
    lazy var eventHelperPaths = Set([SafetyFiles.binary.path, GuardianInstall.protectedBinary.path])
    let hotKey = PanicHotKey()
    let awake = Awake()
    var lastConfig: SafetyConfiguration?
    var responsiveness: NSObjectProtocol?
    var timer: Timer?
    var configSignal: FileChangeSignal?
    var catalogSignal: FileChangeSignal?
    var requestSignal: FileChangeSignal?
    var configurationDirty = true
    var requestsDirty = true
    var statusTargets: [String] = []
    var maintenance = GuardianMaintenanceCounts()
    var checkpointRevision: UInt64?
    var tickQueued = false
    var savedState: SafetyState?
    func queueTick() {
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.tickQueued = false; self.tick()
        }
    }
    func scheduleTimer() {
        let interval: TimeInterval = state.locked || testing || !verifying.isEmpty ? 0.25 : 1
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval == 1 ? 0.1 : 0
        RunLoop.main.add(timer!, forMode: .common)
    }
    var lastSaved = Date.distantPast
    var lastStatus = Date.distantPast
    var lastTracking = Date.distantPast
    var statusError: String?
    var message = "Watching selected local agents"
    var testing = false
    var testResultID: String?
    var suppressShortcutUntil = Date.distantPast
    var testReceived = false
    var testUntil: Date?
    var permissionWorker: Process?
    struct AppMetadata {
        var id: String?
        var name: String?
        var path: String?
        var executable: String?
        var pid: Int32
    }
    var appMetadata: [ProcessIdentity: AppMetadata] = [:]
    var appClients: [String: String] = [:]
    var appPaths: [String: String] = [:]
    var pendingGlobalReset = false
    var lastEvents: [SafetyEvent] = []
    var singleton: Int32 = -1
    var verifying: [ProcessIdentity: (AgentProcess, Date)] = [:]

    func run() {
        do { try SafetyFiles.prepare() } catch { exit(1) }
        singleton = open(SafetyFiles.base.appendingPathComponent("watcher.lock").path, O_CREAT | O_RDWR, 0o600)
        guard singleton >= 0, flock(singleton, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        if state.bootTime == ProcessTable.bootTime {
            tracker.replace(with: Dictionary(state.tracked.map { ($0.process.identity, $0) }, uniquingKeysWith: { a, _ in a }))
        } else { state.tracked = []; state.bootTime = ProcessTable.bootTime }
        cacheSnapshotIdentities()
        if let history = try? String(contentsOf: SafetyFiles.history, encoding: .utf8) {
            lastEvents = history.split(separator: "\n").suffix(200).compactMap { try? JSONDecoder().decode(SafetyEvent.self, from: Data($0.utf8)) }
        }
        hotKey.action = { [weak self] in self?.keyPressed() }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        responsiveness = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Maintain the user-enabled emergency shortcut and process-event protection")
        events.handler = { [weak self] event in self?.consumeEvent(event) }
        configSignal = FileChangeSignal(SafetyFiles.config) { [weak self] in self?.configurationDirty = true; self?.queueTick() }
        catalogSignal = FileChangeSignal(AgentCatalog.installed) { [weak self] in self?.configurationDirty = true; self?.queueTick() }
        requestSignal = FileChangeSignal(SafetyFiles.requests) { [weak self] in self?.requestsDirty = true; self?.queueTick() }
        let server = HelperStatusServer(service: HelperStatusIPC.guardian)
        statusServer = server; server.start()
        try? FileManager.default.removeItem(at: SafetyFiles.base.appendingPathComponent("status.json"))
        tick()
        NSApp.run()
    }

    func record(_ action: String, process: AgentProcess? = nil, name: String = "", result: String) {
        let event = SafetyEvent(action: action, pid: process?.identity.pid, name: process?.name ?? name, result: result)
        lastEvents.append(event)
        if lastEvents.count > 200 { lastEvents.removeFirst(lastEvents.count - 200) }
        if let data = try? JSONEncoder().encode(event) {
            let path = SafetyFiles.history.path
            if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber, size.intValue > 2_000_000 {
                let previous = SafetyFiles.base.appendingPathComponent("events-previous.jsonl")
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: SafetyFiles.history, to: previous)
            }
            let fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0o600)
            if fd >= 0 {
                let line = data + Data([10])
                line.withUnsafeBytes { raw in _ = Darwin.write(fd, raw.baseAddress, raw.count) }
                close(fd)
            }
        }
    }

    func refreshTracking() {
        let processes = ProcessTable.snapshot()
        let identities = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity.pid, $0.identity) })
        appMetadata = appMetadata.filter { identities[$0.key.pid] == $0.key }
        var apps: [AppMetadata] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let identity = identities[app.processIdentifier] else { continue }
            if appMetadata[identity] == nil {
                appMetadata[identity] = AppMetadata(id: app.bundleIdentifier, name: app.localizedName, path: app.bundleURL?.path, executable: app.executableURL?.path, pid: app.processIdentifier)
            }
            if let metadata = appMetadata[identity] { apps.append(metadata) }
        }
        var roots: [ProcessIdentity: String] = [:]
        var excluded = Set<ProcessIdentity>()
        let ownPaths = Set(apps.filter { $0.id == "local.scott.perch" }.compactMap { $0.executable })
        let enabled = config.targets.filter(\.enabled)
        let helperPath = SafetyFiles.binary.path
        let protectedPath = GuardianInstall.protectedBinary.path
        var matchingApps: [String: AppMetadata] = [:]
        for target in enabled where target.kind == "app" {
            matchingApps[target.id] = apps.first { target.matchesApp(bundleID: $0.id, name: $0.name) }
        }
        for process in processes {
            if process.identity.pid == getpid() || ownPaths.contains(process.executable) || process.executable == helperPath || process.executable == protectedPath {
                excluded.insert(process.identity)
                continue
            }
            let processName = process.name
            let nodeScript = (processName == "node" || processName == "bun") ? ProcessTable.nodeScript(process) : nil
            for target in enabled {
                if target.kind == "app" {
                    if let app = matchingApps[target.id],
                       process.identity.pid == app.pid || app.path.map({ process.executable.hasPrefix($0 + "/") }) == true {
                        roots[process.identity] = target.id
                        if let id = app.id { appClients[target.id] = id }; if let path = app.path { appPaths[target.id] = path }
                        break
                    }
                } else if target.kind == "executable", process.executable == target.match {
                    roots[process.identity] = target.id
                    break
                } else if target.kind == "cli" {
                    var matches = processName == target.match
                    if target.match == "claude", process.executable.contains("/.local/share/claude/versions/") { matches = true }
                    if !matches, let script = nodeScript {
                        matches = AgentLaunchIdentity.matches(script: script, target: target.match)
                    }
                    if matches { roots[process.identity] = target.id; break }
                }
            }
        }
        // Never target the watcher/UI or their helper processes, even when launched by an agent.
        var more = true
        while more {
            more = false
            let ids = Set(excluded.map(\.pid))
            for p in processes where ids.contains(p.parent) && !excluded.contains(p.identity) { excluded.insert(p.identity); more = true }
        }
        tracker.update(processes: processes, roots: roots, enabledTargets: Set(enabled.map(\.id)), excluded: excluded)
        cacheSnapshotIdentities()
        eventAppPrefixes = appPaths.mapValues { $0 + "/" }
        lastTracking = Date()
    }

    func cacheSnapshotIdentities() {
        // A snapshot may newly attribute an actor previously seen as unrelated.
        // Reconsider cached misses against the updated membership on its next event.
        observedActors.removeAll(keepingCapacity: true)
        snapshotTrackedByPID = Dictionary(tracker.tracked.keys.map { (UInt32($0.pid), $0) }, uniquingKeysWith: { a, _ in a })
    }

    func consumeEvent(_ event: BorrowedProcessEvent) {
        let actor = event.actor, subject = event.subject
        let actorToken = actor.token, subjectToken = subject.token
        // Exit only removes this execution identity. Its descendants already
        // inherited attribution when they were born, even if this parent vanished.
        if event.kind == .exit {
            _ = ancestry.consume(kind: .exit, actor: actorToken, subject: subjectToken, root: nil, exclude: false)
            observedActors.remove(actorToken)
            if let identity = eventIdentities.removeValue(forKey: actorToken) { tracker.remove(identity) }
            return
        }
        func protected(_ p: BorrowedEventProcess) -> Bool {
            p.token.pid == UInt32(getpid()) || p.signingID.equals("local.scott.perch") || eventHelperPaths.contains(where: { p.path.equals($0) })
        }
        func match(_ p: BorrowedEventProcess, withArguments: Bool = false) -> String? {
            guard p.token.ruid == getuid() else { return nil }
            for t in config.targets where t.enabled {
                if t.kind == "executable" && p.path.equals(t.match) { return t.id }
                if t.kind == "app" {
                    if p.signingID.equals(t.match) || eventAppPrefixes[t.id].map({ p.path.hasPrefix($0) }) == true { return t.id }
                    if t.match == "ChatGPT" && p.path.contains("/ChatGPT.app/Contents/") { return t.id }
                    if t.match == "Claude" && p.path.contains("/Claude.app/Contents/") { return t.id }
                }
                if t.kind == "cli" {
                    if p.path.basenameEquals(t.match) || (t.match == "claude" && p.path.contains("/.local/share/claude/versions/")) { return t.id }
                    if withArguments && event.scriptMatchesAgent(t.match) { return t.id }
                }
            }
            return nil
        }
        let actorProtected = protected(actor)
        if actorToken.ruid == getuid() && ancestry.targets[actorToken] == nil && !actorProtected && observedActors.insert(actorToken).inserted {
            if let root = match(actor) { ancestry.targets[actorToken] = root }
            // Only snapshot-tracked PIDs need bridging into the event graph.
            // Always validate the full audit token and birth identity before use.
            else if let identity = snapshotTrackedByPID[actorToken.pid], let previous = tracker.tracked[identity],
                    actorToken.liveProcess()?.identity == identity { ancestry.targets[actorToken] = previous.targetID }
        }
        let target = ancestry.consume(kind: event.kind, actor: actorToken, subject: subjectToken,
                                      root: match(subject, withArguments: event.usesArguments), exclude: actorProtected || protected(subject))
        if event.kind == .exec {
            observedActors.remove(actorToken)
            eventIdentities.removeValue(forKey: actorToken)
        }
        if let target, let live = subjectToken.liveProcess() {
            tracker.insert(TrackedAgent(process: live, targetID: target))
            eventIdentities[subjectToken] = live.identity
        }
        if ancestry.targets.count + ancestry.excluded.count + observedActors.count > 100_000 {
            ancestry = EventAncestry(); eventIdentities.removeAll(); observedActors.removeAll()
            events.coverageGap = true; events.failure = "Process ancestry capacity exceeded; coverage has a gap."
        }
    }

    func refreshConfigurationIfNeeded() {
        guard configurationDirty else { return }
        configurationDirty = false; maintenance.configurationReads &+= 1
        let loaded = SafetyConfiguration.load()
        let unreadable = FileManager.default.fileExists(atPath: SafetyFiles.config.path)
            && (try? SafetyFiles.read(SafetyConfiguration.self, from: SafetyFiles.config)) == nil
        if loaded != lastConfig {
            config = loaded
            statusTargets = config.targets.filter(\.enabled).map(\.name)
            let enabled = Set(config.targets.filter(\.enabled).map(\.id))
            observedActors.removeAll()
            ancestry.targets = ancestry.targets.filter { enabled.contains($0.value) }
            lastTracking = .distantPast; lastConfig = loaded; statusError = nil
            if !testing {
                do { try hotKey.register(config.shortcut) } catch { statusError = error.localizedDescription }
            }
        }
        if unreadable {
            configurationDirty = true // Retry transient read failures on the recovery tick.
            statusError = "Safety configuration is unreadable. Repair settings before relying on panic."
        } else if statusError == "Safety configuration is unreadable. Repair settings before relying on panic." { statusError = nil }
    }

    func pendingRequests(directory: URL = SafetyFiles.requests) -> [(URL, SafetyRequest)] {
        guard requestsDirty else { return [] }
        requestsDirty = false; maintenance.requestScans &+= 1
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { requestsDirty = true; return [] } // Retry transient I/O failure on the recovery tick.
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, SafetyRequest)? in
            guard let request = try? SafetyFiles.read(SafetyRequest.self, from: url) else { try? FileManager.default.removeItem(at: url); return nil }
            return (url, request)
        }.sorted { $0.1.timestamp < $1.1.timestamp }
    }

    func updateCheckpointTracking() {
        guard checkpointRevision != tracker.revision else { return }
        state.tracked = tracker.tracked.values.sorted { a, b in
            let x = a.process.identity, y = b.process.identity
            return (x.pid, x.seconds, x.microseconds) < (y.pid, y.seconds, y.microseconds)
        }
        checkpointRevision = tracker.revision; maintenance.checkpointSorts &+= 1
    }

    func tick() {
        defer { scheduleTimer() }
        // Keep the original one-second recovery check, but only compare cheap
        // file revisions. Notifications still run the work immediately.
        if configSignal?.refresh() == true { configurationDirty = true }
        if catalogSignal?.refresh() == true { configurationDirty = true }
        if requestSignal?.refresh() == true { requestsDirty = true }
        refreshConfigurationIfNeeded()
        do { try awake.set(config.keepAwake) } catch { statusError = error.localizedDescription }
        events.tick()
        if Date().timeIntervalSince(lastTracking) >= (events.healthy ? 30 : 5) { refreshTracking() }
        let requests = pendingRequests()
        for (url, request) in requests {
            defer { try? FileManager.default.removeItem(at: url) }
            guard Date().timeIntervalSince(request.timestamp) < 30 else { record("request", result: "expired queued request ignored"); continue }
            switch request.action {
            case "stop": testing = false; testUntil = nil; panic()
            case "resume": resume()
            case "test": beginTest()
            case "finish-test": finishTest()
            case "preview": preview()
            case "restart-events":
                record("new event observation", result: "Collector updated; prior collection gaps are not recoverable")
                events.restartObservation()
                ancestry = EventAncestry(); eventIdentities.removeAll(); observedActors.removeAll()
                state.trackingSince = Date()
                refreshTracking()
            case "check-events": events.lastProbe = .distantPast; events.tick()
            case "input-access": try? SafetyFiles.write(Date(), to: InputHelperStatus.permissionRequest)
            case "lockdown": broadReset()
            default: record("request", result: "ignored unknown action")
            }
        }
        for (identity, entry) in verifying {
            if ProcessTable.inspect(identity.pid)?.identity != identity {
                record("verified exit", process: entry.0, result: "process no longer running")
                verifying.removeValue(forKey: identity)
            } else if Date().timeIntervalSince(entry.1) > 2 {
                statusError = "A process has not exited after termination. See report."
            }
        }
        if state.locked { enforce() }
        if pendingGlobalReset && permissionWorker?.isRunning != true { pendingGlobalReset = false; resetPermissions(global: true) }
        if testing, let lease = try? SafetyFiles.read(Date.self, from: SafetyFiles.base.appendingPathComponent("shortcut-test-lease.json")), Date().timeIntervalSince(lease) > 5 {
            finishTest()
            suppressShortcutUntil = Date().addingTimeInterval(3)
        }
        if let until = testUntil, Date() > until, testing && !testReceived {
            // Keep test interception active until explicitly finished; no late press can panic.
            message = "Shortcut test expired — finish the test in Perch"
        }
        if Date().timeIntervalSince(lastSaved) >= 1 {
            updateCheckpointTracking()
            if savedState != state {
                do { try SafetyFiles.write(state, to: SafetyFiles.state); savedState = state; maintenance.checkpointWrites &+= 1 }
                catch { statusError = "Cannot save watcher state: \(error.localizedDescription)" }
            }
            lastSaved = Date()
        }
        if Date().timeIntervalSince(lastStatus) >= 1 || !requests.isEmpty {
            let status = SafetyStatus(locked: state.locked, pendingLaunchJobs: state.disabledJobs.count, shortcutActive: hotKey.active, inputTrusted: nil, inputActive: false, keepAwakeActive: awake.enabled, trackedCount: tracker.tracked.count, targets: statusTargets, message: message, testResultID: testResultID, testUntil: testUntil, error: statusError ?? (events.healthy ? nil : events.failure), eventCoverage: events.healthy ? "Process events active" : "Degraded — process events unavailable or incomplete", processEventCount: events.eventCount, eventLastSeen: events.lastEvent, eventConnected: events.fd >= 0, eventSessionID: events.sessionID, maintenance: maintenance)
            let diagnostics = events.diagnosticSnapshot
            statusServer?.publishSnapshot {
                var result = status
                result.eventDiagnostics = diagnostics.text
                return result
            }
            lastStatus = Date()
        }
    }

    func panic(resetPermissions shouldReset: Bool = true) {
        defer { scheduleTimer() }
        guard !state.locked else { enforce(); return }
        state.locked = true
        state.tracked = Array(tracker.tracked.values)
        do { try SafetyFiles.write(state, to: SafetyFiles.state) } catch { statusError = "Lockdown could not be saved across watcher restart." }
        record("panic", result: "agent stop requested; relaunch monitoring enabled")
        enforce()
        disableAgentJobs()
        message = "Agents blocked until you explicitly resume"
        if shouldReset && config.resetAgentPermissions { resetPermissions(global: config.resetAllPermissions == true) }
    }

    func enforce() {
        events.drain()
        refreshTracking()
        guard !tracker.tracked.isEmpty else { return }
        // Freeze parents and descendants before killing; rescan for children born during the snapshot.
        var frozen: [ProcessIdentity: AgentProcess] = [:]
        for _ in 0..<3 {
            refreshTracking()
            for tracked in tracker.tracked.values where frozen[tracked.process.identity] == nil && verifying[tracked.process.identity] == nil {
                let process = tracked.process
                let result = ProcessTable.signal(process, SIGSTOP)
                if result == "sent" { frozen[process.identity] = process }
                else if result.hasPrefix("failed") || result.hasPrefix("refused") { record("freeze", process: process, result: result); statusError = "Some processes could not be stopped. See report." }
            }
        }
        for process in frozen.values {
            let result = ProcessTable.signal(process, SIGKILL)
            record("terminate", process: process, result: result)
            if result == "sent", verifying[process.identity] == nil { verifying[process.identity] = (process, Date()) }
            if result != "sent" && result != "already exited" {
                // Never leave a process silently suspended if termination failed.
                _ = ProcessTable.signal(process, SIGCONT)
                statusError = "Some processes could not be terminated. See report."
            }
        }
    }

    func keyPressed() {
        guard Date() >= suppressShortcutUntil else { return }
        if testing {
            guard !testReceived else { return }
            testReceived = true
            message = Date() <= (testUntil ?? .distantPast) ? "Shortcut received — no action taken" : "Late test key received — no action taken"
            record("shortcut test", result: message)
            testResultID = UUID().uuidString
            message = "Shortcut worked — test remains harmless until closed"
            suppressShortcutUntil = Date().addingTimeInterval(3)
            return
        }
        panic()
    }
    func beginTest() {
        testing = true
        testReceived = false
        testUntil = Date().addingTimeInterval(30)
        var shortcut = config.shortcut
        shortcut.enabled = true
        do { try hotKey.register(shortcut); message = "Shortcut test active — no destructive action" }
        catch { statusError = error.localizedDescription; testing = false; testUntil = nil; try? hotKey.register(config.shortcut) }
    }
    func finishTest() {
        testing = false
        testUntil = nil
        do { try hotKey.register(config.shortcut); message = state.locked ? "Agents blocked until you explicitly resume" : "Watching selected local agents" }
        catch { statusError = error.localizedDescription }
    }
    func resume() {
        state.locked = false
        // Removed launch jobs remain unloaded; restoring permission to launch does not launch an agent.
        var stillDisabled: [String] = []
        for label in state.disabledJobs {
            let result = SafetyCommand.run("/bin/launchctl", ["enable", "gui/\(getuid())/\(label)"])
            record("restore launch eligibility", name: label, result: result)
            if result != "ok" { stillDisabled.append(label); statusError = "Some launch jobs could not be re-enabled. See report." }
        }
        state.disabledJobs = stillDisabled
        do { try SafetyFiles.write(state, to: SafetyFiles.state) } catch { statusError = "Could not save resumed state." }
        record("resume", result: "relaunch monitoring released; apps and privacy grants were not restored")
        message = "Watching selected local agents"
    }
    func preview() {
        events.drain()
        refreshTracking()
        let list = tracker.tracked.values.sorted { $0.process.identity.pid < $1.process.identity.pid }.map { "\($0.process.identity.pid)  \($0.process.name)  [\($0.targetID)]" }
        let text = "PERCH · AGENT KILL SWITCH\n\nMode: \(state.locked ? "BLOCKING RELAUNCHES" : "WATCHING")\n\nCurrent stop list (read-only preview)\n\(list.isEmpty ? "No matching processes currently observed." : list.joined(separator: "\n"))\n\nCoverage\n• Current-user local processes only.\n• Descendants observed by this watcher, including later reparented ones.\n• Event collection: \(events.healthy ? "active" : "degraded").\n• Collection gaps or descendants created before observation may be missed.\n• Remote jobs, root processes and managed services are not controlled.\n• The watcher is independent and restarted by launchd, but not tamper-resistant.\n\nRecent events\n" + lastEvents.map { "\($0.timestamp): \($0.action) \($0.name) \($0.pid.map(String.init) ?? "") — \($0.result)" }.joined(separator: "\n")
        try? text.write(to: SafetyFiles.report, atomically: true, encoding: .utf8)
    }
    func disableAgentJobs() {
        let roots = config.targets.filter(\.enabled)
        let dirs = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents")]
        for dir in dirs {
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url), let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any], let label = plist["Label"] as? String,
                      label != GuardianInstall.label else { continue }
                let executable = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
                let matches = roots.contains { target in
                    if target.kind == "executable" { return executable == target.match }
                    if target.kind == "cli" { return URL(fileURLWithPath: executable).lastPathComponent == target.match }
                    return appPaths[target.id].map { executable.hasPrefix($0 + "/") } == true
                }
                guard matches else { continue }
                // Only alter loaded jobs that were not already disabled; never guess from labels.
                let disabled = SafetyCommand.capture("/bin/launchctl", ["print-disabled", "gui/\(getuid())"])
                guard let disabled else { record("relaunch job", name: label, result: "could not read prior disabled state; left unchanged"); continue }
                let pattern = "\"" + NSRegularExpression.escapedPattern(for: label) + "\"\\s*=>\\s*true"
                if disabled.range(of: pattern, options: .regularExpression) != nil { continue }
                guard SafetyCommand.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == "ok" else { continue }
                let result = SafetyCommand.run("/bin/launchctl", ["disable", "gui/\(getuid())/\(label)"])
                if result == "ok" {
                    state.disabledJobs.append(label)
                    try? SafetyFiles.write(state, to: SafetyFiles.state)
                    record("disable relaunch job", name: label, result: result)
                    record("unload relaunch job", name: label, result: SafetyCommand.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"]))
                } else { record("disable relaunch job", name: label, result: result) }
            }
        }
    }
    func broadReset() { panic(resetPermissions: false); pendingGlobalReset = true }
    func resetPermissions(global: Bool) {
        guard permissionWorker?.isRunning != true else { record("privacy reset", result: "already running; retry broad reset when complete"); return }
        let bundleIDs = global ? NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) : config.targets.filter(\.enabled).compactMap { appClients[$0.id] }
        if !global && bundleIDs.isEmpty { record("privacy reset", result: "no attributable GUI-app clients; CLI host permissions unchanged"); return }
        do {
            let worker = try PanicReset.launch(bundleIDs: bundleIDs, global: global)
            permissionWorker = worker
            worker.terminationHandler = { [weak self] task in
                DispatchQueue.main.async {
                    self?.permissionWorker = nil
                    self?.record("privacy reset", result: task.terminationStatus == 0 ? "tccutil accepted request; see privacy log" : "one or more reset steps failed; see privacy log")
                    if task.terminationStatus != 0 { self?.statusError = "Privacy reset has failures. Process blocking remains active." }
                }
            }
        } catch { record("privacy reset", result: error.localizedDescription); statusError = "Could not start privacy reset." }
    }
}

enum SafetyCommand {
    static func capture(_ path: String, _ args: [String]) -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: url) }
        guard let output = try? FileHandle(forWritingTo: url) else { return nil }
        defer { try? output.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(2)
            while task.isRunning && Date() < deadline { usleep(10_000) }
            if task.isRunning { kill(task.processIdentifier, SIGKILL); task.waitUntilExit(); return nil }
            guard task.terminationStatus == 0 else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        } catch { return nil }
    }
    static func run(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(2)
            while task.isRunning && Date() < deadline { usleep(10_000) }
            if task.isRunning { task.terminate(); usleep(20_000); if task.isRunning { kill(task.processIdentifier, SIGKILL) }; task.waitUntilExit(); return "timed out" }
            task.waitUntilExit()
            return task.terminationStatus == 0 ? "ok" : "failed (\(task.terminationStatus))"
        } catch { return "failed: \(error.localizedDescription)" }
    }
}
