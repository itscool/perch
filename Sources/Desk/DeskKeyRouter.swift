import CoreGraphics
import Foundation

/// What the input tap does with one key event.
enum DeskKeyDisposition: Equatable {
    /// Control-Option-Escape: return control to this Mac.
    case emergencyStop
    /// A Desk preset shortcut: switch, and keep the keys to itself.
    case activatePreset(UUID)
    /// The rest of a preset shortcut (repeats, release): neither local nor sent.
    case consumed
    /// One of Perch's own shortcuts on this Mac: never sent to a peer.
    case local
    /// Ordinary input: sent to the focused Mac while sharing.
    case forward
}

/// Pure key rules for the Desk input tap, so they are tested without a tap.
/// A shortcut's release follows its press: a local press never leaves an
/// orphan release on a peer, and a fresh ordinary press clears stale state.
struct DeskKeyRouter {
    private(set) var consumedKeys: Set<Int64> = []
    private(set) var localKeys: Set<Int64> = []
    mutating func route(type: CGEventType, keyCode: Int64, flags: CGEventFlags, autorepeat: Bool, sharing: Bool,
                        presets: [KVMPreset], localShortcut: ((Int64, CGEventFlags) -> Bool)?) -> DeskKeyDisposition {
        switch type {
        case .keyDown:
            if keyCode == 53, flags.contains([.maskControl, .maskAlternate]) { return .emergencyStop }
            if sharing, let preset = presets.first(where: { $0.shortcut.local?.matches(keyCode: keyCode, flags: flags) == true }) {
                consumedKeys.insert(keyCode); localKeys.remove(keyCode)
                return autorepeat ? .consumed : .activatePreset(preset.id)
            }
            if localShortcut?(keyCode, flags) == true { localKeys.insert(keyCode); consumedKeys.remove(keyCode); return .local }
            consumedKeys.remove(keyCode); localKeys.remove(keyCode)
            return .forward
        case .keyUp:
            if consumedKeys.remove(keyCode) != nil { return .consumed }
            if localKeys.remove(keyCode) != nil { return .local }
            return .forward
        default:
            return .forward
        }
    }
}
