import Foundation

/// Fit the physical arrangement, including rotated/negative-coordinate screens,
/// into the viewport. This transform never changes saved monitor geometry.
struct DeskCanvasLayout {
    let bounds: CGRect
    let scale: Double
    let origin: CGPoint
    init(rectangles: [CGRect], viewport: CGSize) {
        bounds = rectangles.reduce(CGRect.null) { $0.union($1) }.isNull ? CGRect(x: 0, y: 0, width: 700, height: 500) : rectangles.reduce(CGRect.null) { $0.union($1) }
        scale = max(0.000001, min(max(1, viewport.width - 32) / max(1, bounds.width), max(1, viewport.height - 32) / max(1, bounds.height)))
        origin = CGPoint(x: (viewport.width - bounds.width * scale) / 2, y: (viewport.height - bounds.height * scale) / 2)
    }
}

/// Pure drop calculation in physical millimetres. Snap tolerance is in screen
/// points so it feels the same at every zoom level. Free gaps remain valid.
enum DeskScreenPlacement {
    static func place(_ proposed: CGRect, among others: [CGRect], scale: Double, tolerance: Double = 18) -> CGRect {
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
