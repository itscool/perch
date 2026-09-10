import AppKit
import Sparkle

/// Sparkle owns downloading, verification, replacement and LaunchServices
/// relaunch. Perch owns the bounded lid ticket and Settings interaction lifetime.
final class PerchUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = PerchUpdater()
    private var controller: SPUStandardUpdaterController?
    private var restoreSettings: (() -> Void)?
    private var installing: UpdateIdentity?
    private var verifiedIdentity: UpdateIdentity?
    private var installationRequested = false
    private var preparingTermination = false
    private var ticket: LidRestartTicket?
    private(set) var message = "Release updates are not configured in this development build."
    // A routine background feed read must not disable Restart or maintenance.
    // Only an actual update interaction/installation owns those operations.
    var busy: Bool { restoreSettings != nil || preparingTermination || installationRequested }
    var configured: Bool { controller != nil }
    var waitingToInstall: Bool { installationRequested && !preparingTermination }
    var showRecovery: (() -> Void)?
    var canCheck: Bool { controller?.updater.canCheckForUpdates == true && !AppUpdate.shared.busy && !LidHelperUpdate.shared.busy && !LidGuardClient.shared.changing }
    var automatic: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
    func start() {
        guard controller == nil,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let candidate = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do {
            try candidate.updater.start()
            controller = candidate
            if message == "Release updates are not configured in this development build." {
                message = "Check for a newer Perch release. You choose when to install and restart."
            }
        } catch { message = "Update checking could not start: " + error.localizedDescription }
    }
    func check() {
        guard canCheck, let controller else { return }
        ownSettings()
        message = "Checking for updates…"
        controller.checkForUpdates(nil)
    }
    func retryInstallation() {
        guard waitingToInstall else { return }
        NSApp.terminate(nil)
    }
    private func recover(_ explanation: String) {
        message = explanation + " The update is waiting. Retry installation when ready; quitting Perch will also retry it."
        // Sparkle has already closed its install window before the quit event.
        // Restore our owner and provide a real route out of the failure state.
        releaseSettings()
        DispatchQueue.main.async { self.showRecovery?() }
    }
    private func ownSettings() {
        if restoreSettings == nil { restoreSettings = SettingsWindow.shared.beginAuthorization() }
    }
    private func releaseSettings() {
        let restore = restoreSettings; restoreSettings = nil; restore?()
    }
    private func identity(_ item: SUAppcastItem) throws -> UpdateIdentity {
        guard let payload = item.propertiesDictionary["perch:identity"] as? String,
              let signature = item.propertiesDictionary["perch:identitySignature"] as? String,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bundle = Bundle.main.bundleIdentifier, let requirement = HelperStatusIPC.requirement else {
            throw AppError(message: "This release is missing its signed Perch update identity. Your current app is still running.")
        }
        return try UpdateIdentity.verify(payload: payload, signature: signature, publicKey: publicKey,
            bundle: bundle, build: item.versionString, requirement: requirement, lidProtocol: LidGuardCompatibility.protocolVersion)
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !AppUpdate.shared.busy, !LidHelperUpdate.shared.busy, !LidGuardClient.shared.changing,
              !SettingsWindow.shared.testing else {
            throw AppError(message: "Finish the current Perch operation, then check for updates again.")
        }
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        verifiedIdentity = try identity(updateItem)
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installationRequested = true
        do { installing = try identity(item); message = "Preparing to install Perch…" }
        catch { installing = nil; message = error.localizedDescription }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        // Sparkle can retain an installation until an ordinary Quit. Returning
        // false retains its UI; marking this intent makes that Quit use our gate.
        self.updater(updater, willInstallUpdate: item)
        return false
    }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        // The final NSApplication termination gate below also covers install on
        // quit/resumed installation paths that omit the postponement callback.
        verifiedIdentity != nil && !AppUpdate.shared.busy && !LidHelperUpdate.shared.busy && !LidGuardClient.shared.changing
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        releaseSettings()
        if let error { message = error.localizedDescription }
        else if installing == nil { message = "Update check finished. You can check again at any time." }
        if !preparingTermination {
            if let ticket { LidGuardClient.shared.cancelRestart(ticket.id); NetworkUpdateHandoffFile.remove() }
            ticket = nil; installing = nil; verifiedIdentity = nil; installationRequested = false
        }
    }
    func standardUserDriverWillShowModalAlert() { ownSettings() }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        !SettingsWindow.shared.interactionBusy && !AppUpdate.shared.busy && !LidHelperUpdate.shared.busy
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { ownSettings() }
        else { message = "Perch \(update.displayVersionString) is available. Choose Check for updates to review and install it when ready." }
    }
    func standardUserDriverWillFinishUpdateSession() { releaseSettings() }

    /// Return nil for an ordinary Quit/restart. Never stop inputs until this
    /// asynchronous gate has agreed to termination.
    func terminationReply(_ sender: NSApplication, willExit: @escaping () -> Void) -> NSApplication.TerminateReply? {
        guard installationRequested else { return nil }
        guard let proposed = installing else { return .terminateCancel }
        guard !preparingTermination else { return .terminateLater }
        guard !AppUpdate.shared.busy, !LidHelperUpdate.shared.busy, !LidGuardClient.shared.changing else {
            recover("Finish the current Perch operation before installing the update."); return .terminateCancel
        }
        let active = LidGuardClient.shared.active
        let lidOpen = MacLidGuardHardware().observe().closed == false
        let overrideOff = (try? LidSleepOverride.verify(false)) != nil
        guard AppUpdate.canRestart(active: active, lidOpen: lidOpen, recordedSession: LidGuardOwnership.recorded, overrideOff: overrideOff) else {
            recover("The lid session cannot be handed over. Open the lid before installing, or review Keep awake.")
            return .terminateCancel
        }
        guard active else { willExit(); return .terminateNow }
        guard let boot = CollectorIdentity.bootID else { recover("Could not verify this macOS session."); return .terminateCancel }
        preparingTermination = true
        LidGuardClient.shared.prepareForRestart(identity: proposed.codeHash) { result in
            var allowed = false
            defer {
                self.preparingTermination = false
                if allowed { willExit() }
                // A transport failure may complete synchronously; AppKit must
                // first receive terminateLater before we send its reply.
                DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: allowed) }
            }
            do {
                let ticket = try result.get()
                self.ticket = ticket
                try NetworkUpdateHandoffFile.save(.init(boot: boot, path: Bundle.main.bundleURL.standardizedFileURL.path, build: proposed.build, ticket: ticket))
                allowed = true
            } catch {
                if let ticket = self.ticket { LidGuardClient.shared.cancelRestart(ticket.id) }
                self.ticket = nil; NetworkUpdateHandoffFile.remove()
                self.recover("Perch is still running. The lid handoff failed: " + error.localizedDescription)
            }
        }
        return .terminateLater
    }
    func completeLaunch(_ completion: @escaping () -> Void) {
        guard let record = NetworkUpdateHandoffFile.read() else { completion(); return }
        guard record.path == Bundle.main.bundleURL.standardizedFileURL.path else { completion(); return }
        guard record.matches(boot: CollectorIdentity.bootID, path: Bundle.main.bundleURL.standardizedFileURL.path,
                             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                             identity: LidGuardIdentity.current, now: LidGuardClock.now) else {
            NetworkUpdateHandoffFile.remove()
            message = "The previous update’s lid handoff could not be resumed. Review Keep awake and Lid activity before starting a new session."
            completion()
            DispatchQueue.main.async { self.showRecovery?() }
            return
        }
        LidGuardClient.shared.resumeAfterRestart(record.ticket.id) { result in
            NetworkUpdateHandoffFile.remove()
            switch result {
            case .success: self.message = "Perch updated. Your lid session resumed with its original timeout."
            case .failure(let error): self.message = "Perch updated, but lid protection did not resume: " + error.localizedDescription
            }
            completion()
            if case .failure = result { DispatchQueue.main.async { self.showRecovery?() } }
        }
    }
}

extension AppDelegate {
    @objc func updateSettings() {
        let updater = PerchUpdater.shared
        let page = SettingsTaskPage(title: "Updates", detail: "Check for new Perch releases. Downloaded updates are verified before installation; you choose when to restart.", height: 460, statusHeight: 140)
        let automatic = page.add("Check for updates automatically", detail: "Save this choice immediately. Perch asks before installing an update.", checkbox: true) { updater.automatic.toggle() }
        let check = page.add("Check for updates…", detail: "Show available releases, download progress, and installation or retry options.") { updater.check() }
        let retry = updater.waitingToInstall ? page.add("Retry installation", detail: "Try the waiting update again. Perch verifies the lid handoff before quitting.") { updater.retryInstallation() } : nil
        page.update = { [weak page] in
            automatic.state = updater.automatic ? .on : .off
            automatic.isEnabled = updater.configured
            check.isEnabled = updater.canCheck
            retry?.isEnabled = updater.waitingToInstall
            page?.status.stringValue = updater.message
        }
        page.show(delegate: self)
    }
}
