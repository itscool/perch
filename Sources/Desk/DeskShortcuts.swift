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

/// Local consent shortcut; desk routing itself remains shared in KVMGroup.
enum DeskSharingShortcut {
    static let storageKey = "desk.shareOnThisMac.shortcut"
    static let defaultValue = Shortcut(key: UInt32(kVK_ANSI_S))
    static func load() -> Shortcut { UserDefaults.standard.codable(Shortcut.self, forKey: storageKey) ?? defaultValue }
    static func save(_ value: Shortcut) throws { try UserDefaults.standard.setCodable(value, forKey: storageKey) }
}
