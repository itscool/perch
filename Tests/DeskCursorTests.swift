import CoreGraphics
import Foundation

/// The version 1 desk cursor recipe, pinned without touching the real cursor: park
/// at the centre of the screen left, put it back after every read, add remote
/// movement to the live cursor, and report smoothness as numbers.
private final class RecordingCursor: DeskCursorSystem {
    var location: CGPoint
    var displays: [CGRect]
    var warps: [CGPoint] = []
    var pauseShortened = 0
    init(location: CGPoint, displays: [CGRect]) { self.location = location; self.displays = displays }
    func warp(to point: CGPoint) { warps.append(point); location = point }
    func shortenWarpPause() { pauseShortened += 1 }
}

func runDeskCursorTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let side = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    let centre = CGPoint(x: 2472, y: 540)

    // Parking goes to the centre of the screen the cursor is on, never an edge,
    // after shortening macOS's post-warp pause.
    let cursor = RecordingCursor(location: CGPoint(x: 1900, y: 40), displays: [main, side])
    var parking = DeskCursorParking()
    parking.begin(cursor)
    try check(cursor.warps == [centre] && cursor.pauseShortened == 1, "Parking did not go to the centre of the screen it left: \(cursor.warps)")
    parking.begin(cursor)
    try check(cursor.warps.count == 1, "Beginning again moved an already parked cursor")
    // Every read puts it straight back to that same centre, whatever the drift.
    for drift in [CGPoint(x: 2480, y: 536), CGPoint(x: 2300, y: 700), CGPoint(x: 2473, y: 541)] {
        parking.reset(from: drift, cursor)
    }
    try check(cursor.warps.count == 4 && cursor.warps.allSatisfy { $0 == centre }, "A read did not return the cursor to the centre: \(cursor.warps)")
    let summary = parking.takeSummary()
    try check(summary.resets == 3 && abs(summary.worstDrift - hypot(172.0, 160.0)) < 0.01, "Parking did not measure its resets and worst drift: \(summary)")
    try check(parking.takeSummary().resets == 0, "A summary did not start a fresh count")
    parking.end()
    parking.reset(from: .zero, cursor)
    try check(cursor.warps.count == 4 && !parking.parked, "A reset ran after parking ended")

    // Movement from another Mac is added to the live cursor. It may continue onto
    // this Mac's adjacent screen, but stops at the edge beyond every screen.
    try check(DeskCursorParking.moved(from: CGPoint(x: 100, y: 100), dx: 5.5, dy: -3, displays: [main, side]) == CGPoint(x: 105.5, y: 97),
              "Movement was not added to the live cursor")
    try check(DeskCursorParking.moved(from: CGPoint(x: 1510, y: 500), dx: 10, dy: 0, displays: [main, side]) == CGPoint(x: 1520, y: 500),
              "Movement did not continue onto the adjacent screen")
    try check(DeskCursorParking.moved(from: CGPoint(x: 3, y: 500), dx: -10, dy: 0, displays: [main, side]) == CGPoint(x: 0, y: 500),
              "Movement past the outer edge was not stopped at the screen")
    let below = DeskCursorParking.moved(from: CGPoint(x: 1500, y: 970), dx: 0, dy: 50, displays: [main, side])
    try check(below == CGPoint(x: 1500, y: main.maxY - 1), "Movement below the screen did not stop at its bottom edge: \(below)")

    // Posted movement carries the movement values apps read, not only a position.
    var builder = KVMNativeEvent()
    let posted = builder.make(.init(kind: .motion, x: 3.6, y: -2.2), point: CGPoint(x: 200, y: 200), source: nil)
    try check(posted?.getIntegerValueField(.mouseEventDeltaX) == 4 && posted?.getIntegerValueField(.mouseEventDeltaY) == -2,
              "Posted movement lacks its movement values")

    // Smoothness is a number: gaps while moving, with the hand's pauses ignored.
    var smoothness = DeskMotionSmoothness()
    var times = (0...100).map { 100 + Double($0) * 0.008 }
    times.append(times[times.count - 1] + 0.03)
    var moment = times[times.count - 1] + 1.0
    while moment < 105.2 { times.append(moment); moment += 0.008 }
    var report: String?
    for time in times { if let text = smoothness.arrived(at: time) { report = text; break } }
    try check(report?.contains("median 8.0 ms") == true && report?.contains("worst 30.0 ms") == true,
              "Smoothness did not report movement gaps with pauses ignored: \(report ?? "no report")")

    print("PASS: desk cursor parks at the centre of the screen left and returns there after every read; remote movement adds to the live cursor and stops at the screen edge; posted movement carries its values; smoothness is measured with pauses ignored")
}
