import Foundation
import CoreGraphics

/// Fit the physical arrangement, including rotated/negative-coordinate screens,
/// into the viewport. This transform never changes saved monitor geometry.
struct DeskCanvasLayout {
    /// The smallest card dimensions at which a screen's name, actions and
    /// connector row remain usable.  Below this the desk scrolls instead of
    /// shrinking the cards into an unlabeled pile.
    static let minimumScreenWidth: CGFloat = 145
    // Leaves room for the vertical input labels (including names such as
    // DisplayPort) and the bottom connector row.
    static let minimumScreenHeight: CGFloat = 170

    let bounds: CGRect
    let scale: Double
    let origin: CGPoint
    init(rectangles: [CGRect], viewport: CGSize, minimumScale: Double = 0) {
        bounds = rectangles.reduce(CGRect.null) { $0.union($1) }.isNull ? CGRect(x: 0, y: 0, width: 700, height: 500) : rectangles.reduce(CGRect.null) { $0.union($1) }
        let fit = min(max(1, viewport.width - 32) / max(1, bounds.width),
                      max(1, viewport.height - 32) / max(1, bounds.height))
        scale = max(0.000001, max(minimumScale, min(1, fit)))
        origin = CGPoint(x: (viewport.width - bounds.width * scale) / 2, y: (viewport.height - bounds.height * scale) / 2)
    }

    /// Returns the scale required for every card to retain its interactive
    /// contents.  A caller can use this as a lower bound and let its scroll
    /// container grow when the available viewport is smaller.
    static func minimumScale(for rectangles: [CGRect]) -> Double {
        rectangles.map { rectangle in
            max(minimumScreenWidth / max(1, rectangle.width),
                minimumScreenHeight / max(1, rectangle.height))
        }.max() ?? 0
    }
}

