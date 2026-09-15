import AppKit

/// The menu's appearance model: per-section styling, palettes, the Light/Dark
/// pair and the built-in presets. Pure values; no storage or views here.

struct MenuSectionAppearance: Codable, Equatable {
    enum Scope: String, Codable, CaseIterable { case none = "None", title = "Title", full = "Full section" }
    enum Side: String, Codable, CaseIterable { case left = "Left", right = "Right", top = "Top", bottom = "Bottom" }
    var borderScope: Scope = .title
    var sides = Set(Side.allCases)
    var thickness = 0.7
    var borderIntensity = 0.3
    var backgroundScope: Scope = .title
    var backgroundIntensity = 0.07
    var greyBackground = false
    var greyLevel = 0.5
    var radius = 2.5
    var tintTitle = true
    var titleIntensity = 0.45
    var showIcon = true
    var tintIcon: Bool? = true
    var iconIntensity: Double? = 1
    var iconTinted: Bool { get { tintIcon != false } set { tintIcon = newValue } }
    var iconTintStrength: Double { get { iconIntensity ?? 1 } set { iconIntensity = newValue } }
    var gap = 3.0
    var showTitle: Bool? = true
    var edgeToEdge: Bool? = false
    var fadeLeft: Bool? = false
    var fadeRight: Bool? = false
    var fadeDistance: Double? = 0.08
    var fadeFraction: Double { get { fadeDistance ?? 0.08 } set { fadeDistance = newValue } }
    /// Normalized stops stay ordered even when left/right fades overlap.
    /// At full distance a single edge fades across the entire menu width.
    var fadeStops: [(location: CGFloat, alpha: CGFloat)] {
        let f = CGFloat(fadeFraction)
        guard isEdgeToEdge, f > 0, f <= 1 else { return [] }
        if fadeLeft == true && fadeRight == true {
            return f < 0.5 ? [(0, 0), (f, 1), (1-f, 1), (1, 0)] : [(0, 0), (0.5, 0.5/f), (1, 0)]
        }
        if fadeLeft == true { return f == 1 ? [(0, 0), (1, 1)] : [(0, 0), (f, 1), (1, 1)] }
        if fadeRight == true { return f == 1 ? [(0, 1), (1, 0)] : [(0, 1), (1-f, 1), (1, 0)] }
        return []
    }
    var isEdgeToEdge: Bool { edgeToEdge == true }
    var drawnSides: Set<Side> { isEdgeToEdge ? sides.subtracting([.left, .right]) : sides }
    var decorationMargin: Double { isEdgeToEdge ? 0 : 4 }
    var decorationRadius: Double { isEdgeToEdge ? 0 : radius }
    static var system: Self { var s = Self(); s.borderScope = .none; s.backgroundScope = .none; s.gap = 0; s.showIcon = false; s.tintTitle = false; return s }
    var valid: Bool {
        [(thickness, 0...6), (borderIntensity, 0...1), (backgroundIntensity, 0...1),
         (fadeFraction, 0...1), (greyLevel, 0...1), (iconTintStrength, 0...1), (radius, 0...12), (titleIntensity, 0...1), (gap, 0...8)].allSatisfy { $0.0.isFinite && $0.1.contains($0.0) }
    }
}
enum MenuPalette: String, Codable, CaseIterable {
    case rainbow = "Rainbow", graphite = "Graphite", coast = "Coast", dusk = "Dusk"
    case woodland = "Woodland", mineral = "Mineral", jewel = "Jewel", sorbet = "Sorbet"
    static let sections = ["Agent Kill Switch", "Displays", "Audio", "Scrolling", "Built-in keyboard", "External keyboards", "Sleep", "Perch", "System"]
    /// A complete color assignment per section, except Coast's deliberate triad.
    var swatches: [NSColor] {
        let hex: [UInt32]
        switch self {
        case .rainbow: return Self.sections.map { MenuRowView.tint(for: $0) }
        case .graphite: return Self.sections.indices.map { NSColor(white: 0.4 + Double($0 % 3) * 0.09, alpha: 1) }
        case .coast: return Self.sections.indices.map { [NSColor.systemTeal, .systemBlue, .systemCyan][$0 % 3] }
        case .dusk: hex = [0xB95175, 0xDF8256, 0xCEA34F, 0xAC7594, 0x796FB4, 0x617BA8, 0x82729C, 0xCC7181, 0x91818F]
        case .woodland: hex = [0x3F7155, 0x819448, 0xB47750, 0x8FA88D, 0xB99B55, 0x426F68, 0x856A56, 0x639367, 0x8F9277]
        case .mineral: hex = [0x546A85, 0xB78169, 0x79AAA5, 0x9D9B92, 0x748BA1, 0x4B8981, 0x9A8694, 0xA5B5C3, 0x66757B]
        case .jewel: hex = [0xBC345B, 0x25865C, 0x6052BA, 0xC88727, 0x247EAA, 0xB43D93, 0x268C8C, 0x854DA1, 0x505677]
        case .sorbet: hex = [0xDA92A4, 0xE9AE8C, 0xD9C478, 0xABC58E, 0x8BC5BE, 0x91B6D9, 0xB0A3D7, 0xCFA3C8, 0xAABEC1]
        }
        return hex.map { NSColor(srgbRed: Double(($0 >> 16) & 255) / 255,
                                green: Double(($0 >> 8) & 255) / 255,
                                blue: Double($0 & 255) / 255, alpha: 1) }
    }
    func color(_ name: String) -> NSColor {
        let canonical = name.hasPrefix("External keyboard") ? "External keyboards" : name
        return swatches[Self.sections.firstIndex(of: canonical) ?? 0]
    }
}

