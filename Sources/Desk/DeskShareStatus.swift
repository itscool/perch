import Foundation

/// What the menu bar icon will show about the desk and its clipboard, as one
/// small value. The icon itself is not changed: Scott is settling its design
/// first. This is the state it will read, computed in one place and pinned by
/// tests, so the icon only has to draw it.
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

    static let idle = DeskShareStatus(waitingFrom: nil, waiting: nil, sharingOn: false, connected: 0, onActiveDesk: false)

    static func make(waitingFrom: String?, waiting: DeskClipboardDescriptor?, sharingOn: Bool, online: Set<UUID>, local: UUID,
                     group: KVMGroup, activePreset: UUID?) -> Self {
        let others = online.subtracting([local])
        var inPreset: Set<UUID> = []
        if let preset = group.presets.first(where: { $0.id == activePreset }) {
            for assignment in preset.assignments {
                if let computer = group.connections.first(where: { $0.id == assignment.connection })?.computer { inPreset.insert(computer) }
            }
        }
        return .init(waitingFrom: waiting == nil ? nil : waitingFrom, waiting: waitingFrom == nil ? nil : waiting, sharingOn: sharingOn,
                     connected: others.count, onActiveDesk: !others.isDisjoint(with: inPreset))
    }
}
