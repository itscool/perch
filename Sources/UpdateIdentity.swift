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
            throw AppError(message: "This update requires a separate signing or lid-helper migration. Keep using this version until migration instructions are available.")
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
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read() -> NetworkUpdateHandoff? {
        guard AppUpdate.sameLocation(AppUpdate.base, AppUpdate.base.resolvingSymlinksInPath()) else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size < 8192 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size)), offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), $0.count-offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }; offset += count
        }
        return try? JSONDecoder().decode(NetworkUpdateHandoff.self, from: Data(bytes))
    }
    static func remove() { try? FileManager.default.removeItem(at: url) }
}
