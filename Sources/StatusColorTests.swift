import AppKit

private final class StatusPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    }
}

func runStatusColorTests() throws {
    try runMenuStatusColorTests()
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
    var items: [NSMenuItem] = [] // MenuRowView references its menu item weakly.
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
        items.append(item)
        let row = MenuRowView(item: item, kind: .toggle, text: title); row.hover = index == 1
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

private func runMenuStatusColorTests() throws {
    let app = AppDelegate(); app.buildMenu()
    let reading = app.systemItems[1]
    guard let permanent = app.menu.items.first(where: { $0.action == #selector(AppDelegate.turnDisplayOff) }) else { throw AppError(message: "Display-off item missing from menu") }
    func rgb(_ source: NSColor, _ appearance: NSAppearance) -> NSColor {
        var result: NSColor!
        appearance.performAsCurrentDrawingAppearance { result = source.usingColorSpace(.sRGB) }
        return result
    }
    func color(_ item: NSMenuItem, last: Bool = false) -> NSColor {
        let row = item.view as! MenuRowView
        var result: NSColor!
        row.effectiveAppearance.performAsCurrentDrawingAppearance {
            let text = row.displayedText()
            result = (text.attribute(.foregroundColor, at: last ? text.length - 1 : 0, effectiveRange: nil) as! NSColor).usingColorSpace(.sRGB)
        }
        return result
    }
    func rendered(_ item: NSMenuItem, appearance: NSAppearance) throws -> Data {
        let production = item.view as! MenuRowView
        let row = MenuRowView(item: item, kind: production.kind, text: production.text)
        let background = StatusPreviewView(frame: NSRect(x: 0, y: 0, width: 650, height: 30))
        let window = NSWindow(contentRect: background.bounds, styleMask: [], backing: .buffered, defer: false)
        window.contentView = background; window.appearance = appearance
        row.frame = background.bounds; background.addSubview(row)
        guard let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds) else { throw AppError(message: "Menu renderer capture failed") }
        appearance.performAsCurrentDrawingAppearance { background.cacheDisplay(in: background.bounds, to: bitmap) }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw AppError(message: "Menu renderer capture is empty") }
        return data
    }
    for name in [NSAppearance.Name.aqua, .darkAqua, .vibrantLight, .vibrantDark, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua] {
        let appearance = NSAppearance(named: name)!
        let wrongContext = NSAppearance(named: name == .aqua ? .darkAqua : .aqua)!
        // A live NSMenu sets the row window's appearance. Give the actual renderer
        // that same context offscreen, without changing the user's desktop theme.
        for item in app.menu.items where !item.isSeparatorItem {
            guard let row = item.view as? MenuRowView, item.attributedTitle == nil else { throw AppError(message: "Menu mixed native/custom rendering: \(item.title)") }
            row.appearance = appearance
        }
        var initial: NSColor!, updated: NSColor!
        wrongContext.performAsCurrentDrawingAppearance {
            app.showSystemReading(reading, ("CPU", "18 cores · Measuring…", ""))
            initial = color(reading, last: true)
            app.showSystemReading(reading, ("CPU", "18 cores · 12%", ""))
            updated = color(reading, last: true)
        }
        guard initial == updated, updated == rgb(StatusColors.information, appearance), color(permanent) == rgb(.labelColor, appearance) else {
            throw AppError(message: "Initial/periodic/command colors depend on the ambient appearance in \(name.rawValue)")
        }
        app.menu.update()
        for item in app.menu.items where item.action != nil && (item.view as! MenuRowView).kind != .toggle {
            let row = item.view as! MenuRowView
            guard row.kind == .command, color(item) == rgb(.labelColor, appearance) else { throw AppError(message: "Command text differs from other rows: \(item.title)") }
            row.keyboardHighlight = true
            guard color(item) == rgb(.selectedMenuItemTextColor, appearance) || item.isHidden else { throw AppError(message: "Keyboard selection lost contrast") }
            row.keyboardHighlight = false
        }
        app.label(app.safetySettingsItem, "Settings…")
        let before = try rendered(app.safetySettingsItem, appearance: appearance)
        app.label(app.safetySettingsItem, "Settings…", hint: "⚠ Review keyboards", hintColor: StatusColors.warning)
        let warning = try rendered(app.safetySettingsItem, appearance: appearance)
        app.label(app.safetySettingsItem, "Settings…")
        let after = try rendered(app.safetySettingsItem, appearance: appearance)
        guard before == after, before != warning else { throw AppError(message: "Settings pixels changed after warning was removed") }
        let settings = app.safetySettingsItem.view as! MenuRowView
        guard settings.text.string == "Settings…", app.safetySettingsItem.title == "Settings…", color(app.safetySettingsItem) == rgb(.labelColor, appearance) else {
            throw AppError(message: "Clearing a warning hid or restyled Settings")
        }
        for (text, expected) in [("Warm · OK · Keep ventilated", StatusColors.warning), ("Critical · Let Mac cool", StatusColors.critical)] {
            wrongContext.performAsCurrentDrawingAppearance { app.showSystemReading(reading, ("Thermal", text, "")) }
            guard color(reading, last: true) == rgb(expected, appearance) else { throw AppError(message: "Menu status color lost its theme") }
        }
    }
    print("PASS: every row uses the production renderer; first/periodic colors match in six appearances despite opposite ambient contexts; commands and toggles share semantic colors; Settings warning clears without hiding its text; keyboard highlights keep contrast")
}
