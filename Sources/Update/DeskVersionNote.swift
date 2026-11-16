import Foundation

/// The newest Perch in the published release feed, as Sparkle last reported it.
struct PerchRelease: Equatable {
    let build: Int
    let version: String
}

/// What the menu says about Perch versions across the desk.
///
/// A Mac can only install a published release: it fetches it from the feed
/// itself. A Mac running a local build is newer than anything published, so
/// asking the others to update to it does nothing. The rows show facts, and an
/// action only where one can work.
enum DeskVersionNote: Equatable {
    /// A published release is newer than this Mac: it can be installed here.
    case install(version: String)
    /// Another Mac runs a newer Perch than anything this Mac can fetch.
    /// `released` is false once the feed is known not to have it, nil until
    /// the feed has been read.
    case newerElsewhere(on: String, version: String, released: Bool?)

    struct Peer: Equatable { let name: String; let build: Int; let version: String }

    /// This Mac's note, if any.
    static func here(own: Int, published: PerchRelease?, peers: [Peer]) -> DeskVersionNote? {
        if let published, published.build > own { return .install(version: published.version) }
        guard let newest = peers.filter({ $0.build > own }).max(by: { $0.build < $1.build }) else { return nil }
        return .newerElsewhere(on: newest.name, version: newest.version, released: published.map { $0.build >= newest.build })
    }

    /// The Macs behind this one that could really update: only to a published
    /// release newer than what they run. None until the feed has been read.
    static func updatable(_ older: [Peer], published: PerchRelease?) -> [Peer] {
        guard let published else { return [] }
        return older.filter { $0.build < published.build }
    }

    var label: String {
        switch self {
        case .install: return "Update Perch"
        case .newerElsewhere(let on, _, _): return "Newer Perch on \(on)"
        }
    }
    /// An update reads as from → to (Scott, Nov 15), on this Mac and for others.
    func hint(own: String) -> String {
        switch self {
        case .install(let version): return "\(own) → \(version)"
        case .newerElsewhere(_, let version, let released): return released == false ? "\(version) · not released" : version
        }
    }
    /// The row on a newer Mac that updates the Macs behind it.
    static func peerHint(_ behind: [Peer], to published: PerchRelease) -> String {
        behind.count == 1 ? "\(behind[0].version) → \(published.version)" : "→ \(published.version)"
    }
    var help: String {
        switch self {
        case .install(let version):
            return "Perch \(version) is published. Install it now; Perch restarts and keeps your saved choices."
        case .newerElsewhere:
            return "Not released yet, so this Mac can’t get it. Once it’s released, this Mac can update."
        }
    }
    var actionable: Bool { if case .install = self { return true }; return false }
}
