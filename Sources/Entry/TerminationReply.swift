import AppKit

/// Answers a deferred termination (`.terminateLater`) from the run loop.
///
/// Terminate is often requested from inside a main-queue block: a menu action
/// deferred until tracking ends, a reset or restart completion. The main
/// dispatch queue is serial and never re-enters that block, and AppKit waits
/// for the reply in a nested run loop inside it, so a reply queued on the main
/// queue never runs: Perch could neither quit nor respond to its menu.
/// Common-mode timers do fire in that nested loop.
enum TerminationReply {
    static func send(_ allowed: Bool, after delay: TimeInterval = 0, to sender: NSApplication) {
        schedule(after: delay) { sender.reply(toApplicationShouldTerminate: allowed) }
    }
    static func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) {
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { _ in body() }
        RunLoop.main.add(timer, forMode: .common)
    }
}
