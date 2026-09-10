import Foundation
import Crypto
import X509
import SwiftASN1

/// A private peer identity, unrelated to Developer ID application signing.
public func perchCertificate(privateKey: Data, name: String) throws -> Data {
    let key = try P256.Signing.PrivateKey(x963Representation: privateKey)
    let subject = try DistinguishedName { CommonName(name) }
    let certificate = try Certificate(version: .v3, serialNumber: .init(),
        publicKey: .init(key.publicKey), notValidBefore: Date().addingTimeInterval(-3600),
        notValidAfter: Date().addingTimeInterval(10 * 365 * 86400), issuer: subject,
        subject: subject, signatureAlgorithm: .ecdsaWithSHA256, extensions: .init(), issuerPrivateKey: .init(key))
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}
