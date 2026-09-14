import AppKit
import SwiftUI

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
    static let edgeFadeWidth = 24.0
    var isEdgeToEdge: Bool { edgeToEdge == true }
    var drawnSides: Set<Side> { isEdgeToEdge ? sides.subtracting([.left, .right]) : sides }
    var decorationMargin: Double { isEdgeToEdge ? 0 : 4 }
    var decorationRadius: Double { isEdgeToEdge ? 0 : radius }
    static var system: Self { var s = Self(); s.borderScope = .none; s.backgroundScope = .none; s.gap = 0; s.showIcon = false; s.tintTitle = false; return s }
    var valid: Bool {
        [(thickness, 0...6), (borderIntensity, 0...1), (backgroundIntensity, 0...1),
         (greyLevel, 0...1), (iconTintStrength, 0...1), (radius, 0...12), (titleIntensity, 0...1), (gap, 0...8)].allSatisfy { $0.0.isFinite && $0.1.contains($0.0) }
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
    func style(_ name: String?) -> MenuSectionAppearance { name == "System" ? system : sections }
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
        ribbon.sections.edgeToEdge = true; ribbon.sections.fadeLeft = true; ribbon.sections.fadeRight = true

        var horizon = MenuTheme()
        horizon.palette = .graphite
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

final class MenuAppearanceStore: ObservableObject {
    static let shared = MenuAppearanceStore()
    static let key = "menu.appearance"
    @Published private(set) var value = MenuAppearance()
    @Published private(set) var problem: String?
    @Published private(set) var presets: [MenuAppearancePreset] = []
    @Published private(set) var presetProblem: String?
    static let presetsKey = "menu.appearance.presets"
    private let defaults: UserDefaults
    var changed: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.presetsKey) {
            if let saved = try? JSONDecoder().decode([MenuAppearancePreset].self, from: data), saved.allSatisfy({ $0.appearance.valid }) { presets = saved }
            else { presetProblem = "Saved presets could not be read. They have been kept unchanged." }
        }
        if let data = defaults.data(forKey: Self.key) {
            if let decoded = try? JSONDecoder().decode(MenuAppearance.self, from: data), decoded.valid { value = decoded }
            else { problem = "Saved appearance could not be read. Open Reset Settings → Menu appearance to replace it." }
        }
    }
    func save(_ next: MenuAppearance, restoring: Bool = false) {
        guard problem == nil || restoring, next.valid else { return }
        do { let data = try JSONEncoder().encode(next); defaults.set(data, forKey: Self.key); value = next; problem = nil; changed?() }
        catch { problem = error.localizedDescription }
    }
    func savePreset(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard presetProblem == nil else { return }
        guard !name.isEmpty, name.count <= 60 else { presetProblem = "Use a preset name from 1 to 60 characters."; return }
        guard !presets.contains(where: { $0.name.lowercased() == name.lowercased() }) && !MenuAppearancePreset.builtIns.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            presetProblem = "That name already exists. Choose a different name."; return
        }
        var next = presets; next.append(.init(name: name, appearance: value))
        writePresets(next)
    }
    func clearPresetError() { if (try? defaults.data(forKey: Self.presetsKey).map { try JSONDecoder().decode([MenuAppearancePreset].self, from: $0) }) != nil || defaults.data(forKey: Self.presetsKey) == nil { presetProblem = nil } }
    func removePreset(_ id: UUID) { guard presetProblem == nil else { return }; writePresets(presets.filter { $0.id != id }) }
    private func writePresets(_ next: [MenuAppearancePreset]) {
        do { defaults.set(try JSONEncoder().encode(next), forKey: Self.presetsKey); presets = next; presetProblem = nil }
        catch { presetProblem = error.localizedDescription }
    }
}

