import AppKit

struct LidHelperUpdateState: Equatable {
    let installed: Bool
    let pending: Bool
    let lidOpen: Bool
    var notice: String {
        guard pending else { return installed ? "Lid helper is up to date." : "Lid protection is optional. Set it up in Keep awake when needed." }
        return lidOpen ? "Lid helper update ready. Finish it below when convenient." : "Lid helper update queued. Open the lid to finish it; the existing helper stays installed."
    }
    init(info: [String: Any], lidOpen: Bool, publisherMatches: Bool = true) {
        installed = !info.isEmpty; self.lidOpen = lidOpen
        pending = installed && (!publisherMatches || info["PerchLidProtocolVersion"] as? Int != LidGuardCompatibility.protocolVersion ||
            (info["PerchLidHelperVersion"] as? Int ?? 0) < LidGuardCompatibility.helperVersion)
    }
}
final class LidHelperUpdate {
    static let shared = LidHelperUpdate()
    private(set) var busy = false
    private(set) var result: String?
    private var publisherMarker: String?
    private var matchingPublisher = false
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
        guard !busy, !AppUpdate.shared.busy, !PerchUpdater.shared.busy, !SettingsWindow.shared.testing else { return }
        guard state.pending, state.lidOpen else { result = "Open the lid before finishing the queued helper update."; return }
        busy = true; result = "Installing the lid helper. macOS will ask for administrator authorization."
        let resume = LidGuardClient.shared.active
        do {
            // The root installer repeats this check after authorization and
            // signature verification, immediately before stopping any helper.
            try LidGuardInstall.install(requireOpenLid: true)
            LidGuardClient.shared.start()
            waitForHelper(until: LidGuardClock.now + 5, resume: resume)
        } catch { busy = false; result = "Helper update is still queued. " + error.localizedDescription }
    }
    private func waitForHelper(until: Double, resume: Bool) {
        LidGuardClient.shared.refresh()
        let status = LidGuardClient.shared.status
        if status?.fresh == true, status?.codeIdentity == LidGuardIdentity.current {
            guard resume else {
                busy = false; result = "Lid helper updated and responding. Enable lid protection in Keep awake when you want it."; return
            }
            guard MacLidGuardHardware().observe().closed == false else {
                busy = false; result = "Lid helper updated. The lid closed during installation, so protection was left off. Review Keep awake."; return
            }
            LidGuardClient.shared.change(true) { outcome in
                self.busy = false
                switch outcome {
                case .success: self.result = "Lid helper updated. Your active lid choice was restored with the lid open; continued sleep prevention remains unverified."
                case .failure(let error): self.result = "Lid helper updated, but protection could not resume. " + error.localizedDescription
                }
            }
        } else if LidGuardClock.now >= until {
            busy = false; result = "The new lid helper has not confirmed startup. Review Keep awake or try Repair lid protection."
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