struct MenuTheme: Codable, Equatable {
    var sections = MenuSectionAppearance()
    var system = MenuSectionAppearance.system
    var palette: MenuPalette = .rainbow
    var valid: Bool { sections.valid && system.valid }
    func style(_ name: String?) -> MenuSectionAppearance {
        guard name == "System" else { return sections }
        var result = system; result.gap = 0
        return result
    }
}
struct MenuAppearance: Codable, Equatable {
    var sections = MenuSectionAppearance()
    var system = MenuSectionAppearance.system
    var palette: MenuPalette? = .rainbow
    var dark: MenuTheme?
    var valid: Bool { sections.valid && system.valid && (dark?.valid ?? true) }
    func theme(dark isDark: Bool) -> MenuTheme {
        isDark ? dark ?? MenuTheme() : MenuTheme(sections: sections, system: system, palette: palette ?? .rainbow)
    }
    mutating func setTheme(_ theme: MenuTheme, dark isDark: Bool) {
        if isDark { dark = theme } else { sections = theme.sections; system = theme.system; palette = theme.palette }
    }
    func style(_ name: String?, dark: Bool = false) -> MenuSectionAppearance { theme(dark: dark).style(name) }
}
/// Batch edits change only the touched property, preserving each theme's other choices.
extension MenuAppearance {
    mutating func edit(dark: Bool, both: Bool, _ change: (inout MenuTheme) -> Void) {
        for target in both ? [false, true] : [dark] {
            var theme = self.theme(dark: target); change(&theme); setTheme(theme, dark: target)
        }
    }
    mutating func editSection(dark: Bool, both: Bool, system: Bool, _ change: (inout MenuSectionAppearance) -> Void) {
        edit(dark: dark, both: both) { theme in
            if system { change(&theme.system) } else { change(&theme.sections) }
        }
    }
}
struct MenuAppearancePreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var appearance: MenuAppearance
    static let builtIns: [Self] = {
        // Presets describe composition. Every palette remains independently selectable.
        func pair(_ light: MenuTheme, _ customizeDark: (inout MenuTheme) -> Void = { _ in }) -> MenuAppearance {
            var dark = light; customizeDark(&dark)
            var result = MenuAppearance(); result.setTheme(light, dark: false); result.setTheme(dark, dark: true)
            return result
        }
        var quiet = MenuTheme()
        quiet.palette = .graphite
        quiet.sections.borderScope = .none; quiet.sections.backgroundScope = .none
        quiet.sections.tintTitle = false; quiet.sections.showIcon = false
        quiet.sections.radius = 0; quiet.sections.gap = 2; quiet.system.showTitle = false

        var signal = MenuTheme()
        signal.palette = .coast
        signal.sections.borderScope = .full; signal.sections.sides = [.left]
        signal.sections.thickness = 3; signal.sections.borderIntensity = 0.75
        signal.sections.backgroundScope = .none; signal.sections.radius = 0
        signal.sections.showIcon = false; signal.sections.titleIntensity = 0.5; signal.sections.gap = 4

        var tiles = MenuTheme()
        tiles.palette = .woodland
        tiles.sections.borderScope = .none; tiles.sections.backgroundScope = .full
        tiles.sections.backgroundIntensity = 0.10; tiles.sections.radius = 9
        tiles.sections.titleIntensity = 0.55; tiles.sections.gap = 6; tiles.sections.iconTintStrength = 0.55
        tiles.system.backgroundScope = .full; tiles.system.greyBackground = true
        tiles.system.backgroundIntensity = 0.05; tiles.system.radius = 9

        var outline = MenuTheme()
        outline.palette = .jewel
        outline.sections.borderScope = .full; outline.sections.sides = Set(MenuSectionAppearance.Side.allCases)
        outline.sections.thickness = 1; outline.sections.borderIntensity = 0.45
        outline.sections.backgroundScope = .none; outline.sections.radius = 6
        outline.sections.titleIntensity = 0.5; outline.sections.gap = 5; outline.sections.iconTintStrength = 0.65
        outline.system.borderScope = .full; outline.system.thickness = 0.5
        outline.system.borderIntensity = 0.2; outline.system.radius = 6

        var ribbon = MenuTheme()
        ribbon.palette = .dusk
        ribbon.sections.borderScope = .title; ribbon.sections.sides = [.top, .bottom]
        ribbon.sections.thickness = 1.2; ribbon.sections.borderIntensity = 0.65
        ribbon.sections.backgroundScope = .title; ribbon.sections.greyBackground = true
        ribbon.sections.greyLevel = 0.5; ribbon.sections.backgroundIntensity = 0.09
        ribbon.sections.radius = 0; ribbon.sections.showIcon = false
        ribbon.sections.titleIntensity = 0.5; ribbon.sections.gap = 0
        ribbon.sections.fadeFraction = 0.12
        ribbon.sections.edgeToEdge = true; ribbon.sections.fadeLeft = true; ribbon.sections.fadeRight = true

        var horizon = MenuTheme()
        horizon.palette = .graphite
        horizon.sections.fadeFraction = 0.65
        horizon.sections.edgeToEdge = true; horizon.sections.fadeRight = true
        horizon.sections.borderScope = .full; horizon.sections.sides = [.top]
        horizon.sections.thickness = 0.7; horizon.sections.borderIntensity = 0.35
        horizon.sections.backgroundScope = .full; horizon.sections.greyBackground = true
        horizon.sections.backgroundIntensity = 0.08; horizon.sections.tintTitle = false
        horizon.sections.showIcon = false; horizon.sections.gap = 2; horizon.sections.radius = 0

        return [
            .init(name: "Perch original", appearance: .init()),
            .init(name: "Quiet", appearance: pair(quiet)),
            .init(name: "Signal", appearance: pair(signal) { $0.sections.borderIntensity = 0.85; $0.sections.titleIntensity = 0.7 }),
            .init(name: "Soft tiles", appearance: pair(tiles) { $0.sections.backgroundIntensity = 0.16; $0.system.backgroundIntensity = 0.10; $0.sections.titleIntensity = 0.7; $0.sections.iconTintStrength = 0.45 }),
            .init(name: "Outline", appearance: pair(outline) { $0.sections.borderIntensity = 0.6; $0.system.borderIntensity = 0.35; $0.sections.iconTintStrength = 0.45 }),
            .init(name: "Ribbon", appearance: pair(ribbon) { $0.sections.backgroundIntensity = 0.16; $0.sections.titleIntensity = 0.65 }),
            .init(name: "Horizon", appearance: pair(horizon) { $0.sections.backgroundIntensity = 0.14; $0.sections.borderIntensity = 0.45 })
        ]
    }()
}
