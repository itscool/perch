import Foundation

/// Held-key repeat filtering, independent of Carbon and therefore testable.
struct HotKeyLatch {
    private var down = Set<UInt32>()
    /// True for the first press; false while the key is still held.
    mutating func press(_ key: UInt32) -> Bool { down.insert(key).inserted }
    mutating func release(_ key: UInt32) { down.remove(key) }
    mutating func clear() { down.removeAll() }
}
