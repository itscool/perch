import AppKit

/// A deferred quit must be answerable from inside a main-queue block, which is
/// where AppKit's terminate loop runs. No termination is requested.
func runTerminationReplyTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    _ = NSApplication.shared
    var ran = false, replied = false, queued = false, queuedInside = true, finished = false
    DispatchQueue.main.async {
        ran = true
        TerminationReply.schedule(after: 0.05) { replied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { queued = true }
        let deadline = Date().addingTimeInterval(2)
        while !replied, Date() < deadline { _ = RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.02)) }
        queuedInside = queued
        finished = true
    }
    let deadline = Date().addingTimeInterval(4)
    while !finished, Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    try check(ran && finished, "The main-queue fixture block never ran")
    try check(replied, "A termination reply did not fire inside a main-queue block's modal loop")
    try check(!queuedInside, "The main queue re-entered a running block; the fixture no longer models the terminate deadlock")
    print("PASS: deferred quit reply fires inside a main-queue block's modal loop, where a main-queue reply cannot")
}
