import AppKit
import SwiftUI

func runRecoveryPresentationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    var snapshot = SetupSnapshot(config: SafetyConfiguration())
    snapshot.config.keepAwake = true; snapshot.lidWanted = true; snapshot.lidHelperInstalled = true
    func awake() -> SetupCheck { snapshot.checks.first { $0.id == "awake" }! }
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: true, detail: "Closed on external power.")
    try check(awake().state == .ready && awake().detail.contains("cannot guarantee"), "Active lid session falsely requires repair or promises future wakefulness")
    snapshot.lidGuard?.error = "Live override readback failed"
    try check(awake().state == .attention, "Current helper failure was hidden")
    snapshot.lidGuard?.updatedAt -= 20
    try check(awake().state != .ready && awake().detail != "Live override readback failed", "Stale helper report treated as current")
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: false, detail: "Stopped")
    try check(awake().state != .ready, "Stopped session called ready")
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: true, detail: "Active")
    snapshot.lidHelperUpdatePending = true
    try check(awake().state == .attention && awake().route == .lidSetup, "Pending helper update lost its repair route")
    snapshot.deskInputEnabled = true
    var sharing = snapshot.checks.first { $0.id == "desk-input" }!
    try check(sharing.state == .ready && sharing.detail.contains("select a confirmed screen"), "Idle sharing misreported as broken or actively forwarding")
    snapshot.deskInputProblem = "Named computer offline"
    sharing = snapshot.checks.first { $0.id == "desk-input" }!
    try check(sharing.state == .attention && sharing.detail == "Named computer offline", "Current sharing failure hidden")
    snapshot.deskInputProblem = nil; snapshot.deskInputActive = true
    sharing = snapshot.checks.first { $0.id == "desk-input" }!
    try check(sharing.state == .ready && sharing.detail.contains("active for this session"), "Recovered sharing still reports the old issue")
    snapshot.deskInputEnabled = false
    try check(snapshot.checks.first { $0.id == "desk-input" }!.state == .optional, "Disabled sharing requires repair")
    let picture = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
        DeskDeviceSwitchExample(kind: .keyboard)
        DeskDeviceSwitchExample(kind: .mouse)
    }.padding(16).background(Color.white).environment(\.colorScheme, .light))
    picture.frame = NSRect(x: 0, y: 0, width: 600, height: 220)
    picture.layoutSubtreeIfNeeded()
    if CommandLine.arguments.count > 2, let bitmap = picture.bitmapImageRepForCachingDisplay(in: picture.bounds) {
        picture.cacheDisplay(in: picture.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
    try check(NSApp.windows.isEmpty, "Offscreen presentation test opened a window")
    print("PASS: active/failed/stale/stopped/update-pending lid and idle/failed/recovered/off sharing statuses; illustrated device examples rendered without windows")
}
