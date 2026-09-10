import AppKit
import Foundation

enum GuardianInstall {
    static let label = "local.scott.perch.guardian"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var protectedBinary: URL { URL(fileURLWithPath: "/Library/Application Support/Perch/Perch Helper.app/Contents/MacOS/Perch") }
    static var service: String { "gui/\(getuid())/\(label)" }
    static var status: SafetyStatus? {
        let monitor = HelperStatusIPC.guardianClient.value
        let input = HelperStatusIPC.inputClient.value
        guard var status = monitor else { return nil }
        if status.error == "Process events need setup. Open Agent safety settings." {
            status.error = "Process events need setup. Open Agent Kill Switch settings."
        }
        status.inputTrusted = input?.fresh == true ? input?.trusted : nil
        status.inputActive = input?.fresh == true && input?.active == true
        return status
    }
    static var alive: Bool { status?.fresh == true }

    // Run only at menu-app startup. An empty asynchronous status cache is not
    // evidence that a healthy helper needs reinstalling.
    static var messagingInstalled: Bool {
        for (jobLabel, name) in [(label, HelperStatusIPC.guardian), ("local.scott.perch.input", HelperStatusIPC.input)] {
            let path = plist.deletingLastPathComponent().appendingPathComponent(jobLabel + ".plist")
            guard let data = try? Data(contentsOf: path),
                  let job = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  (job["MachServices"] as? [String: Bool])?[name] == true,
                  let executable = (job["ProgramArguments"] as? [String])?.first,
                  buildMatches(executable: URL(fileURLWithPath: executable), appInfo: Bundle.main.infoDictionary ?? [:]),
                  SafetyCommand.run("/bin/launchctl", ["print", "gui/\(getuid())/" + jobLabel]) == "ok" else { return false }
        }
        return true
    }
    static func buildMatches(executable: URL, appInfo: [String: Any], verifyPublisher: (URL) -> Bool = LidGuardInstall.publisherMatches) -> Bool {
        let info = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        guard let expectedBuild = appInfo["CFBundleVersion"] as? String, !expectedBuild.isEmpty,
              let expectedID = appInfo["CFBundleIdentifier"] as? String, !expectedID.isEmpty,
              let data = try? Data(contentsOf: info),
              let installed = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
        return installed["CFBundleVersion"] as? String == expectedBuild && installed["CFBundleIdentifier"] as? String == expectedID &&
            verifyPublisher(executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }
    static func inputPermissionApp(arguments: [String]?) -> URL? {
        guard let executable = arguments?.first,
              [SafetyFiles.binary.path, protectedBinary.path].contains(executable),
              arguments?.dropFirst().first == "--input-helper" else { return nil }
        return URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var inputPermissionApp: URL? {
        let path = plist.deletingLastPathComponent().appendingPathComponent("local.scott.perch.input.plist")
        guard let data = try? Data(contentsOf: path),
              let job = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return inputPermissionApp(arguments: job["ProgramArguments"] as? [String])
    }
    static func install() throws {
        try SafetyFiles.prepare()
        let source = Bundle.main.bundleURL
        guard source.pathExtension == "app" else { throw AppError(message: "Install the watcher from Perch.app.") }
        let stage = SafetyFiles.base.appendingPathComponent("Perch-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: source, to: stage)
        if FileManager.default.fileExists(atPath: SafetyFiles.helperApp.path) {
            _ = try FileManager.default.replaceItemAt(SafetyFiles.helperApp, withItemAt: stage)
        } else { try FileManager.default.moveItem(at: stage, to: SafetyFiles.helperApp) }
        if !FileManager.default.fileExists(atPath: SafetyFiles.config.path) { try SafetyConfiguration().save() }
        if !FileManager.default.fileExists(atPath: AgentCatalog.installed.path), let catalog = Bundle.main.url(forResource: "agents", withExtension: "json") { try AgentCatalog.install(from: catalog) }
        let existing = (try? Data(contentsOf: plist)).flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] }
        let protected = (existing?["ProgramArguments"] as? [String])?.first == protectedBinary.path
        if protected { try protectExecutable() } else { try writeJob(executable: SafetyFiles.binary) }
    }
    static func writeJob(executable: URL) throws {
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let job: [String: Any] = ["Label": label, "MachServices": [HelperStatusIPC.guardian: true], "ProgramArguments": [executable.path, "--guardian"], "RunAtLoad": true, "KeepAlive": true, "ProcessType": "Interactive", "LimitLoadToSessionType": "Aqua", "ThrottleInterval": 2, "StandardOutPath": SafetyFiles.base.appendingPathComponent("watcher.log").path, "StandardErrorPath": SafetyFiles.base.appendingPathComponent("watcher.log").path]
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: plist, options: .atomic)
        _ = SafetyCommand.run("/bin/launchctl", ["bootout", service])
        let result = SafetyCommand.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist.path])
        guard result == "ok" else { throw AppError(message: "Watcher installation \(result). Try Repair watcher in Agent Kill Switch.") }
        let inputLabel = "local.scott.perch.input"
        let inputPlist = plist.deletingLastPathComponent().appendingPathComponent(inputLabel + ".plist")
        var inputJob = job
        inputJob["Label"] = inputLabel
        inputJob["MachServices"] = [HelperStatusIPC.input: true]
        inputJob["ProgramArguments"] = [executable.path, "--input-helper"]
        try PropertyListSerialization.data(fromPropertyList: inputJob, format: .xml, options: 0).write(to: inputPlist, options: .atomic)
        _ = SafetyCommand.run("/bin/launchctl", ["bootout", "gui/\(getuid())/" + inputLabel])
        let inputResult = SafetyCommand.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", inputPlist.path])
        guard inputResult == "ok" else { throw AppError(message: "Input helper installation \(inputResult).") }

    }
    static func protectExecutable() throws {
        // The admin-owned binary resists accidental edits; this is not a root process or a security boundary.
        let destination = "/Library/Application Support/Perch/Perch Helper.app"
        let command = "/bin/mkdir -p '/Library/Application Support/Perch' && /usr/bin/ditto " + shellQuote(SafetyFiles.helperApp.path) + " " + shellQuote(destination) + " && /usr/sbin/chown -R root:wheel " + shellQuote(destination) + " && /bin/chmod -R go-w " + shellQuote(destination)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try script("do shell script \"\(escaped)\" with administrator privileges")
        try writeJob(executable: protectedBinary)
    }
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
