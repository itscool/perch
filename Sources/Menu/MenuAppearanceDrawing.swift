import AppKit

/// AppKit drawing of an appearance: section decoration on menu rows and the
/// offscreen preview host used by the settings page and the render tool.
extension MenuRowView {
    func drawDecoration(_ style: MenuSectionAppearance) {
        let stops = style.fadeStops
        let fades = !stops.isEmpty
        let context = NSGraphicsContext.current?.cgContext
        if fades { context?.saveGState(); context?.beginTransparencyLayer(auxiliaryInfo: nil) }
        defer {
            if fades, let context {
                let colors = stops.map { CGColor(gray: 0, alpha: $0.alpha) } as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: stops.map(\.location)) {
                    context.setBlendMode(.destinationIn)
                    context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.midY), end: CGPoint(x: bounds.maxX, y: bounds.midY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                context.endTransparencyLayer(); context.restoreGState()
            }
        }
        let isTitle = kind == .section
        let top = panelPart == .top, bottom = panelPart == .bottom
        let tint = appearanceTheme.palette.color(panelSection ?? "")
        func area(_ scope: MenuSectionAppearance.Scope) -> NSRect? {
            guard scope != .none, scope == .full || isTitle else { return nil }
            return NSRect(x: style.decorationMargin, y: 0, width: max(0, bounds.width - style.decorationMargin * 2), height: bounds.height - (isTitle ? style.gap : 0))
        }
        func shape(_ area: NSRect, full: Bool) -> NSBezierPath {
            var rect = area
            // Extend beyond intermediate rows so only the outer section corners round.
            if full && !top { rect.size.height += max(12, style.decorationRadius * 2) }
            if full && !bottom { rect.origin.y -= max(12, style.decorationRadius * 2); rect.size.height += max(12, style.decorationRadius * 2) }
            return NSBezierPath(roundedRect: rect, xRadius: style.decorationRadius, yRadius: style.decorationRadius)
        }
        if let rect = area(style.backgroundScope) {
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let color = style.greyBackground ? NSColor(white: style.greyLevel, alpha: 1) : tint
            color.withAlphaComponent(style.backgroundIntensity).setFill()
            shape(rect, full: style.backgroundScope == .full).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if let rect = area(style.borderScope), style.thickness > 0, !style.drawnSides.isEmpty {
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let full = style.borderScope == .full
            let clips = NSBezierPath()
            let band = style.thickness + style.decorationRadius
            if style.drawnSides.contains(.left) { clips.appendRect(NSRect(x: rect.minX, y: rect.minY, width: band, height: rect.height)) }
            if style.drawnSides.contains(.right) { clips.appendRect(NSRect(x: rect.maxX-band, y: rect.minY, width: band, height: rect.height)) }
            if style.drawnSides.contains(.top) && (!full || top) { clips.appendRect(NSRect(x: rect.minX, y: rect.maxY-band, width: rect.width, height: band)) }
            if style.drawnSides.contains(.bottom) && (!full || bottom) { clips.appendRect(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: band)) }
            clips.addClip()
            let path = shape(rect.insetBy(dx: style.thickness/2, dy: style.thickness/2), full: full)
            path.lineWidth = style.thickness
            (tint.blended(withFraction: 0.25, of: .labelColor) ?? tint).withAlphaComponent(style.borderIntensity).setStroke()
            path.stroke(); NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class MenuAppearancePreviewHost: NSView {
    var value = MenuAppearance() { didSet { needsLayout = true } }
    var dark = false { didSet { appearance = NSAppearance(named: dark ? .darkAqua : .aqua); needsLayout = true } }
    var system = false { didSet { needsLayout = true } }
    var menuRect: NSRect { bounds.insetBy(dx: 10, dy: 8) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var items: [NSMenuItem] = []
    var rows: [MenuRowView] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        // Real section order; System has all five readings. Colored editing
        // retains just its last reading as transition context.
        let sections: [(String, [(String, MenuRowView.Kind)])] = [
            ("System", [("Mac · Apple silicon", .information), ("CPU 12%", .information),
                        ("GPU 4%", .information), ("Memory 42%", .information), ("Thermal · Normal", .information)]),
            ("Agent Kill Switch", [("Panic…", .command)]),
            ("Displays", [("Turn display off", .command)]),
            ("Audio", [("Mute audio", .toggle)])
        ]
        for (section, samples) in sections {
            let contents = [(section, MenuRowView.Kind.section)] + samples
            for (index, entry) in contents.enumerated() {
                let (title, kind) = entry
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let row = MenuRowView(item: item, kind: kind)
                row.panelSection = section
                row.panelPart = index == 0 ? .top : index == contents.count - 1 ? .bottom : .middle
                row.setAccessibilityElement(false)
                items.append(item); rows.append(row); addSubview(row)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A fixed, mid-tone backdrop reveals the dropdown edge in either host
        // theme. Only the menu surface follows the preview's Light/Dark choice.
        NSColor(srgbRed: 0.64, green: 0.68, blue: 0.73, alpha: 1).setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.98, alpha: 1)).setFill()
        NSBezierPath(roundedRect: menuRect, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.18).setStroke()
        let edge = NSBezierPath(roundedRect: menuRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        edge.lineWidth = 1; edge.stroke()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(dark ? "Dark menu preview" : "Light menu preview")
        needsDisplay = true
        var y = menuRect.maxY - 4
        for row in rows {
            row.appearanceOverride = value
            let style = value.style(row.panelSection, dark: dark)
            let isSystem = row.panelSection == "System"
            let hidden = isSystem && ((!system && row.panelPart != .bottom) || (row.kind == .section && style.showTitle == false))
            let height: CGFloat = hidden ? 0 : row.kind == .section ? 22 + style.gap : 24
            y -= height
            row.frame = NSRect(x: menuRect.minX, y: y, width: menuRect.width, height: height)
            // Keep the lower rounded edge clean; show as many whole rows as fit.
            row.isHidden = hidden || y < menuRect.minY + 4
            row.needsDisplay = true
        }
    }
}
