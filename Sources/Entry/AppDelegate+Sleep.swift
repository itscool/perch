import AppKit

// Current protection must not adopt a system override it does not own.
func unownedSleepOverride() throws -> Bool { try LidSleepOverride.systemDisabled() && !LidSleepOverride.owned }

/// Keep awake, lid protection, idle lock, display and audio rows.
extension AppDelegate {
    var actualLidState: NSControl.StateValue {
        LidGuardClient.controlState(unownedOverride: observedLidDisabled, status: LidGuardClient.shared.status, recordedSession: LidGuardOwnership.recorded)
    }
    func sleepPresentation() -> SleepPresentation {
        let client = LidGuardClient.shared
        return SleepPresentation(ordinary: observedSleep, actualLid: actualLidState,
            savedLid: UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey),
            masterWanted: SafetyConfiguration.load().keepAwake,
            changing: client.changing, remaining: client.status?.remaining)
    }
    func applyLidSleepPresentation() {
        guard awakeItem != nil, lidItem != nil else { return }
        let value = sleepPresentation()
        // Do not apply provisional labels or states during a background read.
        // Unchanged polling leaves the native row entirely alone.
        guard value != renderedSleep else { return }
        renderedSleep = value
        awakeItem.state = value.awake; awakeItem.isEnabled = value.awakeEnabled
        lidItem.state = value.lid; lidItem.isEnabled = value.lidEnabled
        label(awakeItem, "Keep awake", hint: value.awakeHint)
        label(lidItem, "Including with lid closed", hint: value.lidHint, hintColor: observedLidDisabled == true ? StatusColors.warning : .secondaryLabelColor)
        awakeItem.menuHelp = ControlHelp.awake
        lidItem.menuHelp = ControlHelp.adding(ControlHelp.lidSaved, to: ControlHelp.lid)
    }
    @objc func toggleIdleLock() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            let enabling = !self.idleLock.enabled
            UserDefaults.standard.set(enabling, forKey: SleepPreferences.preventIdleLockKey)
            self.idleLock.set(enabling)
            self.refreshIdleLock()
        }
    }
    func refreshIdleLock() {
        guard idleLockItem != nil else { return }
        let on = idleLock.enabled
        idleLockItem.state = on ? .on : .off
        label(idleLockItem, "Prevent idle lock", hint: IdleLockPreventer.rowHint(enabled: on))
        idleLockItem.menuHelp = ControlHelp.idleLock
    }
    @objc func toggleAwake() {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try SleepStatus.read()
                let enabling = !(LidGuardClient.shared.active || state.perchActive || state.caffeinateActive)
                guard !enabling || GuardianInstall.alive else {
                    self.advancedSafetySettings()
                    let host = SettingsWindow.shared
                    if let page = host.pages.last, page.title == "Background helpers" {
                        host.feedback = "Keep awake needs the background helper. Complete setup below, then return to Keep awake."
                        host.display(page)
                    }
                    return
                }
                let remembered = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        var config = SafetyConfiguration.load(); config.keepAwake = enabling; try config.save()
                        if !enabling { try state.stopCaffeinate() }
                        self.refresh()
                    } catch {
                        self.refresh()
                        if enabling && remembered { self.showLidSetup(error.localizedDescription) } else { self.showError(error) }
                    }
                }
                if enabling && remembered { self.changeSupervisedLid(true, completion: finish) }
                else if LidGuardClient.shared.status?.armed == true || LidGuardOwnership.recorded { self.changeSupervisedLid(false, completion: finish) }
                else { finish(.success(())) }
            } catch { self.refresh(); self.showError(error) }
        }
    }
    @objc func toggleLid() { changeLidChoice() }
    func showLidSetup(_ explanation: String) {
        let host = SettingsWindow.shared
        host.returnedToApp()
        host.afterInteraction { [weak self] in
            guard let self else { return }
            self.openSetupStage("lid-setup")
            if let page = host.pages.last, page.title == "Lid protection setup" {
                host.feedback = explanation
                host.display(page)
            }
        }
    }
    func changeLidChoice(readSleep: @escaping () throws -> SleepStatus = { try SleepStatus.read() }) {
        withMenuClosed { [weak self] in
            guard let self else { return }
            do {
                let state = try readSleep()
                let saved = UserDefaults.standard.bool(forKey: SleepPreferences.lidPreferenceKey)
                guard saved || LidGuardClient.shared.active || state.perchActive || state.caffeinateActive else { self.refresh(); return }
                let enabling = !saved

                if enabling && (LidHelperUpdate.shared.state.pending || LidGuardClient.shared.status?.fresh != true) {
                    var config = SafetyConfiguration.load(); config.keepAwake = true; try config.save()
                    UserDefaults.standard.set(true, forKey: SleepPreferences.lidPreferenceKey)
                    self.refresh()
                    self.showLidSetup("Your lid choice is saved. Finish lid protection setup below, then return to Keep awake to resume protection. Lid protection has not been confirmed.")
                    return
                }

                let finish: (Result<Void, Error>) -> Void = { result in
                    do {
                        try result.get()
                        UserDefaults.standard.set(enabling, forKey: SleepPreferences.lidPreferenceKey)
                        var config = SafetyConfiguration.load(); if enabling { config.keepAwake = true; try config.save() }
                        self.refresh(); self.settingsRefresh?()
                    } catch { self.refresh(); self.showLidSetup(error.localizedDescription) }
                }
                if !enabling && !LidGuardOwnership.recorded && LidGuardClient.shared.status?.armed != true { finish(.success(())) }
                else { self.changeSupervisedLid(enabling, completion: finish) }
            } catch { self.refresh(); self.showError(error) }
        }
    }
    @objc func turnDisplayOff() {
        menu.cancelTracking()
        // Let the selecting mouse/keyboard event finish before sleeping the display.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.perform {
                guard try Subprocess.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5).succeeded else { throw AppError(message: "macOS could not turn off the display.") }
            }
        }
    }
    @objc func toggleAudio() {
        perform {
            let muted = try AudioStatus.muted()
            _ = try AppleScript.run("set volume output muted \(muted ? "false" : "true")")
            guard try AudioStatus.muted() != muted else {
                throw AppError(message: "This audio output does not support system mute. Use the output device’s volume control.")
            }
        }
    }
}
