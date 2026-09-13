// Test-only SPUUserDriver. No windows, live helpers or production preferences.
import AppKit
import Sparkle

final class FixtureUpdaterController {
    let updater: SPUUpdater
    private let driver = FixtureUserDriver()
    init(startingUpdater: Bool, updaterDelegate: SPUUpdaterDelegate?, userDriverDelegate: SPUStandardUserDriverDelegate?) {
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: updaterDelegate)
    }
    func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }
}
final class FixtureUserDriver: NSObject, SPUUserDriver {
    private var cancelDownload: (() -> Void)?
    private var received: UInt64 = 0
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { log("check started") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("found " + appcastItem.versionString)
        if fixtureScenario == "dismiss" { reply(.dismiss); finishFixture("dismissed") }
        else { reply(.install) }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { log("notes error") }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        log("not found " + error.localizedDescription); acknowledgement(); finishFixture("not-found")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let value = error as NSError
        log("updater error \(value.domain):\(value.code) " + value.localizedDescription)
        acknowledgement(); finishFixture("error:\(value.domain):\(value.code)")
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { received = 0; cancelDownload = cancellation; log("download started") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        if fixtureScenario == "cancel", received > 0, let cancel = cancelDownload {
            cancelDownload = nil; log("cancel download after bytes \(received)"); cancel(); finishFixture("cancelled")
        }
    }
    func showDownloadDidStartExtractingUpdate() { cancelDownload = nil; log("extract started") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        log("ready to install"); reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { log("installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { log("dismiss installation") }
}
var fixtureScenario: String { (try? String(contentsOf: fixtureRoot.appendingPathComponent("scenario"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "success" }
func finishFixture(_ result: String) {
    try? Data(result.utf8).write(to: fixtureRoot.appendingPathComponent("result"))
    DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { NSApp.terminate(nil) }
}
