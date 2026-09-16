import Foundation

// Creates a desk that two guests already share, using Perch's own identity,
// membership and archive types. Pairing itself is covered by the loopback
// suite; seeding lets the lab spend its time on connection and input sharing.
//
// Usage: seed-desk <output directory> <guests json>
// Each guest: {"name", "display", "widthMM", "heightMM", "dial"}. The screen
// size is what CoreGraphics reports in that guest, so the scale Perch computes
// from it is the real one.
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: seed-desk <output> <guests json>\n".utf8))
    exit(2)
}
struct Guest {
    let name: String, display: String, width: Double, height: Double, dial: String?
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
guard let raw = arguments[2].data(using: .utf8),
      let entries = (try? JSONSerialization.jsonObject(with: raw)) as? [[String: Any]], entries.count == 2 else {
    FileHandle.standardError.write(Data("seed failed: expected two guests as JSON\n".utf8))
    exit(2)
}
let guests: [Guest] = entries.map { entry in
    Guest(name: entry["name"] as? String ?? "guest",
          display: entry["display"] as? String ?? UUID().uuidString,
          width: (entry["widthMM"] as? NSNumber)?.doubleValue ?? 368.9,
          height: (entry["heightMM"] as? NSNumber)?.doubleValue ?? 280.7,
          dial: entry["dial"] as? String)
}
let names = guests.map(\.name)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let identities = try [KVMPeerIdentity.fresh(), KVMPeerIdentity.fresh()]
    let cards = zip(identities, names).map { $0.card(name: $1) }
    var group = KVMGroup(name: "Lab desk", computers: cards.map { .init(id: $0.id, name: $0.name) })
    // A screen each, side by side, at the size the guests really are, so the
    // scale Perch derives from physical size over point size is sane. The next
    // screen starts at the previous one's right edge, read back after the same
    // rounding, so the two edges align exactly.
    var monitors: [KVMMonitor] = [], connections: [KVMConnection] = [], nextX = 0.0
    for (index, guest) in guests.enumerated() {
        let geometry = KVMGeometry(x: nextX, y: 0, width: guest.width, height: guest.height)
        nextX = geometry.right
        let monitor = KVMMonitor(name: "\(guest.name) screen", geometry: geometry,
                                 control: KVMMonitorControl(computer: cards[index].id, localDisplay: guest.display, mode: "standard"))
        monitors.append(monitor)
        connections.append(KVMConnection(monitor: monitor.id, computer: cards[index].id, localDisplay: guest.display,
                                         inputName: "HDMI 1", inputCode: 17))
    }
    group.monitors = monitors
    group.connections = connections
    // Slot one drives both screens, so activating it has a remote route.
    group.presets[0].assignments = zip(monitors, connections).map { KVMAssignment(monitor: $0.id, connection: $1.id) }
    _ = try group.validated()
    let membership = try KVMMembership.sign(group: group, peers: cards, authority: cards[0].id,
                                            key: identities[0].signing, generation: 1, previousHeads: [])
    let encoder = JSONEncoder()
    for (index, identity) in identities.enumerated() {
        let label = index == 0 ? "a" : "b"
        var archive = KVMDeskArchive(authorityKey: cards[0].signingKey, membership: membership, history: [])
        if let dial = guests[index].dial {
            // The address this guest uses to reach the other one.
            archive.addresses = [cards[1 - index].id: dial]
        }
        try archive.write(output.appendingPathComponent("desk-\(label).json"))
        try encoder.encode(identity.saved).write(to: output.appendingPathComponent("identity-\(label).json"))
    }
    // Prove both guests would accept what was written.
    for label in ["a", "b"] { _ = try KVMDeskArchive.read(output.appendingPathComponent("desk-\(label).json")).verified() }
    print("seeded desk for \(names[0]) and \(names[1]) in \(output.path)")
} catch {
    FileHandle.standardError.write(Data("seed failed: \(error)\n".utf8))
    exit(1)
}
