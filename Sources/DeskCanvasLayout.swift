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
