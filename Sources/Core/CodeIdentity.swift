import Foundation
import Security

/// Code-signing facts about this process and about app bundles on disk, read
/// through the Security framework. The updater, the lid helper and the
/// helper status service all verify against these same values.
enum CodeIdentity {
    /// Hex cdhash of the running code, or nil when it is unsigned.
    static let current: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hex(hash)
    }()

    /// The designated requirement of the running code. Other Perch processes
    /// prove they are the same publisher by satisfying it.
    static let designatedRequirement: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()

    /// The cdhash of the app bundle at `app`, once the bundle at that exact
    /// path (no symlinks) strictly satisfies `requirement`.
    static func verifiedHash(of app: URL, requirement: String) throws -> String {
        var code: SecStaticCode?, rule: SecRequirement?, info: CFDictionary?
        guard app.pathExtension == "app", app.standardizedFileURL.path == app.resolvingSymlinksInPath().standardizedFileURL.path,
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), rule) == errSecSuccess,
              SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let bytes = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data, bytes.count == 20 else {
            throw AppError(message: "Perch could not verify this app’s signature. Restore an intact copy signed by the same publisher.")
        }
        return hex(bytes)
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
