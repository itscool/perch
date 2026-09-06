import AppKit
import Foundation
import Darwin

struct PanicPlan: Codable {
    static let perchID = "local.scott.perch"
    let otherApps: [String]
    let globalReset: Bool
    init(bundleIDs: [String], global: Bool = true) {
        globalReset = global
        otherApps = Array(Set(bundleIDs.filter {
            $0 != Self.perchID && $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]+$", options: .regularExpression) != nil
        })).sorted()
    }
    var commands: [[String]] {
        otherApps.map { ["reset", "All", $0] } + (globalReset ? [["reset", "All"]] : [])
    }
    func execute(_ run: ([String]) -> Int32) -> [Int32] {
        // Always attempt the final user-wide reset, even after individual failures.
        commands.map(run)
    }
}

struct PanicReport: Codable {
    let started: Date
    let finished: Date
    let commands: [[String]]
    let exitCodes: [Int32]
    var globalResetSucceeded: Bool { exitCodes.last == 0 }
}

enum PanicReset {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Panic", isDirectory: true)
    }
    static var reportURL: URL { folder.appendingPathComponent("latest-report.json") }
    static var logURL: URL { folder.appendingPathComponent("latest-log.txt") }

    static func launch(bundleIDs: [String], global: Bool) throws -> Process {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let plan = PanicPlan(bundleIDs: bundleIDs, global: global)
        let planURL = folder.appendingPathComponent("plan-\(UUID().uuidString).json")
        try JSONEncoder().encode(plan).write(to: planURL, options: .atomic)
        guard let executable = Bundle.main.executableURL else { throw AppError(message: "Cannot locate the panic reset worker.") }
        let worker = Process()
        worker.executableURL = executable
        worker.arguments = ["--panic-worker", planURL.path]
        worker.standardInput = FileHandle.nullDevice
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        try worker.run()
        return worker
    }

    static func worker(planURL: URL) -> Int32 {
        // Independent process with no dependency on Accessibility, event taps, or UI.
        _ = setsid()
        signal(SIGHUP, SIG_IGN)
        do {
            let decoded = try JSONDecoder().decode(PanicPlan.self, from: Data(contentsOf: planURL))
            let plan = PanicPlan(bundleIDs: decoded.otherApps, global: decoded.globalReset) // Revalidate on the worker side.
            let started = Date()
            try Data("Perch privacy reset started \(started)\n".utf8).write(to: logURL, options: .atomic)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close(); try? FileManager.default.removeItem(at: planURL) }
            try log.seekToEnd()
            let codes = plan.execute { args in
                try? log.write(contentsOf: Data("\n/usr/bin/tccutil \(args.joined(separator: " "))\n".utf8))
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = args
                task.standardOutput = log
                task.standardError = log
                task.standardInput = FileHandle.nullDevice
                do {
                    try task.run()
                    let deadline = Date().addingTimeInterval(3)
                    while task.isRunning && Date() < deadline { usleep(20_000) }
                    if task.isRunning {
                        task.terminate()
                        let grace = Date().addingTimeInterval(0.2)
                        while task.isRunning && Date() < grace { usleep(10_000) }
                        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                        task.waitUntilExit()
                        try? log.write(contentsOf: Data("TIMEOUT — continuing to next reset\n".utf8))
                        return 124
                    }
                    task.waitUntilExit()
                    return task.terminationStatus
                } catch {
                    try? log.write(contentsOf: Data("ERROR: \(error.localizedDescription)\n".utf8))
                    return 127
                }
            }
            let report = PanicReport(started: started, finished: Date(), commands: plan.commands, exitCodes: codes)
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
            return codes.allSatisfy { $0 == 0 } ? 0 : 1
        } catch { return 1 }
    }
}

func runPanicTests() throws {
    let plan = PanicPlan(bundleIDs: ["com.example.B", PanicPlan.perchID, "com.example.A", "com.example.A", "/bad; input"])
    var calls: [[String]] = []
    let result = plan.execute { args in calls.append(args); return args.count == 2 ? 0 : 1 }
    guard calls == [["reset", "All", "com.example.A"], ["reset", "All", "com.example.B"], ["reset", "All"]], result == [1,1,0] else {
        throw AppError(message: "Panic ordering, deduplication, or failure continuation failed.")
    }
    guard PanicPlan(bundleIDs: []).commands == [["reset", "All"]] else { throw AppError(message: "Empty panic plan must still reset globally.") }
    print("PASS: panic plan excludes Perch until final reset, rejects invalid IDs, and continues after errors (mock executor; no permissions reset)")
}
