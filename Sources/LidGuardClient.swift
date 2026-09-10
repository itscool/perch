import AppKit
import Security

enum LidGuardInstall {
    static let bundle = "/Library/PrivilegedHelperTools/Perch Lid Helper.app"
    static let binary = bundle + "/Contents/MacOS/Perch"
    static let recoveryName = "local.scott.perch.lid.recovery"
    static func cleanupRequiresUpdate(appInfo: [String: Any] = Bundle.main.infoDictionary ?? [:], executable: URL = URL(fileURLWithPath: binary)) -> Bool {
        guard let data = try? Data(contentsOf: executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")),
              let installed = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let identifier = appInfo["CFBundleIdentifier"] as? String,
              installed["CFBundleIdentifier"] as? String == identifier else { return true }
        return installed["PerchLidProtocolVersion"] as? Int != LidGuardCompatibility.protocolVersion ||
            installed["PerchLidHelperVersion"] as? Int != LidGuardCompatibility.helperVersion
    }

    static func cleanup() throws {
        guard LidGuardOwnership.recorded else { return }
        guard !SettingsWindow.shared.testing, let requirement = HelperStatusIPC.requirement else { throw AppError(message: "Lid cleanup is unavailable.") }
        // The verified, root-owned staged bundle performs cleanup before the
        // installer replaces/restarts the service. Cleanup must use
        // the current verified helper contract.
        if cleanupRequiresUpdate() { try install(); return }
        let quote = GuardianInstall.shellQuote
        let command = "/usr/bin/codesign --verify --strict --test-requirement " + quote("=" + requirement) + " " + quote(bundle) + " && (/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true) && " + quote(binary) + " --lid-cleanup && /bin/launchctl bootstrap system /Library/LaunchDaemons/" + LidGuardService.name + ".plist"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try script("do shell script \"\(escaped)\" with administrator privileges")
    }
    static func install(requireOpenLid: Bool = false) throws {
        guard !SettingsWindow.shared.testing, getuid() >= 501,
              let requirement = HelperStatusIPC.requirement else { throw AppError(message: "Install lid protection from the signed Perch app in your user session.") }
        let command = try installationCommand(source: Bundle.main.bundleURL, requirement: requirement, owner: getuid(), requireOpenLid: requireOpenLid)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        _ = try script("do shell script \"\(escaped)\" with administrator privileges")
    }
    static func installationCommand(source: URL, requirement: String, owner: uid_t, requireOpenLid: Bool = false) throws -> String {
        guard source.pathExtension == "app", owner >= 501 else { throw AppError(message: "Use the signed Perch app to install lid protection.") }
        let plist = "/Library/LaunchDaemons/\(LidGuardService.name).plist"
        let recoveryPlist = "/Library/LaunchDaemons/\(recoveryName).plist"
        let job: [String: Any] = ["Label": LidGuardService.name, "ProgramArguments": [binary, "--lid-guard", String(owner)], "MachServices": [LidGuardService.name: true, LidGuardService.restartName: true], "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 2, "ProcessType": "Background"]
        let encoded = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).base64EncodedString()
        let recovery: [String: Any] = ["Label": recoveryName, "ProgramArguments": [binary, "--lid-recover"], "RunAtLoad": true, "StartInterval": 5, "ThrottleInterval": 1, "ProcessType": "Background", "ExitTimeOut": 5]
        let recoveryEncoded = try PropertyListSerialization.data(fromPropertyList: recovery, format: .xml, options: 0).base64EncodedString()
        let staged = "/Library/PrivilegedHelperTools/.perch-lid-" + UUID().uuidString + ".app"
        let backup = "/Library/PrivilegedHelperTools/.perch-lid-backup-" + UUID().uuidString + ".app"
        let quote = GuardianInstall.shellQuote
        // Keep the complete signed bundle: copying just its Mach-O loses the
        // sealed Info.plist and fails strict verification. Only verified,
        // root-owned code is executed; reject symlinks in this helper bundle.
        return "set -eu\n" +
            "for d in /Library/PrivilegedHelperTools /Library/LaunchDaemons; do /bin/mkdir -p \"$d\"; test ! -L \"$d\"; test \"$(/usr/bin/stat -f %u \"$d\")\" = 0; test -z \"$(/usr/bin/find \"$d\" -prune -perm +022 -print)\"; done\n" +
            "trap " + quote("if test -d " + quote(backup) + " && test ! -e " + quote(bundle) + "; then /bin/mv " + quote(backup) + " " + quote(bundle) + "; fi; /bin/rm -rf " + quote(staged)) + " EXIT\n" +
            "/usr/bin/ditto " + quote(source.path) + " " + quote(staged) + "\ntest -z \"$(/usr/bin/find " + quote(staged) + " -type l -print)\"\n/usr/sbin/chown -R root:wheel " + quote(staged) + "\n/bin/chmod -R go-w " + quote(staged) +
            "\n/usr/bin/codesign --verify --strict --test-requirement " + quote("=" + requirement) + " " + quote(staged) +
            (requireOpenLid ? "\n" + quote(staged + "/Contents/MacOS/Perch") + " --check-lid-update" : "") +
            "\n/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true\n" +
            quote(staged + "/Contents/MacOS/Perch") + " --lid-cleanup\n" +
            "/bin/launchctl bootout system/" + recoveryName + " 2>/dev/null || true\n" +
            "if test -e " + quote(bundle) + "; then /bin/mv " + quote(bundle) + " " + quote(backup) + "; fi\n/bin/mv " + quote(staged) + " " + quote(bundle) +
            "\n/usr/bin/printf %s " + quote(encoded) + " | /usr/bin/base64 -D > " + quote(plist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(plist + ".new") + "\n/bin/chmod 644 " + quote(plist + ".new") +
            "\n/bin/mv -f " + quote(plist + ".new") + " " + quote(plist) +
            "\n/usr/bin/printf %s " + quote(recoveryEncoded) + " | /usr/bin/base64 -D > " + quote(recoveryPlist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(recoveryPlist + ".new") + "\n/bin/chmod 644 " + quote(recoveryPlist + ".new") +
            "\n/bin/mv -f " + quote(recoveryPlist + ".new") + " " + quote(recoveryPlist) +
            "\n/bin/launchctl bootstrap system " + quote(recoveryPlist) +
            "\n/bin/launchctl bootstrap system " + quote(plist) + "\n/bin/rm -rf " + quote(backup)
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
    func prepareForRestart(identity: String, completion: @escaping (Result<LidRestartTicket, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedRestart != nil else { completion(.failure(AppError(message: "Live updates are blocked in tests."))); return }
        queue.async {
            guard let token = self.session.activeToken else {
                DispatchQueue.main.async { completion(.failure(AppError(message: "The active lid session is not owned by this app. Open the lid before updating."))) }; return
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
                    DispatchQueue.main.async { completion(result) }
                }
            }
            self.sendRestart(.prepare(token, identity), reply: finish)
            self.queue.asyncAfter(deadline: .now()+3) { finish(nil) }
        }
    }
    func resumeAfterRestart(_ ticket: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !SettingsWindow.shared.testing || injectedRestart != nil else { completion(.failure(AppError(message: "Live updates are blocked in tests."))); return }
        queue.async {
            self.connection?.invalidate(); self.connection = nil
            var finished = false
            let finish: (Data?) -> Void = { data in
                self.queue.async {
                    guard !finished else { return }; finished = true
                    let result: Result<Void, Error>
                    do {
                        guard let data else { throw AppError(message: "The lid helper did not respond to the updated app.") }
                        try self.session.adoptRestart(data); result = .success(())
                    } catch { result = .failure(error) }
                    DispatchQueue.main.async { completion(result) }
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
        guard let requirement = HelperStatusIPC.requirement else { failure(); return nil }
        if connection == nil {
            let new = NSXPCConnection(machServiceName: restart ? LidGuardService.restartName : LidGuardService.name, options: .privileged)
            new.setCodeSigningRequirement(requirement); new.remoteObjectInterface = NSXPCInterface(with: LidGuardProtocol.self)
            new.resume(); connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in failure() } as? LidGuardProtocol
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
    deinit {
        timer?.cancel(); connection?.invalidate()
        if let responsiveness { ProcessInfo.processInfo.endActivity(responsiveness) }
    }

}

extension AppDelegate {
    func changeSupervisedLid(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let installed = enabled && LidGuardClient.shared.status?.fresh != true
            if installed {
                guard !LidHelperUpdate.shared.state.pending else { throw AppError(message: "A lid-helper update is queued. Open Keep awake and finish it with the lid open before enabling a new session.") }
                try LidGuardInstall.install()
            }
            LidGuardClient.shared.start()
            if installed { DispatchQueue.main.asyncAfter(deadline: .now()+0.8) { LidGuardClient.shared.change(enabled, completion: completion) } }
            else { LidGuardClient.shared.change(enabled, completion: completion) }
        } catch { completion(.failure(error)) }
    }
}
