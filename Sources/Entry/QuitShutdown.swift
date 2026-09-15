import Foundation

/// Runs a confirmed Quit's turn-off steps and calls `completion` exactly once:
/// as soon as the lid session has ended, or after `timeout` when the lid
/// helper never answers, so a missing helper can never hold Quit open.
enum QuitShutdown {
    static func perform(timeout: TimeInterval, endLidSession: (@escaping () -> Void) -> Void,
                        stopHelpers: @escaping () -> Void, completion: @escaping () -> Void) {
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            stopHelpers()
            completion()
        }
        TerminationReply.schedule(after: timeout, finish)
        endLidSession { TerminationReply.schedule(after: 0, finish) }
    }
}
