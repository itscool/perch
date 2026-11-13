import Foundation
import Sparkle

/// Records what reaches Sparkle's standard driver, so a test can tell an update
/// that waits for a click here from one another Mac approved.
private final class RecordingUserDriver: NSObject, SPUUserDriver {
    var calls: [String] = []
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { calls.append("permission") }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { calls.append("checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { calls.append("found") }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { calls.append("notes") }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) { calls.append("notes-failed") }
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) { calls.append("not-found") }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) { calls.append("error") }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { calls.append("download") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { calls.append("length") }
    func showDownloadDidReceiveData(ofLength length: UInt64) { calls.append("data") }
    func showDownloadDidStartExtractingUpdate() { calls.append("extracting") }
    func showExtractionReceivedProgress(_ progress: Double) { calls.append("extraction") }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { calls.append("ready") }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { calls.append("installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { calls.append("installed") }
    func showUpdateInFocus() { calls.append("focus") }
    func dismissUpdateInstallation() { calls.append("dismiss") }
}

/// Updating a Mac from a newer one on the same desk: who may ask, and what the
/// approval changes. Without one, every update behaves exactly as before.
func runRemoteUpdateTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }

    // Only a Mac that announced a newer build may ask, about that build, once
    // every ten minutes.
    try check(RemoteUpdateRequest.accept(requested: 300, announced: 300, own: 297, lastAccepted: -.infinity, now: 1_000), "A newer Mac's request was refused")
    try check(!RemoteUpdateRequest.accept(requested: 297, announced: 297, own: 297, lastAccepted: -.infinity, now: 1_000), "A Mac on the same version could ask this one to update")
    try check(!RemoteUpdateRequest.accept(requested: 296, announced: 296, own: 297, lastAccepted: -.infinity, now: 1_000), "An older Mac could ask this one to update")
    try check(!RemoteUpdateRequest.accept(requested: 300, announced: 299, own: 297, lastAccepted: -.infinity, now: 1_000), "A request for a build the Mac never announced was honoured")
    try check(!RemoteUpdateRequest.accept(requested: 300, announced: nil, own: 297, lastAccepted: -.infinity, now: 1_000), "A Mac that never said what it runs could ask")
    try check(!RemoteUpdateRequest.accept(requested: 300, announced: 300, own: 297, lastAccepted: 700, now: 1_000), "Two requests were honoured within ten minutes")

    // An approval covers one session and expires unused.
    var approval = RemoteUpdateApproval()
    try check(!approval.active(now: 0), "An update was approved before anyone approved it")
    approval.grant(by: "Studio", now: 100)
    try check(approval.active(now: 100 + RemoteUpdateApproval.lifetime - 1) && approval.by == "Studio", "A fresh approval was not active")
    try check(!approval.active(now: 100 + RemoteUpdateApproval.lifetime), "An unused approval never expired")
    approval.clear()
    try check(!approval.active(now: 101), "Clearing left the approval active")

    // Without an approval, every question reaches Sparkle's own window here.
    let standard = RecordingUserDriver()
    var approved = false
    let driver = PerchUserDriver(standard: standard) { approved }
    driver.log = { _ in }
    var choice: SPUUserUpdateChoice?
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    try check(!driver.installsFoundUpdate(), "An update installed without anyone approving it")
    driver.showReady { choice = $0 }
    try check(standard.calls == ["checking", "ready"] && choice == nil, "An unapproved update did not wait for a click here: \(standard.calls)")
    driver.dismissUpdateInstallation()

    // Approved from another Mac: no checking window, and both questions are
    // answered Install. The approval is read when the session starts, so it
    // cannot lapse halfway through.
    standard.calls = []
    approved = true
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    approved = false
    try check(driver.installsFoundUpdate(), "An approved update waited for a click here")
    driver.showReady { choice = $0 }
    try check(choice == .install && !standard.calls.contains("checking") && !standard.calls.contains("ready"),
              "An approved update showed the checking window or waited to restart: \(standard.calls)")
    // Progress still reaches the standard driver.
    driver.showDownloadInitiated(cancellation: {})
    try check(standard.calls.contains("download"), "Download progress was hidden")
    driver.dismissUpdateInstallation()

    // Nothing newer published: the approved session ends quietly.
    approved = true
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    var acknowledged = false
    driver.showUpdateNotFoundWithError(AppError(message: "fixture"), acknowledgement: { acknowledged = true })
    try check(acknowledged && !standard.calls.contains("not-found"), "An approved check with nothing to install showed a window here")
    // An error always reaches the person here, and ends the approval.
    approved = true
    driver.showUserInitiatedUpdateCheck(cancellation: {})
    approved = false
    driver.showUpdaterError(AppError(message: "fixture"), acknowledgement: {})
    try check(standard.calls.contains("error") && !driver.installsFoundUpdate(), "An update error was hidden or left the session approved")

    print("PASS: a newer Mac on the desk may ask once every ten minutes, only about the build it announced; its approval installs without a click here and expires unused; without one, every update waits for a click as before; errors always reach the person here")
}
