import AppKit
import SwiftUI

/// A fixed-width inspector with an overlay scroller in its existing right margin.
/// Own the scroll view so system scroller preferences cannot resize SwiftUI fields.
struct InspectorScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> InspectorNativeScrollView {
        let scroll = InspectorNativeScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.verticalScroller = InspectorScroller()
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        let host = NSHostingView(rootView: paddedContent)
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        return scroll
    }

    func updateNSView(_ scroll: InspectorNativeScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<AnyView>)?.rootView = paddedContent
    }

    private var paddedContent: AnyView {
        // The 16-point gutter exists whether the content overflows or not.
        AnyView(content.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 16))
    }
}

final class InspectorNativeScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

/// Keep native scrolling, dragging and accessibility; draw only a slim rectangle.
final class InspectorScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let knob = rect(for: .knob)
        NSColor.secondaryLabelColor.withAlphaComponent(0.65).setFill()
        NSRect(x: knob.midX - 2, y: knob.minY, width: 4, height: knob.height).fill()
    }
}
