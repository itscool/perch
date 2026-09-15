import Foundation

/// One launchd job in one domain, driven through `launchctl` with a bounded
/// wait. Outcomes are values, so each caller decides what a failure means and
/// how to word it.
struct LaunchdJob: Hashable {
    enum Domain: Hashable {
        case user(uid_t)
        case system
        var name: String {
            switch self {
            case .user(let uid): return "gui/\(uid)"
            case .system: return "system"
            }
        }
    }

    enum Outcome: Equatable, CustomStringConvertible {
        case ok
        case failed(Int32)
        case timedOut
        case error(String)
        var succeeded: Bool { self == .ok }
        var description: String {
            switch self {
            case .ok: return "ok"
            case .failed(let status): return "failed (\(status))"
            case .timedOut: return "timed out"
            case .error(let message): return "failed: \(message)"
            }
        }
    }

    static let launchctl = "/bin/launchctl"
    let domain: Domain
    let label: String

    static func user(_ label: String, uid: uid_t = getuid()) -> LaunchdJob { .init(domain: .user(uid), label: label) }
    static func system(_ label: String) -> LaunchdJob { .init(domain: .system, label: label) }

    /// The `domain/label` target launchctl expects.
    var target: String { domain.name + "/" + label }

    static func run(_ arguments: [String], timeout: TimeInterval = 2) -> Outcome {
        do {
            let output = try Subprocess.run(launchctl, arguments, timeout: timeout)
            return output.succeeded ? .ok : .failed(output.status)
        } catch is Subprocess.Timeout { return .timedOut }
        catch { return .error(error.localizedDescription) }
    }

    func print(timeout: TimeInterval = 2) -> Outcome { Self.run(["print", target], timeout: timeout) }
    /// Whether launchd currently has the job loaded.
    func isLoaded(timeout: TimeInterval = 2) -> Bool { print(timeout: timeout) == .ok }
    func bootout(timeout: TimeInterval = 2) -> Outcome { Self.run(["bootout", target], timeout: timeout) }
    func bootstrap(_ plist: URL, timeout: TimeInterval = 2) -> Outcome { Self.run(["bootstrap", domain.name, plist.path], timeout: timeout) }
    func enable(timeout: TimeInterval = 2) -> Outcome { Self.run(["enable", target], timeout: timeout) }
    func disable(timeout: TimeInterval = 2) -> Outcome { Self.run(["disable", target], timeout: timeout) }
    func kickstart(timeout: TimeInterval = 2) -> Outcome { Self.run(["kickstart", target], timeout: timeout) }

    /// Replace this job with the definition in `plist`. `launchctl bootout`
    /// can return before launchd has finished removing a running service, and
    /// a bootstrap issued in that window fails, leaving the job unloaded. Wait
    /// (bounded) until the old job is gone, then bootstrap, retrying briefly.
    func replace(with plist: URL, unloadDeadline: TimeInterval = 5, attempts: Int = 3,
                 run: ([String]) -> Outcome = { LaunchdJob.run($0) },
                 pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                 now: () -> Double = { MonotonicClock.now }) -> Outcome {
        _ = run(["bootout", target])
        // Measure the deadline on a clock, not by counting pauses: each
        // launchctl check can itself take up to its own timeout.
        let deadline = now() + unloadDeadline
        while now() < deadline, run(["print", target]) == .ok { pause(0.1) }
        var result = Outcome.error("bootstrap was not attempted")
        for attempt in 0..<max(1, attempts) {
            if attempt > 0 { pause(0.25) }
            result = run(["bootstrap", domain.name, plist.path])
            if result.succeeded { break }
        }
        return result
    }

    /// Starts unloading without waiting. The caller polls the returned task
    /// and terminates it if launchd never answers.
    func spawnBootout() throws -> Process { try Subprocess.spawn(Self.launchctl, ["bootout", target]) }

    /// The domain's `print-disabled` listing, or nil when it cannot be read.
    static func disabledListing(in domain: Domain, timeout: TimeInterval = 2) -> String? {
        guard let output = try? Subprocess.run(launchctl, ["print-disabled", domain.name], timeout: timeout, capture: .collect(maximumBytes: 1 << 20)),
              output.succeeded else { return nil }
        return output.text
    }
}
