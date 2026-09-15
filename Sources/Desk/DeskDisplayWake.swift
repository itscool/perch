import Foundation
import CoreGraphics

/// Requests macOS to wake the user-facing display without moving the pointer
/// or pretending that the lock screen has been unlocked. `caffeinate -u` is the
/// supported user-activity path and works for both an idle display and the
/// login/lock screen; normal Perch access checks still decide whether input can
/// be shared afterwards.
enum DeskDisplayWake {
    private static var lastRequest = Date.distantPast

    /// A monitor switch can land on a Mac whose own display has gone to sleep.
    /// Ask macOS first so the remote side is visible before input sharing starts.
    /// This is intentionally best-effort: a locked Mac may report awake while
    /// still requiring its normal unlock flow, and that must not block KVM.
    static func requestIfNeeded() {
        guard DisplayIdentity.online().contains(where: \.isAsleep) else { return }
        request()
    }

    static func request() {
        let now = Date()
        guard now.timeIntervalSince(lastRequest) >= 0.25 else { return }
        lastRequest = now
        do {
            try Subprocess.spawn("/usr/bin/caffeinate", ["-u", "-t", "2"])
        } catch {
            // Waking is best-effort. Monitor switching and KVM readiness must
            // continue to report their actual result if macOS rejects it.
        }
    }
}
