import AppKit
import Carbon

/// Regression journeys use mock monitor transport,
/// temporary preference domains, and canceled/injected forms. No live mutations.
func runReviewFixTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let host = SettingsWindow.shared
    host.testing = true; host.pages = []
    defer { host.modalTestDriver = nil; host.pages = []; host.window.defaultButtonCell = nil }
    let app = AppDelegate(); app.configureSettings(); app.hotkeySettings(); app.configureSettings()
    try check(host.pages.count == 1 && host.pages.last?.title == "Setup & status" && host.back.isHidden, "Reopening Settings created a second home or a redundant exit")
    let previousLevel = host.window.level
    let previousFloating = host.window.isFloatingPanel
    try DesktopTestSession.check()
    host.window.orderFront(nil) // Isolated panel only; never activate or open OS authorization.
    try check(host.window.isVisible, "Authorization fixture did not open")
    let restore = host.beginAuthorization()
    try check(host.authorizing && host.window.level == .normal && !host.window.isFloatingPanel && !host.window.isVisible, "Settings retained a visible floating panel during authorization")
    var notices = 0
    host.afterAuthorization { notices += 1 }
    host.display(host.pages.last!)
    try check(!host.window.isVisible && notices == 0, "A refresh or notice interrupted authorization")
    let nestedRestore = host.beginAuthorization()
    restore()
    restore() // Duplicate/out-of-order completion must not end another handoff.
    try check(host.authorizing && !host.window.isVisible, "Nested authorization restored Settings too early")
    nestedRestore()
    let noticeDeadline = Date().addingTimeInterval(1)
    while notices == 0 && Date() < noticeDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    try check(!host.authorizing && host.window.level == previousLevel && host.window.isFloatingPanel == previousFloating && host.window.isVisible && notices == 1 && host.pages.count == 1, "Authorization restoration: authorizing=\(host.authorizing), level=\(host.window.level.rawValue)/\(previousLevel.rawValue), floating=\(host.window.isFloatingPanel)/\(previousFloating), visible=\(host.window.isVisible), notices=\(notices), pages=\(host.pages.map(\.title))")
    let retry = host.beginAuthorization()
    try check(!host.window.isVisible, "Retry retained the Settings panel")
    retry()
    host.window.orderOut(nil)
    let menuOnly = host.beginAuthorization()
    menuOnly()
    try check(!host.window.isVisible, "Menu-only authorization unexpectedly opened Settings")
    let alert = NSAlert()
    alert.messageText = "Review all changes"
    alert.informativeText = (1...35).map { "Agent \($0): changed recognition rule" }.joined(separator: "\n") + "\nApprove every change?"
    alert.addButton(withTitle: "Apply Updates"); alert.addButton(withTitle: "Cancel")
    alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = "\u{1b}"
    var readable = false, keys = false, renderError: Error?
    host.modalTestDriver = { _ in
        readable = host.detailScroll.documentView === host.detail && host.detail.frame.height > host.detailScroll.contentSize.height && host.detail.stringValue.hasSuffix("Approve every change?") && host.detailScroll.contentView.bounds.minY == 0 && host.detailScroll.verticalScroller?.isHidden == false
        host.detailScroll.contentView.scroll(to: NSPoint(x: 0, y: host.detail.frame.height-host.detailScroll.contentSize.height))
        readable = readable && host.detail.visibleRect.maxY >= host.detail.bounds.maxY - 1 && !host.detailHint.isHidden
        host.detailScroll.contentView.scroll(to: .zero)
        let buttons = host.container.subviews.first!.subviews.compactMap { $0 as? NSButton }
        keys = buttons.contains { $0.title == "Apply Updates" && $0.keyEquivalent == "\r" } && !buttons.contains { $0.title == "Cancel" } && host.back.keyEquivalent == "\u{1b}" && host.cancelCode == .alertSecondButtonReturn
        do { try renderReleaseView(host.window.contentView!, path: "/private/tmp/perch-review-approval.png") }
        catch { renderError = error }
        return .alertSecondButtonReturn
    }
    _ = host.run(alert)
    if let renderError { throw renderError }
    try check(readable && keys, "Approval text clipped or Return/Escape lost")
    host.modalTestDriver = nil
    app.buildMenu(); app.refreshDeskSharingMenu()
    try check(app.shareInputItem.isEnabled, "Desk sharing row is not enabled after building the menu")
    app.keyboardModes.results = [.init(name: "Fixture", detail: "Needs setup", verified: false)]
    app.refreshExternalFunctionKeyItem()
    try check(app.externalFnItem.isEnabled && app.externalFnItem.action == #selector(AppDelegate.keyboardDetails), "Unavailable Fn mode did not route to its detailed recovery")
    try check(app.validateMenuItem(app.externalFnItem), "Menu validation blocks the keyboard setup route")
    let keyboard = NavigationKeyboardIdentity(vendor: 1234, product: 123, version: 1, name: "Saved keyboard", transport: "USB", usages: NavigationLearning.usages.sorted())
    var profiles = [NavigationKeyboardProfile(identity: keyboard, keys: [0x68,0x69,nil,nil])]
    let offline = NavigationProbePage(enumerate: { [] }, hasAccess: { false }, saveProfile: { _ in }, readProfiles: { profiles })
    offline.show()
    try check(offline.picker.titleOfSelectedItem?.contains("disconnected") == true && offline.picker.isEnabled, "Saved disconnected keyboard cannot be selected")
    host.modalTestDriver = { _ in .alertFirstButtonReturn }
    offline.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Reset saved layouts…" }!.performClick(nil)
    try check(host.pages.last?.title == "Reset Settings" && host.back.title == "Back to Keyboards" && profiles.count == 1, "Offline keyboard reset did not open Resets without changing saved layouts")
    profiles.removeAll() // Simulate the separate reset page completing its scoped write.
    host.goBack()
    try check(host.pages.last?.view === offline.view && offline.picker.titleOfSelectedItem == "No connected or saved external keyboard", "Returning from layout reset retained the erased keyboard or rebuilt its origin")
    print("PASS: helper build verification; stable Settings home; scrollable approvals; Return/Escape; nonmodal agent editor; setup action routes")
}
