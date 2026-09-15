import AppKit

extension SettingsWindow {
    /// Opens a System Settings pane while Settings steps aside for it.
    func openSystemSettings(_ pane: SystemSettingsPane) {
        handoffToExternalApp { NSWorkspace.shared.open(pane.url) }
    }
}