/// Pure drop calculation in physical millimetres. Snap tolerance is in screen
/// points so it feels the same at every zoom level. Free gaps remain valid.
enum DeskScreenPlacement {
    struct Guide: Equatable {
        let horizontal: Bool
        let position: CGFloat
        let start: CGFloat
        let end: CGFloat
        let label: String
    }
    struct Preview { let rectangle: CGRect; let guides: [Guide] }
    static func place(_ proposed: CGRect, among others: [CGRect], scale: Double, tolerance: Double = 18) -> CGRect {
        preview(proposed, among: others, scale: scale, tolerance: tolerance).rectangle
    }
    static func preview(_ proposed: CGRect, among others: [CGRect], scale: Double, tolerance: Double = 18, bypass: Bool = false) -> Preview {
        guard !bypass else { return Preview(rectangle: proposed, guides: []) }
        let threshold = tolerance / max(0.000001, scale)
        let docked = dock(proposed, among: others, scale: scale, tolerance: tolerance)
        var result = docked
        func valid(_ r: CGRect) -> Bool { !others.contains { let i = r.intersection($0); return !i.isNull && i.width > 0 && i.height > 0 } }
        // Docking owns its perpendicular axis; align along the edge independently.
        for horizontal in [false, true] {
            if horizontal ? docked.minY != proposed.minY : docked.minX != proposed.minX { continue }
            let own = horizontal ? [result.minY, result.midY, result.maxY] : [result.minX, result.midX, result.maxX]
            let candidates = others.flatMap { r -> [CGFloat] in
                let values = horizontal ? [r.minY, r.midY, r.maxY] : [r.minX, r.midX, r.maxX]
                return zip(own, values).map { $1 - $0 }
            }.filter { abs($0) <= threshold }.sorted { abs($0) < abs($1) }
            if let delta = candidates.first(where: { valid(result.offsetBy(dx: horizontal ? 0 : $0, dy: horizontal ? $0 : 0)) }) {
                result = result.offsetBy(dx: horizontal ? 0 : delta, dy: horizontal ? delta : 0)
            }
        }
        var guides: [Guide] = []
        for other in others {
            for horizontal in [false, true] {
                let own = horizontal ? [result.minY, result.midY, result.maxY] : [result.minX, result.midX, result.maxX]
                let theirs = horizontal ? [other.minY, other.midY, other.maxY] : [other.minX, other.midX, other.maxX]
                let labels = horizontal ? ["Top", "Center", "Bottom"] : ["Left", "Center", "Right"]
                for i in own.indices { for j in theirs.indices where abs(own[i] - theirs[j]) < 0.00001 && (i == j || (i != 1 && j != 1)) {
                    let start = horizontal ? min(result.minX, other.minX) : min(result.minY, other.minY)
                    let end = horizontal ? max(result.maxX, other.maxX) : max(result.maxY, other.maxY)
                    let guide = Guide(horizontal: horizontal, position: own[i], start: start, end: end, label: i == j ? labels[i] : labels[i] + " / " + labels[j])
                    if !guides.contains(guide) { guides.append(guide) }
                } }
            }
        }
        return Preview(rectangle: result, guides: guides)
    }
    private static func dock(_ proposed: CGRect, among others: [CGRect], scale: Double, tolerance: Double) -> CGRect {
        let threshold = tolerance / max(0.000001, scale)
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
            let intersection = a.intersection(b)
            return !intersection.isNull && intersection.width > 0 && intersection.height > 0
        }
        let colliding = others.contains { overlaps(proposed, $0) }
        var candidates: [(CGRect, Double)] = []
        for other in others {
            // Dock on one edge, with a free offset along it or a nearby aligned corner.
            let ys = [proposed.minY, other.minY, other.maxY - proposed.height]
            let xs = [proposed.minX, other.minX, other.maxX - proposed.width]
            for x in [other.minX - proposed.width, other.maxX] {
                for y in ys {
                    let r = CGRect(x: x, y: y, width: proposed.width, height: proposed.height)
                    if min(r.maxY, other.maxY) - max(r.minY, other.minY) > 0.01 { candidates.append((r, hypot(x-proposed.minX, y-proposed.minY))) }
                }
            }
            for y in [other.minY - proposed.height, other.maxY] {
                for x in xs {
                    let r = CGRect(x: x, y: y, width: proposed.width, height: proposed.height)
                    if min(r.maxX, other.maxX) - max(r.minX, other.minX) > 0.01 { candidates.append((r, hypot(x-proposed.minX, y-proposed.minY))) }
                }
            }
        }
        let viable = candidates.filter { candidate in
            (colliding || candidate.1 <= threshold) && !others.contains { overlaps(candidate.0, $0) }
        }
        if let best = viable.min(by: { $0.1 < $1.1 }) { return best.0 }
        return proposed
    }
}

/// A click stays a click only while it never leaves the drag deadzone.
struct DeskWireGesture {
    static let threshold: CGFloat = 3
    enum Result: Equatable { case cancel, click, connect(String, String) }
    private(set) var source: String?
    private(set) var start = CGPoint.zero
    private(set) var point = CGPoint.zero
    private(set) var dragging = false
    mutating func begin(_ source: String, at point: CGPoint) { self = Self(); self.source = source; start = point; self.point = point }
    mutating func move(to point: CGPoint) {
        guard source != nil else { return }; self.point = point
        dragging = dragging || hypot(point.x - start.x, point.y - start.y) >= Self.threshold
    }
    static func compatible(_ a: String, _ b: String) -> Bool {
        (a.hasPrefix("port:") && (b.hasPrefix("computer:") || b.hasPrefix("preset:"))) ||
        (b.hasPrefix("port:") && (a.hasPrefix("computer:") || a.hasPrefix("preset:")))
    }
    mutating func finish(insideSource: Bool, target: String?) -> Result {
        defer { self = Self() }
        guard let source else { return .cancel }
        if !dragging { return insideSource ? .click : .cancel }
        guard let target, Self.compatible(source, target) else { return .cancel }
        return .connect(source, target)
    }
}


/// Estimates the visible panel, before rotation, from its diagonal and detected ratio.
enum DeskPhysicalSize {
    static func estimate(inches: Double, aspect: Double) -> CGSize? {
        guard inches.isFinite, aspect.isFinite, (1...300).contains(inches), (0.1...10).contains(aspect) else { return nil }
        let height = inches * 25.4 / hypot(aspect, 1)
        return CGSize(width: height * aspect, height: height)
    }
}
