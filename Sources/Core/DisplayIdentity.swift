import ColorSync
import CoreGraphics
import Foundation

/// One WindowServer display and the cheap facts CoreGraphics knows about it.
/// Enumerating never opens a monitor transport, reads an input or launches
/// the display adapter; every caller that used to copy the
/// `CGGetOnlineDisplayList` boilerplate reads through here instead.
struct DisplayIdentity: Hashable {
    let id: CGDirectDisplayID

    var isBuiltin: Bool { CGDisplayIsBuiltin(id) != 0 }
    var isActive: Bool { CGDisplayIsActive(id) != 0 }
    var isOnline: Bool { CGDisplayIsOnline(id) != 0 }
    var isAsleep: Bool { CGDisplayIsAsleep(id) != 0 }
    var isMirrored: Bool { CGDisplayIsInMirrorSet(id) != 0 }

    /// The WindowServer UUID for this display, stable across reconnects.
    var uuid: String? {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, value) as String
    }

    /// Every online display, or nil when WindowServer cannot be asked. The
    /// limit is far above anything a Mac drives; reaching it is treated as an
    /// unreadable topology rather than a truncated one.
    static func list(limit: Int = 64) -> [DisplayIdentity]? {
        var ids = [CGDirectDisplayID](repeating: 0, count: limit)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(limit), &ids, &count) == .success, Int(count) < limit else { return nil }
        return ids.prefix(Int(count)).map(DisplayIdentity.init)
    }

    /// Every online display; empty when WindowServer cannot be asked.
    static func online() -> [DisplayIdentity] { list() ?? [] }
}
