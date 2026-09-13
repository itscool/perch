import Foundation

/// Read-before-write policy; adapters provide hardware operations and timing.
enum DeskMonitorCommand {
    enum Outcome { case alreadySelected, switched, unverified }
    struct Cancelled: LocalizedError {
        var errorDescription: String? { "The switch was cancelled before its monitor command." }
    }
    static func run(input: UInt16, permitted: () -> Bool, read: () throws -> UInt16?,
                    write: () throws -> Void, settle: () -> Void) throws -> Outcome {
        guard permitted() else { throw Cancelled() }
        let current = try? read()
        guard permitted() else { throw Cancelled() }
        if current == input { return .alreadySelected }
        try write()
        settle()
        guard permitted() else { return .unverified }
        let observed = try? read()
        return permitted() && observed == input ? .switched : .unverified
    }
}
