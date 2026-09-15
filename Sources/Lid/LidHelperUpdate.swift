import AppKit

struct LidHelperUpdateState: Equatable {
    let installed: Bool
    let pending: Bool
    let lidOpen: Bool
    var notice: String {
        guard pending else { return installed ? "Lid helper is up to date." : "Lid protection is optional. Set it up in Setup → Lid protection when needed." }
        return "Lid helper update ready. Sleep protection is held briefly during replacement, then restored to its previous state."
    }
    init(info: [String: Any], lidOpen: Bool, publisherMatches: Bool = true) {
        installed = !info.isEmpty; self.lidOpen = lidOpen
        pending = installed && (!publisherMatches || info["PerchLidProtocolVersion"] as? Int != LidGuardCompatibility.protocolVersion ||
            (info["PerchLidHelperVersion"] as? Int ?? 0) < LidGuardCompatibility.helperVersion)
    }
}
struct LidHelperStartupUpdate {
    private(set) var attempted = false
    mutating func claim(pending: Bool, available: Bool) -> Bool {
        guard pending, available, !attempted else { return false }
        attempted = true
        return true
    }
}
final class LidHelperUpdate {
    static let shared = LidHelperUpdate()
    private(set) var busy = false {
        didSet { if oldValue && !busy { completeStartup() } }
    }
    private(set) var result: String?
    private var publisherMarker: String?
    private var matchingPublisher = false
    private var startup = LidHelperStartupUpdate()
    private var startupCompletion: (() -> Void)?
    private func completeStartup() {
        let completion = startupCompletion; startupCompletion = nil
        if let completion { DispatchQueue.main.async(execute: completion) }
    }
    func recordResumeFailure(_ error: Error) {
        result = "Your lid choice is saved, but protection could not start. " + error.localizedDescription
    }
    func afterLaunch(explain: @escaping () -> Void, refresh: @escaping () -> Void, completion: @escaping () -> Void) {
        guard !SettingsWindow.shared.testing else { completion(); return }
        SettingsWindow.shared.afterInteraction { [weak self] in
            guard let self, self.startup.claim(pending: self.state.pending,
                available: !self.busy && !AppUpdate.shared.busy && !PerchUpdater.shared.busy && !LidGuardClient.shared.changing) else { completion(); return }
            self.startupCompletion = completion
            self.result = "Perch needs to update its installed lid helper. macOS will ask for administrator authorization. Your saved choices and existing timer are kept."
            explain()
            // Render the explanation before yielding focus to system authorization.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindow.shared.afterInteraction {
                    self.finish(); refresh()
                }
            }
        }
    }
    var state: LidHelperUpdateState {
        // This cache only controls the update notice. XPC and the installer
        // independently verify signatures before accepting or executing code.
        let attributes = try? FileManager.default.attributesOfItem(atPath: LidGuardInstall.binary)
        let marker = [FileAttributeKey.systemFileNumber, .size, .modificationDate].map { String(describing: attributes?[$0]) }.joined(separator: "|")
        if marker != publisherMarker {
            publisherMarker = marker
            matchingPublisher = LidGuardInstall.publisherMatches(URL(fileURLWithPath: LidGuardInstall.bundle))
        }
        return LidHelperUpdateState(info: AppUpdate.appInfo(URL(fileURLWithPath: LidGuardInstall.bundle)), lidOpen: MacLidGuardHardware().observe().closed == false, publisherMatches: matchingPublisher)
    }
    func finish() {
        guard !busy, !AppUpdate.shared.busy, !PerchUpdater.shared.busy, !SettingsWindow.shared.testing else { completeStartup(); return }
        guard state.pending else { completeStartup(); return }
        busy = true; result = "Installing the lid helper. macOS will ask for administrator authorization."
        do {
            let resume = try LidGuardInstall.install(protectedUpdate: true)
            LidGuardClient.shared.start()
            waitForHelper(until: LidGuardClock.now + 5, resume: resume)
        } catch { busy = false; result = "The previous helper update did not complete. Retry the update below. " + error.localizedDescription }
    }
    private func waitForHelper(until: Double, resume: Bool) {
        LidGuardClient.shared.refresh()
        let status = LidGuardClient.shared.status
        if status?.fresh == true, status?.codeIdentity == CodeIdentity.current {
            guard resume else {
                busy = false; result = "Lid helper updated and responding. Your saved Keep awake choices apply automatically."
                if let app = NSApp.delegate as? AppDelegate {
                    app.automaticLidResume.repaired(); app.resumeSavedLidProtectionIfReady()
                }
                return
            }
            LidGuardClient.shared.change(true) { outcome in
                self.busy = false
                switch outcome {
                case .success: self.result = "Lid helper updated. The temporary update allowance ended and the original session resumed. macOS can still force sleep; check Lid activity if the Mac sleeps unexpectedly."
                case .failure(let error): self.result = "Lid helper updated, but protection could not resume. " + error.localizedDescription
                }
            }
        } else if LidGuardClock.now >= until {
            busy = false; result = "The new lid helper has not confirmed startup. Review Setup → Lid protection to retry."
        } else { DispatchQueue.main.asyncAfter(deadline: .now()+0.25) { self.waitForHelper(until: until, resume: resume) } }
    }
}

struct LidHelperSettingsSnapshot {
    var busy = false
    var result: String?
    var helper: LidHelperUpdateState
    static var current: Self { .init(busy: LidHelperUpdate.shared.busy, result: LidHelperUpdate.shared.result, helper: LidHelperUpdate.shared.state) }
}
struct RestartSettingsSnapshot {
    var busy = false
    var message = ""
    static var current: Self {
        .init(busy: PerchUpdater.shared.busy || AppUpdate.shared.busy || LidHelperUpdate.shared.busy || LidGuardClient.shared.changing, message: AppUpdate.shared.message)
    }
}
