import Foundation

/// One way to run a child process with a bounded wait.
///
/// Every helper used to hand-roll this with its own busy-wait, semaphore or
/// poll loop and its own idea of how to kill a stuck child. This runner waits
/// on termination, collects bounded output on a reader thread so a full pipe
/// can never deadlock the child, and on timeout terminates, waits briefly,
/// then kills. The process is always reaped before this returns.
enum Subprocess {
    struct Output {
        let status: Int32
        let data: Data
        var succeeded: Bool { status == 0 }
        var text: String? { String(data: data, encoding: .utf8) }
    }
    enum Capture {
        /// Discard standard output.
        case discard
        /// Keep up to this many bytes; more than that fails the run.
        case collect(maximumBytes: Int)
        /// Append standard output (and standard error) to this handle.
        case handle(FileHandle)
    }
    struct Timeout: LocalizedError {
        let executable: String
        let seconds: TimeInterval
        var errorDescription: String? { "\(URL(fileURLWithPath: executable).lastPathComponent) did not finish within \(Int(seconds.rounded(.up))) seconds." }
    }
    struct Oversized: LocalizedError {
        let executable: String
        var errorDescription: String? { "\(URL(fileURLWithPath: executable).lastPathComponent) produced more output than allowed." }
    }

    /// Run to completion within `timeout` seconds.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval,
                    capture: Capture = .discard, environment: [String: String]? = nil) throws -> Output {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        if let environment { task.environment = environment }
        let pipe: Pipe?
        switch capture {
        case .discard:
            pipe = nil; task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        case .collect:
            let p = Pipe(); pipe = p; task.standardOutput = p; task.standardError = FileHandle.nullDevice
        case .handle(let handle):
            pipe = nil; task.standardOutput = handle; task.standardError = handle
        }
        let ended = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in ended.signal() }
        try task.run()
        // Read on a separate thread; waiting on the child first would deadlock
        // once it fills the pipe.
        var collected = Data(), overflow = false
        let reader = Thread {
            guard let pipe else { return }
            let limit: Int = { if case .collect(let maximum) = capture { return maximum } else { return 0 } }()
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if collected.count + chunk.count > limit { overflow = true; break }
                collected.append(chunk)
            }
            try? handle.close()
        }
        if pipe != nil { reader.start() }
        if ended.wait(timeout: .now() + timeout) != .success {
            reap(task, ended: ended)
            throw Timeout(executable: executable, seconds: timeout)
        }
        // The termination handler has run, so the child has exited. Never call
        // waitUntilExit: it spins the caller's run loop, and on the main thread
        // that re-enters timers and menu code in the middle of a command.
        settle(task)
        if pipe != nil {
            // The child exited; its write end is closed, so the reader ends soon.
            let readerDeadline = Date().addingTimeInterval(1)
            while !reader.isFinished && Date() < readerDeadline { usleep(5_000) }
            if !reader.isFinished { reader.cancel() }
        }
        if overflow { throw Oversized(executable: executable) }
        return Output(status: task.isRunning ? -1 : task.terminationStatus, data: collected)
    }

    /// Terminate politely, then kill, then reap. Safe on an already-exited task.
    static func reap(_ task: Process, grace: TimeInterval = 0.2, ended: DispatchSemaphore? = nil) {
        guard task.isRunning else { settle(task); return }
        task.terminate()
        if let ended, ended.wait(timeout: .now() + grace) == .success { settle(task); return }
        let deadline = Date().addingTimeInterval(grace)
        while task.isRunning && Date() < deadline { usleep(10_000) }
        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        if let ended { _ = ended.wait(timeout: .now() + 2) }
        settle(task)
    }
    /// Wait for Foundation to report the child gone without running the run
    /// loop. Bounded so a wedged child can never hold the caller.
    private static func settle(_ task: Process, limit: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(limit)
        while task.isRunning && Date() < deadline { usleep(1_000) }
    }

    /// Start a child that is not waited for. Foundation keeps a running task
    /// alive until it exits; callers need no bookkeeping.
    @discardableResult
    static func spawn(_ executable: String, _ arguments: [String]) throws -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        return task
    }
}
