import AppKit

/// Resetting Perch's own privacy decisions has a fixed executable and argument
/// list naming only Perch. Resetting every app's decisions belonged to the
/// Agent Kill Switch and was removed with it, so no argument list here can
/// reach another app.
enum PrivacyOnlyReset {
    static let perchBundleID = "local.scott.perch"
    static func arguments(global: Bool = false) -> [String] { ["reset", "All", perchBundleID] }
    static let operation = PrivacyResetOperation { global, completion in
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                let output = try Subprocess.run("/usr/bin/tccutil", arguments(global: global), timeout: 30)
                if output.succeeded {
                    result = .success("✓ macOS accepted the privacy reset. Apps may ask for access again. Review Privacy & Security for entries that remain; some changes require an app relaunch.")
                } else { throw AppError(message: "macOS did not complete the privacy reset (exit \(output.status)). Review Privacy & Security before retrying; some permissions may already have changed.") }
            } catch is Subprocess.Timeout {
                result = .failure(AppError(message: "macOS did not finish the privacy reset within 30 seconds. Review Privacy & Security before retrying; some permissions may already have changed."))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// Owned by the app, not a page. Leaving never cancels a command already sent.
final class PrivacyResetOperation {
    enum State { case idle, running, succeeded(String), failed(String) }
    private(set) var states: [Bool: State] = [:]
    private(set) var runningScope: Bool?
    private var generation = UUID()
    private let execute: (Bool, @escaping (Result<String, Error>) -> Void) -> Void
    init(execute: @escaping (Bool, @escaping (Result<String, Error>) -> Void) -> Void) { self.execute = execute }
    func state(global: Bool) -> State { states[global] ?? .idle }
    func prepare(global: Bool) { guard runningScope == nil else { return }; states[global] = .idle }
    @discardableResult
    func run(global: Bool, completion: ((Result<String, Error>) -> Void)? = nil) -> Bool {
        guard runningScope == nil else { return false }
        generation = UUID(); let request = generation
        runningScope = global; states[global] = .running
        execute(global) { [self] result in
            guard runningScope == global, generation == request else { return }
            runningScope = nil
            switch result {
            case .success(let message): states[global] = .succeeded(message)
            case .failure(let error): states[global] = .failed("⚠ " + error.localizedDescription)
            }
            completion?(result)
        }
        return true
    }
}

