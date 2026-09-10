import AppKit

/// Captured once for the running process; never rediscovered from a replaced bundle.
struct AppBuild: Equatable {
    let version: String
    let build: String
    init?(_ info: [String: Any]) {
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              Self.parts(version) != nil, Self.parts(build) != nil else { return nil }
        self.version = version; self.build = build
    }
    private static func parts(_ value: String) -> [UInt64]? {
        guard !value.isEmpty, value.count <= 64 else { return nil }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { return nil }
        let numbers = pieces.compactMap { UInt64($0) }
        return numbers.count == pieces.count ? numbers : nil
    }
    private static func compare(_ a: String, _ b: String) -> Int {
        let a = parts(a)!, b = parts(b)!
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
    func newer(than other: AppBuild) -> Bool {
        let versionOrder = Self.compare(version, other.version)
        return versionOrder > 0 || (versionOrder == 0 && Self.compare(build, other.build) > 0)
    }
    var title: String { version }
}

struct AppReplacementState {
    let running: AppBuild?
    var available: AppBuild?
    private(set) var notified = false
    mutating func takeNotice(interacting: Bool) -> AppBuild? {
        guard !interacting, !notified, let available else { return nil }
        notified = true
        return available
    }
}

/// Only this worker touches disk/signatures. A failed verification is retried:
/// an updater can replace Info.plist before the rest of the bundle is ready.
final class AppReplacementReader {
    let path: URL
    let running: AppBuild?
    let identifier: String?
    let verify: (URL) throws -> Void
    private var revision: [FileRevision?]?
    private var cached: AppBuild?
    init(path: URL, running: AppBuild?, identifier: String?, verify: @escaping (URL) throws -> Void) {
        self.path = path; self.running = running; self.identifier = identifier; self.verify = verify
    }
    func read() -> AppBuild? {
        let plist = path.appendingPathComponent("Contents/Info.plist")
        let binary = path.appendingPathComponent("Contents/MacOS/Perch")
        func revisions() -> [FileRevision?] { [FileRevision.read(path), FileRevision.read(plist), FileRevision.read(binary)] }
        let before = revisions()
        if revision == before { return cached }
        guard let running, let identifier, before.allSatisfy({ $0 != nil }),
              let handle = try? FileHandle(forReadingFrom: plist) else { revision = nil; cached = nil; return nil }
        defer { try? handle.close() }
        do {
            let data = try handle.read(upToCount: 65_537) ?? Data()
            guard data.count < 65_536,
                  let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == identifier,
                  let disk = AppBuild(info) else { revision = nil; cached = nil; return nil }
            if disk.newer(than: running) { try verify(path) }
            guard before == revisions() else { revision = nil; cached = nil; return nil }
            cached = disk.newer(than: running) ? disk : nil
            revision = before
            return cached
        } catch { revision = nil; cached = nil; return nil }
    }
}

final class AppReplacementMonitor {
    var state: AppReplacementState
    var onChange: (() -> Void)?
    private let reader: AppReplacementReader
    private let queue = DispatchQueue(label: "Perch.installed-app", qos: .utility)
    private var checking = false
    private var lastCheck = Date.distantPast
    private var timer: Timer?
    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let running = AppBuild(info)
        state = .init(running: running)
        reader = AppReplacementReader(path: Bundle.main.bundleURL, running: running, identifier: info["CFBundleIdentifier"] as? String) { path in
            guard let requirement = HelperStatusIPC.requirement else { throw AppError(message: "No signing identity") }
            _ = try AppUpdate.identity(path, requirement: requirement)
        }
    }
    func start() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer!, forMode: .common)
        check()
    }
    func check() {
        guard !checking, Date().timeIntervalSince(lastCheck) >= 5 else { return }
        checking = true; lastCheck = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let available = self.reader.read()
            DispatchQueue.main.async {
                self.checking = false
                self.state.available = available
                self.onChange?()
            }
        }
    }
    deinit { timer?.invalidate() }
}

extension AppDelegate {
    func refreshAppReplacement(showNotice: Bool = true) {
        // Do not insert/remove rows or interrupt an open menu while a scan finishes.
        guard !menuOpen, let info = replacementInfoItem, let restart = replacementRestartItem else { return }
        let available = appReplacement.state.available
        info.isHidden = available == nil; restart.isHidden = available == nil
        if let available, let running = appReplacement.state.running {
            label(info, "Running \(running.title)", hint: "On disk \(available.title)", hintColor: StatusColors.information)
            info.menuHelp = "A newer Perch is installed at this app’s location. Restart to use it."
            label(restart, "Restart Perch", hint: "Use \(available.title)")
        }
        restart.isEnabled = available != nil && !RestartSettingsSnapshot.current.busy
        if showNotice { considerAppReplacementNotice() }
    }
    func considerAppReplacementNotice() {
        let host = SettingsWindow.shared
        guard let available = appReplacement.state.takeNotice(interacting: menuOpen || host.interactionBusy || host.window.isVisible || RestartSettingsSnapshot.current.busy),
              let running = appReplacement.state.running else { return }
        let alert = NSAlert(); alert.messageText = "A newer Perch is ready"
        alert.informativeText = "Running: \(running.title)\nOn disk: \(available.title)\n\nRestart to use the installed version. Your saved choices are kept, and an active lid session keeps its existing timeout. You can also restart later from the Perch menu."
        alert.addButton(withTitle: "Restart now"); alert.addButton(withTitle: "Later")
        host.present(alert) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.restartForReplacement() }
        }
    }
    @objc func restartForReplacement() {
        guard !RestartSettingsSnapshot.current.busy else { return }
        withMenuClosed { [weak self] in
            guard let self else { return }
            if let driver = self.replacementRestartTestDriver { driver(); return }
            // Keep errors/progress discoverable if signature or handoff revalidation fails.
            self.configureSettings(); self.appSettings()
            AppUpdate.shared.restartCurrentApp()
        }
    }
}
