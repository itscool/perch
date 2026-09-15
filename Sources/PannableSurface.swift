import SwiftUI
import AppKit

/// Geometry shared by pannable surfaces.
///
/// A surface has one document rectangle and one viewport.  Keeping that
/// contract in one place prevents the common failure mode where the border is
/// one scrollable view and its contents are a second, clipped viewport.
struct PannableSurfaceLayout: Equatable {
    let document: CGSize
    let viewport: CGSize

    init(content: CGSize, viewport: CGSize, inset: CGFloat = 0) {
        let safeInset = Self.finiteNonnegative(inset)
        let safeContent = CGSize(width: Self.finiteNonnegative(content.width), height: Self.finiteNonnegative(content.height))
        let safeViewport = CGSize(width: Self.finiteNonnegative(viewport.width), height: Self.finiteNonnegative(viewport.height))
        self.viewport = safeViewport
        // The document is finite and at least as large as its viewport.  This
        // gives NSScrollView a real overflow decision and avoids both infinite
        // blank space and a clipped border when a view is resized.
        self.document = CGSize(width: max(safeViewport.width, safeContent.width + safeInset * 2),
                               height: max(safeViewport.height, safeContent.height + safeInset * 2))
    }

    var overflow: CGSize {
        CGSize(width: max(0, document.width - viewport.width),
               height: max(0, document.height - viewport.height))
    }

    /// Clamp a rendered document offset to the finite scrollable area.
    /// Positive offsets are never allowed to reveal blank space before the
    /// document; the caller can use this for an empty-area drag gesture.
    static func clampedOffset(_ offset: CGSize, content: CGSize, viewport: CGSize) -> CGSize {
        let layout = Self(content: content, viewport: viewport)
        // Pan values are conventionally negative, so preserve finite negative
        // input while treating NaN/positive values as the origin.
        let x = offset.width.isFinite ? offset.width : 0
        let y = offset.height.isFinite ? offset.height : 0
        return CGSize(width: min(0, max(-layout.overflow.width, x)),
                      height: min(0, max(-layout.overflow.height, y)))
    }

    static func finiteNonnegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

/// A single finite document inside a native two-axis scroll viewport.
///
/// The caller supplies the document size after measuring its complete inner
/// layout.  The content is framed to that exact rectangle and receives a
/// stable named coordinate space, so overlays, wires and hit testing all move
/// together when the viewport scrolls.  Use `PannableSurfaceLayout` when the
/// document should include a border inset around its measured contents.
struct PannableSurface<Content: View>: View {
    let documentSize: CGSize
    let coordinateSpace: String
    let scrollerInset: CGFloat
    @Binding private var pan: CGSize
    private let viewportSize: CGSize?
    private let allowsDrag: Bool
    private let dragHitTest: ((CGPoint) -> Bool)?
    private let content: () -> Content
    @State private var dragStart: CGSize?

    init(documentSize: CGSize,
         viewportSize: CGSize? = nil,
         pan: Binding<CGSize> = .constant(.zero),
         coordinateSpace: String = "pannableSurface",
         scrollerInset: CGFloat = 8,
         allowsDrag: Bool = true,
         dragHitTest: ((CGPoint) -> Bool)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.documentSize = CGSize(width: PannableSurfaceLayout.finiteNonnegative(documentSize.width), height: PannableSurfaceLayout.finiteNonnegative(documentSize.height))
        self.viewportSize = viewportSize.map { CGSize(width: PannableSurfaceLayout.finiteNonnegative($0.width), height: PannableSurfaceLayout.finiteNonnegative($0.height)) }
        self._pan = pan
        self.coordinateSpace = coordinateSpace
        self.scrollerInset = PannableSurfaceLayout.finiteNonnegative(scrollerInset)
        self.allowsDrag = allowsDrag
        self.dragHitTest = dragHitTest
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let viewport = viewportSize ?? proxy.size
            let layout = PannableSurfaceLayout(content: documentSize, viewport: viewport)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                content()
                    .frame(width: layout.document.width, height: layout.document.height, alignment: .topLeading)
                    .coordinateSpace(name: coordinateSpace)
                    .offset(clampedPan(for: layout))
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture(for: layout))
            }
            .scrollIndicators(.visible)
            .background(PannableSurfaceScrollIndicatorConfigurator(inset: scrollerInset))
        }
    }

    private func clampedPan(for layout: PannableSurfaceLayout) -> CGSize {
        PannableSurfaceLayout.clampedOffset(pan, content: layout.document, viewport: layout.viewport)
    }

    private func dragGesture(for layout: PannableSurfaceLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                guard allowsDrag else { return }
                if dragStart == nil {
                    guard dragHitTest?(value.startLocation) ?? true else { return }
                    dragStart = pan
                }
                let start = dragStart ?? .zero
                pan = PannableSurfaceLayout.clampedOffset(
                    CGSize(width: start.width + value.translation.width,
                           height: start.height + value.translation.height),
                    content: layout.document,
                    viewport: layout.viewport)
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// SwiftUI's ScrollView is backed by NSScrollView on macOS.  Keep native
/// scrolling and accessibility while using a small overlay scroller that can
/// sit inside the surface's border inset instead of covering its content.
struct PannableSurfaceScrollIndicatorConfigurator: NSViewRepresentable {
    let inset: CGFloat

    func makeNSView(context: Context) -> PannableSurfaceScrollIndicatorProbe {
        PannableSurfaceScrollIndicatorProbe(inset: inset)
    }

    func updateNSView(_ nsView: PannableSurfaceScrollIndicatorProbe, context: Context) {
        nsView.inset = inset
        nsView.configureSoon()
    }
}

final class PannableSurfaceScrollIndicatorProbe: NSView {
    var inset: CGFloat

    init(inset: CGFloat) {
        self.inset = PannableSurfaceLayout.finiteNonnegative(inset)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureSoon()
    }

    func configureSoon() {
        DispatchQueue.main.async { [weak self] in self?.configure() }
    }

    private func configure() {
        var view: NSView? = self
        while let current = view {
            if let scroll = current as? NSScrollView {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                // Positive insets place the knobs in the rounded surface's
                // border area, leaving the readable document unobscured.
                scroll.scrollerInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
                scroll.verticalScroller = PannableSurfaceThinScroller()
                scroll.horizontalScroller = PannableSurfaceThinScroller()
                return
            }
            view = current.superview
        }
    }
}

final class PannableSurfaceThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        NSColor.secondaryLabelColor.withAlphaComponent(0.7).setFill()
        if knob.width >= knob.height {
            NSRect(x: knob.minX, y: knob.midY - 2, width: knob.width, height: 4).fill()
        } else {
            NSRect(x: knob.midX - 2, y: knob.minY, width: 4, height: knob.height).fill()
        }
    }
}
