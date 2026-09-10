import Foundation
import CryptoKit

struct KVMMembershipPayload: Codable {
    var version = 1
    let generation: UInt64
    let authority: UUID
    let peers: [KVMPeerCard]
    let root: KVMSignedRevision
    let previousHeads: [String]
}
struct KVMMembership: Codable, Equatable {
    let payload: Data
    let signature: Data
    static let domain = Data("Perch Desk membership v1\0".utf8)
    func verified(authorityKey: Data) throws -> KVMMembershipPayload {
        guard payload.count <= 512 * 1024, signature.count == 64,
              try Curve25519.Signing.PublicKey(rawRepresentation: authorityKey).isValidSignature(signature, for: Self.domain + payload) else { throw KVMError("The desk membership is not signed by its trusted owner.") }
        let value = try JSONDecoder().decode(KVMMembershipPayload.self, from: payload)
        guard value.version == 1, value.generation > 0, (1...16).contains(value.peers.count),
              Set(value.peers.map(\.id)).count == value.peers.count,
              Set(value.peers.map(\.certificate)).count == value.peers.count,
              value.peers.first(where: { $0.id == value.authority })?.signingKey == authorityKey else { throw KVMError("Invalid desk membership.") }
        for peer in value.peers { try peer.validate() }
        let root = try JSONDecoder().decode(KVMRevisionPayload.self, from: value.root.payload)
        let roster = value.roster(group: root.group.id, epoch: root.epoch)
        try roster.validate()
        let verified = try value.root.verified(roster: roster)
        guard verified.author == value.authority, verified.parents.isEmpty else { throw KVMError("The desk starting revision is not authorized.") }
        return value
    }
    static func sign(group: KVMGroup, peers: [KVMPeerCard], authority: UUID, key: Curve25519.Signing.PrivateKey, generation: UInt64, previousHeads: [String]) throws -> Self {
        let root = try KVMSignedRevision.sign(.init(group: group, epoch: UUID(), author: authority, parents: []), key: key)
        let value = KVMMembershipPayload(generation: generation, authority: authority, peers: peers, root: root, previousHeads: previousHeads)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(value)
        let result = Self(payload: payload, signature: try key.signature(for: domain + payload))
        _ = try result.verified(authorityKey: key.publicKey.rawRepresentation)
        return result
    }
}
extension KVMMembershipPayload {
    func roster(group: UUID, epoch: UUID) -> KVMTrustRoster { .init(group: group, epoch: epoch, keys: Dictionary(uniqueKeysWithValues: peers.map { ($0.id, $0.signingKey) })) }
    func graph() throws -> KVMSyncGraph {
        let root = try JSONDecoder().decode(KVMRevisionPayload.self, from: root.payload)
        var graph = try KVMSyncGraph(roster: roster(group: root.group.id, epoch: root.epoch))
        try graph.receive(self.root)
        return graph
    }
}

struct KVMDeskArchive: Codable {
    var version = 1
    let authorityKey: Data
    let membership: KVMMembership
    var history: [KVMSignedRevision]
    var recoveredDraft: KVMGroup?
    var addresses: [UUID: String] = [:]
    func verified() throws -> (KVMMembershipPayload, KVMSyncGraph) {
        guard version == 1, history.count <= 4096 else { throw KVMError("Unsupported or oversized Desk history.") }
        let value = try membership.verified(authorityKey: authorityKey)
        var graph = try value.graph()
        for revision in history { try graph.receive(revision) }
        return (value, graph)
    }
    static func read(_ url: URL) throws -> Self {
        let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard attributes.isSymbolicLink != true, attributes.isRegularFile == true, (attributes.fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw KVMError("The saved Desk file is not a bounded regular file.") }
        let archive = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)); _ = try archive.verified(); return archive
    }
    func write(_ url: URL) throws {
        let bytes = try JSONEncoder().encode(self)
        guard bytes.count <= 64 * 1024 * 1024 else { throw KVMError("Desk history is full. Reconnect the desk owner for a checkpoint.") }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw KVMError("Desk storage must not be a symbolic link.") }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
