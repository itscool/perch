import Foundation
import os

/// Perch's record of decisions that are otherwise invisible: why keyboard and
/// mouse sharing did or did not start, and when control changed hands.
///
/// Only Perch's own state is recorded, never a keystroke, a pointer position
/// or anything typed. Entries go to the unified log, so they can be read from
/// outside the process with:
///
///     log show --predicate 'subsystem == "local.scott.perch"' --last 10m
///
/// `note` records only when a category's message changes. Its callers are
/// polled loops: the input session re-decides four times a second, and a log
/// that repeated that would bury the one transition worth seeing. `record`
/// is for events that matter every time they happen.
enum PerchLog {
    struct Entry: Equatable {
        let at: Date
        let category: String
        let message: String
    }
    /// Bounded: a desk left running for days must not grow this without limit.
    static let limit = 400
    private(set) static var entries: [Entry] = []
    /// The recent decisions, oldest first, for sharing with the other Macs on a
    /// desk. Perch's own state only: never a keystroke, pointer or anything typed.
    static func recent(seconds: Double, limit: Int = 200) -> [Entry] {
        let start = clock().addingTimeInterval(-max(1, seconds))
        return entries.filter { $0.at >= start }.suffix(limit)
    }
    private static var last: [String: String] = [:]
    /// Tests replace these; production keeps the clock and the unified log.
    static var clock: () -> Date = { Date() }
    static var sink: ((Entry) -> Void)?
    private static let logger = Logger(subsystem: "local.scott.perch", category: "desk")

    /// Record `message` for `category` only when it differs from the last one.
    /// Returns whether it was recorded, which is what makes a polled caller safe.
    @discardableResult
    static func note(_ category: String, _ message: String) -> Bool {
        guard last[category] != message else { return false }
        last[category] = message
        record(category, message)
        return true
    }

    /// Record an event that is meaningful on every occurrence. A repeated
    /// message here is a fact (control changed hands twice), not noise.
    static func record(_ category: String, _ message: String) {
        let entry = Entry(at: clock(), category: category, message: message)
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        if let sink { sink(entry); return }
        logger.log("\(category, privacy: .public): \(message, privacy: .public)")
    }

    /// The recent record as plain text, newest last, for a report or a test.
    static func transcript() -> String {
        let format = ISO8601DateFormatter()
        return entries.map { "\(format.string(from: $0.at)) \($0.category) \($0.message)" }.joined(separator: "\n")
    }

    static func reset() { entries = []; last = [:] }
}
