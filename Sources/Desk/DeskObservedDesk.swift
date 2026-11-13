import Foundation

/// What each screen on the desk is showing, worked out from what the Macs can
/// see rather than from what Perch last told the monitors.
///
/// A Mac knows which screens it is showing on. A monitor that switches to
/// another input drops the Mac that was on it, and that Mac's display goes
/// away. Put together, the Macs' own display reports are the desk. They settle
/// which preset is active and whether a switch worked. Monitors such as LG's
/// never report their input, and judging from Perch's own commands left every
/// switch "accepted without readback" and the active preset a guess.
enum DeskScreenState: Equatable {
    /// Exactly one Mac sees the screen: it is showing that Mac.
    case showing(UUID)
    /// Every Mac cabled to the screen has reported and none of them sees it:
    /// it is on another source, such as a PC without Perch.
    case elsewhere
    /// The Macs cannot settle it. Several see it, because some monitors keep a
    /// link alive on an input they are not showing, or a Mac cabled to it has
    /// not reported.
    case unknown
}

enum DeskObservedDesk {
    /// - seenBy: Macs reporting a live display that is this screen. A display
    ///   Perch let go of on purpose is not counted: that Mac is not showing.
    /// - cabled: Perch Macs with a cable to this screen. A PC never reports,
    ///   so it is not waited for.
    /// - reporting: Macs that are online and have reported their displays.
    static func state(seenBy: Set<UUID>, cabled: Set<UUID>, reporting: Set<UUID>) -> DeskScreenState {
        if seenBy.count == 1, let only = seenBy.first { return .showing(only) }
        if seenBy.isEmpty, !cabled.isEmpty, cabled.isSubset(of: reporting) { return .elsewhere }
        return .unknown
    }

    /// Whether a preset's choice for one screen agrees with what it shows.
    /// The screens decide whenever they can; the monitor's own report, else
    /// the last command, only when they cannot. `perch` is the desk's Perch
    /// Macs: a screen none of them sees is on a computer outside that set.
    static func agrees(_ state: DeskScreenState, computer: UUID?, perch: Set<UUID>, input: UInt16?, fallback: UInt16?) -> Bool {
        switch state {
        case .showing(let mac): return computer == mac
        case .elsewhere: return computer.map { !perch.contains($0) } ?? true
        case .unknown: return input != nil && fallback == input
        }
    }

    /// One line for the log: each screen, what it shows and why, then the preset.
    static func summary(_ screens: [(name: String, state: DeskScreenState)], name: (UUID) -> String, preset: String?) -> String {
        let parts = screens.map { screen -> String in
            switch screen.state {
            case .showing(let mac): return "\(screen.name) shows \(name(mac)) (only \(name(mac)) sees it)"
            case .elsewhere: return "\(screen.name) shows another source (no Mac sees it)"
            case .unknown: return "\(screen.name) unknown from the screens"
            }
        }
        return parts.joined(separator: "; ") + " → " + (preset.map { "preset " + $0 } ?? "no preset matches")
    }
}
