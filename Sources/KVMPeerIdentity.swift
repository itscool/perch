import Foundation
import CryptoKit
import Security
import PerchCertificates

struct KVMPeerCard: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let signingKey: Data
    let certificate: Data
    var fingerprint: String { SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined() }
    func validate() throws {
        guard !name.isEmpty, name.utf8.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              certificate.count <= 8192, SecCertificateCreateWithData(nil, certificate as CFData) != nil else { throw KVMError("Invalid computer identity.") }
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: signingKey)
    }
}
final class KVMPeerIdentity {
    struct Saved: Codable { let id: UUID; let signing: Data; let tls: Data; let certificate: Data }
    let saved: Saved
    let signing: Curve25519.Signing.PrivateKey
    let tls: sec_identity_t
    func card(name: String) -> KVMPeerCard { .init(id: saved.id, name: name, signingKey: signing.publicKey.rawRepresentation, certificate: saved.certificate) }
    init(saved: Saved) throws {
        self.saved = saved; signing = try .init(rawRepresentation: saved.signing)
        var error: Unmanaged<CFError>?
        guard let certificate = SecCertificateCreateWithData(nil, saved.certificate as CFData),
              let key = SecKeyCreateWithData(saved.tls as CFData, [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate, kSecAttrKeySizeInBits: 256] as CFDictionary, &error),
              let identity = SecIdentityCreate(nil, certificate, key), let tls = sec_identity_create(identity) else { throw KVMError("The saved Desk identity could not be opened.") }
        self.tls = tls
    }
    static func fresh() throws -> Self {
        let id = UUID(), key = P256.Signing.PrivateKey()
        return try Self(saved: Saved(id: id, signing: Curve25519.Signing.PrivateKey().rawRepresentation, tls: key.x963Representation,
                                    certificate: perchCertificate(privateKey: key.x963Representation, name: "Perch " + id.uuidString)))
    }
    static func load() throws -> KVMPeerIdentity {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "local.scott.perch.desk.identity", kSecAttrAccount: "device"]
        var result: CFTypeRef?
        var read = query; read[kSecReturnData] = true; read[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try .init(saved: JSONDecoder().decode(Saved.self, from: data)) }
        guard status == errSecItemNotFound else { throw KVMError("Unlock your login Keychain to open this Mac’s Desk identity (\(status)).") }
        let value = try fresh()
        var add = query; add[kSecValueData] = try JSONEncoder().encode(value.saved); add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw KVMError("Could not save this Mac’s Desk identity in Keychain.") }
        return value
    }
}
