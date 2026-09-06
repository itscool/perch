import AppKit

private final class StatusPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    }
}

func runStatusColorTests() throws {
    let colors: [(String, NSColor)] = [("✓ Ready", StatusColors.success), ("⚠ Review protection", StatusColors.warning), ("⛔ Protection unavailable", StatusColors.critical), ("CPU 18 cores · 4%", StatusColors.information)]
    func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB)!
        func linear(_ v: CGFloat) -> Double { let n = Double(v); return n <= 0.04045 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
    for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
        let appearance = NSAppearance(named: name)!
        var lowest = Double.infinity
        appearance.performAsCurrentDrawingAppearance {
            for (_, color) in colors {
                for background in [NSColor.windowBackgroundColor, .controlBackgroundColor] {
                    let a = luminance(color), b = luminance(background)
                    lowest = min(lowest, (max(a,b)+0.05) / (min(a,b)+0.05))
                }
            }
        }
        guard lowest >= 4.5 else { throw AppError(message: "Status color contrast \(lowest) in \(name.rawValue)") }
        print("PASS: \(name.rawValue) minimum status text contrast \(String(format: "%.2f", lowest)):1")
    }

    // Exercise the same dynamic color objects after an appearance switch, including
    // attributed native buttons and custom menu rows. No desktop capture is used.
    let view = StatusPreviewView(frame: NSRect(x: 0, y: 0, width: 490, height: 360))
    let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    var items: [NSMenuItem] = [] // ToggleMenuView references its menu item weakly.
    for (index, entry) in colors.enumerated() {
        let label = NSTextField(labelWithString: entry.0)
        label.textColor = entry.1; label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 320 - index*30, width: 450, height: 24)
        view.addSubview(label)
    }
    let button = NSButton(title: "✓ Input controls…", target: nil, action: nil)
    button.bezelStyle = .rounded
    button.attributedTitle = NSAttributedString(string: button.title, attributes: [.foregroundColor: StatusColors.success, .font: NSFont.systemFont(ofSize: 13)])
    button.frame = NSRect(x: 20,y: 158,width: 450,height: 30); view.addSubview(button)
    for index in 0..<3 {
        let item = NSMenuItem(title: "Keep awake with lid closed", action: nil, keyEquivalent: "")
        item.isEnabled = index != 2; item.state = .on
        let title = NSMutableAttributedString(string: item.title, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(string: "   ⚠ Keep ventilated", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: StatusColors.warning]))
        item.attributedTitle = title; items.append(item)
        let row = ToggleMenuView(item: item); row.hover = index == 1
        row.frame = NSRect(x: 10,y: 114-index*30,width: 470,height: 24); view.addSubview(row)
    }
    for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let appearance = NSAppearance(named: name)!
        window.appearance = appearance
        view.appearance = appearance
        view.needsDisplay = true
        view.subviews.forEach { $0.needsDisplay = true }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/perch-colors-\(suffix).png"))
        }
    }
    withExtendedLifetime(items) {}
}
