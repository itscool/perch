import CoreGraphics
import Foundation

/// Everything that reads or moves this Mac's real cursor for desk sharing, behind
/// one small interface so the recipe is pinned by fast tests.
///
/// The desk has one pointer, owned by one Mac:
/// - While the pointer is on another Mac, this Mac's cursor is hidden and parked at
///   the centre of the screen it left, and put straight back after every read. The
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
    /// Hide this Mac's cursor while the pointer is on another Mac, and show it
    /// again when it comes back. Both are safe to call twice.
    func hide()
    func show()
    /// Stop and resume the cursor following this Mac's own mouse. While the
    /// pointer is on another Mac, the cursor should not move at all: a cursor
    /// that is merely hidden still sits over a window, and every time Perch put
    /// it back that window saw the pointer arrive and showed its tooltip.
    func detach()
    func attach()
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
    /// macOS only hides the cursor for the app in front unless a connection
    /// asks to set it in the background, which is how Deskflow and Lan Mouse
    /// hide it from a menu bar app. Hiding is counted, so this stays balanced:
    /// one hide, one show. If Perch ever exits while hidden, macOS restores the
    /// cursor with the connection.
    private var hidden = false
    private var backgroundCursorRequested = false
    func hide() {
        guard !hidden else { return }
        if !backgroundCursorRequested {
            backgroundCursorRequested = true
            Self.setsCursorInBackground(true)
        }
        hidden = true
        CGDisplayHideCursor(CGMainDisplayID())
    }
    func show() {
        guard hidden else { return }
        hidden = false
        CGDisplayShowCursor(CGMainDisplayID())
    }
    private var detached = false
    func detach() {
        guard !detached else { return }
        detached = true
        CGAssociateMouseAndMouseCursorPosition(0)
    }
    func attach() {
        guard detached else { return }
        detached = false
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    deinit { show(); attach() }
    private static func setsCursorInBackground(_ value: Bool) {
        typealias Connection = UInt32
        typealias MainConnection = @convention(c) () -> Connection
        typealias SetProperty = @convention(c) (Connection, Connection, CFString, CFTypeRef) -> Int32
        let handle = dlopen(nil, RTLD_NOW)
        defer { if handle != nil { dlclose(handle) } }
        guard let mainSymbol = dlsym(handle, "CGSMainConnectionID"), let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let main = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let set = unsafeBitCast(setSymbol, to: SetProperty.self)
        let connection = main()
        _ = set(connection, connection, "SetsCursorInBackground" as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
    }
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
        // Hidden, and then stopped: the cursor stays exactly where it was and
        // does not move again until the pointer comes back. Nothing warps, so no
        // window under it sees the pointer arrive, and the hardware's movement
        // still reaches Perch to be sent on.
        cursor.hide()
        cursor.shortenWarpPause()
        cursor.detach()
        park = cursor.location
    }

    /// After a movement read, put the cursor straight back, remembering how far it
    /// had moved so a failing reset shows up in the log.
    /// A detached cursor does not drift, so there is nothing to put back. The
    /// reading is kept to prove it: any drift here means detaching failed.
    mutating func reset(from location: CGPoint, _ cursor: DeskCursorSystem) {
        guard let park else { return }
        let drift = Double(hypot(location.x - park.x, location.y - park.y))
        worstDrift = max(worstDrift, drift)
        resets += 1
        guard drift > 1 else { return }
        cursor.warp(to: park)
    }

    mutating func end(_ cursor: DeskCursorSystem? = nil) {
        if park != nil { cursor?.attach(); cursor?.show() }
        park = nil; resets = 0; worstDrift = 0
    }

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

/// How much the travel time from the other Mac varies. The clocks need not
/// agree: a constant offset cancels, so what is left is the jitter that a
/// person feels. It says whether a late movement was late on the network or
/// late being posted here.
struct DeskTravelJitter {
    static let window = 5.0
    private var samples: [Double] = []
    private var started: Double?
    mutating func arrived(sent: Double, at now: Double) -> String? {
        guard sent > 0 else { return nil }
        samples.append(now - sent)
        let start = started ?? now
        started = start
        guard now - start >= Self.window, samples.count >= 8 else { return nil }
        defer { samples = []; started = now }
        let sorted = samples.sorted()
        let smallest = sorted[0]
        // Only the variation is meaningful, so measure everything from the
        // quickest arrival in this window.
        func ms(_ value: Double) -> String { String(format: "%.1f", value * 1000) }
        let median = sorted[sorted.count / 2] - smallest
        let high = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))] - smallest
        return "\(sorted.count) movements; beyond the quickest, median \(ms(median)) ms, 95th percentile \(ms(high)) ms, worst \(ms(sorted[sorted.count - 1] - smallest)) ms"
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