extension MenuRowView {
    func drawDecoration(_ style: MenuSectionAppearance) {
        let fades = style.isEdgeToEdge && (style.fadeLeft == true || style.fadeRight == true)
        let context = NSGraphicsContext.current?.cgContext
        if fades { context?.saveGState(); context?.beginTransparencyLayer(auxiliaryInfo: nil) }
        defer {
            if fades, let context {
                let fraction = min(0.49, MenuSectionAppearance.edgeFadeWidth / max(1, bounds.width))
                let alpha: [CGFloat] = [style.fadeLeft == true ? 0 : 1, 1, 1, style.fadeRight == true ? 0 : 1]
                let colors = alpha.map { CGColor(gray: 0, alpha: $0) } as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, fraction, 1-fraction, 1]) {
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

struct MenuAppearancePage: View {
    @ObservedObject var store = MenuAppearanceStore.shared
    @State private var system = false
    @State private var dark = false
    @State private var both = false
    @State private var presetName = ""
    @State private var namingPreset = false
    @State private var deletingPreset: MenuAppearancePreset?
    func edit(_ change: (inout MenuSectionAppearance) -> Void) {
        var value = store.value
        value.editSection(dark: dark, both: both, system: system, change); store.save(value)
    }
    func binding<T>(_ path: WritableKeyPath<MenuSectionAppearance, T>) -> Binding<T> {
        Binding(get: { style[keyPath: path] }, set: { next in edit { $0[keyPath: path] = next } })
    }
    func mixed<T: Equatable>(_ path: KeyPath<MenuSectionAppearance, T>) -> Bool {
        both && style[keyPath: path] != otherStyle[keyPath: path]
    }
    func selection<T: Equatable>(_ path: WritableKeyPath<MenuSectionAppearance, T>) -> Binding<T?> {
        Binding(get: { mixed(path) ? nil : style[keyPath: path] }, set: { next in
            if let next { binding(path).wrappedValue = next }
        })
    }
    var theme: MenuTheme { store.value.theme(dark: dark) }
    var style: MenuSectionAppearance { system ? theme.system : theme.sections }
    var otherStyle: MenuSectionAppearance { store.value.theme(dark: !dark).style(system ? "System" : nil) }
    func neither(_ predicate: (MenuSectionAppearance) -> Bool) -> Bool { !predicate(style) && (!both || !predicate(otherStyle)) }
    func toggle(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Bool>) -> some View {
        AppearanceMixedToggle(title: label, value: mixed(path) ? nil : style[keyPath: path]) { next in edit { $0[keyPath: path] = next } }.frame(height: 22).fixedSize(horizontal: true, vertical: false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Menu preview").font(.headline)
                Spacer()
                Toggle("Edit both", isOn: $both).help("Changes apply to this setting in Light and Dark. Other differences stay unchanged.")
            }
            HStack(spacing: 12) { preview(dark: false); preview(dark: true) }
            HStack {
                Menu("Presets") {
                    Section("Built-in") { ForEach(MenuAppearancePreset.builtIns) { preset in Button(preset.name) { store.save(preset.appearance, restoring: true) } } }
                    if !store.presets.isEmpty {
                        Section("Saved") { ForEach(store.presets) { preset in Button(preset.name) { store.save(preset.appearance, restoring: true) } } }
                        Menu("Delete saved preset") { ForEach(store.presets) { preset in Button(preset.name) { deletingPreset = preset } } }
                    }
                }
                Button("Save as preset…") { namingPreset.toggle(); store.clearPresetError() }
                Spacer()
            }
            if namingPreset {
                HStack {
                    TextField("Preset name", text: $presetName).onChange(of: presetName) { _, _ in store.clearPresetError() }
                    Button("Save preset") { store.savePreset(name: presetName); if store.presetProblem == nil { namingPreset = false; presetName = "" } }
                    Button("Cancel") { namingPreset = false }
                }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            if let deletingPreset {
                HStack {
                    Text("Delete “\(deletingPreset.name)”? Your current menu stays as it is.").font(.caption)
                    Button("Delete preset", role: .destructive) { store.removePreset(deletingPreset.id); self.deletingPreset = nil }
                    Button("Cancel") { self.deletingPreset = nil }
                }
            }
            if let error = store.presetProblem { Text(error).foregroundStyle(.orange) }
            if both { Text("Editing both · Mixed means the values differ. Changes affect only the setting you touch.").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 0) {
                sectionButton("Colored sections", system: false)
                sectionButton("System", system: true)
            }.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3)))
            Picker("Palette", selection: Binding<MenuPalette?>(get: { both && theme.palette != store.value.theme(dark: !dark).palette ? nil : theme.palette }, set: { palette in
                guard let palette else { return }; var value = store.value
                value.edit(dark: dark, both: both) { $0.palette = palette }; store.save(value)
            })) {
                if both && theme.palette != store.value.theme(dark: !dark).palette { Text("Mixed").tag(nil as MenuPalette?).disabled(true) }
                ForEach(MenuPalette.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            if let problem = store.problem { Text(problem).foregroundStyle(.orange) }
            Group {
                HStack(spacing: 12) {
                    AppearanceMixedToggle(title: "Edge to edge", value: both && style.isEdgeToEdge != otherStyle.isEdgeToEdge ? nil : style.isEdgeToEdge) { next in edit { $0.edgeToEdge = next } }
                        .frame(height: 22).fixedSize(horizontal: true, vertical: false).help("Remove the decoration margin. Full-width bands have square corners and no left/right borders. Turning this off restores your saved sides and radius.")
                    AppearanceMixedToggle(title: "Fade left", value: both && (style.fadeLeft == true) != (otherStyle.fadeLeft == true) ? nil : style.fadeLeft == true) { next in edit { $0.fadeLeft = next } }.frame(height: 22).fixedSize(horizontal: true, vertical: false).disabled(neither { $0.isEdgeToEdge })
                    AppearanceMixedToggle(title: "Fade right", value: both && (style.fadeRight == true) != (otherStyle.fadeRight == true) ? nil : style.fadeRight == true) { next in edit { $0.fadeRight = next } }.frame(height: 22).fixedSize(horizontal: true, vertical: false).disabled(neither { $0.isEdgeToEdge })
                    Spacer(minLength: 0)
                }
                Text("Border").font(.headline).padding(.top, 4)
                HStack(spacing: 10) {
                    scopePicker("Border area", path: \.borderScope).frame(width: 215)
                    ForEach(MenuSectionAppearance.Side.allCases, id: \.self) { side in
                        AppearanceMixedToggle(title: side.rawValue, value: both && style.drawnSides.contains(side) != otherStyle.drawnSides.contains(side) ? nil : style.drawnSides.contains(side)) { enabled in
                            edit { style in
                                if style.isEdgeToEdge && (side == .left || side == .right) { return }
                                if enabled { style.sides.insert(side) } else { style.sides.remove(side) }
                            }
                        }.frame(height: 22).fixedSize(horizontal: true, vertical: false).disabled(neither { $0.borderScope != .none && (!($0.isEdgeToEdge) || (side != .left && side != .right)) })
                    }
                    Spacer(minLength: 0)
                }
                slider("Thickness", path: \.thickness, range: 0...6, suffix: "pt").disabled(neither { $0.borderScope != .none && !$0.drawnSides.isEmpty })
                slider("Line intensity", path: \.borderIntensity, range: 0...1).disabled(neither { $0.borderScope != .none && !$0.drawnSides.isEmpty })
                slider("Corner radius", path: \.radius, range: 0...12, suffix: "pt").disabled(neither { !$0.isEdgeToEdge && ($0.backgroundScope != .none || ($0.borderScope != .none && !$0.drawnSides.isEmpty)) })
                Text("Fill").font(.headline).padding(.top, 4)
                HStack(spacing: 12) {
                    scopePicker("Highlight area", path: \.backgroundScope).frame(width: 215)
                    toggle("Use grey highlights", path: \.greyBackground).disabled(neither { $0.backgroundScope != .none })
                }
                slider("Grey shade", path: \.greyLevel, range: 0...1).disabled(neither { $0.greyBackground && $0.backgroundScope != .none })
                slider("Highlight intensity", path: \.backgroundIntensity, range: 0...1).disabled(neither { $0.backgroundScope != .none })
                Text("Titles").font(.headline).padding(.top, 4)
                HStack(spacing: 12) {
                    toggle("Tint title text to its section color", path: \.tintTitle).frame(width: 275, alignment: .leading)
                    valueSlider("Title tint", path: \.titleIntensity, range: 0...1).disabled(neither { $0.tintTitle })
                }
                HStack {
                    toggle("Show title icons", path: \.showIcon)
                    if system {
                        AppearanceMixedToggle(title: "Show System title", value: both && (style.showTitle != false) != (otherStyle.showTitle != false) ? nil : style.showTitle != false) { next in edit { $0.showTitle = next } }.frame(height: 22)
                    }
                }
                HStack(spacing: 12) {
                    toggle("Tint icons to their section color", path: \.iconTinted).frame(width: 275, alignment: .leading)
                    valueSlider("Icon tint", path: \.iconTintStrength, range: 0...1).disabled(neither { $0.showIcon && $0.iconTinted })
                }.disabled(neither { $0.showIcon })
                slider("Space above titles", path: \.gap, range: 0...8, suffix: "pt")
            }.disabled(store.problem != nil)
            HStack {
                Spacer()
                Button("Reset appearance…") { SettingsWindow.shared.navigateToReset(.appearance) }.help("Open appearance reset options for rainbow sections and System, then return here.")
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    func sectionButton(_ title: String, system target: Bool) -> some View {
        Button { system = target } label: {
            Text(title).fontWeight(system == target ? .semibold : .regular)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(system == target ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(system == target ? "Selected" : "Not selected")
    }
    func preview(dark: Bool) -> some View {
        Button { self.dark = dark; both = false } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dark ? "Dark" : "Light").font(.caption)
                    Spacer()
                    if both || self.dark == dark { Text("Editing").font(.caption).foregroundStyle(Color.accentColor) }
                }
                MenuAppearancePreview(value: store.value, dark: dark, system: system).frame(height: 210).allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }.padding(10).contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(both || self.dark == dark ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: both || self.dark == dark ? 2 : 1))
        }.buttonStyle(.plain)
            .accessibilityLabel("Edit " + (dark ? "Dark" : "Light") + " appearance")
            .accessibilityValue(both || self.dark == dark ? "Selected" : "Not selected")
    }
    func scopePicker(_ label: String, path: WritableKeyPath<MenuSectionAppearance, MenuSectionAppearance.Scope>) -> some View {
        Picker(label, selection: selection(path)) {
            if mixed(path) { Text("Mixed").tag(nil as MenuSectionAppearance.Scope?).disabled(true) }
            ForEach(MenuSectionAppearance.Scope.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
    }
    func valueSlider(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Double>, range: ClosedRange<Double>, suffix: String = "%") -> some View {
        HStack(spacing: 8) {
            Slider(value: binding(path), in: range, step: suffix == "%" ? 0.01 : 0.1).accessibilityLabel(label).accessibilityValue(mixed(path) ? "Mixed" : String(style[keyPath: path]))
            Text(mixed(path) ? "Mixed" : suffix == "%" ? "\(Int(style[keyPath: path] * 100))%" : String(format: "%.1f %@", style[keyPath: path], suffix)).monospacedDigit().frame(width: 65, alignment: .trailing)
        }
    }
    func slider(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Double>, range: ClosedRange<Double>, suffix: String = "%") -> some View {
        HStack {
            Text(label).frame(width: 145, alignment: .leading)
            valueSlider(label, path: path, range: range, suffix: suffix)
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
struct MenuAppearancePreview: NSViewRepresentable {
    let value: MenuAppearance
    var dark = false
    var system = false
    func makeNSView(context: Context) -> MenuAppearancePreviewHost { MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 540, height: 168)) }
    func updateNSView(_ view: MenuAppearancePreviewHost, context: Context) { view.value = value; view.dark = dark; view.system = system }
}
extension AppDelegate {
    @objc func appearanceSettings() {
        let view = NSHostingView(rootView: MenuAppearancePage())
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 1100)
        SettingsWindow.shared.show(.init(title: "Menu Appearance", detail: "", view: view))
    }
}

struct AppearanceMixedToggle: NSViewRepresentable {
    let title: String
    let value: Bool?
    let changed: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject {
        var owner: AppearanceMixedToggle
        init(_ owner: AppearanceMixedToggle) { self.owner = owner }
        @objc func click(_ sender: NSButton) { owner.changed(owner.value == nil ? true : sender.state == .on) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.click(_:)))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.owner = self; button.title = title; button.isEnabled = enabled
        button.allowsMixedState = value == nil
        button.state = value.map { $0 ? .on : .off } ?? .mixed
    }
}
