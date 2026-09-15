import Foundation

/// A repeating timer on the main run loop in the common modes, so it keeps
/// firing while a menu is tracking or a sheet is up. Callers keep the
/// returned timer and invalidate it when they stop.
enum MainTimer {
    @discardableResult
    static func every(_ interval: TimeInterval, tolerance: TimeInterval = 0, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in body() }
        if tolerance > 0 { timer.tolerance = tolerance }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
