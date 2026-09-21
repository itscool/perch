import Foundation

/// Reported repeatedly from the real two-Mac desk: the pointer was taken over
/// even when the two Macs' screens had no shared edge, leaving it captured
/// with nowhere to cross. Virtual control must follow the monitor arrangement,
/// never merely the fact that a preset names another Mac.
func runDeskSharedSpaceTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let group = KVMGroup.sample()

    // "Together" places one Mac's screen against the other's, so an edge exists.
    try check(KVMEdge.sharesDeskSpace(group: group, preset: group.presets[0]),
              "A preset with two Macs side by side reported no shared desk space")

    // Presets that put every screen on one Mac have no edge between computers,
    // so Perch must leave that Mac's pointer alone.
    try check(!KVMEdge.sharesDeskSpace(group: group, preset: group.presets[1]),
              "An all-on-one-Mac preset claimed shared desk space")
    try check(!KVMEdge.sharesDeskSpace(group: group, preset: group.presets[2]),
              "An all-on-one-Mac preset claimed shared desk space")

    // Two computers, but their screens are far apart: still nothing to cross.
    var apart = group
    let portrait = apart.monitors.firstIndex { $0.name == "Portrait screen" }
    try check(portrait != nil, "The fixture lost its portrait screen")
    apart.monitors[portrait!].geometry = .init(x: 3000, y: 0, width: 530, height: 300, rotation: .clockwise)
    try check(!KVMEdge.sharesDeskSpace(group: apart, preset: apart.presets[0]),
              "Screens with a gap between them reported shared desk space")

    // Edge geometry itself: a corner is not a crossing, and a gap is not an edge.
    let base = KVMGeometry(x: 0, y: 0, width: 300, height: 200)
    try check(!KVMEdge.touching(base, KVMGeometry(x: 300, y: 200, width: 300, height: 200)),
              "A corner-to-corner touch counted as shared desk space")
    try check(KVMEdge.touching(base, KVMGeometry(x: 300, y: 100, width: 300, height: 200)),
              "Screens meeting along a vertical edge were not counted as shared")
    try check(KVMEdge.touching(base, KVMGeometry(x: 50, y: 200, width: 300, height: 200)),
              "Screens stacked one above the other were not counted as shared")
    try check(!KVMEdge.touching(base, KVMGeometry(x: 301, y: 0, width: 300, height: 200)),
              "A one millimetre gap counted as shared desk space")

    // Why it cannot cross, in the person's terms. Scott's desk had two screens
    // side by side on two Macs, and Perch told him to place them side by side,
    // because the screen it could not place was left out of the arrangement.
    try check(KVMEdge.sharedSpaceIssue(group: group, preset: group.presets[0]) == nil, "A preset that can share reported a reason it cannot")
    // Scott's desk exactly: two screens side by side, one Mac each, and the
    // second Mac's cable not matched to a display yet.
    let mac = KVMComputer(name: "Scott's MacBook Pro"), studio = KVMComputer(name: "Mac Studio")
    let first = KVMMonitor(name: "Home Screen 1", geometry: .init(x: 0, y: 0, width: 599.3, height: 340.2))
    let second = KVMMonitor(name: "Home screen 2", geometry: .init(x: 599.3, y: 0, width: 599.3, height: 340.2))
    var pending = KVMGroup(name: "Home", computers: [mac, studio], monitors: [first, second])
    let matched = KVMConnection(monitor: first.id, computer: mac.id, localDisplay: UUID().uuidString, inputName: "USB-C", inputCode: 209)
    let unmatchedCable = KVMConnection(monitor: second.id, computer: studio.id, localDisplay: nil, inputName: "HDMI 2", inputCode: 145)
    pending.connections = [matched, unmatchedCable]
    pending.presets[0].assignments = [.init(monitor: first.id, connection: matched.id), .init(monitor: second.id, connection: unmatchedCable.id)]
    let unmatched = KVMEdge.sharedSpaceIssue(group: pending, preset: pending.presets[0]) ?? ""
    try check(unmatched.contains("has not seen") && unmatched.contains("Mac Studio") && unmatched.contains("Home screen 2") && !unmatched.contains("side by side"),
              "An unmatched display was reported as screens not being side by side: \(unmatched)")
    // Once that cable is matched, the same desk shares space.
    var matchedDesk = pending
    matchedDesk.connections[1].localDisplay = UUID().uuidString
    try check(KVMEdge.sharedSpaceIssue(group: matchedDesk, preset: matchedDesk.presets[0]) == nil,
              "Matching the display did not make the two side-by-side screens shareable")
    let oneMac = KVMEdge.sharedSpaceIssue(group: group, preset: group.presets[1]) ?? ""
    try check(oneMac.contains("one Mac on every screen"), "An all-on-one-Mac preset did not say so: \(oneMac)")
    let gap = KVMEdge.sharedSpaceIssue(group: apart, preset: apart.presets[0]) ?? ""
    try check(gap.contains("do not sit next to each other"), "Screens with a gap did not report the arrangement: \(gap)")

    // None of this Mac's screens are in the preset: there is nothing to cross to,
    // so its keyboard and mouse drive the Mac that is on screen instead of being
    // refused. Scott: "if i'm on pc 1, and i switch to a preset which is only
    // both pc 2, pc 1 input should still work to solely drive pc 2's displays".
    let mine = group.computers[0].id, theirs = group.computers[1].id
    let allTheirs = group.presets.first { preset in
        let computers = Set(preset.assignments.compactMap { a in group.connections.first { $0.id == a.connection }?.computer })
        return computers == [theirs]
    }
    try check(allTheirs != nil, "The fixture lost its all-on-one-Mac preset")
    try check(KVMEdge.drivesAnother(group: group, preset: allTheirs!, local: mine), "A preset with none of this Mac's screens did not drive the other Mac")
    try check(KVMEdge.sharedSpaceIssue(group: group, preset: allTheirs!, local: mine) == nil,
              "Driving the other Mac outright was refused: \(KVMEdge.sharedSpaceIssue(group: group, preset: allTheirs!, local: mine) ?? "")")
    // The Mac that is on screen everywhere keeps its own input: there is no other
    // Mac to drive, and nothing to cross to.
    try check(!KVMEdge.drivesAnother(group: group, preset: allTheirs!, local: theirs) &&
              KVMEdge.sharedSpaceIssue(group: group, preset: allTheirs!, local: theirs) != nil,
              "The Mac showing on every screen was told it drives another Mac")

    print("PASS: virtual pointer control follows the monitor arrangement; no shared edge means no shared control, and Perch names which of an unmatched display, one Mac or an actual gap is stopping it, and a Mac with no screen in the preset drives the one that has them")
}
