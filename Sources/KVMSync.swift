import Foundation
import CryptoKit

// Established by pairing/membership, never by decoding a configuration snapshot.
struct KVMTrustRoster {
    let group: UUID
    let epoch: UUID
    let keys: [UUID: Data]
    func validate() throws {
        guard (1...16).contains(keys.count), Set(keys.values).count == keys.count else { throw KVMError("The paired membership roster is invalid.") }
        for key in keys.values { _ = try Curve25519.Signing.PublicKey(rawRepresentation: key) }
    }
}

struct KVMRevisionPayload: Codable {
    var protocolVersion = 1
    var group: KVMGroup
    var epoch: UUID
    var author: UUID
    var parents: [String]
    var nonce = UUID()
}

struct KVMSignedRevision: Codable {
    var payload: Data
    var signature: Data
    // Hash payload bytes, not a re-encoding or a randomized signature.
    var id: String { SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined() }
    static let domain = Data("Perch KVM configuration v1\0".utf8)
    static let maximumPayload = 256 * 1024
    static func sign(_ value: KVMRevisionPayload, key: Curve25519.Signing.PrivateKey) throws -> Self {
        _ = try value.group.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumPayload else { throw KVMError("This desk revision is too large.") }
        return Self(payload: data, signature: try key.signature(for: domain + data))
    }
    func verified(roster: KVMTrustRoster) throws -> KVMRevisionPayload {
        guard payload.count <= Self.maximumPayload, signature.count == 64 else { throw KVMError("Invalid desk message size.") }
        let value = try JSONDecoder().decode(KVMRevisionPayload.self, from: payload)
        guard value.protocolVersion == 1, value.epoch == roster.epoch, value.group.id == roster.group,
              let raw = roster.keys[value.author],
              try Curve25519.Signing.PublicKey(rawRepresentation: raw).isValidSignature(signature, for: Self.domain + payload) else {
            throw KVMError("This change isn't authenticated for the current group membership.")
        }
        guard Set(value.group.computers.map(\.id)) == Set(roster.keys.keys) else { throw KVMError("A desk change cannot add or restore unpaired computers.") }
        guard value.parents.count <= 16, Set(value.parents).count == value.parents.count,
              value.parents.allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) else { throw KVMError("Invalid desk revision ancestry.") }
        _ = try value.group.validated()
        return value
    }
}

// Called on one serialized executor by the eventual transport/store adapter.
// No network is opened and no trust is established by this object.
struct KVMSyncGraph {
    let roster: KVMTrustRoster
    private(set) var revisions: [String: KVMSignedRevision] = [:]
    private(set) var heads: Set<String> = []
    private var ancestors: [String: Set<String>] = [:]
    private var receipts: [UUID: Set<String>] = [:]
    var hasConflict: Bool { heads.count > 1 }
    var current: KVMGroup? {
        guard heads.count == 1, let id = heads.first, let revision = revisions[id] else { return nil }
        return try? revision.verified(roster: roster).group
    }
    init(roster: KVMTrustRoster) throws { try roster.validate(); self.roster = roster }

    mutating func receive(_ revision: KVMSignedRevision) throws {
        let value = try revision.verified(roster: roster)
        let id = revision.id
        if revisions[id] != nil { return }
        guard revisions.count < 4096 else { throw KVMError("The desk history needs a coordinated checkpoint before another edit.") }
        guard value.parents.allSatisfy({ revisions[$0] != nil }) else { throw KVMError("Earlier desk changes must arrive before this revision.") }
        // An epoch has one root. A peer cannot introduce an unrelated new history.
        guard !value.parents.isEmpty || revisions.isEmpty else { throw KVMError("This desk already has a starting revision.") }
        var ancestry = Set(value.parents)
        for parent in value.parents { ancestry.formUnion(ancestors[parent] ?? []) }
        let newer = heads.contains { ancestors[$0]?.contains(id) == true }
        var nextHeads = heads.subtracting(ancestry)
        if !newer { nextHeads.insert(id) }
        guard nextHeads.count <= 16 else { throw KVMError("Resolve the existing desk conflicts before adding another branch.") }
        revisions[id] = revision; ancestors[id] = ancestry; heads = nextHeads
        // An author has its own revision, but this does not acknowledge it for peers.
        receipts[value.author, default: []].insert(id)
    }

    mutating func edit(_ group: KVMGroup, author: UUID, key: Curve25519.Signing.PrivateKey,
                       resolving expectedHeads: Set<String>? = nil) throws -> KVMSignedRevision {
        guard key.publicKey.rawRepresentation == roster.keys[author] else { throw KVMError("This computer's signing identity does not match the group.") }
        if hasConflict { guard expectedHeads == heads else { throw KVMError("Review both desk changes before resolving the conflict.") }; }
        if let expectedHeads, expectedHeads != heads { throw KVMError("The desk changed while you were reviewing it. Review the new changes.") }
        let revision = try KVMSignedRevision.sign(KVMRevisionPayload(group: group, epoch: roster.epoch, author: author, parents: heads.sorted()), key: key)
        try receive(revision)
        return revision
    }

    // The connection adapter must authenticate the peer and bind its receipt to
    // this epoch. Receiving a revision is NOT an acknowledgement from all peers.
    mutating func acknowledge(_ id: String, from authenticatedPeer: UUID, epoch: UUID) throws {
        guard epoch == roster.epoch, roster.keys[authenticatedPeer] != nil, revisions[id] != nil else { throw KVMError("Unrecognized synchronization acknowledgement.") }
        receipts[authenticatedPeer, default: []].insert(id)
    }
    func awaitingAcknowledgement(of id: String) -> Set<UUID> {
        Set(roster.keys.keys.filter { peer in
            !(receipts[peer] ?? []).contains { receipt in receipt == id || ancestors[receipt]?.contains(id) == true }
        })
    }
    func history() throws -> [KVMSignedRevision] {
        try revisions.values.sorted { a, b in
            let ac = ancestors[a.id]?.count ?? 0, bc = ancestors[b.id]?.count ?? 0
            return ac == bc ? a.id < b.id : ac < bc
        }.map { revision in _ = try revision.verified(roster: roster); return revision }
    }
}

// Length-prefixed, bounded messages for an authenticated transport. Byte chunks
// may split anywhere; there is no dependence on TCP packet boundaries.
struct KVMMessageFramer {
    static let maximum = 512 * 1024
    private var buffer = Data()
    static func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximum else { throw KVMError("Invalid KVM message length.") }
        let n = UInt32(data.count)
        return Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + data
    }
    mutating func append(_ chunk: Data) throws -> [Data] {
        // Transport receive calls must be bounded. Fail closed, clear framing
        // state and close the connection after any framing error.
        guard chunk.count <= Self.maximum + 4 else { buffer.removeAll(); throw KVMError("Oversized KVM transport read.") }
        buffer.append(chunk)
        var messages: [Data] = []
        while buffer.count >= 4 {
            guard messages.count < 256 else { buffer.removeAll(); throw KVMError("Too many KVM frames in one transport read.") }
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.maximum else { buffer.removeAll(); throw KVMError("Invalid KVM frame length.") }
            guard buffer.count >= length + 4 else { break }
            messages.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(length + 4))
        }
        return messages
    }
}
