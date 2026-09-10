// Compiled only by check-sparkle.py. No production helpers, preferences, input
// capture, permission checks or hardware APIs are linked into this fixture.
import AppKit
import Security
import CryptoKit

struct AppError: LocalizedError { let message: String; var errorDescription: String? { message } }
let fixtureRoot = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureRoot") as! String)
func log(_ text: String) {
    let url = fixtureRoot.appendingPathComponent("events.log")
    let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
}
enum SafetyFiles { static var base: URL { fixtureRoot.appendingPathComponent("storage") } }
enum AppUpdate {
    static var shared: Self { .value }; case value
    var busy: Bool { false }
    static var base: URL { SafetyFiles.base.appendingPathComponent("Updates") }
    static func sameLocation(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL == b.standardizedFileURL }
    static func canRestart(active: Bool, lidOpen: Bool, recordedSession: Bool, overrideOff: Bool) -> Bool { active || lidOpen || (!recordedSession && overrideOff) }
}
enum LidHelperUpdate { static var shared: Self { .value }; case value; var busy: Bool { false } }
enum LidGuardClock { static var now: Double { ProcessInfo.processInfo.systemUptime } }
enum CollectorIdentity { static let bootID: UUID? = UUID(uuidString: "44E03998-665F-4A6B-8C88-FCB05140E626") }
enum LidGuardOwnership { static var recorded: Bool { true } }
struct MacLidGuardHardware { struct Observation { let closed = true }; func observe() -> Observation { Observation() } }
enum LidSleepOverride { static func verify(_ value: Bool) throws { throw AppError(message: "Fixture reports an active mock session") } }
enum HelperStatusIPC {
    static var requirement: String? {
        var code: SecCode?, staticCode: SecStaticCode?, rule: SecRequirement?, text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &rule) == errSecSuccess, let rule,
              SecRequirementCopyString(rule, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }
}
enum LidGuardIdentity {
    static var current: String? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let bytes = (info as? [String:Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
final class LidGuardClient {
    static let shared = LidGuardClient()
    let changing = false, active = true
    func prepareForRestart(identity: String, completion: @escaping (Result<LidRestartTicket, Error>) -> Void) {
        log("prepare exact identity " + identity)
        if FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("fail-prepare").path) {
            completion(.failure(AppError(message: "Injected fixture transport failure"))); return
        }
        completion(.success(.init(id: UUID().uuidString, targetIdentity: identity, deadline: LidGuardClock.now+60)))
    }
    func cancelRestart(_ ticket: String) { log("cancel ticket") }
    func resumeAfterRestart(_ ticket: String, completion: @escaping (Result<Void, Error>) -> Void) {
        log("claim exact identity " + (LidGuardIdentity.current ?? "missing")); completion(.success(()))
    }
}
// These UI stubs log production ownership callbacks. Sparkle's UI is real.
final class SettingsWindow {
    static let shared = SettingsWindow(); let testing = false
    let interactionBusy = false
    func beginAuthorization() -> () -> Void { log("yield settings"); return { log("restore settings") } }
}
final class SettingsTaskPage {
    let status = NSTextField(); var update: (() -> Void)?
    init(title: String, detail: String, height: CGFloat, statusHeight: CGFloat = 60) {}
    @discardableResult func add(_ title: String, detail: String, checkbox: Bool = false, action: @escaping () -> Void) -> NSButton { NSButton() }
    func show(delegate: AppDelegate) {}
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recoveryWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        PerchUpdater.shared.showRecovery = { [weak self] in self?.showRecovery() }
        log("launch build " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String))
        PerchUpdater.shared.completeLaunch {
            if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
                log(PerchUpdater.shared.message)
                try? Data("PASS".utf8).write(to: fixtureRoot.appendingPathComponent("completed"))
                NSApp.terminate(nil)
            } else {
                PerchUpdater.shared.start()
                DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { PerchUpdater.shared.check() }
            }
        }
    }
    func showRecovery() {
        log(PerchUpdater.shared.message)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Disposable update recovery"
        window.isReleasedWhenClosed = false
        let message = NSTextField(wrappingLabelWithString: PerchUpdater.shared.message)
        message.frame = NSRect(x: 24, y: 75, width: 470, height: 100)
        let retry = NSButton(title: "Retry installation", target: self, action: #selector(retryUpdate))
        retry.frame = NSRect(x: 300, y: 22, width: 190, height: 32)
        window.contentView?.addSubview(message); window.contentView?.addSubview(retry)
        recoveryWindow = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    @objc func retryUpdate() { PerchUpdater.shared.retryInstallation() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        PerchUpdater.shared.terminationReply(sender, willExit: { log("termination allowed") }) ?? .terminateNow
    }
}
