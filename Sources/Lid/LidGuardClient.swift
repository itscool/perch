import AppKit
import Security

enum LidGuardInstall {
    static let bundle = "/Library/PrivilegedHelperTools/Perch Lid Helper.app"
    static let binary = bundle + "/Contents/MacOS/Perch"
    static let recoveryName = "local.scott.perch.lid.recovery"
    static func publisherMatches(_ app: URL) -> Bool {
        guard let requirement = CodeIdentity.designatedRequirement else { return false }
        return (try? CodeIdentity.verifiedHash(of: app, requirement: requirement)) != nil
    }
    static func cleanupRequiresUpdate(appInfo: [String: Any] = Bundle.main.infoDictionary ?? [:], executable: URL = URL(fileURLWithPath: binary), verifyPublisher: (URL) -> Bool = publisherMatches) -> Bool {
        guard let data = try? Data(contentsOf: executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")),
              let installed = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let identifier = appInfo["CFBundleIdentifier"] as? String,
              installed["CFBundleIdentifier"] as? String == identifier else { return true }
        return !verifyPublisher(executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) ||
            installed["PerchLidProtocolVersion"] as? Int != LidGuardCompatibility.protocolVersion ||
            installed["PerchLidHelperVersion"] as? Int != LidGuardCompatibility.helperVersion
    }

    static func cleanup() throws {
        guard LidGuardOwnership.recorded else { return }
        guard !SettingsWindow.shared.testing, let requirement = CodeIdentity.designatedRequirement else { throw AppError(message: "Lid cleanup is unavailable.") }
        // The verified, root-owned staged bundle performs cleanup before the
        // installer replaces/restarts the service. Cleanup must use
        // the current verified helper contract.
        if cleanupRequiresUpdate() { try install(); return }
        let quote = AdminShell.quote
        let command = "/usr/bin/codesign --verify --strict --test-requirement " + quote("=" + requirement) + " " + quote(bundle) + " && (/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true) && " + quote(binary) + " --lid-cleanup && /bin/launchctl bootstrap system /Library/LaunchDaemons/" + LidGuardService.name + ".plist"
        try AdminShell.runPrivileged(command)
    }
    @discardableResult static func install(requireOpenLid: Bool = false, protectedUpdate: Bool = false) throws -> Bool {
        guard !SettingsWindow.shared.testing, getuid() >= 501,
              let requirement = CodeIdentity.designatedRequirement else { throw AppError(message: "Install lid protection from the signed Perch app in your user session.") }
        let command = try installationCommand(source: Bundle.main.bundleURL, requirement: requirement, owner: getuid(), requireOpenLid: requireOpenLid, protectedUpdate: protectedUpdate)
        let outcome = try AdminShell.runPrivileged(command)
        return protectedUpdate && outcome.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == "resume"
    }
    static func bundleLinkValidationCommand(_ staged: String) -> String {
        let quote = AdminShell.quote
        let framework = staged + "/Contents/Frameworks/Sparkle.framework/"
        let links = ["PrivateHeaders", "Resources", "Autoupdate", "Updater.app", "Headers", "XPCServices", "Modules", "Sparkle"]
        let cases = links.map { quote(framework + $0) + ") expected=" + quote("Versions/Current/" + $0) + ";;" }.joined(separator: "\n")
        // Permit only the exact relative links in the pinned signed framework.
        // Any extra link or redirected target aborts before chown or execution.
        return "/usr/bin/find " + quote(staged) + " -type l -print | while IFS= read -r link; do\ncase \"$link\" in\n" + cases + "\n" +
            quote(framework + "Versions/Current") + ") expected=B;;\n*) exit 1;;\nesac\ntest \"$(/usr/bin/readlink \"$link\")\" = \"$expected\" || exit 1\ndone"
    }
    /// The supervisor's launchd job. It must answer its watchdog within two
    /// seconds, so it runs Interactive: a Background job's timers can be
    /// delayed by seconds, which the watchdog correctly treats as a hang and
    /// ends the lid session. The recovery and update-guard jobs have no such
    /// deadline and stay Background.
    static func serviceJob(owner: uid_t) -> [String: Any] {
        ["Label": LidGuardService.name, "ProgramArguments": [binary, "--lid-guard", String(owner)], "MachServices": [LidGuardService.name: true, LidGuardService.restartName: true], "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 2, "ProcessType": "Interactive"]
    }
    static func installationCommand(source: URL, requirement: String, owner: uid_t, requireOpenLid: Bool = false, protectedUpdate: Bool = false) throws -> String {
        guard source.pathExtension == "app", owner >= 501 else { throw AppError(message: "Use the signed Perch app to install lid protection.") }
        let plist = "/Library/LaunchDaemons/\(LidGuardService.name).plist"
        let recoveryPlist = "/Library/LaunchDaemons/\(recoveryName).plist"
        let job = serviceJob(owner: owner)
        let encoded = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).base64EncodedString()
        let recovery: [String: Any] = ["Label": recoveryName, "ProgramArguments": [binary, "--lid-recover"], "RunAtLoad": true, "StartInterval": 5, "ThrottleInterval": 1, "ProcessType": "Background", "ExitTimeOut": 5]
        let recoveryEncoded = try PropertyListSerialization.data(fromPropertyList: recovery, format: .xml, options: 0).base64EncodedString()
        let staged = "/Library/PrivilegedHelperTools/.perch-lid-" + UUID().uuidString + ".app"
        let backup = "/Library/PrivilegedHelperTools/.perch-lid-backup-" + UUID().uuidString + ".app"
        let quote = AdminShell.quote
        let attempt = UUID().uuidString
        let guardPlist = "/Library/LaunchDaemons/" + LidMaintenance.name + ".plist"
        let guardJob: [String: Any] = ["Label": LidMaintenance.name, "ProgramArguments": [LidMaintenance.binary, "--lid-maintenance-recover"], "RunAtLoad": true, "KeepAlive": ["PathState": [LidMaintenance.path: true]], "ThrottleInterval": 1, "ProcessType": "Background"]
        let guardEncoded = try PropertyListSerialization.data(fromPropertyList: guardJob, format: .xml, options: 0).base64EncodedString()
        let stagedBinary = staged + "/Contents/MacOS/Perch"
        let guardStage = "/Library/PrivilegedHelperTools/.perch-lid-guard-" + UUID().uuidString + ".app"
        let bridge = "\n" + quote(stagedBinary) + " --lid-maintenance-check\n" +
            "/usr/bin/ditto " + quote(staged) + " " + quote(guardStage) +
            "\n/usr/bin/codesign --verify --deep --strict --test-requirement " + quote("=" + requirement) + " " + quote(guardStage) +
            "\n(/bin/launchctl bootout system/" + LidMaintenance.name + " 2>/dev/null || true)\n/bin/rm -rf " + quote(LidMaintenance.bundle) +
            "\n/bin/mv " + quote(guardStage) + " " + quote(LidMaintenance.bundle) +
            "\n/usr/bin/printf %s " + quote(guardEncoded) + " | /usr/bin/base64 -D > " + quote(guardPlist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(guardPlist + ".new") + "\n/bin/chmod 644 " + quote(guardPlist + ".new") +
            "\n/bin/mv -f " + quote(guardPlist + ".new") + " " + quote(guardPlist) +
            "\n/bin/launchctl bootstrap system " + quote(guardPlist) +
            "\n" + quote(LidMaintenance.binary) + " --lid-maintenance-begin " + quote(String(owner)) + " " + quote(attempt) +
            "\n" + quote(LidMaintenance.binary) + " --lid-maintenance-enable\n"
        // Keep the complete signed bundle: copying just its Mach-O loses the
        // sealed Info.plist and fails strict verification. Only verified,
        // root-owned code is executed; allow only Sparkle's sealed framework links.
        let body = "set -eu\n" +
            "for d in /Library/PrivilegedHelperTools /Library/LaunchDaemons; do /bin/mkdir -p \"$d\"; test ! -L \"$d\"; test \"$(/usr/bin/stat -f %u \"$d\")\" = 0; test -z \"$(/usr/bin/find \"$d\" -prune -perm +022 -print)\"; done\n" +
            "trap " + quote((protectedUpdate ? quote(LidMaintenance.binary) + " --lid-maintenance-abort " + quote(attempt) + " >/dev/null 2>&1 || true; " : "") + "if test -d " + quote(backup) + " && test ! -e " + quote(bundle) + "; then /bin/mv " + quote(backup) + " " + quote(bundle) + "; fi; /bin/rm -rf " + quote(staged)) + " EXIT\n" +
            "/usr/bin/ditto " + quote(source.path) + " " + quote(staged) + "\n" + bundleLinkValidationCommand(staged) + "\n/usr/sbin/chown -R root:wheel " + quote(staged) + "\n/bin/chmod -R go-w " + quote(staged) +
            "\n/usr/bin/codesign --verify --deep --strict --test-requirement " + quote("=" + requirement) + " " + quote(staged) +
            (requireOpenLid ? "\n" + quote(staged + "/Contents/MacOS/Perch") + " --check-lid-update" : "") +
            (protectedUpdate ? bridge : "\n/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true\n" +
            quote(stagedBinary) + " --lid-cleanup\n" +
            "/bin/launchctl bootout system/" + recoveryName + " 2>/dev/null || true\n") +
            "if test -e " + quote(bundle) + "; then /bin/mv " + quote(bundle) + " " + quote(backup) + "; fi\n/bin/mv " + quote(staged) + " " + quote(bundle) +
            "\n/usr/bin/printf %s " + quote(encoded) + " | /usr/bin/base64 -D > " + quote(plist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(plist + ".new") + "\n/bin/chmod 644 " + quote(plist + ".new") +
            "\n/bin/mv -f " + quote(plist + ".new") + " " + quote(plist) +
            "\n/usr/bin/printf %s " + quote(recoveryEncoded) + " | /usr/bin/base64 -D > " + quote(recoveryPlist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(recoveryPlist + ".new") + "\n/bin/chmod 644 " + quote(recoveryPlist + ".new") +
            "\n/bin/mv -f " + quote(recoveryPlist + ".new") + " " + quote(recoveryPlist) +
            "\n/bin/launchctl bootstrap system " + quote(recoveryPlist) +
            "\n/bin/launchctl bootstrap system " + quote(plist) + "\n/bin/rm -rf " + quote(backup) +
            (protectedUpdate ? "\n" + quote(LidMaintenance.binary) + " --lid-maintenance-finish " + quote(attempt) + "\ntrap - EXIT" : "")
        // Serialize the whole installer so another app cannot replace an
        // in-progress update's independent recovery job.
        let lock = "/var/run/local.scott.perch.lid-install.lock"
        return "umask 077; test ! -L " + quote(lock) + " && /usr/bin/lockf -k -t 0 " + quote(lock) + " /bin/sh -c " + quote(body)
    }
}

final class LidGuardClient {
    static let shared = LidGuardClient()
    var onChange: (() -> Void)?
    static func controlState(unownedOverride: Bool?, status: LidGuardStatus?, recordedSession: Bool) -> NSControl.StateValue {
        if status?.fresh == true && status?.armed == true && status?.error == nil { return .on }
        if unownedOverride != false || recordedSession { return .mixed }
        // A rejected start that has already been cleaned up is off. Retain its
        // error message, but do not turn it into an unknown active override.
        return .off
    }
    private let queue = DispatchQueue(label: "local.scott.perch.lid-heartbeat", qos: .userInitiated)
    private let stateLock = NSLock()
    private var publishedStatus: LidGuardStatus?
    private var publishedChanging = false
    private var connection: NSXPCConnection?
    private var restartConnection: NSXPCConnection?
    private var claimingRestart = false
    private var timer: DispatchSourceTimer?
    private var responsiveness: NSObjectProtocol?
    enum RestartRequest: Equatable { case prepare(String, String), resume(String), cancel(String, String) }
    typealias RestartSend = (RestartRequest, @escaping (Data?) -> Void) -> Void
    private let injectedTransport: LidGuardSession.Send?
    private let injectedRestart: RestartSend?
    init(transport: LidGuardSession.Send? = nil, restart: RestartSend? = nil) { injectedTransport = transport; injectedRestart = restart }
    private func sendRestart(_ request: RestartRequest, reply: @escaping (Data?) -> Void) {
        if let injectedRestart { injectedRestart(request, reply); return }
        let claiming: Bool
        if case .resume = request { claiming = true } else { claiming = false }
        guard let remote = proxy(restart: claiming, failure: { reply(nil) }) else { return }
        switch request {
        case .prepare(let token, let identity): remote.prepareRestart(token, targetIdentity: identity, reply: reply)
        case .resume(let ticket): remote.resumeRestart(ticket, reply: reply)
        case .cancel(let token, let ticket): remote.cancelRestart(token, ticket: ticket, reply: reply)
        }
    }
    var status: LidGuardStatus? { stateLock.withLock { publishedStatus } }
    var changing: Bool { stateLock.withLock { publishedChanging } }
    var active: Bool { let current = status; return current?.fresh == true && current?.armed == true && current?.error == nil }
    var detail: String { let current = status; return current?.fresh == true ? current!.displayDetail : "Lid protection is not confirmed. Checking the helper connection…" }
    /// Restart handoff results are consumed while AppKit waits in its
    /// terminate loop, possibly inside a main-queue block. Deliver them from
    /// the main run loop (common modes), which that loop services, instead of
    /// the main dispatch queue, which it cannot re-enter.
    static func deliver(_ body: @escaping () -> Void) { TerminationReply.schedule(after: 0, body) }
    func prepareForRestart(identity: String, completion: @escaping (Result<LidRestartTicket, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedRestart != nil else { completion(.failure(AppError(message: "Live updates are blocked in tests."))); return }
        queue.async {
            guard let token = self.session.activeToken else {
                Self.deliver { completion(.failure(AppError(message: "The active lid session is not owned by this app. Open the lid before updating."))) }; return
            }
            var finished = false
            let finish: (Data?) -> Void = { data in
                self.queue.async {
                    guard !finished else { return }; finished = true
                    let result: Result<LidRestartTicket, Error>
                    if let data, let reply = try? JSONDecoder().decode(LidGuardReply.self, from: data), reply.status.fresh,
                       reply.restartError == nil, let ticket = reply.restart, ticket.targetIdentity == identity,
                       ticket.deadline > LidGuardClock.now {
                        result = .success(ticket)
                    } else {
                        self.sendRestart(.cancel(token, ""), reply: { _ in })
                        result = .failure(AppError(message: "Restart preparation was not confirmed. Perch is still running; review Keep awake because the lid session may end if the helper connection was lost."))
                    }
                    Self.deliver { completion(result) }
                }
            }
            self.sendRestart(.prepare(token, identity), reply: finish)
            self.queue.asyncAfter(deadline: .now()+3) { finish(nil) }
        }
    }
    func resumeAfterRestart(_ ticket: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedRestart != nil else { completion(.failure(AppError(message: "Live updates are blocked in tests."))); return }
        queue.async {
            guard !self.claimingRestart else {
                Self.deliver { completion(.failure(AppError(message: "The lid restart handoff is already in progress."))) }
                return
            }
            self.claimingRestart = true
            self.session.beginRestartClaim()
            self.connection?.invalidate(); self.connection = nil
            var finished = false
            let finish: (Data?) -> Void = { data in
                self.queue.async {
                    guard !finished else { return }; finished = true
                    let result: Result<Void, Error>
                    do {
                        guard let data else { throw AppError(message: "The lid helper did not respond to the updated app.") }
                        try self.session.adoptRestart(data); result = .success(())
                    } catch { self.session.failRestartClaim(); result = .failure(error) }
                    self.claimingRestart = false
                    self.restartConnection?.invalidate(); self.restartConnection = nil
                    // Move immediately to the normal heartbeat endpoint.
                    // A claim-only connection is never reused for polling.
                    self.session.refresh()
                    Self.deliver { completion(result) }
                }
            }
            self.sendRestart(.resume(ticket), reply: finish)
            self.queue.asyncAfter(deadline: .now()+3) { finish(nil) }
        }
    }
    func cancelRestart(_ ticket: String) {
        guard !SettingsWindow.shared.testing || injectedRestart != nil else { return }
        queue.async {
            guard let token = self.session.activeToken else { return }
            self.sendRestart(.cancel(token, ticket), reply: { _ in })
        }
    }
    private lazy var session = LidGuardSession(send: { [weak self] request, reply in
        guard let self else { reply(nil); return }
        let complete: (Data?) -> Void = { [weak self] data in self?.queue.async { reply(data) } }
        if let transport = self.injectedTransport { transport(request, complete); return }
        guard let remote = self.proxy(failure: { complete(nil) }) else { return }
        switch request {
        case .status: remote.status { complete($0) }
        case .renew(let token): remote.renew(token) { complete($0) }
        case .change(let enabled): remote.setEnabled(enabled) { complete($0) }
        case .countdown(let direction, let token, let request): remote.countdown(direction, token: token, request: request) { complete($0) }
        }
    }, schedule: { [weak self] delay, action in
        self?.queue.asyncAfter(deadline: .now() + delay, execute: action)
    }, invalidate: { [weak self] in
        self?.connection?.invalidate(); self?.connection = nil
    }, publish: { [weak self] status, changing in
        self?.stateLock.withLock { self?.publishedStatus = status; self?.publishedChanging = changing }
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }, activity: { [weak self] active in
        guard let self else { return }
        if active && self.responsiveness == nil {
            // Keep this user-requested heartbeat responsive while the menu and
            // Settings are hidden, without asserting that the Mac cannot sleep.
            self.responsiveness = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Maintain the user-enabled lid session heartbeat")
        } else if !active, let activity = self.responsiveness {
            ProcessInfo.processInfo.endActivity(activity); self.responsiveness = nil
        }
    })
    func start() {
        guard !SettingsWindow.shared.testing || injectedTransport != nil else { return }
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.session.refresh() }
            self.timer = timer; timer.resume()
        }
    }
    private func proxy(restart: Bool = false, failure: @escaping () -> Void) -> LidGuardProtocol? {
        guard let requirement = CodeIdentity.designatedRequirement else { failure(); return nil }
        if (restart ? restartConnection : connection) == nil {
            let new = NSXPCConnection(machServiceName: restart ? LidGuardService.restartName : LidGuardService.name, options: .privileged)
            new.setCodeSigningRequirement(requirement); new.remoteObjectInterface = NSXPCInterface(with: LidGuardProtocol.self)
            new.resume()
            if restart { restartConnection = new } else { connection = new }
        }
        return (restart ? restartConnection : connection)?.remoteObjectProxyWithErrorHandler { _ in failure() } as? LidGuardProtocol
    }
    func refresh() {
        guard !SettingsWindow.shared.testing || injectedTransport != nil else { return }
        queue.async { [weak self] in self?.session.refresh() }
    }
    func change(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedTransport != nil else {
            completion(.failure(AppError(message: "Live lid changes are blocked in tests."))); return
        }
        queue.async { [weak self] in
            self?.session.change(enabled) { result in DispatchQueue.main.async { completion(result) } }
        }
    }
    func adjustCountdown(_ direction: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedTransport != nil else { completion(.failure(AppError(message: "Live countdowns are blocked in tests."))); return }
        start()
        queue.async { self.session.adjustCountdown(direction) { result in DispatchQueue.main.async { completion(result) } } }
    }
    deinit {
        timer?.cancel(); connection?.invalidate()
        restartConnection?.invalidate()
        if let responsiveness { ProcessInfo.processInfo.endActivity(responsiveness) }
    }

}

extension AppDelegate {
    func changeSupervisedLid(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            if enabled && (LidGuardClient.shared.status?.fresh != true || LidHelperUpdate.shared.state.pending) {
                throw AppError(message: "Complete Setup → Lid protection before starting a session. Your saved choice is kept.")
            }
            LidGuardClient.shared.start()
            LidGuardClient.shared.change(enabled, completion: completion)
        } catch { completion(.failure(error)) }
    }
}
