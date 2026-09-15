import AppKit
import IOKit.hid

/// Every way the Perch executable runs other than as the menu app: privileged
/// lid helpers, background workers and headless tests. Matching keeps the
/// historical order, since an earlier match wins over a later flag.
enum ProcessRole: Equatable {
    case checkModifierAccess
    case restartWorker(path: String)
    case lidMaintenance(operation: String, arguments: [String])
    case checkLidUpdate
    case updateCatalog(path: String)
    case lidOverrideWorker(path: String, token: String, deadline: Double)
    case lidRecover
    case lidGuard(owner: UInt32)
    case lidWatchdog
    case lidCleanup
    case prepareSafetyConfig
    case installWatcher
    case safetyPreview
    case inputHelper
    case guardian
    case panicWorker(planPath: String)
    case statusStream
    case ipcSelfTest
    case cpuBenchmark
    case settingsSelfTest
    case eventSelfTest
    case navigationDeviceInfo
    case selfTest

    /// `root` stands in for the process's effective user: the lid guard runs
    /// only as root and otherwise falls through to the menu app.
    static func parse(_ arguments: [String], root: Bool = geteuid() == 0) -> ProcessRole? {
        guard let executable = arguments.first else { return nil }
        if arguments.contains("--check-modifier-access") { return .checkModifierAccess }
        if arguments.count == 3, arguments[1] == "--restart-worker" { return .restartWorker(path: arguments[2]) }
        if arguments.count >= 2, arguments[1].hasPrefix("--lid-maintenance-") {
            return .lidMaintenance(operation: arguments[1], arguments: Array(arguments.dropFirst(2)))
        }
        if arguments == [executable, "--check-lid-update"] { return .checkLidUpdate }
        if let index = arguments.firstIndex(of: "--update-catalog"), arguments.count > index + 1 { return .updateCatalog(path: arguments[index + 1]) }
        if arguments.count == 5, arguments[1] == "--lid-override-worker", let deadline = Double(arguments[4]) {
            return .lidOverrideWorker(path: arguments[2], token: arguments[3], deadline: deadline)
        }
        if arguments.contains("--lid-recover") { return .lidRecover }
        if arguments.count == 3, arguments[1] == "--lid-guard", let owner = UInt32(arguments[2]), owner >= 501, root { return .lidGuard(owner: owner) }
        if arguments == [executable, "--lid-watchdog"] { return .lidWatchdog }
        if arguments == [executable, "--lid-cleanup"] { return .lidCleanup }
        if arguments.contains("--prepare-safety-config") { return .prepareSafetyConfig }
        if arguments.contains("--install-watcher") { return .installWatcher }
        if arguments.contains("--safety-preview") { return .safetyPreview }
        if arguments.contains("--input-helper") { return .inputHelper }
        if arguments.contains("--guardian") { return .guardian }
        if let index = arguments.firstIndex(of: "--panic-worker"), arguments.count > index + 1 { return .panicWorker(planPath: arguments[index + 1]) }
        if arguments.contains("--status-stream") { return .statusStream }
        if arguments.contains("--ipc-self-test") { return .ipcSelfTest }
        if arguments.contains("--cpu-benchmark") { return .cpuBenchmark }
        if arguments.contains("--settings-self-test") { return .settingsSelfTest }
        if arguments.contains("--event-self-test") { return .eventSelfTest }
        if arguments.contains("--navigation-device-info") { return .navigationDeviceInfo }
        if arguments.contains("--self-test") { return .selfTest }
        return nil
    }

