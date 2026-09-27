import Foundation
import Carbon

/// Desk preset shortcuts travel between Macs by key name (KVMShortcut). On
/// each Mac they resolve to a local Shortcut for registration and matching.
extension KVMShortcut {
    var modifiers: Shortcut.Modifiers {
        get {
            var value: Shortcut.Modifiers = []
            if control { value.insert(.control) }; if option { value.insert(.option) }
            if command { value.insert(.command) }; if shift { value.insert(.shift) }
            return value
        }
        set {
            control = newValue.contains(.control); option = newValue.contains(.option)
            command = newValue.contains(.command); shift = newValue.contains(.shift)
        }
    }
    /// This Mac's registration, or nil for a key the Desk does not offer:
    /// a peer's unknown name never gains a guessed key code.
    var local: Shortcut? { ShortcutKey.desk.first { $0.name == key }.map { Shortcut(key: $0.code, modifiers: modifiers) } }
    func matches(_ shortcut: Shortcut) -> Bool { local?.matches(shortcut) == true }
}

/// Bring over the newest copy from another Mac: ⌃⌥⌘V.
///
/// Default (e), pending Scott's confirmation: it belongs with Perch's other
/// shortcuts, is claimed in `ShortcutRegistry` so every other Perch shortcut
/// editor refuses the same keys, and yields to one already there. It is fixed
/// for now: changing it would need an editor on the Hotkeys page, which is
/// Scott's to decide (TODO.md).
///
/// It is not a system hot key. The input tap recognises it, because it must act
/// for the Mac typing goes to rather than the Mac whose keyboard was pressed
/// (default (a)), and the tap is the one place that knows both. Without the
/// tap (sharing off on this Mac) there is nothing to bring over.
enum DeskBringOverShortcut {
    static let shortcut = Shortcut(key: UInt32(kVK_ANSI_V))
    static let owner = "Bring over the other Mac's copy"
    /// The shortcut while no other Perch shortcut holds the same keys, else nil:
    /// the one already there keeps working and this one steps aside.
    static func active(in registry: ShortcutRegistry) -> Shortcut? {
        registry.conflicts(with: shortcut, excluding: ShortcutRegistry.Source.deskClipboard).isEmpty ? shortcut : nil
    }
    /// What it claims among Perch's shortcuts: its keys while it holds them,
    /// nothing while it has stepped aside, so a shortcut that was there first is
    /// never reported as conflicting with it.
    static func claims(in registry: ShortcutRegistry) -> [ShortcutClaim] {
        active(in: registry).map { [ShortcutClaim(owner: owner, shortcut: $0)] } ?? []
    }
}

/// Local consent shortcut; desk routing itself remains shared in KVMGroup.
enum DeskSharingShortcut {
    static let storageKey = "desk.shareOnThisMac.shortcut"
    static let defaultValue = Shortcut(key: UInt32(kVK_ANSI_S))
    static func load() -> Shortcut { UserDefaults.standard.codable(Shortcut.self, forKey: storageKey) ?? defaultValue }
    static func save(_ value: Shortcut) throws { try UserDefaults.standard.setCodable(value, forKey: storageKey) }
}
