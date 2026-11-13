import Foundation

/// Shows a `DeskPasteProgress` on screen. The AppKit panel implements it; tests
/// and the network fixture use a recorder.
protocol DeskPastePresenting: AnyObject {
    func present(_ progress: DeskPasteProgress)
}

/// The little popup that says another Mac's copy is on its way here, as logic
/// only: what it says, how far along it is, when it closes, and its one action.
/// The panel that draws it holds no state of its own, so all of this is pinned
/// by fast tests without a window.
///
/// Scott's rule (September 27, 2026): anything but small text is brought over
/// with ⌃⌥⌘V, with a small progress popup that closes itself when done. After
/// that every ordinary paste works.
final class DeskPasteProgress {
    /// `informed`: nothing was coming; the popup only says why, in its title.
    enum Phase: Equatable { case moving, done, failed, cancelled, informed }
    /// Long enough that a transfer over the cable does not flash for one frame.
    static let minimumVisible = 0.5
    /// "Ready to paste" stays this long once it is here, then the popup closes.
    static let doneVisible = 1.0
    /// A failure's one line stays this long. Bringing it over again retries.
    static let failureVisible = 3.0

    let title: String
    private(set) var phase = Phase.moving
    private(set) var fraction = 0.0
    /// The one line under the title once it is over: "Ready to paste", or why
    /// it did not arrive. Nil while moving.
    private(set) var line: String?
    private(set) var isClosed = false
    let shownAt: Double
    private let clock: () -> Double
    private let after: (Double, @escaping () -> Void) -> Void
    private var reported = 0.0
    /// Redraw. Called on the main thread, at most once per percent of progress.
    var changed: () -> Void = {}
    /// Take the popup off the screen. Called once.
    var closed: () -> Void = {}
    /// The person pressed Cancel. Stops the transfer.
    var onCancel: () -> Void = {}

    init(title: String, clock: @escaping () -> Double, after: @escaping (Double, @escaping () -> Void) -> Void) {
        self.title = title; self.clock = clock; self.after = after
        shownAt = clock()
    }

    /// Only a transfer still on its way can be cancelled: stopping it is the one
    /// thing only the person can decide, so Cancel is the popup's only action.
    var canCancel: Bool { phase == .moving }

    func advance(to value: Double) {
        guard phase == .moving, value.isFinite else { return }
        fraction = min(1, max(fraction, value))
        guard fraction - reported >= 0.01 || (fraction == 1 && reported < 1) else { return }
        reported = fraction
        changed()
    }

    /// Here: say so briefly, then close.
    func finish() { end(.done, line: "Ready to paste", hold: Self.doneVisible) }
    /// One short factual line, then close. No retry button.
    func fail(_ line: String) { end(.failed, line: line, hold: Self.failureVisible) }
    /// Nothing is coming, and the title already says why: show it, then close.
    func inform() { end(.informed, line: nil, hold: Self.failureVisible) }

    /// The person pressed Cancel: stop, and close at once.
    func cancel() {
        guard phase == .moving else { return }
        phase = .cancelled
        changed()
        onCancel()
        close()
    }

    private func end(_ next: Phase, line: String?, hold: Double) {
        guard phase == .moving else { return }
        phase = next; self.line = line
        if next == .done { fraction = 1 }
        changed()
        let now = clock()
        let closeAt = max(shownAt + Self.minimumVisible, now + hold)
        after(max(0, closeAt - now)) { [weak self] in self?.close() }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        closed()
    }

    // MARK: Words

    /// What is coming, in plain feature terms: "A photo from Studio".
    static func title(_ what: DeskClipboardDescriptor, from name: String) -> String {
        switch what.kind {
        case .text: return "Text from \(name)"
        case .image: return what.count == 1 ? "A photo from \(name)" : "\(what.count) photos from \(name)"
        case .files: return what.count == 1 ? "A file from \(name)" : "\(what.count) files from \(name)"
        case .folders: return what.count == 1 ? "A folder from \(name)" : "\(what.count) items from \(name)"
        }
    }

