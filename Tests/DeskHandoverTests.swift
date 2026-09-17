import Foundation

/// Where the pointer lands when control moves to another screen. Picking up
/// the mouse attached to the other Mac carries no requested position, and
/// dropping the pointer in the middle of that screen is the jump Scott
/// reported: control must continue from where the cursor already is, and
/// Perch must never invent a position it was not given.
func runDeskHandoverTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func at(_ point: KVMPoint?, _ x: Double, _ y: Double) -> Bool {
        guard let point else { return false }
        return abs(point.x - x) < 0.05 && abs(point.y - y) < 0.05
    }
    let screen = KVMGeometry(x: 600, y: 0, width: 400, height: 300)
    let centre = (x: 800.0, y: 150.0)

    // Switching mice sends no requested position. The pointer carries over,
    // moved only as far as it must to land on the new screen.
    let carried = KVMPoint(x: 550, y: 120)
    let landed = KVMInputSession.entryPoint(requested: nil, carried: carried, screen: screen)
    try check(at(landed, 600, 120), "A switch did not carry the pointer over: \(String(describing: landed))")
    try check(!at(landed, centre.x, centre.y), "A switch landed on the screen centre")

    // A pointer already inside the target screen is left exactly where it is.
    let inside = KVMPoint(x: 700, y: 200)
    try check(at(KVMInputSession.entryPoint(requested: nil, carried: inside, screen: screen), 700, 200),
              "A pointer already on the screen was moved")

    // Both axes clamp, so a diagonal switch still arrives at the nearest point.
    try check(at(KVMInputSession.entryPoint(requested: nil, carried: .init(x: 100, y: 900), screen: screen), 600, 300),
              "A diagonal switch did not land on the nearest edge")

    // An explicit position is honoured when it is on the screen.
    let asked = KVMPoint(x: 650, y: 50)
    try check(KVMInputSession.entryPoint(requested: asked, carried: carried, screen: screen) == asked,
              "A valid requested position was overridden")

    // Off the screen, the shared pointer outranks the asking Mac's own cursor.
    try check(at(KVMInputSession.entryPoint(requested: .init(x: 5, y: 5), carried: inside, screen: screen), 700, 200),
              "An off-screen request did not defer to the carried pointer")

    // A first focus with no shared pointer still uses the asking Mac's cursor,
    // wherever it sits, rather than inventing a centre.
    try check(at(KVMInputSession.entryPoint(requested: .init(x: 200, y: 260), carried: nil, screen: screen), 600, 260),
              "A first focus ignored the asking Mac's own cursor")

    // With no pointer anywhere, Perch invents nothing and control waits.
    try check(KVMInputSession.entryPoint(requested: nil, carried: nil, screen: screen) == nil,
              "Control started at an invented position with no pointer to carry")

    print("PASS: switching control carries the pointer to the nearest point on the new screen, and never invents a position")
}
