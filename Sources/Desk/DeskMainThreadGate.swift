import Foundation

/// Asks the main thread a question from a worker without waiting forever.
/// `DispatchQueue.main.sync` blocks until the main queue is free; while the
/// main thread sits in a modal loop inside another main-queue block, that is
/// never, and a monitor switch would stall until its 45-second timeout.
enum DeskMainThreadGate {
    /// The main thread's answer, or nil when it did not answer within `timeout`.
    static func ask<T>(timeout: TimeInterval, _ question: @escaping () -> T) -> T? {
        if Thread.isMainThread { return question() }
        let lock = NSLock(), answered = DispatchSemaphore(value: 0)
        var answer: T?, abandoned = false
        DispatchQueue.main.async {
            lock.lock(); defer { lock.unlock() }
            guard !abandoned else { return }
            answer = question(); answered.signal()
        }
        if answered.wait(timeout: .now() + timeout) == .success { lock.lock(); defer { lock.unlock() }; return answer }
        lock.lock(); defer { lock.unlock() }
        if let answer { return answer }
        abandoned = true
        return nil
    }
}
