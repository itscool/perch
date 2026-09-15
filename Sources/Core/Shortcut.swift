import AppKit
import Carbon

/// A keyboard shortcut on this Mac: a Carbon virtual key plus modifiers.
/// Persisted and sent to the guardian as `{key, modifiers, enabled}` with the
/// Carbon modifier bits, so saved and helper-reported values stay readable.
struct Shortcut: Codable, Equatable, Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: UInt32
        init(rawValue: UInt32) { self.rawValue = rawValue }
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        /// ⌃⌥⌘: the default for every Perch shortcut.
        static let standard: Modifiers = [.control, .option, .command]
        /// Editor order, which is also the symbol order in titles.
        static let editable: [(modifier: Modifiers, name: String, short: String, symbol: String)] = [
            (.control, "Control", "Ctrl", "⌃"), (.option, "Option", "Opt", "⌥"), (.shift, "Shift", "Shift", "⇧"), (.command, "Command", "Cmd", "⌘")]
        init(_ flags: NSEvent.ModifierFlags) {
            self.init(rawValue: (flags.contains(.control) ? Self.control.rawValue : 0) | (flags.contains(.option) ? Self.option.rawValue : 0) |
                                (flags.contains(.shift) ? Self.shift.rawValue : 0) | (flags.contains(.command) ? Self.command.rawValue : 0))
        }
        init(_ flags: CGEventFlags) {
            self.init(rawValue: (flags.contains(.maskControl) ? Self.control.rawValue : 0) | (flags.contains(.maskAlternate) ? Self.option.rawValue : 0) |
                                (flags.contains(.maskShift) ? Self.shift.rawValue : 0) | (flags.contains(.maskCommand) ? Self.command.rawValue : 0))
        }
        /// The value RegisterEventHotKey expects.
        var carbonFlags: UInt32 { rawValue }
        var eventFlags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.control) { flags.insert(.control) }; if contains(.option) { flags.insert(.option) }
            if contains(.shift) { flags.insert(.shift) }; if contains(.command) { flags.insert(.command) }
            return flags
        }
        var count: Int { rawValue.nonzeroBitCount }
        var symbols: String { Self.editable.filter { contains($0.modifier) }.map(\.symbol).joined() }
    }

    var key: UInt32
    var modifiers: Modifiers
    var enabled: Bool
    init(key: UInt32 = UInt32(kVK_Escape), modifiers: Modifiers = .standard, enabled: Bool = true) {
        self.key = key; self.modifiers = modifiers; self.enabled = enabled
    }
    private enum CodingKeys: String, CodingKey { case key, modifiers, enabled }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(UInt32.self, forKey: .key)
        modifiers = Modifiers(rawValue: try container.decode(UInt32.self, forKey: .modifiers))
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(enabled, forKey: .enabled)
    }

    /// "⌃⌥⌘F5"; the key name comes from the shared key table.
    var title: String { modifiers.symbols + (ShortcutKey.name(key) ?? "?") }
    /// Two enabled shortcuts that would fire on the same keys.
    func matches(_ other: Shortcut) -> Bool { enabled && other.enabled && key == other.key && modifiers == other.modifiers }
    /// Whether an enabled shortcut fires for a CGEvent key code and flags.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        enabled && keyCode >= 0 && keyCode <= Int64(UInt32.max) && UInt32(keyCode) == key && Modifiers(flags) == modifiers
    }
    func matches(_ event: NSEvent) -> Bool {
        enabled && UInt32(event.keyCode) == key && Modifiers(event.modifierFlags) == modifiers
    }
}

/// The one table of key names Perch offers and stores. Features offer a
/// subset of it, never their own spelling of a key.
enum ShortcutKey {
    typealias Choice = (name: String, code: UInt32)
    static let escape: [Choice] = [("Esc", UInt32(kVK_Escape))]
    static let functionKeys: [Choice] = zip((1...20).map { "F\($0)" }, [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                                                          kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20])
        .map { ($0, UInt32($1)) }
    static let letters: [Choice] = zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init),
        [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M,
         kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z])
        .map { ($0, UInt32($1)) }
    static let digits: [Choice] = zip((0...9).map(String.init), [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9])
        .map { ($0, UInt32($1)) }
    /// The +/= and -/_ keys, named by the action they suggest.
    static let arithmetic: [Choice] = [("+", UInt32(kVK_ANSI_Equal)), ("−", UInt32(kVK_ANSI_Minus))]
    static let all: [Choice] = escape + functionKeys + letters + digits + arithmetic

    /// Offered subsets. Desk keys travel between Macs by name, so only keys
    /// with the same meaning on every keyboard are shared.
    static let emergency: [Choice] = named(["Esc", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "P", "S"])
    static let countdown: [Choice] = arithmetic + emergency
    static let desk: [Choice] = functionKeys

    static func named(_ names: [String]) -> [Choice] { names.compactMap { name in all.first { $0.name == name } } }
    static func code(named name: String) -> UInt32? { all.first { $0.name == name }?.code }
    static func name(_ code: UInt32) -> String? { all.first { $0.code == code }?.name }
}
