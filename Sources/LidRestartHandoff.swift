import Foundation

enum LidGuardCompatibility {
    static let protocolVersion = 2
    // Increment only when the lid helper needs replacement, not for app UI edits.
    static let helperVersion = 1
}

struct LidRestartTicket: Codable, Equatable {
    let id: String
    let targetIdentity: String
    let deadline: Double
}

/// The app-update allowance replaces only the app heartbeat deadline. The
/// helper still evaluates battery policy and renews its short watchdog lease.
struct LidRestartHandoff {
    private(set) var pending: LidRestartTicket?
    mutating func prepare(identity: String, now: Double, active: Bool) throws -> LidRestartTicket {
        guard active, now.isFinite, now >= 0, identity.count == 40,
              identity.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw AppError(message: "An active, confirmed helper session and verified update are required.")
        }
        if let pending {
            guard pending.targetIdentity == identity, now < pending.deadline else {
                throw AppError(message: "The restart allowance is already used or expired.")
            }
            return pending // Retry does not buy more time.
        }
        let ticket = LidRestartTicket(id: UUID().uuidString, targetIdentity: identity, deadline: now + 60)
        pending = ticket
        return ticket
    }
    mutating func claim(_ id: String, pinnedConnection: String?, now: Double, active: Bool) throws {
        guard let pending, active, now.isFinite, now >= pending.deadline - 60,
              now < pending.deadline, id == pending.id, pinnedConnection == pending.id else {
            throw AppError(message: "The updated app could not reclaim the lid session. It may have expired; review Keep awake.")
        }
        self.pending = nil
    }
    mutating func clear() { pending = nil }
}
