import Foundation

/// macOS records a permission against the publisher that asked for it. When
/// Perch is re-signed by a different publisher, the entry an earlier copy
/// created stays in Privacy & Security looking granted while this copy has no
/// access. These values decide when those dead entries should be removed, so
/// nobody has to find and delete the lookalike entry by hand.

/// A permission Perch can clear for itself, named as macOS names it.
enum PermissionService: String, Codable, CaseIterable, Equatable {
    /// The `tccutil` service names.
    case accessibility = "Accessibility"
    case inputMonitoring = "ListenEvent"

    /// What the person sees in System Settings.
    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }
    var pane: SystemSettingsPane {
        switch self {
        case .accessibility: return .accessibility
        case .inputMonitoring: return .inputMonitoring
        }
    }
    /// "Accessibility and Input Monitoring", for one short sentence.
    static func list(_ services: [PermissionService]) -> String {
        let names = services.map(\.title)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

/// What Perch ran under last, and which publisher it has already cleaned up for.
struct PublisherRecord: Codable, Equatable {
    var publisher: String
    var seen: Date
    /// The publisher whose stale entries were already removed, so a normal
    /// launch never clears again.
    var cleared: String?
    var clearedServices: [PermissionService] = []
}

enum PublisherChange {
    static let key = "permissions.publisher.v1"

    enum Decision: Equatable {
        /// Remember this publisher; touch no permission.
        case record
        /// Remove these permissions' stale entries, then remember the publisher.
        case clear([PermissionService])
    }

    /// `failing` is what this copy cannot use right now. Clearing happens only
    /// when the publisher is new to Perch and something actually fails, and only
    /// once per publisher: an ordinary not-yet-granted permission is left alone.
    static func decide(current: String, stored: PublisherRecord?, failing: [PermissionService]) -> Decision {
        if failing.isEmpty { return .record }
        if stored?.cleared == current { return .record }
        guard let stored, stored.publisher == current else { return .clear(failing) }
        return .record
    }

    /// The permissions Perch removed for this publisher that are still missing.
    /// Empty once they are granted, so the explanation disappears by itself.
    static func restoreNeeded(current: String?, stored: PublisherRecord?, failing: [PermissionService]) -> [PermissionService] {
        guard let current, let stored, stored.cleared == current else { return [] }
        return failing.filter { stored.clearedServices.contains($0) }
    }
}
