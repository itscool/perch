import AppKit

func runAboutDialogTests() throws {
    let host = SettingsWindow.shared
    let titles = host.pages.map(\.title), modal = host.modal, busy = host.interactionBusy
    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
    try DesktopTestSession.check()
    AppDelegate().about()
    let panels = NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) && $0.isVisible }
    defer { panels.forEach { $0.orderOut(nil) } }
    guard !panels.isEmpty, NSApp.modalWindow == nil,
          host.pages.map(\.title) == titles, host.modal == modal, host.interactionBusy == busy,
          panels.allSatisfy({ $0 !== host.window }) else { throw AppError(message: "About took over Settings instead of opening independently") }
    print("PASS: standalone About window leaves Settings page and interaction state unchanged")
}
