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
    var lidSleepAllowed: Bool? = nil
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
    private var lastNow: Double?
    private var externalSince: Double?
    mutating func constrainDeadline(_ value: Double?) { if let value, value.isFinite { deadline = min(deadline ?? value, value) } }
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
            return .init(preventLidSleep: false, requestSleep: observation.closed != false && observation.power != .external, remaining: nil,
                         detail: known ? "Lid protection stopped. Open the lid and enable it again." : "Lid or power status is unknown. Sleep protection has been released; check the Mac.")
        }
        if observation.closed == true && observation.power == .battery {
            if deadline == nil { deadline = now + Self.grace }
            if now >= deadline! {
                stopped = true
                return .init(preventLidSleep: false, requestSleep: true, remaining: 0, detail: "The lid stayed closed on battery for 60 seconds. Requesting sleep.")
            }
            let remaining = Int(ceil(deadline! - now))
            return .init(preventLidSleep: true, requestSleep: false, remaining: remaining, detail: "Open the lid within \(remaining) seconds. If it stays closed on battery, the Mac will sleep.")
        }
        // Power cancels enforcement. Require five stable seconds before clearing
        // the old deadline so repeated brief dock/power flapping cannot extend it.
        return .init(preventLidSleep: true, requestSleep: false, remaining: nil,
                     detail: observation.closed == true ? "Lid closed on external power. Unplugging gives up to 60 seconds to open it." : "Ready. Closed on external power: stay awake. Closed on battery: 60 seconds to open the lid, then sleep.")
    }
}

struct LidGuardStatus: Codable {
    static let revision = 1
    var revision = Self.revision
    var codeIdentity = LidGuardIdentity.current
    var updatedAt: Double
    var armed: Bool
    var remaining: Int?
    var detail: String
    var error: String? = nil
    var fresh: Bool { let age = LidGuardClock.now - updatedAt; return revision == Self.revision && codeIdentity != nil && codeIdentity == LidGuardIdentity.current && age >= 0 && age < 3 }
}
