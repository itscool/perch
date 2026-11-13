import Foundation

/// What the menu bar icon shows about the desk and its clipboard, as one small
/// value, computed in one place and pinned by tests, so the icon only has to
/// draw it (`PerchIconState`, `perchStatusImage`).
struct DeskShareStatus: Equatable {
    /// A copy on another Mac is newer than anything on this one: which Mac has
    /// it, and what it is (kind, count, size bucket). Nil when nothing waits.
    var waitingFrom: String?
    var waiting: DeskClipboardDescriptor?
    /// Share on this Mac.
    var sharingOn: Bool
    /// How many other Perches are connected now.
    var connected: Int
    /// Whether any of them takes part in the preset that is active now.
    var onActiveDesk: Bool
    /// How many of them have their own sharing on, as far as this Mac knows.
    /// Only a Mac whose sharing is on hears this, so it is 0 while it is off.
    var othersSharing: Int = 0

    static let idle = DeskShareStatus(waitingFrom: nil, waiting: nil, sharingOn: false, connected: 0, onActiveDesk: false)

    /// `sharing`: the Macs whose keyboard and mouse sharing is on and ready
    /// (`KVMInputSession.sharingComputers`).
    static func make(waitingFrom: String?, waiting: DeskClipboardDescriptor?, sharingOn: Bool, online: Set<UUID>, local: UUID,
                     group: KVMGroup, activePreset: UUID?, sharing: Set<UUID> = []) -> Self {
        let others = online.subtracting([local])
        var inPreset: Set<UUID> = []
        if let preset = group.presets.first(where: { $0.id == activePreset }) {
            for assignment in preset.assignments {
                if let computer = group.connections.first(where: { $0.id == assignment.connection })?.computer { inPreset.insert(computer) }
            }
        }
        return .init(waitingFrom: waiting == nil ? nil : waitingFrom, waiting: waitingFrom == nil ? nil : waiting, sharingOn: sharingOn,
                     connected: others.count, onActiveDesk: !others.isDisjoint(with: inPreset), othersSharing: others.intersection(sharing).count)
    }

    /// The icon for this status. The envelope shows only while sharing is on
    /// here (Scott, November 2026); the hearts and the other bird follow the
    /// facts above.
    func icon(awake: Bool) -> PerchIconState {
        PerchIconState(awake: awake, waiting: waiting != nil && sharingOn, others: connected, sharingHere: sharingOn,
                       sharingThere: connected > 0 && othersSharing > 0, otherActive: onActiveDesk)
    }
}
