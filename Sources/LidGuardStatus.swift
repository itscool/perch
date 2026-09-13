import Foundation
import Darwin
import Security

enum LidGuardIdentity {
    static let current: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }()
}

enum LidGuardClock {
    /// Includes time asleep; wall-clock edits cannot extend a battery deadline.
    private static let scale: Double = { var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase); return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 }()
    static var now: Double { Double(mach_continuous_time()) * scale }
}

struct LidGuardStatus: Codable {
    static let revision = LidGuardCompatibility.protocolVersion
    var revision = Self.revision
    var helperVersion = LidGuardCompatibility.helperVersion
    var helperBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    var codeIdentity = LidGuardIdentity.current
    var updatedAt: Double
    var armed: Bool
    var remaining: Int?
    var detail: String
    var error: String? = nil
    var activityError: String? = nil
    var countdown: LidCountdown? = nil
    var displayDetail: String { armed && error == nil ? "The lid helper reports an active session. " + detail + " macOS can still force sleep; an active session cannot guarantee continued wakefulness." : detail }
    // The authenticated XPC connection verifies the helper's signing identity.
    // Compatibility is independent of the app's executable hash/build number.
    var fresh: Bool { let age = LidGuardClock.now - updatedAt; return revision == Self.revision && helperVersion > 0 && age >= 0 && age < 3 }
}
