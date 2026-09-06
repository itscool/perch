import Foundation
import Darwin
import IOKit.pwr_mgt

struct CaffeinateProcess {
    let pid: pid_t
    let owner: uid_t
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    static func inspect(_ pid: pid_t) -> CaffeinateProcess? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(cString: path) == "/usr/bin/caffeinate" else { return nil }
        return CaffeinateProcess(pid: pid, owner: info.pbi_uid, startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec)
    }

    func stop() throws {
        // Recheck executable, owner and birth time immediately before signaling.
        guard let current = Self.inspect(pid), current.startedSeconds == startedSeconds,
              current.startedMicroseconds == startedMicroseconds else { return }
        guard current.owner == getuid() else { throw AppError(message: "caffeinate (PID \(pid)) belongs to another user. Perch can only stop your own sessions.") }
        if kill(pid, SIGTERM) != 0 && errno != ESRCH {
            throw AppError(message: "Could not stop caffeinate (PID \(pid)): \(String(cString: strerror(errno))).")
        }
    }
}

struct SleepStatus {
    let perchActive: Bool
    var currentProcessActive = false
    let caffeinateProcesses: [CaffeinateProcess]
    var caffeinateActive: Bool { !caffeinateProcesses.isEmpty }

    static func read() throws -> SleepStatus {
        var assertions: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&assertions)
        guard status == kIOReturnSuccess, let assertions else { throw AppError(message: "Could not read current sleep assertions.") }
        let processes = assertions.takeRetainedValue() as NSDictionary
        var own = false
        var current = false
        var caffeine: [CaffeinateProcess] = []
        for (pid, value) in processes {
            guard let pid = (pid as? NSNumber)?.int32Value, let items = value as? [[String: Any]] else { continue }
            let active = items.contains { item in
                guard (item[kIOPMAssertionLevelKey] as? NSNumber)?.intValue ?? 0 != 0,
                      let type = item[kIOPMAssertionTypeKey] as? String else { return false }
                return [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventSystemSleep, kIOPMAssertionTypeNoDisplaySleep, "UserIsActive"].contains(type)
            }
            guard active else { continue }
            if pid == getpid() { current = true }
            if pid == getpid() || items.contains(where: { ($0[kIOPMAssertionNameKey] as? String) == "Perch: keep Mac awake" && (($0[kIOPMAssertionLevelKey] as? NSNumber)?.intValue ?? 0) != 0 }) { own = true }
            if let process = CaffeinateProcess.inspect(pid) { caffeine.append(process) }
        }
        return SleepStatus(perchActive: own, currentProcessActive: current, caffeinateProcesses: caffeine)
    }

    func stopCaffeinate() throws {
        var errors: [String] = []
        for process in caffeinateProcesses {
            do { try process.stop() } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw AppError(message: errors.joined(separator: "\n")) }
    }
}

func runCaffeinateTests() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    child.arguments = ["-i", "-t", "15"]
    try child.run()
    defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
    let unrelated = Process()
    unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
    unrelated.arguments = ["15"]
    try unrelated.run()
    defer { if unrelated.isRunning { unrelated.terminate(); unrelated.waitUntilExit() } }
    var target: CaffeinateProcess?
    for _ in 0..<100 {
        target = try SleepStatus.read().caffeinateProcesses.first { $0.pid == child.processIdentifier }
        if target != nil { break }
        usleep(20_000)
    }
    guard let target else { throw AppError(message: "Did not detect test caffeinate assertion.") }
    guard CaffeinateProcess.inspect(unrelated.processIdentifier) == nil else { throw AppError(message: "Matched an unrelated process.") }
    // Only terminate the process created by this test; never touch existing sessions.
    try SleepStatus(perchActive: false, caffeinateProcesses: [target]).stopCaffeinate()
    for _ in 0..<100 {
        if !child.isRunning { break }
        usleep(20_000)
    }
    guard !child.isRunning, unrelated.isRunning else { throw AppError(message: "caffeinate stop/isolation check failed.") }
    try target.stop() // Already-exited processes are harmless.
    print("PASS: detect and stop a test caffeinate session; unrelated processes preserved")
}
