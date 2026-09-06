import Foundation

struct LidSettingResult {
    let enabled: Bool?
    let error: String?
    var title: String {
        enabled.map { "Stay awake with lid closed: " + ($0 ? "On" : "Off") } ?? "Couldn’t confirm the lid-close setting"
    }
    var detail: String {
        let state = enabled.map { $0 ? "The Mac currently stays awake with the lid closed.\n\n⚠ Keep ventilated" : "Currently sleeps on lid close." }
            ?? "Perch could not read the current setting. Reopen the menu to check it."
        return state + (error.map { "\n\n" + $0 } ?? "")
    }
}

enum LidSettingChange {
    /// Report the actual state after success, cancellation or failure. Never
    /// present the requested value as if authorization had already succeeded.
    static func run(read: () throws -> Bool, write: (Bool) throws -> Void) -> LidSettingResult {
        var failure: String?
        do { try write(!read()) } catch { failure = error.localizedDescription }
        return LidSettingResult(enabled: try? read(), error: failure)
    }
}
