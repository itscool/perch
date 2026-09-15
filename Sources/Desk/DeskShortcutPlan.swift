import Foundation

/// The Desk's hotkeys for one registration pass, and where each problem is
/// shown: preset problems on the Desk preset shortcuts, sharing problems on
/// Share on this Mac. A problem with one never hides behind the other.
struct DeskShortcutPlan {
    struct Binding: Equatable { let preset: UUID; let shortcut: Shortcut }
    var presets: [Binding] = []
    var sharing: Shortcut
    var presetProblem: String?
    var sharingProblem: String?

    /// `problem` answers whether a shortcut collides with another Perch action,
    /// excluding the named source (the registry's `problem(with:excluding:)`).
    static func make(presets: [KVMPreset], sharing: Shortcut, problem: (Shortcut, String) -> String?) -> DeskShortcutPlan {
        var plan = DeskShortcutPlan(sharing: sharing)
        for preset in presets {
            guard let shortcut = preset.shortcut.local else {
                plan.presetProblem = "This Mac cannot register \(preset.shortcut.label). Change the shortcut in App settings → Hotkeys."
                plan.presets = []; break
            }
            if let issue = problem(shortcut, ShortcutRegistry.Source.deskPresets) { plan.presetProblem = issue; plan.presets = []; break }
            plan.presets.append(.init(preset: preset.id, shortcut: shortcut))
        }
        if sharing.enabled, let issue = problem(sharing, ShortcutRegistry.Source.deskSharing) { plan.sharingProblem = issue }
        return plan
    }
}

/// Remembers the inputs of the last complete registration so an unchanged
/// desk is not re-registered, while a failed pass is retried on the next one.
struct DeskShortcutRegistrationMemory {
    private var registered: (claims: [ShortcutClaim], presets: [KVMPreset])?
    func needsRegistration(claims: [ShortcutClaim], presets: [KVMPreset]) -> Bool {
        guard let registered else { return true }
        return registered.claims != claims || registered.presets != presets
    }
    mutating func finished(claims: [ShortcutClaim], presets: [KVMPreset], succeeded: Bool) {
        registered = succeeded ? (claims, presets) : nil
    }
    mutating func reset() { registered = nil }
}
