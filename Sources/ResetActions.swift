import AppKit

/// Privacy-only actions have a fixed executable and argument list. They never
/// enter the guardian's panic, process-tracking or launch-job code paths.
enum PrivacyOnlyReset {
    static func arguments(global: Bool) -> [String] {
        global ? ["reset", "All"] : ["reset", "All", PanicPlan.perchID]
    }
    private static var running = false
    static func run(global: Bool, completion: @escaping (String) -> Void) {
        guard !running else { completion("⚠ A privacy reset is already running."); return }
        running = true
        DispatchQueue.global(qos:.userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath:"/usr/bin/tccutil")
            task.arguments = arguments(global:global)
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            let result: String
            do {
                try task.run(); task.waitUntilExit()
                result = task.terminationStatus == 0
                    ? "✓ macOS accepted the privacy reset. Apps may ask for access again. Review Privacy & Security for any entries that remain; some changes require an app relaunch."
                    : "⚠ macOS did not complete the privacy reset (exit \(task.terminationStatus)). Review Privacy & Security for remaining permissions."
            } catch { result = "⚠ " + error.localizedDescription }
            DispatchQueue.main.async { running = false; completion(result) }
        }
    }
}

extension AppDelegate {
    @objc func globalPrivacyReset() { withMenuClosed { [weak self] in self?.privacyOnlyReset(global:true) } }
    func privacyOnlyReset(global: Bool) {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:274))
        let status = NSTextField(wrappingLabelWithString:global
            ? "Resets privacy decisions for all apps in your macOS account, including Perch. Perch sends no app-termination commands and does not block relaunches. This is not guaranteed to stop an agent: shell and network activity can continue."
            : "Resets privacy decisions for Perch and its helpers, which share Perch’s bundle identity. Other apps are excluded. The shared macOS eslogger permission is not Perch-owned; review it separately in Privacy & Security if needed.")
        status.frame = NSRect(x:0,y:108,width:572,height:150); status.textColor = .secondaryLabelColor
        var active = true
        weak var confirmReference: SettingsActionButton?
        let confirm = SettingsActionButton(title:global ? "Reset all apps’ privacy permissions" : "Reset Perch’s privacy permissions") {
            guard !SettingsWindow.shared.testing else { return }
            confirmReference?.isEnabled = false
            status.stringValue = "Resetting privacy permissions…"
            PrivacyOnlyReset.run(global:global) { result in
                guard active else { return }
                status.stringValue = result
                status.textColor = result.hasPrefix("✓") ? StatusColors.success : StatusColors.warning
            }
        }
        confirmReference = confirm
        confirm.frame = NSRect(x:0,y:54,width:572,height:32)
        let recovery = SettingsActionButton(title: "Review Perch setup & status…") { [weak self] in self?.setupOverview() }
        recovery.frame = NSRect(x:0,y:10,width:572,height:32)
        recovery.toolTip = "Check current access and restore missing Perch setup. Opening this does not reset anything."
        page.addSubview(status); page.addSubview(confirm); page.addSubview(recovery)
        SettingsWindow.shared.show(.init(title:global ? "Reset all apps’ privacy permissions?" : "Reset Perch’s privacy permissions?",detail:"Only clicking the reset button below performs this action. Resetting permissions also forgets previous denials; it is not a permanent block. Back cancels.",view:page,leave:{active=false}))
    }
    func systemResetPage(includeAudio: Bool = true) {
        let page = NSView(frame:NSRect(x:0,y:0,width:572,height:includeAudio ? 260 : 220))
        weak var applyReference: SettingsActionButton?
        let update: () -> Void = { [weak page] in
            applyReference?.isEnabled = page?.subviews.compactMap { $0 as? NSButton }.contains { $0.state == .on } == true
        }
        let sleep = SettingsActionButton(title:"Remove the lid override and Perch’s keep-awake request",action:update)
        let audio = SettingsActionButton(title:"Unmute system audio",action:update)
        sleep.setButtonType(.switch); audio.setButtonType(.switch)
        sleep.frame = NSRect(x:0,y:includeAudio ? 210 : 170,width:572,height:28)
        audio.frame = NSRect(x:0,y:170,width:572,height:28)
        audio.isHidden = !includeAudio
        let result = NSTextField(wrappingLabelWithString:"These are system-wide changes, regardless of which app set them. Other apps’ sleep assertions remain. Keyboard system/firmware settings are not reset: Perch has no recorded original values to restore.")
        result.frame = NSRect(x:0,y:55,width:572,height:110); result.textColor = .secondaryLabelColor
        let apply = SettingsActionButton(title:"Reset selected system settings") { [weak self] in
            guard !SettingsWindow.shared.testing, sleep.state == .on || audio.state == .on else { return }
            applyReference?.isEnabled = false
            var results: [String] = []
            if sleep.state == .on {
                do {
                    try LidGuardInstall.cleanup()
                    try SleepMasterChange.run(enabled:false,includeLid:false,readLid:sleepDisabled,writeLid:setSleepDisabled,setAwake:{ enabled in
                        var config = SafetyConfiguration.load(); config.keepAwake = enabled; try config.save()
                    },stopCaffeinate:{})
                    UserDefaults.standard.removeObject(forKey:SleepMasterChange.lidPreferenceKey)
                    results.append("✓ Lid override removed; Perch’s keep-awake request cleared.")
                    sleep.state = .off
                } catch { results.append("⚠ Sleep: " + error.localizedDescription) }
            }
            if audio.state == .on {
                do {
                    _ = try script("set volume output muted false")
                    guard try !AudioStatus.muted() else { throw AppError(message:"Audio is still muted.") }
                    results.append("✓ System audio is unmuted.")
                    audio.state = .off
                } catch { results.append("⚠ Audio: " + error.localizedDescription) }
            }
            result.stringValue = results.joined(separator:"\n")
            result.textColor = results.contains { $0.hasPrefix("⚠") } ? StatusColors.warning : StatusColors.success
            applyReference?.title = results.contains { $0.hasPrefix("⚠") } ? "Retry failed system changes" : "Reset selected system settings"
            update()
            self?.refresh()
        }
        applyReference = apply; apply.isEnabled = false
        apply.frame = NSRect(x:0,y:10,width:572,height:32)
        [sleep,audio,result,apply].forEach { page.addSubview($0) }
        SettingsWindow.shared.show(.init(title:includeAudio ? "Reset system sleep and audio" : "Reset sleep overrides",detail:"Select the exact changes to apply. Nothing is selected initially. macOS may ask for administrator authorization for sleep changes.",view:page))
    }
}