    /// Why the newest copy on another Mac stays there, in one sentence, when
    /// ⌃⌥⌘V finds it cannot come (Scott, November 2026: invisible when copied,
    /// "shown on the screen if you try to paste them anyway").
    static func explain(_ refusal: DeskClipboardRefusal, from name: String) -> String {
        let copy = "The newest copy on \(name)"
        let over = refusal.amount.map(amountText), limit = refusal.limit
        switch refusal.reason {
        case .concealed: return "\(copy) is private, so it stays there."
        case .transient: return "\(copy) was marked temporary by its app, so it stays there."
        case .autoGenerated: return "\(copy) was made automatically, so it stays there."
        case .tooLarge:
            if let over, let limit { return "\(copy) is \(over); the limit is \(amountText(limit))." }
            return "\(copy) is larger than Perch brings over."
        case .fileTooLarge:
            if let over, let limit { return "A file in the newest copy on \(name) is \(over); the limit is \(amountText(limit))." }
            return "A file in the newest copy on \(name) is larger than Perch brings over."
        case .tooMany:
            if let limit { return "\(copy) holds more than \(grouped(limit)) items." }
            return "\(copy) holds more items than Perch brings over."
        case .tooDeep:
            if let limit { return "\(copy) has folders more than \(limit) deep." }
            return "\(copy) has folders deeper than Perch brings over."
        case .links: return "\(copy) is a link or alias, so it stays there."
        case .linkOutside: return "\(copy) links to something outside it, so it stays there."
        case .unreadable: return "A file in the newest copy on \(name) can’t be read."
        case .unsupported: return "\(copy) isn’t text, an image, files or folders."
        case .readTimedOut: return "The app on \(name) didn’t hand over its newest copy."
        default: return "\(copy) can’t be brought over."
        }
    }

    /// A size as a person reads it, in the binary units Perch's limits are set
    /// in: "3.4 GB", "2 GB", "50 MB". Rounded up, so an amount over a limit
    /// never reads as the limit itself. Shown on screen only, never logged.
    static func amountText(_ bytes: UInt64) -> String {
        let units: [(Double, String)] = [(1_073_741_824, "GB"), (1_048_576, "MB"), (1024, "KB")]
        for (size, unit) in units where Double(bytes) >= size {
            let value = Double(bytes) / size
            let rounded = value < 10 ? (value * 10).rounded(.up) / 10 : value.rounded(.up)
            let text = rounded == rounded.rounded(.down) ? String(Int(rounded)) : String(format: "%.1f", rounded)
            return "\(text) \(unit)"
        }
        return "\(bytes) bytes"
    }

    /// "10,000": the same on every Mac, whatever its region.
    static func grouped(_ value: UInt64) -> String {
        var digits = String(value), groups: [String] = []
        while digits.count > 3 { groups.insert(String(digits.suffix(3)), at: 0); digits.removeLast(3) }
        return ([digits] + groups).joined(separator: ",")
    }

    /// Why it did not arrive, in one short line: the sentence with its sizes
    /// when it went over a limit, otherwise the reason.
    static func line(for refusal: DeskClipboardRefusal, from name: String) -> String {
        if refusal.amount != nil || refusal.limit != nil { return explain(refusal, from: name) }
        return line(for: refusal.reason, from: name)
    }

    /// Why it did not arrive, in one short line.
    static func line(for reason: DeskClipboardReason, from name: String) -> String {
        switch reason {
        case .peerGone, .timedOut, .notSupported, .format: return "Couldn’t reach \(name)"
        case .sharingOff: return "Sharing is off on \(name)"
        case .sharingOffHere: return "Sharing is off on this Mac"
        case .changed, .unknownCopy: return "It changed on \(name) before it arrived"
        case .tooLarge, .fileTooLarge, .tooMany, .tooDeep: return "Too large to bring over"
        case .noSpace: return "Not enough space on this Mac"
        case .links: return "Links and aliases aren’t brought over"
        case .linkOutside: return "It holds a link to something outside it"
        case .unreadable: return "A file couldn’t be read on \(name)"
        case .corrupt: return "It arrived damaged"
        case .newerHere: return "Something newer was copied here"
        case .newerThere: return "Something newer was copied on another Mac"
        case .readTimedOut: return "The app on \(name) didn’t hand it over"
        case .busy, .rateLimited: return "\(name) is busy"
        case .writeFailed, .quarantine, .unsafeName: return "This Mac couldn’t keep it"
        case .cancelled: return "Cancelled"
        case .concealed, .transient, .autoGenerated, .unsupported, .noCopy, .notReady, .received:
            return "Couldn’t bring it over"
        }
    }
}
