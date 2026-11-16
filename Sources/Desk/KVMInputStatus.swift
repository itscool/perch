import Foundation

/// Why a Mac cannot share its keyboard and mouse right now, as that Mac says
/// about itself in its readiness poll. The other Macs then name the real cause
/// ("Mac Studio is locked") instead of guessing that Share is off.
enum KVMShareReason: String, Codable, CaseIterable {
    /// The person pressed Ctrl-Opt-Esc on that Mac.
    case choseLocal
    case needsAccessibility
    case needsInputMonitoring
    case locked
    /// Another user is active at that Mac's screen (fast user switching).
    case inactiveSession
    /// macOS would not start input capture; Perch tries again by itself.
    case captureFailed
    /// macOS kept stopping input capture; Perch restarts it by itself.
    case captureRestarting
}

/// Why control cannot start on a screen, as facts the session finds.
enum KVMInputBlocker: Equatable {
    /// Sharing is off on this Mac, or this Mac cannot share right now.
    case notHere(KVMShareReason?)
    /// This Mac's place in the desk (left, a conflict, the owner unreachable).
    case desk(String)
    /// A cable whose display Perch has not matched yet.
    case screenNotSeen
    /// No answer from the owner yet.
    case waitingForOwner(String)
    /// A Mac the pointer needs is not sharing: its name and its own reason.
    /// No reason and no polls means Share on this Mac is off there.
    case notSharing(String, KVMShareReason?)
    case offline(String)
    /// Another way of sharing (a different sharing version), already worded.
    case version(String)
    /// The screens in this preset do not touch, already worded.
    case noSharedEdge(String)
    /// The input has no computer wired to it.
    case noComputer
}

/// Every sentence keyboard and mouse sharing says about why it is not running,
/// in one place, pinned by fast tests. Plain, short, and it names the Mac and
/// what to do there (PERCH.md rules 3 and 5).
enum KVMInputStatus {
    static func sentence(_ blocker: KVMInputBlocker) -> String {
        switch blocker {
        case .notHere(let reason):
            guard let reason else { return "Share on this Mac is off, or this Mac cannot share right now." }
            return here(reason)
        case .desk(let text): return text
        case .screenNotSeen:
            return "Perch has not seen this screen from that Mac yet. Switch to this input once and Perch picks it up. The picture still switches meanwhile."
        case .waitingForOwner(let name):
            return "Waiting for " + name + " to answer. Perch keeps trying."
        case .notSharing(let name, let reason):
            guard let reason else { return "Share on this Mac is off on " + name + ". Turn it on in the Perch menu there." }
            return there(name, reason)
        case .offline(let name):
            return name + " is offline. Perch reconnects by itself when it is back."
        case .version(let text), .noSharedEdge(let text): return text
        case .noComputer:
            return "No computer is wired to this input. Draw a wire from a computer to it."
        }
    }
    /// This Mac's own reason, said on this Mac.
    static func here(_ reason: KVMShareReason) -> String {
        switch reason {
        case .choseLocal: return "Ctrl-Opt-Esc stopped sharing on this Mac. Choose a preset or Share to start again."
        case .needsAccessibility: return "Perch needs Accessibility on this Mac. Allow it in Setup → Shared input access."
        case .needsInputMonitoring: return "Perch needs Input Monitoring on this Mac. Allow it in Setup → Keyboard access."
        case .locked: return "This Mac is locked. Unlock it to share."
        case .inactiveSession: return "Another user is active on this Mac. Sharing resumes when you switch back."
        case .captureFailed: return "macOS would not start input sharing on this Mac. Perch tries again every few seconds."
        case .captureRestarting: return "macOS kept stopping input sharing on this Mac. Perch starts it again in a few seconds."
        }
    }
    /// Another Mac's reason, said on this Mac.
    static func there(_ name: String, _ reason: KVMShareReason) -> String {
        switch reason {
        case .choseLocal: return "Ctrl-Opt-Esc stopped sharing on " + name + ". Choose a preset or Share to start again."
        case .needsAccessibility: return "Perch needs Accessibility on " + name + ". Allow it in Setup there."
        case .needsInputMonitoring: return "Perch needs Input Monitoring on " + name + ". Allow it in Setup there."
        case .locked: return name + " is locked. Unlock it to share."
        case .inactiveSession: return "Another user is active on " + name + ". Sharing resumes when you switch back there."
        case .captureFailed: return "macOS would not start input sharing on " + name + ". Perch tries again there by itself."
        case .captureRestarting: return "macOS kept stopping input sharing on " + name + ". Perch starts it again there by itself."
        }
    }
    /// The desk changed while sharing ran. Sharing starts again by itself.
    static let layoutChanged = "The desk layout changed, so control came back to this Mac. Sharing starts again by itself."
}