    /// Run the role to completion; every role ends the process itself.
    func run() -> Never {
        switch self {
        case .checkModifierAccess:
            NativeModifierKeys.checkExistingAccess()
            exit(0)
        case .restartWorker(let path):
            _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
            do { try AppUpdate.runWorker(path); exit(0) }
            catch {
                UserDefaults.standard.set("Restart did not complete. " + error.localizedDescription, forKey: AppUpdate.noticeKey)
                fputs("Update failed: \(error.localizedDescription)\n", stderr); exit(1)
            }
        case .lidMaintenance(let operation, let arguments): Self.lidMaintenance(operation, arguments)
        case .checkLidUpdate:
            guard MacLidGuardHardware().observe().closed == false else {
                fputs("Open the lid before finishing the helper update. Nothing has been replaced.\n", stderr); exit(1)
            }
            exit(0)
        case .updateCatalog(let path):
            do { try AgentCatalog.install(from: URL(fileURLWithPath: path)); print("Catalog updated; new targets default to checked and existing choices are preserved."); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        case .lidOverrideWorker(let path, let token, let deadline):
            do { try LidSleepOverride.worker(path, token: token, deadline: deadline); exit(0) }
            catch { fputs("Lid override failed: \(error.localizedDescription)\n", stderr); exit(1) }
        case .lidRecover: Self.lidRecover()
        case .lidGuard(let owner):
            let service = LidGuardService(owner: owner)
            service.run()
        case .lidWatchdog: runLidGuardWatchdog()
        case .lidCleanup: Self.lidCleanup()
        case .prepareSafetyConfig:
            do {
                if !FileManager.default.fileExists(atPath: SafetyFiles.config.path) {
                    var config = SafetyConfiguration()
                    config.keepAwake = try SleepStatus.read().perchActive
                    try config.save()
                }
                exit(0)
            } catch { fputs("\(error)\n", stderr); exit(1) }
        case .installWatcher:
            do { try GuardianInstall.install(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
        case .safetyPreview:
            _ = NSApplication.shared
            let guardian = AgentGuardian()
            guardian.refreshTracking()
            let grouped = Dictionary(grouping: guardian.tracker.tracked.values, by: \.targetID)
            for (target, processes) in grouped.sorted(by: { $0.key < $1.key }) { print("\(target): \(processes.count) observed local processes") }
            print("Read-only preview. No signals or permission resets sent.")
            exit(0)
        case .inputHelper:
            _ = NSApplication.shared
            let helper = InputHelper()
            withExtendedLifetime(helper) { helper.run() }
            exit(0)
        case .guardian:
            _ = NSApplication.shared
            let guardian = AgentGuardian()
            withExtendedLifetime(guardian) { guardian.run() }
            exit(0)
        case .panicWorker(let planPath):
            exit(PanicReset.worker(planURL: URL(fileURLWithPath: planPath)))
        case .statusStream: runStatusStream(); exit(0)
        case .ipcSelfTest:
            do { try runHelperStatusTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        case .cpuBenchmark:
            runProcessCPUBenchmark()
            do { try runProcessCPULiveTest(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        case .settingsSelfTest:
            _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
            do { try runSettingsTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        case .eventSelfTest:
            do { try runProcessEventTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        case .navigationDeviceInfo: Self.navigationDeviceInfo()
        case .selfTest: Self.selfTest()
        }
    }

    /// Root-only lid helper update steps, invoked by the privileged installer.
    private static func lidMaintenance(_ operation: String, _ arguments: [String]) -> Never {
        guard geteuid() == 0 else { exit(1) }
        do {
            switch operation {
            case "--lid-maintenance-check":
                guard !FileManager.default.fileExists(atPath: LidMaintenance.path) else { throw AppError(message: "Previous helper update recovery is pending. Retry in a few seconds.") }
            case "--lid-maintenance-snapshot":
                guard arguments.count == 1, let owner = UInt32(arguments[0]) else { throw AppError(message: "Missing session owner.") }
                if let snapshot = try LidMaintenance.snapshotAsUser(owner: owner) { print(snapshot.base64EncodedString()) }
            case "--lid-maintenance-begin":
                guard arguments.count == 2, let owner = UInt32(arguments[0]) else { throw AppError(message: "Missing helper-update identity.") }
                try LidMaintenance.begin(owner: owner, token: arguments[1])
            case "--lid-maintenance-enable": try LidMaintenance.enable()
            case "--lid-maintenance-finish", "--lid-maintenance-abort":
                guard arguments.count == 1 else { throw AppError(message: "Missing helper-update identity.") }
                let resume = try LidMaintenance.finish(success: operation == "--lid-maintenance-finish", token: arguments[0])
                if operation == "--lid-maintenance-finish" { print(resume ? "resume" : "off") }
            case "--lid-maintenance-recover":
                repeat {
                    do { try LidMaintenance.recover() }
                    catch { fputs("Lid update recovery will retry: \(error.localizedDescription)\n", stderr) }
                    if !FileManager.default.fileExists(atPath: LidMaintenance.path) { break }
                    usleep(250_000)
                } while true
            default: throw AppError(message: "Unknown lid update operation.")
            }
            exit(0)
        } catch { fputs("Lid helper update: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    private static func lidRecover() -> Never {
        guard geteuid() == 0 else { exit(1) }
        let activity = LidActivityRecorder(source: "Recovery")
        do {
            if try LidSleepOverride.recover(force: false) {
                activity.record("Independent recovery restored normal system sleep after an expired or missing supervisor lease.")
                let hardware = MacLidGuardHardware(), observation = hardware.observe()
                if observation.closed != false && observation.power != .external { try hardware.requestSleep(); activity.record("Independent recovery requested sleep with the lid closed without external power.") }
            }
            activity.finish(); exit(0)
        } catch { activity.record("Independent system sleep recovery failed: " + error.localizedDescription); activity.finish(); exit(1) }
    }

    private static func lidCleanup() -> Never {
        guard geteuid() == 0 else { exit(1) }
        do {
            if let maintenance = LidMaintenance.record { _ = try LidMaintenance.finish(success: false, token: maintenance.token) }
            let hardware = MacLidGuardHardware(), observation = hardware.observe()
            let recovered = try LidSleepOverride.recover(force: true)
            try LidGuardOwnership.release(LidGuardEnforcer(hardware), sleep: observation.closed != false && observation.power != .external, now: LidGuardClock.now)
            if recovered && observation.closed != false && observation.power != .external { try hardware.requestSleep() }
            exit(0)
        } catch { fputs("Lid cleanup failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    private static func navigationDeviceInfo() -> Never {
        let connected = NavigationProbeKeyboard.connected()
        let saved = (try? KeyboardNavigationProfiles.read()) ?? []
        let registrations = connected.map { KeyboardRegistrationStatus.assess($0.identity, saved: saved) }
        let devices = NavigationEventDevices.read(profiles: registrations.compactMap { $0.profile })
        let native = NativeModifierKeys.keyboards().map { keyboard -> [String:Any] in
            let result: [String:Any] = ["name":keyboard.name,"vendor":keyboard.vendor,"builtIn":keyboard.builtIn,"id":IOHIDServiceClientGetRegistryID(keyboard.service),"product":IOHIDServiceClientCopyProperty(keyboard.service,"ProductID" as CFString) ?? NSNull(),"transport":IOHIDServiceClientCopyProperty(keyboard.service,"Transport" as CFString) ?? NSNull()]
            return result
        }
        let physical = connected.map { ["name":$0.name,"vendor":$0.identity.vendor,"product":$0.identity.product,"transport":$0.transport,"usages":$0.identity.usages] as [String:Any] }
        let registration = registrations.map { ["name":$0.name,"needsSetup":$0.needsSetup,"detail":$0.detail] as [String:Any] }
        let output: [String:Any] = ["native":native,"physical":physical,"registration":registration,"profiles":BundledNavigationProfiles.entries.count,"matched":devices.map { ["sender":String($0.key),"keyCount":$0.value.count] as [String:Any] }]
        if let data = try? JSONSerialization.data(withJSONObject: output,options:[.sortedKeys]), let text = String(data:data,encoding:.utf8) { print(text) }
        exit(0)
    }

    /// The headless self-test: every suite that needs no window or helper.
    private static func selfTest() -> Never {
        do {
            let awake = Awake()
            try awake.set(true)
            guard try SleepStatus.read().currentProcessActive else { throw AppError(message: "Awake assertion failed") }
            try awake.set(false)
            guard try !SleepStatus.read().currentProcessActive else { throw AppError(message: "Assertion release failed") }
            try runProcessRoleTests()
            try runCoreServiceTests()
            try runCaffeinateTests()
            try runCatalogTests()
            try runSystemTests()
            try runProcessCPUTests()
            try runProtectionIssueTests()
            try runProcessEventTests()
            try runHelperStatusTests()
            try runAgentSafetyTests()
            try runHousekeepingTests()
            try runPanicTests()
            try runHotKeyTests()
            try runTerminationReplyTests()
            try runQuitPlanTests()
            try runSettingsPageLifetimeTests()
            try runLidSchedulingTests()
            try runInputTests()
            try runKeyboardModeTests()
            try runNavigationKeyTests()
            try runNavigationRuntimeTests()
            try runSettingsResetTests()
            try runNavigationProbeTests()
            try runKeyboardRegistrationTests()
            print("PASS: function-key mode = \(try FunctionKeys.standard())")
            print("PASS: create/release Mac sleep assertion")
            print("PASS: read sleep override = \(try LidSleepOverride.systemDisabled())")
            print("PASS: read audio muted = \(try AudioStatus.muted()); native read supported = \(AudioStatus.nativeMuted() != nil)")
            exit(0)
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
