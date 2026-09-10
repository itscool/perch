import Foundation
import CryptoKit
guard CommandLine.arguments.count == 4,
      let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else { exit(2) }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
exit(key.isValidSignature(signature, for: payload) ? 0 : 1)
