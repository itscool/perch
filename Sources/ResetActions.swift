import AppKit

/// Privacy-only actions have a fixed executable and argument list. They never
/// enter the guardian's panic, process-tracking or launch-job code paths.
enum PrivacyOnlyReset {
    static func arguments(global: Bool) -> [String] {
        global ? ["reset", "All"] : ["reset", "All", PanicPlan.perchID]
    }
    static let operation = PrivacyResetOperation { global, completion in
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = arguments(global: global)
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            let result: Result<String, Error>
            do {
                try task.run(); task.waitUntilExit()
                if task.terminationStatus == 0 {
                    result = .success("✓ macOS accepted the privacy reset. Apps may ask for access again. Review Privacy & Security for entries that remain; some changes require an app relaunch.")
                } else { throw AppError(message: "macOS did not complete the privacy reset (exit \(task.terminationStatus)). Review Privacy & Security before retrying; some permissions may already have changed.") }
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// Owned by the app, not a page. Leaving never cancels a command already sent.
final class PrivacyResetOperation {
    enum State { case idle, running, succeeded(String), failed(String) }
    private(set) var states: [Bool: State] = [:]
    private(set) var runningScope: Bool?
    private var generation = UUID()
    private let execute: (Bool, @escaping (Result<String, Error>) -> Void) -> Void
    init(execute: @escaping (Bool, @escaping (Result<String, Error>) -> Void) -> Void) { self.execute = execute }
    func state(global: Bool) -> State { states[global] ?? .idle }
    func prepare(global: Bool) { guard runningScope == nil else { return }; states[global] = .idle }
    func run(global: Bool) {
        guard runningScope == nil else { return }
        generation = UUID(); let request = generation
        runningScope = global; states[global] = .running
        execute(global) { [self] result in
            guard runningScope == global, generation == request else { return }
            runningScope = nil
            switch result {
            case .success(let message): states[global] = .succeeded(message)
            case .failure(let error): states[global] = .failed("⚠ " + error.localizedDescription)
            }
        }
    }
}

extension AppDelegate {
    @objc func globalPrivacyReset() { withMenuClosed { [weak self] in self?.privacyOnlyReset(global:true) } }
    func privacyOnlyReset(global: Bool, operation: PrivacyResetOperation = PrivacyOnlyReset.operation) {
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 320))
        let scope = global
            ? "Resets privacy decisions for all apps in your macOS account, including Perch. This does not terminate apps or block shell and network activity."
            : "Resets privacy decisions for Perch and its helpers, which share Perch’s bundle identity. Other apps are excluded. Review the shared eslogger permission separately in Privacy & Security if needed."
        let explanation = NSTextField(wrappingLabelWithString: scope)
        explanation.frame = NSRect(x: 0, y: 218, width: 572, height: 94); explanation.textColor = .secondaryLabelColor
        let status = NSTextField(wrappingLabelWithString: "")
        status.identifier = .init("privacy.result")
        status.frame = NSRect(x: 0, y: 100, width: 572, height: 110)
        weak var confirmReference: SettingsActionButton?
        let update = { [weak page] in
            let resetTitle = global ? "Reset all apps’ privacy permissions" : "Reset Perch’s privacy permissions"
            confirmReference?.isEnabled = operation.runningScope == nil
            confirmReference?.isHidden = false
            status.textColor = .secondaryLabelColor
            switch operation.state(global: global) {
            case .idle:
                status.stringValue = operation.runningScope == nil ? "Nothing has been reset. Only the reset button starts this action." : "Another privacy reset is running. Wait for its result before starting this one."
                confirmReference?.title = resetTitle
            case .running:
                status.stringValue = "Resetting privacy permissions… You can leave this page. macOS will continue; return here to see the result during this Perch session."
                confirmReference?.title = "Reset in progress…"
            case .succeeded(let result):
                status.stringValue = result; status.textColor = StatusColors.success
                confirmReference?.title = "Start another reset…"
            case .failed(let result):
                status.stringValue = result; status.textColor = StatusColors.warning
                confirmReference?.title = "Retry privacy reset"
            }
            if let page, SettingsWindow.shared.pages.last?.view === page {
                let host = SettingsWindow.shared
                switch operation.state(global: global) {
                case .idle: host.heading.stringValue = global ? "Reset all apps’ privacy permissions?" : "Reset Perch’s privacy permissions?"
                case .running: host.heading.stringValue = "Resetting privacy permissions"
                case .succeeded: host.heading.stringValue = "Privacy reset completed"
                case .failed: host.heading.stringValue = "Privacy reset needs attention"
                }
            }
        }
        let confirm = SettingsActionButton(title: "") {
            guard !SettingsWindow.shared.testing || operation !== PrivacyOnlyReset.operation else { return }
            if case .succeeded = operation.state(global: global) { operation.prepare(global: global) }
            else { operation.run(global: global) }
            update()
        }
        confirm.identifier = .init("privacy.reset"); confirmReference = confirm
        confirm.frame = NSRect(x: 0, y: 54, width: 572, height: 32)
        let recovery = SettingsActionButton(title: "Review Perch setup & status…") { [weak self] in self?.setupOverview() }
        recovery.frame = NSRect(x: 0, y: 10, width: 572, height: 32)
        [explanation, status, confirm, recovery].forEach { page.addSubview($0) }
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in update() }
        RunLoop.main.add(timer, forMode: .common)
        SettingsWindow.shared.show(.init(title: global ? "Reset all apps’ privacy permissions?" : "Reset Perch’s privacy permissions?", detail: "Resetting permissions also forgets previous denials; it is not a permanent block. Leaving before starting makes no changes. Once started, the reset cannot be cancelled here.", view: page, leave: { timer.invalidate() }, refresh: update))
        update()
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
