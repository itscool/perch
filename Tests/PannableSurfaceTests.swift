import CoreGraphics

/// Regression coverage for the shared surface contract. These are deliberately
/// pure geometry tests: narrow and short settings windows must not need a
/// native window or a live Desk model to prove their document remains finite.
func runPannableSurfaceTests() throws {
    func check(_ value: Bool, _ message: String) throws {
        if !value { throw AppError(message: "Pannable surface: " + message) }
    }

    let content = CGSize(width: 900, height: 620)
    for viewport in [CGSize(width: 1200, height: 900),
                     CGSize(width: 600, height: 360),
                     CGSize(width: 220, height: 150),
                     CGSize(width: 0, height: 0)] {
        let layout = PannableSurfaceLayout(content: content, viewport: viewport, inset: 12)
        try check(layout.document.width.isFinite && layout.document.height.isFinite,
                  "document escaped finite bounds at \(viewport)")
        try check(layout.document.width >= layout.viewport.width && layout.document.height >= layout.viewport.height,
                  "document was smaller than its viewport at \(viewport)")
        try check(layout.overflow.width >= 0 && layout.overflow.height >= 0,
                  "overflow became negative at \(viewport)")
        let lowerRight = PannableSurfaceLayout.clampedOffset(
            CGSize(width: -100_000, height: -100_000), content: content, viewport: viewport)
        try check(lowerRight.width == -layout.overflow.width && lowerRight.height == -layout.overflow.height,
                  "pan did not clamp to the document edge at \(viewport)")
        try check(PannableSurfaceLayout.clampedOffset(
            CGSize(width: 100, height: 100), content: content, viewport: viewport) == .zero,
            "positive pan exposed space before the document at \(viewport)")
    }

    let inset = PannableSurfaceLayout(content: CGSize(width: 180, height: 100),
                                      viewport: CGSize(width: 160, height: 80), inset: 10)
    try check(inset.document == CGSize(width: 200, height: 120),
              "border inset was omitted from the one measured document")
    let damaged = PannableSurfaceLayout(content: CGSize(width: CGFloat.nan, height: CGFloat.infinity),
                                         viewport: CGSize(width: CGFloat.nan, height: -CGFloat.infinity), inset: CGFloat.nan)
    try check(damaged.document == .zero && damaged.viewport == .zero,
              "non-finite measurements were allowed into the surface")
    print("PASS: pannable surface finite document sizing, inset accounting and bounded pan across wide, narrow, short and empty viewports")
}
