import Foundation

/// Every Perch action that owns a keyboard shortcut on this Mac, so the
/// Hotkeys editors, the Desk registrar and the input tap agree on conflicts.
extension ShortcutRegistry {
    enum Source {
        static let emergency = "emergency"
        static let countdown = "countdown"
        static let deskSharing = "deskSharing"
        static let deskPresets = "deskPresets"
    }
    static let perch: ShortcutRegistry = {
        let registry = ShortcutRegistry()
        registry.provide(Source.emergency) { [ShortcutClaim(owner: "the Agent Kill Switch", shortcut: SafetyConfiguration.load().shortcut)] }
        registry.provide(Source.countdown) {
            let shortcuts = LidCountdownController.shared.shortcuts
            return [ShortcutClaim(owner: "the countdown's add five minutes", shortcut: shortcuts.increase),
                    ShortcutClaim(owner: "the countdown's subtract five minutes", shortcut: shortcuts.decrease)]
        }
        registry.provide(Source.deskSharing) { [ShortcutClaim(owner: "Share on this Mac", shortcut: DeskSharingShortcut.load())] }
        registry.provide(Source.deskPresets) {
            (DeskCoordinator.shared.runtime?.node.group.presets ?? []).compactMap { preset in
                preset.shortcut.local.map { ShortcutClaim(owner: "the Desk preset “\(preset.name)”", shortcut: $0) }
            }
        }
        return registry
    }()
}
