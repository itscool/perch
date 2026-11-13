import Foundation

/// The system-wide process watcher the Agent Kill Switch installed, and how to
/// take it off a Mac.
///
/// To follow short-lived agent processes, the kill switch installed a root
/// launch daemon that ran Apple's eslogger, recording every process start,
/// fork and exit on the Mac. Removing the feature from Perch does not remove
/// that daemon: it is owned by root, outside the app, and would keep watching
/// every process for as long as the Mac runs. It is the likeliest cause of the
/// slowdown that led Scott to remove the feature on November 12, 2026.
///
/// Removing it needs an administrator, which only the person can provide, so
/// Setup shows that it is still installed with a single Remove… action.
enum RetiredProcessWatcher {
    static let label = "local.scott.perch.events"
    static let job = "/Library/LaunchDaemons/local.scott.perch.events.plist"
    static let directory = "/Library/Application Support/Perch Events"
    static func installed(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        exists(job) || exists(directory)
    }
    /// Stop the daemon, then delete its job and its folder (launcher, identity
    /// record and pipe). Each step is allowed to find its target already gone.
    static var removalCommand: String {
        "/bin/launchctl bootout system/\(label) 2>/dev/null; /bin/rm -f \(AdminShell.quote(job)); /bin/rm -rf \(AdminShell.quote(directory))"
    }
    static func remove() throws { _ = try AdminShell.runPrivileged(removalCommand) }
}

/// This boot of macOS, so a record written before a restart is never taken
/// for one written after it.
enum BootSession {
    static var id: UUID? {
        var bytes = [CChar](repeating: 0, count: 64), size = 64
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0, size <= bytes.count, bytes.last == 0 else { return nil }
        return UUID(uuidString: String(cString: bytes))
    }
}
