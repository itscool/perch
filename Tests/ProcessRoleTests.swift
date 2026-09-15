import Foundation

/// The executable's role dispatch: exact argument shapes, precedence between
/// flags, and the shapes that must fall through to the menu app.
func runProcessRoleTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let exe = "/Applications/Perch.app/Contents/MacOS/Perch"
    func parse(_ arguments: [String], root: Bool = false) -> ProcessRole? { ProcessRole.parse([exe] + arguments, root: root) }
    try check(ProcessRole.parse([]) == nil && parse([]) == nil, "An empty or bare launch is not a role")
    try check(parse(["--check-modifier-access"]) == .checkModifierAccess, "modifier access check")
    try check(parse(["--restart-worker", "/tmp/Perch.app"]) == .restartWorker(path: "/tmp/Perch.app"), "restart worker takes exactly one path")
    try check(parse(["--restart-worker"]) == nil && parse(["--restart-worker", "a", "b"]) == nil, "restart worker with a wrong count fell through wrongly")
    try check(parse(["--lid-maintenance-begin", "501", "token"]) == .lidMaintenance(operation: "--lid-maintenance-begin", arguments: ["501", "token"]), "lid maintenance keeps its operation and operands")
    try check(parse(["--lid-maintenance-check"]) == .lidMaintenance(operation: "--lid-maintenance-check", arguments: []), "lid maintenance without operands")
    try check(parse(["x", "--lid-maintenance-check"]) == nil, "lid maintenance must be the first argument")
    try check(parse(["--check-lid-update"]) == .checkLidUpdate && parse(["--check-lid-update", "extra"]) == nil, "lid update check must be the only argument")
    try check(parse(["--update-catalog", "/tmp/catalog.json"]) == .updateCatalog(path: "/tmp/catalog.json") && parse(["--update-catalog"]) == nil, "catalog update needs its path")
    try check(parse(["--lid-override-worker", "/p", "t", "12.5"]) == .lidOverrideWorker(path: "/p", token: "t", deadline: 12.5), "override worker")
    try check(parse(["--lid-override-worker", "/p", "t", "soon"]) == nil && parse(["--lid-override-worker", "/p", "t"]) == nil, "override worker needs a numeric deadline and four operands")
    try check(parse(["--lid-recover"]) == .lidRecover, "lid recovery")
    try check(parse(["--lid-guard", "501"], root: true) == .lidGuard(owner: 501), "lid guard as root")
    try check(parse(["--lid-guard", "501"]) == nil && parse(["--lid-guard", "500"], root: true) == nil && parse(["--lid-guard", "501", "x"], root: true) == nil, "lid guard outside root, below uid 501 or with extra operands falls through to the menu app")
    try check(parse(["--lid-watchdog"]) == .lidWatchdog && parse(["--lid-watchdog", "x"]) == nil, "lid watchdog is exact")
    try check(parse(["--lid-cleanup"]) == .lidCleanup && parse(["--lid-cleanup", "x"]) == nil, "lid cleanup is exact")
    try check(parse(["--prepare-safety-config"]) == .prepareSafetyConfig, "safety config")
    try check(parse(["--install-watcher"]) == .installWatcher, "watcher install")
    try check(parse(["--safety-preview"]) == .safetyPreview, "safety preview")
    try check(parse(["--input-helper"]) == .inputHelper, "input helper")
    try check(parse(["--guardian"]) == .guardian, "guardian")
    try check(parse(["--panic-worker", "/tmp/plan.json"]) == .panicWorker(planPath: "/tmp/plan.json") && parse(["--panic-worker"]) == nil, "panic worker needs its plan")
    try check(parse(["--status-stream"]) == .statusStream, "status stream")
    try check(parse(["--ipc-self-test"]) == .ipcSelfTest, "ipc self-test")
    try check(parse(["--cpu-benchmark"]) == .cpuBenchmark, "cpu benchmark")
    try check(parse(["--settings-self-test"]) == .settingsSelfTest, "settings self-test")
    try check(parse(["--event-self-test"]) == .eventSelfTest, "event self-test")
    try check(parse(["--navigation-device-info"]) == .navigationDeviceInfo, "navigation device info")
    try check(parse(["--self-test"]) == .selfTest, "self-test")
    // Earlier matches win: contains-style flags beat later ones anywhere in the list.
    try check(parse(["--self-test", "--guardian"]) == .guardian && parse(["--guardian", "--check-modifier-access"]) == .checkModifierAccess, "role precedence follows declaration order")
    try check(parse(["--show-keyboard-setup"]) == nil && parse(["--complete-restart"]) == nil, "menu-app presentation flags are not roles")
    print("PASS: process role parsing for every helper, worker and test role; exact shapes, uid gating, precedence and menu-app fall-through")
}
