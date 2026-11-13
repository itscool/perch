import AppKit

/// What the menu bar icon shows, as plain facts. Built from the desk's share
/// status (`DeskShareStatus.icon`); drawn by `perchStatusImage`. Nothing here
/// reads the desk itself, so every state can be drawn offscreen and pinned.
///
/// Scott's design, November 2026:
/// - The bird is this Mac. With the cup, Perch is keeping it awake (as before).
/// - Two birds face each other while any other Perch is connected; this Mac's
///   bird is on the left.
/// - A heart in this Mac's bird: Share on this Mac is on. A heart in the other
///   bird: at least one connected Mac shares too.
/// - The other bird is greyed while none of the connected Macs is in the
///   active preset, or no preset is active.
/// - A small number in the other bird: how many other Perches are connected,
///   when more than one.
/// - The envelope, where the cup goes but at the top: another Mac has a newer
///   copy waiting for ⌃⌥⌘V. Only while sharing is on here.
struct PerchIconState: Equatable, Hashable {
    var awake = false
    var waiting = false
    /// Other Perches connected now.
    var others = 0
    var sharingHere = false
    var sharingThere = false
    /// At least one connected Mac takes part in the active preset.
    var otherActive = false

    /// The number in the other bird: nothing for one Mac, then 2 to 9, then "9+".
    var countText: String? {
        guard others > 1 else { return nil }
        return others > 9 ? "9+" : String(others)
    }
    /// A short stable description, so the image is rebuilt only when it changes.
    var key: String {
        [awake ? "awake" : "bird", waiting ? "mail" : "", "peers\(others)", sharingHere ? "here" : "", sharingThere ? "there" : "",
         otherActive ? "active" : "idle"].joined(separator: "-")
    }
    /// Words for VoiceOver, in the order the icon reads. The awake bird alone
    /// says exactly what it always said.
    var accessibility: String {
        var parts: [String] = []
        if awake { parts.append("keeping Mac awake") }
        if others > 0 { parts.append(others == 1 ? "1 other Mac connected" : "\(others) other Macs connected") }
        if sharingHere { parts.append("sharing on") }
        if others > 0, sharingThere { parts.append("another Mac shares") }
        if others > 0, !otherActive { parts.append("not in the active preset") }
        if waiting { parts.append("a copy waits on another Mac") }
        return parts.isEmpty ? "Perch" : "Perch — " + parts.joined(separator: ", ")
    }
}

/// How the icon is laid out, in points, on an 18-point-high canvas. The single
/// bird and its cup keep exactly the places they always had.
enum PerchIconLayout {
    static let height: CGFloat = 18
    static let single = NSRect(x: 0, y: 2, width: 17, height: 16)
    static let singleWidth: CGFloat = 22
    static let cup = NSRect(x: 12, y: 0, width: 10, height: 8)
    /// Two birds: smaller, beak to beak, with the envelope above the beaks and
    /// the cup below them, between the birds.
    static let pairWidth: CGFloat = 30
    static let left = NSRect(x: 0, y: 2, width: 13.5, height: 13)
    static let right = NSRect(x: 16.5, y: 2, width: 13.5, height: 13)
    static let pairCup = NSRect(x: 11.25, y: 0, width: 7.5, height: 5.6)
    static let pairEnvelope = NSRect(x: 10.25, y: 12.4, width: 9.5, height: 5.6)
    static let singleEnvelope = NSRect(x: 12, y: 11, width: 10, height: 7)
    /// Where a heart or a number sits inside a bird, as fractions of its frame
    /// (the body, between the wing and the head; the bird faces right).
    static let body = CGPoint(x: 0.55, y: 0.385)
    static let wing = CGPoint(x: 0.25, y: 0.62)
    static let heart: CGFloat = 0.34
    /// A greyed bird's opacity: the template's alpha, so macOS lightens it.
    static let greyed: CGFloat = 0.38
    /// The clear ring cut around an overlay so it reads against the bird.
    static let knockout: CGFloat = 1
}

