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
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["python3", checker, "check", "--session", session]
        task.standardInput = FileHandle.nullDevice
        try task.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !task.isRunning else {
            task.terminate()
            throw AppError(message: "AGENT MODE check timed out. Stop desktop tests; do not bypass the session check.")
        }
        guard task.terminationStatus == 0 else {
            throw AppError(message: "AGENT MODE is not active or control was requested. Stop desktop tests and hand control back.")
        }
    }
}
