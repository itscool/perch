import AppKit
import Security

enum LidGuardInstall {
    static let bundle = "/Library/PrivilegedHelperTools/Perch Lid Helper.app"
    static let binary = bundle + "/Contents/MacOS/Perch"
    static func cleanupRequiresUpdate(appInfo: [String: Any] = Bundle.main.infoDictionary ?? [:], executable: URL = URL(fileURLWithPath: binary)) -> Bool {
        !GuardianInstall.buildMatches(executable: executable, appInfo: appInfo)
    }
    static func cleanup() throws {
        guard LidGuardOwnership.exists else { return }
        guard !SettingsWindow.shared.testing, let requirement = HelperStatusIPC.requirement else { throw AppError(message: "Lid cleanup is unavailable.") }
        // The verified, root-owned staged bundle performs cleanup before the
        // installer replaces/restarts the service. An app update must not keep
        // invoking the older helper's broken cleanup implementation.
        if cleanupRequiresUpdate() { try install(); return }
        let quote = GuardianInstall.shellQuote
        let command = "/usr/bin/codesign --verify --strict --test-requirement " + quote("=" + requirement) + " " + quote(bundle) + " && (/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true) && " + quote(binary) + " --lid-cleanup && /bin/launchctl bootstrap system /Library/LaunchDaemons/" + LidGuardService.name + ".plist"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try script("do shell script \"\(escaped)\" with administrator privileges")
    }
    static func install() throws {
        guard !SettingsWindow.shared.testing, getuid() >= 501,
              let requirement = HelperStatusIPC.requirement else { throw AppError(message: "Install lid protection from the signed Perch app in your user session.") }
        let command = try installationCommand(source: Bundle.main.bundleURL, requirement: requirement, owner: getuid())
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        _ = try script("do shell script \"\(escaped)\" with administrator privileges")
    }
    static func installationCommand(source: URL, requirement: String, owner: uid_t) throws -> String {
        guard source.pathExtension == "app", owner >= 501 else { throw AppError(message: "Use the signed Perch app to install lid protection.") }
        let plist = "/Library/LaunchDaemons/\(LidGuardService.name).plist"
        let job: [String: Any] = ["Label": LidGuardService.name, "ProgramArguments": [binary, "--lid-guard", String(owner)], "MachServices": [LidGuardService.name: true], "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 2, "ProcessType": "Background"]
        let encoded = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).base64EncodedString()
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
            "\n/bin/launchctl bootout system/" + LidGuardService.name + " 2>/dev/null || true\n" +
            quote(staged + "/Contents/MacOS/Perch") + " --lid-cleanup\nif test -e " + quote(bundle) + "; then /bin/mv " + quote(bundle) + " " + quote(backup) + "; fi\n/bin/mv " + quote(staged) + " " + quote(bundle) +
            "\n/usr/bin/printf %s " + quote(encoded) + " | /usr/bin/base64 -D > " + quote(plist + ".new") +
            "\n/usr/sbin/chown root:wheel " + quote(plist + ".new") + "\n/bin/chmod 644 " + quote(plist + ".new") +
            "\n/bin/mv -f " + quote(plist + ".new") + " " + quote(plist) + "\n/bin/launchctl bootstrap system " + quote(plist) + "\n/bin/rm -rf " + quote(backup)
    }
}

final class LidGuardClient {
    static let shared = LidGuardClient()
    static func controlState(legacyDisabled: Bool?, status: LidGuardStatus?, recordedSession: Bool) -> NSControl.StateValue {
        if legacyDisabled == true || (status?.fresh == true && status?.armed == true && status?.error == nil) { return .on }
        if legacyDisabled == nil || recordedSession { return .mixed }
        // A rejected start that has already been cleaned up is off. Retain its
        // error message, but do not turn it into an unknown active override.
        return .off
    }
    private var connection: NSXPCConnection?
    private var token: String?
    private var timer: Timer?
    private var pending = false
    private var generation = UUID()
    private(set) var status: LidGuardStatus?
    private(set) var changing = false
    var active: Bool { status?.fresh == true && status?.armed == true && status?.error == nil }
    var detail: String { status?.fresh == true ? status!.detail : "Lid protection is not confirmed. Open the lid before setting it up or repairing it." }
    func start() {
        guard !SettingsWindow.shared.testing, timer == nil else { return }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common); refresh()
    }
    private func proxy(failure: @escaping () -> Void) -> LidGuardProtocol? {
        guard !SettingsWindow.shared.testing, let requirement = HelperStatusIPC.requirement else { failure(); return nil }
        if connection == nil {
            let new = NSXPCConnection(machServiceName: LidGuardService.name, options: .privileged)
            new.setCodeSigningRequirement(requirement); new.remoteObjectInterface = NSXPCInterface(with: LidGuardProtocol.self)
            new.resume(); connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in DispatchQueue.main.async(execute: failure) } as? LidGuardProtocol
    }
    private func received(_ data: Data) -> Bool {
        guard data.count <= 4096, let reply = try? JSONDecoder().decode(LidGuardReply.self, from: data), reply.status.fresh else { return false }
        status = reply.status
        if !reply.status.armed { token = nil }
        return true
    }
    func refresh() {
        guard !pending, !changing, !SettingsWindow.shared.testing else { return }
        pending = true; generation = UUID(); let request = generation
        let finish: (Data?) -> Void = { [weak self] data in
            guard let self, self.generation == request else { return }; self.pending = false
            if let data { _ = self.received(data) } else { self.connection?.invalidate(); self.connection = nil; self.token = nil }
        }
        let remote = proxy { finish(nil) }
        let reply: (Data) -> Void = { data in DispatchQueue.main.async { finish(data) } }
        if let token { remote?.renew(token, reply: reply) } else { remote?.status(reply) }
        DispatchQueue.main.asyncAfter(deadline: .now()+2) { [weak self] in
            guard let self, self.pending, self.generation == request else { return }; finish(nil); self.generation = UUID()
        }
    }
    func change(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !changing else { return }
        changing = true; pending = false; generation = UUID(); let request = generation
        if !enabled { token = nil }
        var finished = false
        let finish: (Data?) -> Void = { [weak self] data in
            guard let self, !finished, self.generation == request else { return }; finished = true; self.changing = false
            if let data, self.received(data), let reply = try? JSONDecoder().decode(LidGuardReply.self, from: data), reply.status.error == nil, reply.status.armed == enabled {
                self.token = enabled ? reply.token : nil; completion(.success(()))
            } else {
                self.token = nil; self.connection?.invalidate(); self.connection = nil
                completion(.failure(AppError(message: self.status?.fresh == true ? self.status!.detail : "The lid helper did not confirm the change. Keep the lid open and retry setup.")))
            }
        }
        let remote = proxy { finish(nil) }
        remote?.setEnabled(enabled) { data in DispatchQueue.main.async { finish(data) } }
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { finish(nil) }
    }
}

extension AppDelegate {
    func changeSupervisedLid(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let installed = enabled && LidGuardClient.shared.status?.fresh != true
            if installed { try LidGuardInstall.install() }
            LidGuardClient.shared.start()
            if installed { DispatchQueue.main.asyncAfter(deadline: .now()+0.8) { LidGuardClient.shared.change(enabled, completion: completion) } }
            else { LidGuardClient.shared.change(enabled, completion: completion) }
        } catch { completion(.failure(error)) }
    }
}