/// A single template image lets macOS provide menu-bar contrast in either
/// theme; alpha carries the greyed bird.
func perchStatusImage(_ state: PerchIconState) -> NSImage? {
    guard let bird = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch") else { return nil }
    let symbols = (cup: NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil),
                   envelope: NSImage(systemSymbolName: "envelope", accessibilityDescription: nil),
                   heart: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil))
    let pair = state.others > 0
    // Exactly the old image when there is nothing new to show.
    if !pair, !state.sharingHere, !state.waiting, !state.awake {
        bird.accessibilityDescription = state.accessibility
        return bird
    }
    let width = pair ? PerchIconLayout.pairWidth : PerchIconLayout.singleWidth
    let image = NSImage(size: NSSize(width: width, height: PerchIconLayout.height), flipped: false) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        func inner(_ frame: NSRect, _ point: CGPoint, mirrored: Bool) -> CGPoint {
            CGPoint(x: frame.minX + frame.width * (mirrored ? 1 - point.x : point.x), y: frame.minY + frame.height * point.y)
        }
        /// Cut a clear ring of `ring` points around where `draw` will paint,
        /// then paint it. `draw` paints with the operation it is given: an
        /// image sets its own compositing, so the clear pass must be explicit.
        func overlay(ring: CGFloat = PerchIconLayout.knockout, _ draw: (NSCompositingOperation) -> Void) {
            context.saveGState()
            context.setBlendMode(.destinationOut)
            let k = ring, d = ring * 0.7
            for (dx, dy) in [(-k, 0), (k, 0), (0, -k), (0, k), (-d, -d), (d, d), (-d, d), (d, -d)] {
                context.saveGState(); context.translateBy(x: dx, y: dy); draw(.destinationOut); context.restoreGState()
            }
            context.restoreGState()
            draw(.sourceOver)
        }
        func symbol(_ image: NSImage?, in rect: NSRect) {
            guard let image else { return }
            overlay { operation in image.draw(in: rect, from: .zero, operation: operation, fraction: 1) }
        }
        func heart(in frame: NSRect, mirrored: Bool) {
            guard let heart = symbols.heart else { return }
            let size = frame.width * PerchIconLayout.heart
            let center = inner(frame, PerchIconLayout.body, mirrored: mirrored)
            let rect = NSRect(x: center.x - size / 2, y: center.y - size * 0.45, width: size, height: size * 0.9)
            overlay(ring: PerchIconLayout.knockout / 2) { operation in heart.draw(in: rect, from: .zero, operation: operation, fraction: 1) }
        }
        if pair {
            bird.draw(in: PerchIconLayout.left)
            // The other bird, turned to face this one, greyed when it is not
            // in the active preset.
            context.saveGState()
            context.setAlpha(state.otherActive ? 1 : PerchIconLayout.greyed)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.translateBy(x: PerchIconLayout.right.maxX + PerchIconLayout.right.minX, y: 0)
            context.scaleBy(x: -1, y: 1)
            bird.draw(in: PerchIconLayout.right)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -(PerchIconLayout.right.maxX + PerchIconLayout.right.minX), y: 0)
            if state.sharingThere { heart(in: PerchIconLayout.right, mirrored: true) }
            if let count = state.countText {
                let font = NSFont.systemFont(ofSize: count.count > 1 ? 5 : 6.5, weight: .heavy)
                let text = NSAttributedString(string: count, attributes: [.font: font, .foregroundColor: NSColor.black])
                let size = text.size()
                var center = inner(PerchIconLayout.right, PerchIconLayout.wing, mirrored: true)
                center.x = min(center.x, PerchIconLayout.pairWidth - size.width / 2 - PerchIconLayout.knockout)
                // Text follows the context's blend mode, so the clear pass works as is.
                overlay { _ in text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)) }
            }
            context.endTransparencyLayer()
            context.restoreGState()
            if state.sharingHere { heart(in: PerchIconLayout.left, mirrored: false) }
            if state.awake { symbol(symbols.cup, in: PerchIconLayout.pairCup) }
            if state.waiting { symbol(symbols.envelope, in: PerchIconLayout.pairEnvelope) }
        } else {
            bird.draw(in: PerchIconLayout.single)
            if state.sharingHere { heart(in: PerchIconLayout.single, mirrored: false) }
            if state.awake, let cup = symbols.cup { cup.draw(in: PerchIconLayout.cup) }
            if state.waiting { symbol(symbols.envelope, in: PerchIconLayout.singleEnvelope) }
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = state.accessibility
    return image
}
