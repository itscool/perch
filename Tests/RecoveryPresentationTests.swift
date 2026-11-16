import AppKit
import SwiftUI

func runRecoveryPresentationTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    // Lid protection reports the helper, not the keep-awake session: a running
    // or stopped session is the Keep awake feature's business, shown in the menu.
    var snapshot = SetupSnapshot(config: SafetyConfiguration())
    snapshot.config.keepAwake = true; snapshot.lidWanted = true; snapshot.lidHelperInstalled = true
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: true, detail: "Closed on external power.")
    try check(snapshot.lid.state == .ready, "An installed, working lid helper was not ready")
    snapshot.lidGuard?.error = "Live override readback failed"
    try check(snapshot.lid.state == .attention && snapshot.lid.detail == "Live override readback failed", "Current helper failure was hidden")
    snapshot.lidGuard?.updatedAt -= 20
    try check(snapshot.lid.detail != "Live override readback failed", "Stale helper report treated as current")
    snapshot.lidGuard = .init(updatedAt: LidGuardClock.now, armed: false, detail: "Stopped")
    try check(snapshot.lid.state == .ready, "A stopped keep-awake session was reported as broken setup")
    snapshot.lidHelperUpdatePending = true
    try check(snapshot.lid.state == .attention && snapshot.lid.route == .lidSetup, "Pending helper update lost its repair route")
    // Shared input access reports the permissions, not the session.
    snapshot.deskInputEnabled = true
    try check(snapshot.sharing.state == .attention, "Sharing turned on without access did not ask for it")
    snapshot.sharingAccessGranted = true
    try check(snapshot.sharing.state == .ready, "Granted sharing access was not ready")
    snapshot.deskInputEnabled = false; snapshot.sharingAccessGranted = false
    try check(snapshot.sharing.state == .optional, "Disabled sharing requires repair")
    try check(NSApp.windows.isEmpty, "Offscreen presentation test opened a window")
    print("PASS: Lid protection reports the helper (working, failed, stale, update pending) and not the session; Shared input access reports its permissions; no windows opened")
}
