import AppKit
import Darwin

struct InputHelperStatus: Codable {
    var timestamp = Date()
    var pid = getpid()
    var helperBuild: String = HelperBuild.current
    var statusProtocol: Int = HelperBuild.protocolVersion
    var trusted: Bool
    var active: Bool
    var navigationDevices: Int?
    var navigationObserved: Bool?
    var navigationUnidentified: Bool?
    var fresh: Bool { HelperBuild.compatible(build: helperBuild, protocolVersion: statusProtocol) && Date().timeIntervalSince(timestamp) < 4 }
    static var permissionRequest: URL { SafetyFiles.base.appendingPathComponent("input-permission-request.json") }
}
final class InputHelper {
    let inputs = InputControls()
    lazy var navigationRuntime = NavigationRuntime(engine: inputs.navigation)
    let collectorConnection = CollectorPipeAnchor(path: ProcessEventStream.pipePath)
    var timer: Timer?
    var configSignal: FileChangeSignal?
    var lastStatus: InputHelperStatus?
    var statusServer: HelperStatusServer?
    var lock: Int32 = -1
    func run() {
        try? SafetyFiles.prepare()
        lock = open(SafetyFiles.base.appendingPathComponent("input.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        NSApp.setActivationPolicy(.prohibited)
        configSignal = FileChangeSignal(SafetyFiles.config) { [weak self] in self?.tick() }
        let server = HelperStatusServer(service: HelperStatusIPC.input)
        statusServer = server; server.start()
        try? FileManager.default.removeItem(at: SafetyFiles.base.appendingPathComponent("input-status.json"))
        tick()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        RunLoop.main.add(timer!, forMode: .common)
        NSApp.run()
    }
    func tick() {
        collectorConnection.refresh()
        configSignal?.refresh()
        // Input preferences only: no catalog parsing, process scans or app metadata queries.
        if let config = try? SafetyFiles.read(SafetyConfiguration.self, from: SafetyFiles.config) {
            navigationRuntime.configure(config.navigation ?? NavigationPreferences(), profiles: config.navigationProfiles ?? [])
            inputs.reverseTrackpad = config.reverseTrackpad
            inputs.reverseWheel = config.reverseWheel
            inputs.swapModifiers = false // Native per-keyboard modifier settings replace the v1 global event filter.
        }
        let requested = (try? SafetyFiles.read(Date.self, from: InputHelperStatus.permissionRequest)).map { Date().timeIntervalSince($0) < 10 } ?? false
        if requested { try? FileManager.default.removeItem(at: InputHelperStatus.permissionRequest) }
        let trusted = AXIsProcessTrusted()
        let active = inputs.update(requestPermission: requested, trusted: trusted)
        let status = InputHelperStatus(trusted: trusted, active: active, navigationDevices: inputs.navigation.devices.count, navigationObserved: inputs.navigation.observed, navigationUnidentified: inputs.navigation.unidentified)
        if lastStatus?.trusted != status.trusted || lastStatus?.active != status.active || Date().timeIntervalSince(lastStatus?.timestamp ?? .distantPast) >= 1 {
            statusServer?.publish(status); lastStatus = status
        }
    }
}
