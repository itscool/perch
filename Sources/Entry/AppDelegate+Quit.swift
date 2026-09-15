import AppKit

/// Manual Quit turns Perch's features off. It asks first only when something
/// is on, naming what stops in feature terms. Restart for an update and the
/// preferences reset quit through their own paths and keep their behavior.
extension AppDelegate {
    @objc func quit() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            let plan = QuitPlan(self.quitFeatures())
            guard plan.needsConfirmation else { self.quitTurningOff(plan); return }
            let alert = NSAlert()
            alert.messageText = plan.title
            alert.informativeText = plan.detail
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            SettingsWindow.shared.presentStandaloneNotice(alert) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.quitTurningOff(plan) }
            }
        }
    }

    func quitFeatures() -> QuitPlan.Features {
        let config = SafetyConfiguration.load()
        let state = try? SafetyFiles.read(SafetyState.self, from: SafetyFiles.state)
        return .init(closedLid: LidGuardClient.shared.active,
                     keepAwake: config.keepAwake,
                     preventIdleLock: UserDefaults.standard.bool(forKey: SleepPreferences.preventIdleLockKey),
                     scrolling: inputs.reverseTrackpad || inputs.reverseWheel || inputs.navigation.preferences.enabled,
                     desk: DeskCoordinator.shared.runtime != nil,
                     panicShortcut: GuardianInstall.alive && config.shortcut.enabled,
                     agentsBlocked: state.map { $0.locked || !$0.disabledJobs.isEmpty } ?? false)
    }

    func quitTurningOff(_ plan: QuitPlan) {
        pendingQuit = plan
        // Terminate from the run loop rather than inside this main-queue block,
        // so the lid helper's reply can arrive while AppKit waits.
        TerminationReply.schedule(after: 0) { NSApp.terminate(nil) }
    }

    /// Runs inside the deferred termination: end the lid session, then stop
    /// the helpers. Saved choices are untouched, so the next launch restores them.
    func turnOffForQuit(_ plan: QuitPlan, completion: @escaping () -> Void) {
        QuitShutdown.perform(timeout: 3, endLidSession: { done in
            guard LidGuardClient.shared.status?.armed == true || LidGuardOwnership.recorded else { done(); return }
            LidGuardClient.shared.change(false) { _ in done() }
        }, stopHelpers: { HelperLifecycle.stopForQuit(keepGuardian: plan.keepsGuardian) }, completion: completion)
    }
}
