import Foundation
import CoreGraphics

/// A shortcut some feature holds on this Mac, named for people.
struct ShortcutClaim: Equatable {
    var owner: String
    var shortcut: Shortcut
}

/// The one place that answers "is this shortcut already taken by another
/// Perch action?". Each feature provides its current claims under a source
/// key; editors and registrars ask for conflicts excluding their own source.
final class ShortcutRegistry {
    private var providers: [String: () -> [ShortcutClaim]] = [:]
    init() {}
    func provide(_ source: String, _ claims: @escaping () -> [ShortcutClaim]) { providers[source] = claims }
    func claims(excluding source: String? = nil) -> [ShortcutClaim] {
        providers.filter { $0.key != source }.sorted { $0.key < $1.key }.flatMap { $0.value() }
    }
    /// Enabled claims from other sources that would fire on the same keys.
    func conflicts(with shortcut: Shortcut, excluding source: String) -> [ShortcutClaim] {
        claims(excluding: source).filter { $0.shortcut.matches(shortcut) }
    }
    /// A sentence naming the first conflict, or nil when the keys are free.
    func problem(with shortcut: Shortcut, excluding source: String) -> String? {
        conflicts(with: shortcut, excluding: source).first.map { "\(shortcut.title) is already used by \($0.owner). Choose another combination." }
    }
    /// Whether a key event belongs to a shortcut some other source owns.
    func owns(keyCode: Int64, flags: CGEventFlags, excluding source: String? = nil) -> Bool {
        claims(excluding: source).contains { $0.shortcut.matches(keyCode: keyCode, flags: flags) }
    }
}
