import Foundation

/// Perch's user-level helpers run only while Perch is in use. A confirmed
/// manual Quit stops them and keeps launchd from starting them at the next
/// login; the next launch allows them again. Restart for an update and the
/// preferences reset never come through here.
enum HelperLifecycle {
    static let inputLabel = "local.scott.perch.input"
    typealias Run = ([String]) -> LaunchdJob.Outcome
    /// Present while Perch is closed by a manual Quit. A guardian that stays to
    /// enforce a block releases Keep awake while this exists.
    static var closedMarker: URL { SafetyFiles.base.appendingPathComponent("perch-closed") }

    static func stopForQuit(keepGuardian: Bool, uid: uid_t = getuid(), marker: URL = HelperLifecycle.closedMarker,
                            run: Run = { LaunchdJob.run($0) }) {
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        for label in (keepGuardian ? [] : [GuardianInstall.label]) + [inputLabel] {
            let target = LaunchdJob.user(label, uid: uid).target
            // Disable first so KeepAlive cannot restart the job between the two.
            _ = run(["disable", target])
            _ = run(["bootout", target])
        }
    }

    /// Launch-time helper start, in the only safe order: allow the jobs a manual
    /// Quit told launchd to skip, then load the installed copy when it is this
    /// build, and copy a fresh one only when it is not.
    static func startForLaunch(allow: () -> Void = { HelperLifecycle.allowAtLaunch() },
                               loaded: () -> Bool = { GuardianInstall.messagingInstalled },
                               startIfCurrent: () throws -> Bool = { try GuardianInstall.startIfCurrent() },
                               install: () throws -> Void = { try GuardianInstall.install() }) throws {
        allow()
        guard !loaded() else { return }
        if try !startIfCurrent() { try install() }
    }

    static func allowAtLaunch(uid: uid_t = getuid(), marker: URL = HelperLifecycle.closedMarker,
                              run: Run = { LaunchdJob.run($0) }) {
        try? FileManager.default.removeItem(at: marker)
        for label in [GuardianInstall.label, inputLabel] { _ = run(["enable", LaunchdJob.user(label, uid: uid).target]) }
    }
}
