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

    print("PASS: virtual pointer control follows the monitor arrangement; no shared edge means no shared control")
}
