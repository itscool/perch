import CoreGraphics
import Foundation

/// Everything that reads or moves this Mac's real cursor for desk sharing, behind
/// one small interface so the recipe is pinned by fast tests.
///
/// The desk has one pointer, owned by one Mac. Version 1 keeps the cursor visible:
/// - While the pointer is on another Mac, this Mac's cursor is parked at the centre
///   of the screen it left and put straight back after every movement read. The
///   centre leaves room in every direction, so movement is never clamped at an edge
///   or mistaken for another crossing. Deskflow re-centres the same way on Windows
///   and Linux; Lan Mouse re-warps after every motion on macOS.
/// - While the pointer is here, movement from another Mac is added to the live
///   cursor, exactly like this Mac's own mouse, so two mice add together.
protocol DeskCursorSystem: AnyObject {
    /// The cursor's current global position.
    var location: CGPoint { get }
    /// The bounds of every active display, in global coordinates.
    var displays: [CGRect] { get }
    /// Move the cursor without generating events.
    func warp(to point: CGPoint)
    /// Shorten the pause macOS applies to real mouse input after a warp, so a
    /// parked cursor never drops movement.
    func shortenWarpPause()
}

/// The real cursor.
final class NativeDeskCursor: DeskCursorSystem {
    /// Lan Mouse found zero breaks the warp and the 0.25 s default stalls movement
    /// after it; a short pause keeps both working.
    static let warpPause: CFTimeInterval = 0.05
    /// Kept alive for the process: the pause belongs to this event source state.
    private let combined = CGEventSource(stateID: .combinedSessionState)
    var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }
    var displays: [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [CGDisplayBounds(CGMainDisplayID())] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
    func warp(to point: CGPoint) { CGWarpMouseCursorPosition(point) }
    func shortenWarpPause() { combined?.localEventsSuppressionInterval = Self.warpPause }
}

/// Parks this Mac's cursor while the pointer is on another Mac.
struct DeskCursorParking {
    private(set) var park: CGPoint?
    private var resets = 0
    private var worstDrift = 0.0
    var parked: Bool { park != nil }

    /// Park at the centre of the screen the cursor is on. Beginning again while
    /// parked changes nothing.
    mutating func begin(_ cursor: DeskCursorSystem) {
        guard park == nil else { return }
        let here = cursor.location, screens = cursor.displays
        guard let screen = screens.first(where: { $0.contains(here) }) ?? screens.first else { return }
        let centre = CGPoint(x: screen.midX.rounded(.down), y: screen.midY.rounded(.down))
        cursor.shortenWarpPause()
        cursor.warp(to: centre)
        park = centre
    }

    /// After a movement read, put the cursor straight back, remembering how far it
    /// had moved so a failing reset shows up in the log.
    mutating func reset(from location: CGPoint, _ cursor: DeskCursorSystem) {
        guard let park else { return }
        worstDrift = max(worstDrift, Double(hypot(location.x - park.x, location.y - park.y)))
        resets += 1
        cursor.warp(to: park)
    }

    mutating func end() { park = nil; resets = 0; worstDrift = 0 }

    /// Resets and the furthest drift since the last summary, then a fresh count.
    mutating func takeSummary() -> (resets: Int, worstDrift: Double) {
        defer { resets = 0; worstDrift = 0 }
        return (resets, worstDrift)
    }

    /// Where movement from another Mac takes the live cursor: added to where it is
    /// now and kept on a real screen. It may carry the cursor onto an adjacent
    /// display of this Mac; beyond every display it stops at the edge.
    static func moved(from location: CGPoint, dx: Double, dy: Double, displays: [CGRect]) -> CGPoint {
        let target = CGPoint(x: location.x + dx, y: location.y + dy)
        if displays.contains(where: { $0.contains(target) }) { return target }
        guard let screen = displays.first(where: { $0.contains(location) }) ?? displays.first else { return location }
        return CGPoint(x: min(screen.maxX - 1, max(screen.minX, target.x)),
                       y: min(screen.maxY - 1, max(screen.minY, target.y)))
    }
}

/// Where the first event after control arrives lands.
///
/// Control can arrive in the same batch as the movement that caused it, and the
/// cursor is still parked at the centre of this Mac's screen until the pointer
/// is placed. Adding that movement to the parked cursor is what made the pointer
/// hop to the middle of the screen it was entering, whatever edge it came in by.
/// So the first event after control arrives continues from the entry point, and
/// every event after it from the live cursor, which the person may be moving too.
struct DeskPointerHandover {
    private(set) var placed = false
    /// Control went to another Mac: the next arrival places the pointer again.
    mutating func left() { placed = false }
    /// The pointer was put at the entry point by itself, with no event to carry.
    mutating func placedPointer() { placed = true }
    mutating func base(entry: CGPoint?, live: CGPoint) -> CGPoint {
        defer { placed = true }
        return placed ? live : (entry ?? live)
    }
}

/// How evenly movement arrives on the Mac showing the pointer, so "smooth" is a
/// number in the log rather than an impression.
struct DeskMotionSmoothness {
    /// A gap longer than this is the hand pausing, not jitter.
    static let pause = 0.25
    static let window = 5.0
    private var last: Double?
    private var started: Double?
    private var gaps: [Double] = []
    private var arrivals = 0

    /// Record one arrival. Returns a summary each time a window completes.
    mutating func arrived(at now: Double) -> String? {
        arrivals += 1
        if let last, now >= last, now - last <= Self.pause { gaps.append(now - last) }
        last = now
        let start = started ?? now
        started = start
        guard now - start >= Self.window else { return nil }
        defer { gaps = []; arrivals = 0; started = now }
        guard gaps.count >= 2 else { return nil }
        let sorted = gaps.sorted()
        let median = sorted[sorted.count / 2]
        let high = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))]
        func ms(_ value: Double) -> String { String(format: "%.1f", value * 1000) }
        return "\(arrivals) movements; gaps median \(ms(median)) ms, 95th percentile \(ms(high)) ms, worst \(ms(sorted[sorted.count - 1])) ms"
    }
}
