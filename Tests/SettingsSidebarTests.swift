import AppKit

func runSettingsSidebarTests() throws {
    let host = SettingsWindow()
    host.testing = true
    func require(_ result: Bool, _ message: String) throws {
        if !result { throw AppError(message: "Sidebar: " + message) }
    }
    var opened = 0, left = 0
    func page(_ title: String, height: CGFloat = 100) -> SettingsWindow.Page {
        .init(title: title, detail: "Fixture", view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: height)))
    }
    let keyboard = SettingsDestination(id: "keyboard", title: "Keyboards", pageTitles: ["Keyboard"]) { opened += 1; host.show(page("Keyboard")) }
    let awake = SettingsDestination(id: "awake", title: "Keep awake", pageTitles: ["Awake"]) { opened += 1; host.show(page("Awake", height: 900)) }
    host.configureNavigation([keyboard, awake])
    host.navigate(to: keyboard)
    let size = host.window.frame.size
    try require(opened == 1 && host.pages.count == 1 && host.sidebar.table.selectedRow == 0, "direct entry")
    try require(host.back.isHidden && !host.window.settingsKeyViews().contains { $0 === host.back }, "sidebar destination has no redundant Back/Close control or hidden Tab stop")
    host.navigate(to: keyboard)
    try require(opened == 1, "same destination must not rebuild")
    var child = page("Child")
    child.leave = { left += 1 }
    host.show(child)
    try require(host.sidebar.table.selectedRow == 0, "child retains its feature")
    try require(!host.back.isHidden, "temporary child keeps its scoped exit")
    host.navigate(to: awake)
    try require(opened == 2 && left == 1 && host.pages.count == 1, "switch cleans up child once without growing stack")
    try require(host.window.frame.size == size, "short and long pages keep window size")
    try require(host.window.firstResponder === host.sidebar.table, "arrow navigation retains actual list focus")
    try require(host.window.settingsKeyViews().contains(where: { $0 === host.sidebar.table }), "sidebar participates in local Tab navigation")
    var valid = false
    var draft = page("Draft")
    draft.beforeBack = { valid }; draft.backTitle = "Cancel"
    host.show(draft)
    host.navigate(to: keyboard)
    try require(host.pages.last?.title == "Draft" && opened == 2, "invalid draft refuses destination change")
    valid = true
    host.modalTestDriver = { _ in .alertFirstButtonReturn }
    host.navigate(to: keyboard)
    try require(host.pages.last?.title == "Draft" && opened == 2 && !host.modal, "cancel preserves draft")
    try require(host.window.firstResponder === host.sidebar.table, "cancelling sidebar navigation restores category keyboard focus")
    host.modalTestDriver = { _ in .alertSecondButtonReturn }
    host.navigate(to: keyboard)
    try require(host.pages.count == 1 && host.pages.last?.title == "Keyboard" && opened == 3, "confirmed discard opens chosen destination")
    host.modalTestDriver = nil
    let alert = NSAlert(); alert.messageText = "Operation"; alert.addButton(withTitle: "Cancel")
    host.present(alert)
    try require(!host.back.isHidden, "operation cancellation remains visible")
    host.navigate(to: awake)
    try require(host.modal && opened == 3 && !host.sidebar.table.isEnabled, "active operation excludes navigation without queueing it")
    host.finish(alert, response: .alertFirstButtonReturn)
    try require(host.sidebar.table.isEnabled && opened == 3, "finishing operation restores sidebar without surprise navigation")
    try require(host.back.isHidden && host.window.firstResponder !== host.back, "returning to sidebar page hides redundant exit and preserves valid focus")
    host.show(page("Child"))
    host.navigate(to: keyboard)
    try require(host.pages.count == 1 && host.pages.last?.title == "Keyboard", "same category returns from its child")
    host.pages = []
    let overview = SettingsDestination(id: "overview", title: "Setup & status", pageTitles: ["Setup & status"]) { host.show(page("Setup & status")) }
    host.configureNavigation([overview, keyboard, awake])
    host.navigate(to: overview)
    host.show(page("Keyboard"))
    try require(!host.back.isHidden && host.back.title == "Back to setup", "Setup repair lost its clear return route")
    host.goBack()
    try require(host.pages.count == 1 && host.pages.last?.title == "Setup & status" && host.back.isHidden, "Setup return did not restore the checklist")
    host.navigate(to: keyboard)
    try require(host.back.isHidden, "Ordinary category navigation acquired a wizard Back")
    host.pages = []; host.show(page("Recovery"))
    try require(host.back.title == "Back to setup", "Standalone settings recovery offered Close")
    host.goBack()
    try require(host.pages.last?.title == "Setup & status", "Recovery Back closed Settings instead of opening setup")
    host.window.close()
    print("PASS: sidebar direct/child navigation, stable geometry, keyboard focus, draft refusal/cancel/discard, operation ownership and cleanup")
}
