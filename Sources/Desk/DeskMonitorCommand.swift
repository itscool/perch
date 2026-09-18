import Foundation

/// Read-before-write policy; adapters provide hardware operations and timing.
enum DeskMonitorCommand {
    enum Outcome { case alreadySelected, switched, unverified }
    struct Cancelled: LocalizedError {
        var errorDescription: String? { "The switch was cancelled before its monitor command." }
    }
    /// - Parameter pause: the wait before the one repeat sent to a monitor that
    ///   cannot say which input it is showing. LG panels drop a side-channel
    ///   command sent just after an input change, and with no readback Perch
    ///   cannot tell; selecting the input already showing does nothing, so the
    ///   repeat is harmless when the first one landed.
    static func run(input: UInt16, permitted: () -> Bool, read: () throws -> UInt16?,
                    write: () throws -> Void, settle: () -> Void, pause: () -> Void = {}, force: Bool = false) throws -> Outcome {
        guard permitted() else { throw Cancelled() }
        let current = try? read()
        guard permitted() else { throw Cancelled() }
        if !force && current == input { return .alreadySelected }
        try write()
        settle()
        guard permitted() else { return .unverified }
        let observed = try? read()
        if permitted() && observed == input { return .switched }
        // Only an unknown answer is repeated. A monitor reporting another input
        // contradicted the command, and sending it again would not change that.
        guard observed == nil || observed == 0 else { return .unverified }
        pause()
        guard permitted() else { return .unverified }
        try write()
        return .unverified
    }
}
