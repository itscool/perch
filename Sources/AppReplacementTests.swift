import AppKit

func runAppReplacementTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func info(_ version: String, _ build: String) -> [String: Any] { ["CFBundleIdentifier": "test.perch", "CFBundleShortVersionString": version, "CFBundleVersion": build] }
    let running = AppBuild(info("1.2.79", "79"))!, next = AppBuild(info("1.2.80", "80"))!
    try check(next.newer(than: running), "New build was missed")
    try check(!running.newer(than: running) && !running.newer(than: next), "Equal/older build offered restart")
    try check(AppBuild(info("1.10", "1"))!.newer(than: AppBuild(info("1.9", "999"))!), "Release ordering was lexical or build-only")
    try check(!AppBuild(info("1.2.79.0", "79.0"))!.newer(than: running), "Equivalent dotted versions differed")
    try check(AppBuild(info("1.2", "bad")) == nil && AppBuild(info("", "80")) == nil, "Malformed version accepted")
    var state = AppReplacementState(running: running)
    try check(state.takeNotice(interacting: false) == nil && !state.notified, "Consumed notice before detection")
    state.available = next
    try check(state.takeNotice(interacting: true) == nil && !state.notified, "Interrupted an active interaction")
    try check(state.takeNotice(interacting: false) == next && state.takeNotice(interacting: false) == nil, "Notice did not fire once per process")
    state.available = nil; state.available = AppBuild(info("1.2.81", "81"))
    try check(state.takeNotice(interacting: false) == nil, "A second disk update repeated the notice in one run")
    var relaunched = AppReplacementState(running: running, available: next)
    try check(relaunched.takeNotice(interacting: false) == next, "A new process inherited dismissal")

    let path = FileManager.default.temporaryDirectory.appendingPathComponent("perch-replacement-" + UUID().uuidString).appendingPathComponent("Perch.app")
    defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: path.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let plist = path.appendingPathComponent("Contents/Info.plist"), binary = path.appendingPathComponent("Contents/MacOS/Perch")
    try Data("fixture only".utf8).write(to: binary)
    func write(_ value: [String: Any]) throws { try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: plist, options: .atomic) }
    var verifications = 0, intact = true, mutate = false
    let reader = AppReplacementReader(path: path, running: running, identifier: "test.perch") { _ in
        verifications += 1
        if !intact { throw AppError(message: "incomplete installation") }
        if mutate { try Data("changed during scan".utf8).write(to: binary, options: .atomic); mutate = false }
    }
    try write(info("1.2.79", "79")); try check(reader.read() == nil && verifications == 0, "Verified unchanged app unnecessarily")
    try write(info("1.2.80", "80")); intact = false
    try check(reader.read() == nil, "Incomplete/untrusted bundle offered restart")
    intact = true
    try check(reader.read() == next && reader.read() == next && verifications == 2, "Valid replacement was not retried/cached")
    try write(info("1.2.81", "81")); mutate = true
    try check(reader.read() == nil, "Accepted app changed during signature verification")
    try check(reader.read()?.build == "81", "Stable replacement did not recover")
    try write(info("1.2.78", "78")); try check(reader.read() == nil, "Rollback still appeared newer")
    var wrong = info("1.2.99", "99"); wrong["CFBundleIdentifier"] = "other.app"
    try write(wrong); try check(reader.read() == nil, "Different app offered restart")
    try Data(repeating: 65, count: 70_000).write(to: plist, options: .atomic)
    try check(reader.read() == nil, "Oversized metadata accepted")
    try FileManager.default.removeItem(at: plist); try check(reader.read() == nil, "Missing app stayed ready")

    let host = SettingsWindow.shared; host.testing = true
    defer { if let alert = host.activeAlert { host.finish(alert, response: .alertSecondButtonReturn) } }
    let app = AppDelegate(); app.buildMenu()
    app.appReplacement.state = .init(running: running)
    app.refreshAppReplacement(showNotice: false)
    try check(app.replacementInfoItem!.isHidden && app.replacementRestartItem!.isHidden, "Unchanged app added menu clutter")
    app.appReplacement.state.available = next; app.menuOpen = true
    app.refreshAppReplacement(showNotice: false)
    try check(app.replacementRestartItem!.isHidden, "Background completion inserted a row in the open menu")
    app.menuOpen = false; app.refreshAppReplacement(showNotice: false)
    try check(!app.replacementRestartItem!.isHidden && app.validateMenuItem(app.replacementRestartItem!), "Cached newer app had no restart action")
    try check(app.replacementInfoItem!.title.contains("79") && app.replacementInfoItem!.menuHelp != nil, "Running version/help missing")
    app.considerAppReplacementNotice()
    try check(host.activeAlert?.informativeText.contains("1.2.79") == true && host.activeAlert?.informativeText.contains("1.2.80") == true, "First notice did not explain both versions")
    if let alert = host.activeAlert { host.finish(alert, response: .alertSecondButtonReturn) }
    app.considerAppReplacementNotice()
    try check(host.activeAlert == nil && app.appReplacement.state.notified, "Later did not dismiss this run's notice")
    print("PASS: installed-version ordering, partial/untrusted/replaced/missing bundles, verification caching, once-per-run/deferred notice and stable conditional menu; fixture files only, no restart")
}
