import Foundation

/// The one error type Perch throws: a sentence for the user.
///
/// `AppError(message:)` and `KVMError(_:)` were two identical types that only
/// existed because the KVM files could not see `main.swift`; both names remain
/// as aliases so call sites and the headless suites keep compiling.
struct PerchError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    init(message: String) { self.message = message }
    var errorDescription: String? { message }
}
typealias AppError = PerchError
typealias KVMError = PerchError
