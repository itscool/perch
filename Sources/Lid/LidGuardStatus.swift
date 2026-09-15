import Foundation
import Darwin
import Security

struct LidGuardStatus: Codable {
    static let revision = LidGuardCompatibility.protocolVersion
    var revision = Self.revision
    var helperVersion = LidGuardCompatibility.helperVersion
    var helperBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    var codeIdentity = CodeIdentity.current
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
