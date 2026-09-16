import Foundation

/// The desk's diagnostic record. The property that matters is that a polled
/// caller cannot flood it: the input session decides four times a second, so
/// a log which repeated every decision would hide the transitions that
/// explain why sharing did not start. Written after a two-VM run where no
/// evidence existed to tell "never started" from "started and collapsed".
func runDeskDiagnosticsTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let savedSink = PerchLog.sink, savedClock = PerchLog.clock
    defer { PerchLog.sink = savedSink; PerchLog.clock = savedClock; PerchLog.reset() }

    var seen: [PerchLog.Entry] = []
    var now = Date(timeIntervalSince1970: 1_000)
    PerchLog.reset()
    PerchLog.clock = { now }
    PerchLog.sink = { seen.append($0) }

    // A polled caller repeating the same verdict records once, and says so.
    try check(PerchLog.note("input.start", "no preset is active"), "The first note was not recorded")
    for _ in 0..<100 { _ = PerchLog.note("input.start", "no preset is active") }
    try check(seen.count == 1, "A repeated verdict flooded the log: \(seen.count) entries")

    // A changed verdict is recorded, and returning to the earlier one is too:
    // that pair is exactly how a flapping lease becomes visible.
    try check(PerchLog.note("input.start", "starting control"), "A changed verdict was not recorded")
    try check(PerchLog.note("input.start", "no preset is active"), "A verdict returning to its earlier value was dropped")
    try check(seen.count == 3, "Expected three transitions, saw \(seen.count)")

    // Categories are independent: access health does not silence start reasons.
    try check(PerchLog.note("input.access", "ready"), "A second category was suppressed by the first")
    try check(!PerchLog.note("input.access", "ready"), "A second category was not de-duplicated")

    // Events that matter every time are never de-duplicated.
    now = now.addingTimeInterval(1)
    PerchLog.record("input.focus", "control local")
    PerchLog.record("input.focus", "control local")
    try check(seen.filter { $0.category == "input.focus" }.count == 2, "A repeated event was collapsed")
    try check(seen.last?.at == now, "The entry did not use the injected clock")

    // The ring stays bounded, keeping the newest entries.
    PerchLog.sink = nil
    PerchLog.reset()
    for index in 0..<(PerchLog.limit + 50) { PerchLog.record("fill", "entry \(index)") }
    try check(PerchLog.entries.count == PerchLog.limit, "The log grew past its limit: \(PerchLog.entries.count)")
    try check(PerchLog.entries.last?.message == "entry \(PerchLog.limit + 49)", "The newest entry was dropped")
    try check(PerchLog.entries.first?.message == "entry 50", "The oldest entry was not the one dropped")
    try check(PerchLog.transcript().contains("fill entry 50"), "The transcript lost its category or message")

    // reset clears the de-duplication memory too, or a test would see nothing.
    PerchLog.reset()
    try check(PerchLog.entries.isEmpty && PerchLog.note("input.start", "no preset is active"), "reset left the de-duplication memory behind")
    print("PASS: desk diagnostics de-duplicate polled verdicts, keep repeated events, and stay bounded")
}
