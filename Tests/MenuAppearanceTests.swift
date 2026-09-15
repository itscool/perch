import AppKit

func runMenuAppearanceTests() throws {
    let preview = MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 540, height: 168))
    preview.layout()
    for pair in zip(preview.rows, preview.rows.dropFirst()) {
        guard pair.0.frame.minY >= pair.1.frame.maxY else { throw AppError(message: "Appearance preview rows overlap") }
    }
    preview.setFrameSize(NSSize(width: 400, height: 168)); preview.layout()
    guard preview.rows.allSatisfy({ $0.frame.width == preview.menuRect.width }) else { throw AppError(message: "Appearance preview did not resize") }
    let suite = "local.perch.appearance-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    func require(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: "Appearance: " + message) } }
    let store = MenuAppearanceStore(defaults: defaults)
    try require(store.value.sections.sides == Set(MenuSectionAppearance.Side.allCases) && store.value.sections.thickness == 0.7 && store.value.sections.borderIntensity == 0.3 && store.value.sections.backgroundIntensity == 0.07 && store.value.sections.radius == 2.5 && store.value.sections.titleIntensity == 0.45 && store.value.sections.gap == 3 && !store.value.system.showIcon && !store.value.system.tintTitle && store.value.system.backgroundScope == .none, "exact Perch original defaults")
    var changed = store.value
    changed.sections.sides = [.left, .right, .bottom]; changed.sections.borderScope = .full
    changed.sections.radius = 8; changed.sections.greyBackground = true; changed.sections.backgroundScope = .full
    changed.sections.backgroundIntensity = 0.2; store.save(changed)
    try require(MenuAppearanceStore(defaults: defaults).value == changed, "all choices persist on reopening")
    try require(store.value.system == .system, "rainbow edits changed System")
    changed.system.thickness = 4; changed.system.sides = [.top, .bottom]; changed.system.borderScope = .title
    store.save(changed)
    try require(store.value.sections.radius == 8, "System editing changed rainbow sections")
    var invalid = changed; invalid.sections.radius = .nan; store.save(invalid)
    try require(store.value == changed, "invalid values replaced usable appearance")
    var fade = MenuSectionAppearance(); fade.edgeToEdge = true; fade.fadeLeft = true
    for distance in [0.0, 0.08, 0.5, 0.65, 1.0] {
        fade.fadeFraction = distance
        for right in [false, true] {
            fade.fadeRight = right
            let stops = fade.fadeStops
            try require(distance == 0 ? stops.isEmpty : !stops.isEmpty, "zero fade must draw no mask")
            try require(zip(stops, stops.dropFirst()).allSatisfy { $0.location < $1.location } && stops.allSatisfy { (0...1).contains($0.alpha) }, "overlapping fades have invalid stops")
            let decoded = try JSONDecoder().decode(MenuSectionAppearance.self, from: JSONEncoder().encode(fade))
            try require(decoded.fadeFraction == distance, "fade distance did not persist")
        }
    }
    fade.fadeRight = false
    try require(fade.fadeStops.count == 2 && fade.fadeStops.last?.location == 1, "full-distance fade does not span full width")
    for invalid in [-0.01, 1.01, Double.nan, Double.infinity] { fade.fadeFraction = invalid; try require(!fade.valid, "invalid fade accepted") }
    var systemGap = MenuTheme(); systemGap.system.gap = 8
    try require(systemGap.style("System").gap == 0 && systemGap.style("Sleep").gap == 3, "System retained an uneditable title gap")
    let item = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
    let row = MenuRowView(item: item, kind: .section); item.view = row; row.panelSection = "Sleep"; row.panelPart = .top
    row.appearance = NSAppearance(named: .aqua) // The edits above target the light theme.
    row.appearanceOverride = changed
    let tinted = row.displayedText()
    changed.sections.tintTitle = false; row.appearanceOverride = changed
    try require(!tinted.isEqual(to: row.displayedText()), "title tint does not reach production renderer")
    try require((row.displayedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .labelColor, "normal title doesn't use semantic label color")
    var darkFixture = changed
    darkFixture.editSection(dark: true, both: false, system: false) { $0.tintTitle = true }
    row.appearance = NSAppearance(named: .darkAqua); row.appearanceOverride = darkFixture
    let darkTinted = row.displayedText()
    darkFixture.editSection(dark: true, both: false, system: false) { $0.tintTitle = false }
    row.appearanceOverride = darkFixture
    try require(!darkTinted.isEqual(to: row.displayedText()), "dark title tint does not reach production renderer")
    row.appearance = NSAppearance(named: .aqua)
    changed.sections.showIcon = false; row.appearanceOverride = changed
    try require(row.textDrawingRect.minX == 25, "Hidden icons still indent titles")
    var dark = changed.theme(dark: true); dark.palette = .coast; dark.sections.thickness = 3
    changed.setTheme(dark, dark: true); store.save(changed)
    try require(store.value.theme(dark: false).sections.thickness != 3 && store.value.theme(dark: true) == dark, "Light/dark are not independent")
    var batch = changed
    let initialLight = batch.theme(dark: false), initialDark = batch.theme(dark: true)
    batch.editSection(dark: false, both: true, system: false) { $0.thickness = 1.7 }
    var expectedLight = initialLight, expectedDark = initialDark
    expectedLight.sections.thickness = 1.7; expectedDark.sections.thickness = 1.7
    try require(batch.theme(dark: false) == expectedLight && batch.theme(dark: true) == expectedDark, "Edit both copied unrelated theme differences")
    batch.editSection(dark: true, both: true, system: false) { $0.sides.insert(.left) }
    expectedLight.sections.sides.insert(.left); expectedDark.sections.sides.insert(.left)
    try require(batch.theme(dark: false) == expectedLight && batch.theme(dark: true) == expectedDark, "Border-side edit replaced other sides")
    batch.editSection(dark: true, both: false, system: true) { $0.showTitle = false }
    expectedDark.system.showTitle = false
    try require(batch.theme(dark: false) == expectedLight && batch.theme(dark: true) == expectedDark, "Single preview edit affected other scope")
    batch.edit(dark: false, both: true) { $0.palette = .dusk }
    expectedLight.palette = .dusk; expectedDark.palette = .dusk
    try require(batch.theme(dark: false) == expectedLight && batch.theme(dark: true) == expectedDark, "Palette batch edit copied section settings")
    store.savePreset(name: "My desk")
    try require(MenuAppearanceStore(defaults: defaults).presets.first?.appearance == changed, "Preset failed to retain the complete light/dark pair")
    store.savePreset(name: "My desk")
    try require(store.presets.count == 1 && store.presetProblem != nil, "Duplicate preset silently overwrote a saved style")
    store.clearPresetError(); store.removePreset(store.presets[0].id)
    try require(store.presets.isEmpty && store.value == changed, "Deleting preset changed current appearance")
    for builtIn in MenuAppearancePreset.builtIns { try require(builtIn.appearance.valid, "Invalid built-in preset") }
    changed.system.showTitle = false; preview.value = changed; preview.layout()
    try require(preview.rows[0].isHidden && preview.rows[0].frame.height == 0, "System title did not collapse")
    for size in [CGSize(width: 180, height: 150), CGSize(width: 600, height: 400)] {
        var rectangles: [CGRect] = []
        for index in 0..<16 {
            let rotated = index % 2 == 0
            rectangles.append(CGRect(x: Double(-800 + index * 550), y: rotated ? -300.0 : 0.0, width: rotated ? 310.0 : 550.0, height: rotated ? 550.0 : 310.0))
        }
        let layout = DeskCanvasLayout(rectangles: rectangles, viewport: size)
        try require(layout.bounds.width * layout.scale <= size.width && layout.bounds.height * layout.scale <= size.height, "Desk layout does not fit all screens")
        let translation = 37.0
        try require(abs((translation / layout.scale) * layout.scale - translation) < 0.00001, "Drag coordinates lose inverse scale")
        let readable = DeskCanvasLayout.minimumScale(for: rectangles)
        let readableLayout = DeskCanvasLayout(rectangles: rectangles, viewport: size, minimumScale: readable)
        try require(readableLayout.scale + 0.000001 >= readable, "Desk cards shrank below their readable minimum")
        try require(readableLayout.origin.x >= 16 && readableLayout.origin.y >= 16, "Desk layout kept a stable inset")
    }
    let panContent = CGSize(width: 1200, height: 900), panViewport = CGSize(width: 800, height: 700)
    try require(PannableSurfaceLayout.clampedOffset(.zero, content: panContent, viewport: panViewport) == .zero, "Desk pan starts at the visible origin")
    try require(PannableSurfaceLayout.clampedOffset(CGSize(width: -999, height: -999), content: panContent, viewport: panViewport) == CGSize(width: -400, height: -200), "Desk pan clamps to content bounds")
    try require(PannableSurfaceLayout.clampedOffset(CGSize(width: -500, height: -500), content: panContent, viewport: CGSize(width: 1400, height: 1000)) == .zero, "Desk pan recenters when the viewport grows")
    defaults.set(Data("broken".utf8), forKey: MenuAppearanceStore.key)
    let damaged = MenuAppearanceStore(defaults: defaults)
    damaged.save(changed)
    try require(defaults.data(forKey: MenuAppearanceStore.key) == Data("broken".utf8), "unreadable preferences were overwritten silently")
    damaged.save(.init(), restoring: true)
    try require(damaged.problem == nil && MenuAppearanceStore(defaults: defaults).value == MenuAppearance(), "explicit restore failed")
    print("PASS: appearance original defaults, independent System/rainbow changes, durable reopen, invalid/corrupt preservation, title renderer and explicit restore; isolated preferences only")
}
