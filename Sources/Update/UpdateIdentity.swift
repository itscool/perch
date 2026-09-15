import Foundation
import CryptoKit

/// Independently signed metadata: even a feed error/fallback cannot authorize a
/// lid handoff. The archive remains subject to Sparkle's own verification.
struct UpdateIdentity: Codable, Equatable {
    let schema: Int
    let bundle: String
    let build: String
    let codeHash: String
    let requirement: String
    let lidProtocol: Int

    static func verify(payload: String, signature: String, publicKey: String,
                       bundle: String, build: String, requirement: String, lidProtocol: Int) throws -> Self {
        guard payload.utf8.count <= 16_384, signature.utf8.count == 88,
              publicKey.utf8.count == 44,
              let data = Data(base64Encoded: payload), let signed = Data(base64Encoded: signature), signed.count == 64,
              let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signed, for: data) else {
            throw AppError(message: "This update’s Perch identity could not be verified. Your current app is still running. Try checking again later.")
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema == 1, value.bundle == bundle, value.build == build,
              Int(build).map({ $0 > 0 }) == true,
              value.codeHash.count == 40, value.codeHash.allSatisfy({ "0123456789abcdef".contains($0) }),
              value.requirement == requirement, value.lidProtocol == lidProtocol else {
            throw AppError(message: "This update is incompatible with this app’s verified publisher or lid-helper protocol. Your current app is still running.")
        }
        return value
    }
}

struct NetworkUpdateHandoff: Codable {
    let boot: UUID
    let path: String
    let build: String
    let ticket: LidRestartTicket

    func matches(boot: UUID?, path: String, build: String, identity: String?, now: Double) -> Bool {
        self.boot == boot && self.path == path && self.build == build && ticket.targetIdentity == identity &&
        now.isFinite && ticket.deadline.isFinite && ticket.deadline > now && ticket.deadline <= now + 60
    }
}

enum NetworkUpdateHandoffFile {
    static var url: URL { AppUpdate.base.appendingPathComponent("network-restart.json") }
    static func save(_ record: NetworkUpdateHandoff) throws {
        try FileManager.default.createDirectory(at: AppUpdate.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard AppUpdate.sameLocation(AppUpdate.base, AppUpdate.base.resolvingSymlinksInPath()) else {
            throw AppError(message: "The update folder must not be a symbolic link.")
        }
        // A new process must reopen the record after restart. Use macOS's
        // after-login class; "unless open" can make a closed file unreadable.
        try SecureFile.writeAtomically(record, to: url, protection: true)
    }
    static func read() -> NetworkUpdateHandoff? {
        guard AppUpdate.sameLocation(AppUpdate.base, AppUpdate.base.resolvingSymlinksInPath()),
              let data = try? SecureFile.read(url.path, .init(maximumBytes: 8191, requirePrivate: true, singleLink: false)) else { return nil }
        return try? JSONDecoder().decode(NetworkUpdateHandoff.self, from: data)
    }
    static func remove() { try? FileManager.default.removeItem(at: url) }
}
