import AppKit
import Carbon

/// Local consent shortcut; desk routing itself remains shared in KVMGroup.
enum DeskSharingShortcut {
    static let storageKey = "desk.shareOnThisMac.shortcut"
    static let defaultValue = PanicShortcut(key: UInt32(kVK_ANSI_S), enabled: true)
    static func load() -> PanicShortcut {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(PanicShortcut.self, from: data) else { return defaultValue }
        return value
    }
    static func save(_ value: PanicShortcut) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: storageKey)
    }
}
