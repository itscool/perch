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
    enum Phase: Equatable { case moving, done, failed, cancelled }
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

    /// The person pressed Cancel: stop, and close at once.
    func cancel() {
        guard phase == .moving else { return }
        phase = .cancelled
        changed()
        onCancel()
        close()
    }

    private func end(_ next: Phase, line: String, hold: Double) {
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
        }
    }

    /// Why it did not arrive, in one short line.
    static func line(for reason: DeskClipboardReason, from name: String) -> String {
        switch reason {
        case .peerGone, .timedOut, .notSupported, .format: return "Couldn’t reach \(name)"
        case .sharingOff: return "Sharing is off on \(name)"
        case .sharingOffHere: return "Sharing is off on this Mac"
        case .changed, .unknownCopy: return "It changed on \(name) before it arrived"
        case .tooLarge: return "Too large to bring over"
        case .noSpace: return "Not enough space on this Mac"
        case .folders: return "Folders aren’t brought over yet"
        case .links: return "Links and aliases aren’t brought over"
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
