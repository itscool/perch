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

enum LidPower: String, Codable { case external, battery, unknown }
struct LidObservation: Equatable {
    var closed: Bool?
    var power: LidPower
}

enum LidGuardStart {
    /// A new session may start remotely on a powered, closed Mac. Starting on
    /// battery still needs an open lid; an existing session keeps its 60s grace.
    static func validate(_ observation: LidObservation) throws {
        guard observation.closed != nil, observation.power != .unknown else {
            throw AppError(message: "Perch could not read the lid and power state. Review lid protection before enabling it.")
        }
        guard observation.closed == false || observation.power == .external else {
            throw AppError(message: "Connect external power or open the lid before starting lid protection.")
        }
    }
}
enum LidGuardClock {
    /// Includes time asleep; wall-clock edits cannot extend a battery deadline.
    private static let scale: Double = { var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase); return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 }()
    static var now: Double { Double(mach_continuous_time()) * scale }
}
struct LidGuardDecision: Equatable {
    var preventLidSleep: Bool
    var requestSleep: Bool
    var remaining: Int?
    var detail: String
}
struct LidGuardPolicy {
    static let grace: Double = 60
    private(set) var deadline: Double?
    private(set) var stopped = false
    private(set) var sleepInterruption: String?
    private var lastNow: Double?
    private var externalSince: Double?
    mutating func constrainDeadline(_ value: Double?) { if let value, value.isFinite { deadline = min(deadline ?? value, value) } }
    mutating func systemSleepBegan() {
        stopped = true
        sleepInterruption = "macOS began sleep while lid mode was requested. The session stopped. Review Lid activity, then enable it again."
    }
    mutating func step(_ observation: LidObservation, now: Double, authorized: Bool) -> LidGuardDecision {
        let timeValid = now.isFinite && now >= 0 && (lastNow == nil || now >= lastNow!)
        lastNow = now
        if !authorized || !timeValid { stopped = true }
        if observation.closed == false { deadline = nil }
        if observation.power == .external {
            if externalSince == nil { externalSince = now }
            if now - externalSince! >= 5 { deadline = nil }
        } else { externalSince = nil }
        let known = observation.closed != nil && observation.power != .unknown
        if !known { stopped = true }
        if stopped {
            if let sleepInterruption {
                // macOS has already announced sleep. Release our command, but
                // do not add a second sleep request or obscure the first cause.
                return .init(preventLidSleep: false, requestSleep: false, remaining: nil, detail: sleepInterruption)
            }
            return .init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external, remaining: nil,
                         detail: known ? "Lid protection stopped. Enable it again with the lid open or external power connected." : "Lid or power status is unknown. Sleep protection has been released; check the Mac.")
        }
        if observation.closed == true && observation.power == .battery {
            if deadline == nil { deadline = now + Self.grace }
            if now >= deadline! {
                stopped = true
                return .init(preventLidSleep: false, requestSleep: true, remaining: 0, detail: "The lid stayed closed on battery for 60 seconds. Requesting sleep.")
            }
            let remaining = Int(ceil(deadline! - now))
            return .init(preventLidSleep: true, requestSleep: false, remaining: remaining, detail: "\(remaining) seconds to open the lid or reconnect power before Perch requests sleep.")
        }
        // Power cancels enforcement. Require five stable seconds before clearing
        // the old deadline so repeated brief dock/power flapping cannot extend it.
        return .init(preventLidSleep: true, requestSleep: false, remaining: nil,
                     detail: observation.closed == true ? "Lid closed on external power. Unplugging starts 60 seconds to open it or reconnect power." : "Closed on external power: request keep awake. Closed on battery: 60 seconds to open the lid or reconnect power.")
    }
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
    var displayDetail: String { armed && error == nil ? "Lid mode requested; prevention is unverified. " + detail : detail }
    // The authenticated XPC connection verifies the helper's signing identity.
    // Compatibility is independent of the app's executable hash/build number.
    var fresh: Bool { let age = LidGuardClock.now - updatedAt; return revision == Self.revision && helperVersion > 0 && age >= 0 && age < 3 }
}
