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
        // Center content while it fits. Once it is wider/taller than the
        // viewport, keep a small, stable inset instead of centering it in an
        // oversized scroll region. That keeps resizing from moving the
        // visible group to a different anchor point.
        origin = CGPoint(x: max(16, (viewport.width - bounds.width * scale) / 2),
                         y: max(16, (viewport.height - bounds.height * scale) / 2))
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

    /// A physical millimetre point rendered into the graph area.
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + (x - bounds.minX) * scale, y: origin.y + (y - bounds.minY) * scale)
    }
}

/// The whole desk surface, derived from one viewport: the graph area, its
/// layout, and the finite document that also holds the computer row. While
/// the arrangement fits, the document is exactly the viewport, so there is
/// never dead space below the computers; it grows only when the tiles would
/// otherwise shrink below their readable minimum.
struct DeskCanvasGeometry: Equatable {
    static let padding: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    let viewport: CGSize
    let graphSize: CGSize
    let layout: DeskCanvasLayout
    let documentSize: CGSize
    init(rectangles: [CGRect], viewport: CGSize, computersHeight: CGFloat) {
        let minimumScale = DeskCanvasLayout.minimumScale(for: rectangles)
        let rows = max(0, computersHeight)
        let available = CGSize(width: max(1, viewport.width - 2 * Self.padding),
                               height: max(120, viewport.height - 2 * Self.padding - Self.rowSpacing - rows))
        let fitting = DeskCanvasLayout(rectangles: rectangles, viewport: available, minimumScale: minimumScale)
        let needed = CGSize(width: fitting.bounds.width * fitting.scale + 32, height: fitting.bounds.height * fitting.scale + 32)
        graphSize = CGSize(width: max(available.width, needed.width), height: max(available.height, needed.height))
        layout = DeskCanvasLayout(rectangles: rectangles, viewport: graphSize, minimumScale: minimumScale)
        documentSize = CGSize(width: graphSize.width + 2 * Self.padding,
                              height: graphSize.height + Self.rowSpacing + rows + 2 * Self.padding)
        self.viewport = viewport
    }
}
extension DeskCanvasLayout: Equatable {
    static func == (a: DeskCanvasLayout, b: DeskCanvasLayout) -> Bool { a.bounds == b.bounds && a.scale == b.scale && a.origin == b.origin }
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
        // Docking normally resolves a collision in one pass. Keep a final
        // deterministic escape hatch for dense layouts and tenth-millimetre
        // rounding: never hand the model a rectangle that still intersects a
        // neighbour after the snap/alignment pass.
        if !valid(result) {
            for _ in 0..<others.count + 2 where !valid(result) {
                var candidates: [(CGRect, CGFloat)] = []
                for other in others {
                    let overlap = result.intersection(other)
                    guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                    let epsilon: CGFloat = 0.1
                    candidates.append((result.offsetBy(dx: -(overlap.width + epsilon), dy: 0), overlap.width + epsilon))
                    candidates.append((result.offsetBy(dx: overlap.width + epsilon, dy: 0), overlap.width + epsilon))
                    candidates.append((result.offsetBy(dx: 0, dy: -(overlap.height + epsilon)), overlap.height + epsilon))
                    candidates.append((result.offsetBy(dx: 0, dy: overlap.height + epsilon), overlap.height + epsilon))
                }
                guard let next = candidates.filter({ valid($0.0) }).min(by: { $0.1 < $1.1 })?.0 else { break }
                result = next
            }
        }
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
        // Alignment can move a just-rescued rectangle back into a neighbour.
        // Run the same finite escape once more after alignment.
        if !valid(result) {
            for other in others where !result.intersection(other).isNull {
                let overlap = result.intersection(other)
                guard overlap.width > 0, overlap.height > 0 else { continue }
                let epsilon: CGFloat = 0.1
                let options = [
                    result.offsetBy(dx: -(overlap.width + epsilon), dy: 0),
                    result.offsetBy(dx: overlap.width + epsilon, dy: 0),
                    result.offsetBy(dx: 0, dy: -(overlap.height + epsilon)),
                    result.offsetBy(dx: 0, dy: overlap.height + epsilon)
                ]
                if let safe = options.first(where: valid) { result = safe; break }
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
}

/// What letting go of a wire does. The rules, as Scott set them:
/// - An unconnected input can draw a new wire from either side.
/// - A connected input detaches when dragged, so it can be rewired.
/// - A drag from a computer always creates a new connection.
/// - Either end dropped in empty space disappears.
enum DeskWireOutcome: Equatable {
    case nothing, click
    /// This computer uses the input in this preset, claiming the input for it.
    case draw(slot: Int, computer: UUID, port: UUID)
    /// A detached connection's monitor end moves to another input.
    case move(from: UUID, to: UUID)
    /// A detached connection dropped in empty space.
    case remove(port: UUID)

    static func resolve(source: String, target: String?, dragging: Bool, insideSource: Bool, detached: UUID?) -> Self {
        guard dragging else { return insideSource ? .click : .nothing }
        if let detached {
            guard let target else { return .remove(port: detached) }
            guard let port = portID(target), port != detached else { return .nothing }
            return .move(from: detached, to: port)
        }
        guard let target else { return .nothing }
        if let port = portID(source), let socket = presetSocket(target) { return .draw(slot: socket.slot, computer: socket.computer, port: port) }
        if let port = portID(target), let socket = presetSocket(source) { return .draw(slot: socket.slot, computer: socket.computer, port: port) }
        return .nothing
    }
    static func portID(_ id: String) -> UUID? { id.hasPrefix("port:") ? UUID(uuidString: String(id.dropFirst(5))) : nil }
    static func presetSocket(_ id: String) -> (computer: UUID, slot: Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "preset", let computer = UUID(uuidString: String(parts[1])),
              let slot = Int(parts[2]), (1...3).contains(slot) else { return nil }
        return (computer, slot)
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
