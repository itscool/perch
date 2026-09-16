import Foundation

// Creates a desk that two guests already share, using Perch's own identity,
// membership and archive types. Pairing itself is covered by the loopback
// suite; seeding lets the lab spend its time on connection and input sharing.
// Usage: seed-desk <output directory> <name A> <name B>
let arguments = CommandLine.arguments
guard arguments.count == 4 || arguments.count == 6 else {
    FileHandle.standardError.write(Data("usage: seed-desk <output> <nameA> <nameB> [addressAdialsB addressBdialsA]\n".utf8))
    exit(2)
}
// Optional dial addresses let the lab connect a seeded desk over a relay when
// the guests cannot reach each other directly. Discovery is bypassed.
let dial: [String] = arguments.count == 6 ? [arguments[4], arguments[5]] : []
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
let names = [arguments[2], arguments[3]]
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let identities = try [KVMPeerIdentity.fresh(), KVMPeerIdentity.fresh()]
    let cards = zip(identities, names).map { $0.card(name: $1) }
    let group = KVMGroup(name: "Lab desk", computers: cards.map { .init(id: $0.id, name: $0.name) })
    let membership = try KVMMembership.sign(group: group, peers: cards, authority: cards[0].id,
                                            key: identities[0].signing, generation: 1, previousHeads: [])
    let encoder = JSONEncoder()
    for (index, identity) in identities.enumerated() {
        let label = index == 0 ? "a" : "b"
        var archive = KVMDeskArchive(authorityKey: cards[0].signingKey, membership: membership, history: [])
        if dial.count == 2 {
            // The address this guest uses to reach the other one.
            archive.addresses = [cards[1 - index].id: dial[index]]
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
