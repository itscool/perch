import Foundation
import CoreGraphics

/// Requests macOS to wake the user-facing display without moving the pointer
/// or pretending that the lock screen has been unlocked. `caffeinate -u` is the
/// supported user-activity path and works for both an idle display and the
/// login/lock screen; normal Perch access checks still decide whether input can
/// be shared afterwards.
enum DeskDisplayWake {
    private static var lastRequest = Date.distantPast
    private static var active: [Process] = []

    /// A monitor switch can land on a Mac whose own display has gone to sleep.
    /// Ask macOS first so the remote side is visible before input sharing starts.
    /// This is intentionally best-effort: a locked Mac may report awake while
    /// still requiring its normal unlock flow, and that must not block KVM.
    static func requestIfNeeded() {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let hasSleepingDisplay = CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success
            && displays.prefix(Int(count)).contains { CGDisplayIsAsleep($0) != 0 }
        guard hasSleepingDisplay else { return }
        request()
    }

    static func request() {
        let now = Date()
        guard now.timeIntervalSince(lastRequest) >= 0.25 else { return }
        lastRequest = now
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", "2"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            active.removeAll { $0 === finished }
        }
        do {
            try process.run()
            active.append(process)
        } catch {
            // Waking is best-effort. Monitor switching and KVM readiness must
            // continue to report their actual result if macOS rejects it.
        }
    }
}
