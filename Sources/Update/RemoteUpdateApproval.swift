import Foundation
import Sparkle

/// Permission for one update, given by a newer Mac on the same desk.
///
/// When a connected Mac runs a newer Perch, the person there can choose
/// "Update Perch on <this Mac>": the two are paired friends on one desk. That
/// choice is the approval this Mac would otherwise ask for, so the update
/// installs without waiting for someone to click Install here. The newer Mac
/// never sends the app: this Mac fetches the signed release from Perch's own
/// update feed exactly as it does when asked by hand, and Sparkle checks its
/// signature. An approval covers one update session and expires if that
/// session never starts.
struct RemoteUpdateApproval: Equatable {
    static let lifetime: TimeInterval = 600
    private(set) var by: String?
    private var until: TimeInterval = 0
    mutating func grant(by name: String, now: TimeInterval) { by = name; until = now + Self.lifetime }
    func active(now: TimeInterval) -> Bool { by != nil && now < until }
    mutating func clear() { by = nil; until = 0 }
}

/// Whether a request to update from another Mac on the desk is honoured.
enum RemoteUpdateRequest {
    static let minimumInterval: TimeInterval = 600
    /// Only a Mac that announced a newer build, asking about that same build,
    /// at most once every ten minutes.
    static func accept(requested: Int, announced: Int?, own: Int, lastAccepted: TimeInterval, now: TimeInterval) -> Bool {
        requested > own && announced == requested && now - lastAccepted >= minimumInterval
    }
}

/// Sparkle's own update window and progress, with one difference: during an
/// update another Mac approved, the two questions that would wait for a click
/// here, "Install this update?" and "Restart now?", are answered Install.
/// Everything else is passed to Sparkle's standard driver unchanged, so an
/// update someone starts on this Mac behaves exactly as before. Restarting
/// still goes through Perch's termination gate, which hands over a lid session
/// first, the same as a manual install.
final class PerchUserDriver: NSObject, SPUUserDriver {
    let standard: SPUUserDriver
    /// Read once when a session starts, so an approval cannot expire halfway
    /// through an update it began.
    private let approved: () -> Bool
    private(set) var sessionApproved = false
    var log: (String) -> Void = { PerchLog.record("update.remote", $0) }
    init(standard: SPUUserDriver, approved: @escaping () -> Bool) {
        self.standard = standard; self.approved = approved
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        sessionApproved = approved()
        // An approved update shows no checking window: nobody here asked to check.
        if !sessionApproved { standard.showUserInitiatedUpdateCheck(cancellation: cancellation) }
    }
    /// Whether an update just found installs without asking here. Once true,
    /// it stays true for the rest of that session.
    func installsFoundUpdate() -> Bool {
        if sessionApproved || approved() { sessionApproved = true }
        return sessionApproved
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installsFoundUpdate() {
            log("Installing Perch \(appcastItem.displayVersionString), approved from another Mac on the desk")
            reply(.install)
        } else { standard.showUpdateFound(with: appcastItem, state: state, reply: reply) }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { standard.showUpdateReleaseNotes(with: downloadData) }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if sessionApproved {
            log("Already running the newest published Perch; nothing to install")
            sessionApproved = false
            acknowledgement()
        } else { standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement) }
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        // An error is shown either way: someone here needs to know.
        if sessionApproved { log("The approved update could not finish: " + error.localizedDescription) }
        sessionApproved = false
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { standard.showDownloadInitiated(cancellation: cancellation) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) }
    func showDownloadDidReceiveData(ofLength length: UInt64) { standard.showDownloadDidReceiveData(ofLength: length) }
    func showDownloadDidStartExtractingUpdate() { standard.showDownloadDidStartExtractingUpdate() }
    func showExtractionReceivedProgress(_ progress: Double) { standard.showExtractionReceivedProgress(progress) }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if sessionApproved { reply(.install) } else { standard.showReady(toInstallAndRelaunch: reply) }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
    func showUpdateInFocus() { standard.showUpdateInFocus?() }
    func dismissUpdateInstallation() {
        sessionApproved = false
        standard.dismissUpdateInstallation()
    }
}
