import Foundation

/// Isolated storage and prohibited activation do not prevent orderFront from
/// showing a panel. Tests that present windows must check the visible banner.
enum DesktopTestSession {
    static func check() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let checker = environment["PERCH_AGENT_MODE_CHECKER"],
              let session = environment["PERCH_AGENT_MODE_SESSION"],
              checker.hasPrefix("/"), session.hasPrefix("/") else {
            throw AppError(message: "Desktop tests require an announced AGENT MODE session. Use Tools/check-functional-review.py --agent-session with the active session path.")
        }
        let output: Subprocess.Output
        do { output = try Subprocess.run("/usr/bin/env", ["python3", checker, "check", "--session", session], timeout: 5) }
        catch is Subprocess.Timeout { throw AppError(message: "AGENT MODE check timed out. Stop desktop tests; do not bypass the session check.") }
        guard output.succeeded else {
            throw AppError(message: "AGENT MODE is not active or control was requested. Stop desktop tests and hand control back.")
        }
    }
}
