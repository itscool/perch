import Foundation

/// Isolated storage and prohibited activation do not prevent orderFront from
/// showing a panel. Tests that present windows must check the visible banner,
/// unless they run unattended inside a virtual machine.
enum DesktopTestSession {
    /// A virtual machine nobody sits at, such as a CI runner or a test VM, has no
    /// person's screen to protect, so window tests run there without the AGENT
    /// MODE banner. The hardware is asked, not only the flag: on a physical Mac
    /// the banner is always required, so a stray flag can never take over
    /// someone's screen.
    static func unattended(flag: String?, virtualMachine: Bool) -> Bool {
        flag == "1" && virtualMachine
    }
    static var runningInVirtualMachine: Bool {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
    }
    static func check() throws {
        let environment = ProcessInfo.processInfo.environment
        if unattended(flag: environment["PERCH_UNATTENDED"], virtualMachine: runningInVirtualMachine) { return }
        guard let checker = environment["PERCH_AGENT_MODE_CHECKER"],
              let session = environment["PERCH_AGENT_MODE_SESSION"],
              checker.hasPrefix("/"), session.hasPrefix("/") else {
            throw AppError(message: "Desktop tests require an announced AGENT MODE session. Use Tools/check-functional-review.py --agent-session with the active session path, or --unattended inside a virtual machine.")
        }
        let output: Subprocess.Output
        do { output = try Subprocess.run("/usr/bin/env", ["python3", checker, "check", "--session", session], timeout: 5) }
        catch is Subprocess.Timeout { throw AppError(message: "AGENT MODE check timed out. Stop desktop tests; do not bypass the session check.") }
        guard output.succeeded else {
            throw AppError(message: "AGENT MODE is not active or control was requested. Stop desktop tests and hand control back.")
        }
    }
}
