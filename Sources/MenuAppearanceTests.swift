import AppKit

func runMenuAppearanceTests() throws {
    let preview = MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 540, height: 168))
    preview.layout()
    for pair in zip(preview.rows, preview.rows.dropFirst()) {
        guard pair.0.frame.minY >= pair.1.frame.maxY else { throw AppError(message: "Appearance preview rows overlap") }
    }
    preview.setFrameSize(NSSize(width: 400, height: 168)); preview.layout()
    guard preview.rows.allSatisfy({ $0.frame.width == 400 }) else { throw AppError(message: "Appearance preview did not resize") }
    let suite = "local.perch.appearance-test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    func require(_ condition: Bool, _ message: String) throws { if !condition { throw AppError(message: "Appearance: " + message) } }
    let store = MenuAppearanceStore(defaults: defaults)
    try require(store.value.sections.sides == [.top] && store.value.system.backgroundScope == .none, "tuned original defaults")
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
    let item = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
    let row = MenuRowView(item: item, kind: .section); item.view = row; row.panelSection = "Sleep"; row.panelPart = .top
    row.appearanceOverride = changed
    let tinted = row.displayedText()
    changed.sections.tintTitle = false; row.appearanceOverride = changed
    try require(!tinted.isEqual(to: row.displayedText()), "title tint does not reach production renderer")
    try require((row.displayedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .labelColor, "normal title doesn't use semantic label color")
    defaults.set(Data("broken".utf8), forKey: MenuAppearanceStore.key)
    let damaged = MenuAppearanceStore(defaults: defaults)
    damaged.save(changed)
    try require(defaults.data(forKey: MenuAppearanceStore.key) == Data("broken".utf8), "unreadable preferences were overwritten silently")
    damaged.save(.init(), restoring: true)
    try require(damaged.problem == nil && MenuAppearanceStore(defaults: defaults).value == MenuAppearance(), "explicit restore failed")
    print("PASS: appearance original defaults, independent System/rainbow changes, durable reopen, invalid/corrupt preservation, title renderer and explicit restore; isolated preferences only")
}
