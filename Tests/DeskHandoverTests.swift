import Foundation

/// Where the pointer lands when control moves to another screen. Picking up
/// the mouse attached to the other Mac carries no requested position, and
/// dropping the pointer in the middle of that screen is the jump Scott
/// reported: control should continue from where the cursor already is.
func runDeskHandoverTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.05 }
    let screen = KVMGeometry(x: 600, y: 0, width: 400, height: 300)

    // Switching mice sends no requested position. The pointer carries over,
    // moved only as far as it must to land on the new screen.
    let carried = KVMPoint(x: 550, y: 120)
    let landed = KVMInputSession.entryPoint(requested: nil, carried: carried, screen: screen)
    try check(near(landed.x, 600) && near(landed.y, 120), "A switch did not carry the pointer over: \(landed)")
    try check(!near(landed.x, 800) || !near(landed.y, 150), "A switch landed on the screen centre")

    // A pointer already inside the target screen is left exactly where it is.
    let inside = KVMPoint(x: 700, y: 200)
    let kept = KVMInputSession.entryPoint(requested: nil, carried: inside, screen: screen)
    try check(near(kept.x, 700) && near(kept.y, 200), "A pointer already on the screen was moved: \(kept)")

    // Both axes clamp, so a diagonal switch still arrives at the nearest point.
    let corner = KVMInputSession.entryPoint(requested: nil, carried: .init(x: 100, y: 900), screen: screen)
    try check(near(corner.x, 600) && near(corner.y, 300), "A diagonal switch did not land on the nearest edge: \(corner)")

    // An explicit position is honoured when it is on the screen, ignored when not.
    let asked = KVMPoint(x: 650, y: 50)
    try check(KVMInputSession.entryPoint(requested: asked, carried: carried, screen: screen) == asked, "A valid requested position was overridden")
    let offscreen = KVMInputSession.entryPoint(requested: .init(x: 5, y: 5), carried: inside, screen: screen)
    try check(near(offscreen.x, 700) && near(offscreen.y, 200), "An off-screen request did not fall back to the carried pointer")

    // Only with nothing to carry does control start at the centre.
    let centre = KVMInputSession.entryPoint(requested: nil, carried: nil, screen: screen)
    try check(near(centre.x, 800) && near(centre.y, 150), "The first focus did not start at the screen centre: \(centre)")

    print("PASS: switching control carries the pointer to the nearest point on the new screen, never to its centre")
}
