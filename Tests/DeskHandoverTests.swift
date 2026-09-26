import Foundation

/// Handing control to the other Mac: where the pointer lands, and which route
/// carries it there.
///
/// Where it lands — picking up the mouse attached to the other Mac carries no
/// requested position, and dropping the pointer in the middle of that screen is
/// the jump Scott reported: control must continue from where the cursor already
/// is, and Perch must never invent a position it was not given.
///
/// How it gets there — the same handover measured 67 to 73 ms at the
/// ninety-fifth percentile over Wi-Fi and under 1.3 ms over the Thunderbolt
/// cable that was plugged in the whole time. `KVMPeerPath` states that rule;
/// these cases pin it, including the one failure the rule exists to prevent:
/// discovery reporting the same cable over and over and Perch dialling once
/// for each report.
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

    // Sharing starts once, and after that only crossing a screen edge moves the
    // pointer. Every Mac keeps offering to start sharing on its own screen; once
    // sharing runs, none of those offers may move it.
    try check(KVMInputSession.placementAllowed(sharing: false, automatic: true, pointerAlreadyThere: false),
              "Sharing could not start on its own")
    try check(!KVMInputSession.placementAllowed(sharing: true, automatic: true, pointerAlreadyThere: false),
              "A Mac took the pointer away from the Mac holding it, without the person asking")
    // The person is the exception: picking a preset or Share on this Mac places it.
    try check(KVMInputSession.placementAllowed(sharing: true, automatic: false, pointerAlreadyThere: false),
              "The person could not move the pointer while sharing was running")
    // Asking for where it already is never re-prepares a handoff on top of itself.
    try check(!KVMInputSession.placementAllowed(sharing: true, automatic: false, pointerAlreadyThere: true),
              "A request for where the pointer already was started another handoff")

    // The loop that made the pointer unusable, replayed. Preparing a handoff
    // clears each Mac's record of where the pointer is, so every Mac that is not
    // holding it offers to start sharing on its own screen, over and over. If any
    // of those offers can move it, the desk trades the pointer with itself for as
    // long as sharing runs. The rule does not count Macs, so this holds for a desk
    // of two the same as a desk of five.
    for macs in 2...5 {
        var holder = 0, seizures = 0
        for _ in 0..<50 {
            for mac in 0..<macs where mac != holder {
                guard KVMInputSession.placementAllowed(sharing: true, automatic: true, pointerAlreadyThere: false) else { continue }
                holder = mac; seizures += 1
            }
        }
        try check(seizures == 0 && holder == 0,
                  "On a desk of \(macs) Macs the pointer was seized \(seizures) times by Macs that did not hold it")
    }

    print("PASS: switching control carries the pointer to the nearest point on the new screen, and never invents a position; sharing starts once and then only an edge crossing or the person moves the pointer, on a desk of any size")

    // A wire beats wireless: a Mac discovered on a cable is dialled over it.
    try check(KVMPeerPath.dialsOverWire(wireFound: true, loopback: false, triedWire: false),
              "A Mac found on the cable between them was still dialled over Wi-Fi")
    // With no cable, nothing changes: the ordinary path is used.
    try check(!KVMPeerPath.dialsOverWire(wireFound: false, loopback: false, triedWire: false),
              "A dial insisted on a wire that does not exist")
    // The desk's own loopback fixtures have no wire and must never be pinned to
    // one, or every real-TLS network test would hang waiting for an interface.
    try check(!KVMPeerPath.dialsOverWire(wireFound: true, loopback: true, triedWire: false),
              "A loopback connection was pinned to a physical interface")
    // A cable that is plugged in but does not carry this peer costs one
    // attempt, not every attempt.
    try check(!KVMPeerPath.dialsOverWire(wireFound: true, loopback: false, triedWire: true),
              "A cable that had already failed to reach the peer took another attempt")

    // A move is only ever an extra dial beside a working link, so there is
    // nothing to move when the desk is not connected, and nothing to add while
    // a dial is already in flight.
    try check(!KVMPeerPath.movesToWire(wireFound: true, loopback: false, connected: false,
                                       linkIsWired: false, triedWire: false, dialInFlight: false),
              "A move was started for a Mac the desk is not connected to")
    try check(!KVMPeerPath.movesToWire(wireFound: true, loopback: false, connected: true,
                                       linkIsWired: false, triedWire: false, dialInFlight: true),
              "A second wired dial was started while the first was still in flight")

    // One move per cable event, replayed the way macOS delivers it. Discovery
    // republishes a Mac whenever anything about it changes, so the same cable
    // arrives over and over; exactly one of those reports may dial, and while
    // that dial is in flight the link actually carrying the desk is untouched.
    var tried = false, lastWire: String?, dials = 0, wirelessOpen = true, onTheWire = false
    for _ in 0..<200 {
        let wire: String? = "bridge0"
        if !KVMPeerPath.remembersWiredTry(tried, wire: wire, lastWire: lastWire) { tried = false }
        lastWire = wire
        if KVMPeerPath.movesToWire(wireFound: wire != nil, loopback: false, connected: wirelessOpen,
                                   linkIsWired: onTheWire, triedWire: tried, dialInFlight: false) {
            tried = true; dials += 1
        }
        try check(wirelessOpen, "The working Wi-Fi link was dropped for a wired route that had not arrived")
    }
    try check(dials == 1, "Two hundred reports of the same cable started \(dials) wired dials")

    // The wired route finally connects and its signed hello checks out. Only
    // now does the desk let go of the link it was using, and only for the wire.
    onTheWire = KVMPeerPath.keepsArrivingRoute(arrivingIsWired: true, workingIsWired: false,
                                               simultaneous: false, arrivingWinsTieBreak: false)
    wirelessOpen = !onTheWire
    try check(onTheWire, "An authenticated wired route did not take over from Wi-Fi")
    // Both Macs dialling at once must still pick the same survivor, and the
    // cable is the survivor whichever end it arrived at.
    try check(KVMPeerPath.keepsArrivingRoute(arrivingIsWired: true, workingIsWired: false,
                                             simultaneous: true, arrivingWinsTieBreak: false),
              "A wired route lost a simultaneous tie-break to Wi-Fi")
    try check(!KVMPeerPath.keepsArrivingRoute(arrivingIsWired: false, workingIsWired: true,
                                              simultaneous: true, arrivingWinsTieBreak: true),
              "A wireless route displaced the cable the two Macs share")
    // With no cable in it, the tie-break is the one the desk already used.
    try check(KVMPeerPath.keepsArrivingRoute(arrivingIsWired: false, workingIsWired: false,
                                             simultaneous: true, arrivingWinsTieBreak: true) &&
              !KVMPeerPath.keepsArrivingRoute(arrivingIsWired: false, workingIsWired: false,
                                              simultaneous: true, arrivingWinsTieBreak: false),
              "The symmetric tie-break between two wireless routes changed")
    // A route arriving long after the one in hand means the other Mac gave up
    // on that one, so it wins whatever each of them runs over.
    try check(KVMPeerPath.keepsArrivingRoute(arrivingIsWired: false, workingIsWired: true,
                                             simultaneous: false, arrivingWinsTieBreak: false),
              "A Mac redialling over Wi-Fi was refused for a wired route it had already given up on")

    // A desk already on the cable never dials again for it.
    for _ in 0..<200 {
        if !KVMPeerPath.remembersWiredTry(tried, wire: "bridge0", lastWire: lastWire) { tried = false }
        lastWire = "bridge0"
        if KVMPeerPath.movesToWire(wireFound: true, loopback: false, connected: true,
                                   linkIsWired: onTheWire, triedWire: tried, dialInFlight: false) {
            tried = true; dials += 1
        }
    }
    try check(dials == 1, "A desk already running over the cable dialled it again: \(dials) dials")

    // Unplugging and plugging in again is a new cable event, and earns exactly
    // one more move — not one per report of the cable coming back.
    onTheWire = false
    for report in 0..<200 {
        let wire: String? = report < 100 ? nil : "bridge0"
        if !KVMPeerPath.remembersWiredTry(tried, wire: wire, lastWire: lastWire) { tried = false }
        lastWire = wire
        if KVMPeerPath.movesToWire(wireFound: wire != nil, loopback: false, connected: true,
                                   linkIsWired: onTheWire, triedWire: tried, dialInFlight: false) {
            tried = true; dials += 1
        }
    }
    try check(dials == 2, "A replugged cable moved the desk \(dials - 1) times instead of once")

    print("PASS: a Mac discovered on the cable between them is dialled over the cable, Wi-Fi is used when there is none, a working link is kept until the wired one has connected and authenticated, and repeated reports of the same cable move the desk exactly once")
}
