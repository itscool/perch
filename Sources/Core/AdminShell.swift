import Foundation

/// Runs AppleScript for the app. Privileged shell commands go through the
/// standard macOS administrator prompt; the app installs the two hooks below
/// so Settings can pause its own interaction while the prompt is up and
/// automation refusals are explained in Perch's words.
enum AppleScript {
    /// Called before a privileged command; returns the closure that restores
    /// the app afterwards.
    static var beginAuthorization: () -> (() -> Void)? = { nil }
    /// Turns an AppleScript error into the message shown to the user.
    static var describeFailure: (String, Int?) -> String = { message, _ in message }

    static func run(_ source: String) throws -> NSAppleEventDescriptor { try perform(source) }

    private static func perform(_ source: String) throws -> NSAppleEventDescriptor {
        var restore: (() -> Void)?
        if source.contains(AdminShell.privilegedSuffix) { restore = beginAuthorization() }
        defer { restore?() }
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw AppError(message: "Could not prepare the system command.") }
        let result = script.executeAndReturnError(&error)
        if let error {
            throw AppError(message: describeFailure(error[NSAppleScript.errorMessage] as? String ?? "System command failed.", error[NSAppleScript.errorNumber] as? Int))
        }
        return result
    }
}

/// Builds privileged shell commands. One quoting rule for POSIX arguments and
/// one escaping rule for AppleScript string literals replace the copies every
/// installer used to carry.
enum AdminShell {
    static let privilegedSuffix = "with administrator privileges"

    /// `text` as one POSIX shell word, safe for any bytes including quotes,
    /// spaces, backslashes and newlines.
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The body of an AppleScript string literal that evaluates to `text`.
    static func literal(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// The AppleScript that runs `command` as an administrator.
    static func privilegedSource(_ command: String) -> String { "do shell script \"" + literal(command) + "\" " + privilegedSuffix }

    /// Runs `command` as an administrator through the system prompt.
    @discardableResult
    static func runPrivileged(_ command: String) throws -> NSAppleEventDescriptor { try AppleScript.run(privilegedSource(command)) }
}
