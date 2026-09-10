import AppKit
import SwiftUI

struct MenuSectionAppearance: Codable, Equatable {
    enum Scope: String, Codable, CaseIterable { case none = "None", title = "Title", full = "Full section" }
    enum Side: String, Codable, CaseIterable { case left = "Left", right = "Right", top = "Top", bottom = "Bottom" }
    var borderScope: Scope = .title
    var sides: Set<Side> = [.top]
    var thickness = 2.0
    var borderIntensity = 1.0
    var backgroundScope: Scope = .title
    var backgroundIntensity = 0.075
    var greyBackground = false
    var greyLevel = 0.5
    var radius = 0.0
    var tintTitle = true
    var titleIntensity = 0.45
    var showIcon = true
    var gap = 3.0
    static var system: Self { var s = Self(); s.borderScope = .none; s.backgroundScope = .none; s.gap = 0; return s }
    var valid: Bool {
        [(thickness, 0...6), (borderIntensity, 0...1), (backgroundIntensity, 0...1),
         (greyLevel, 0...1), (radius, 0...12), (titleIntensity, 0...1), (gap, 0...8)].allSatisfy { $0.0.isFinite && $0.1.contains($0.0) }
    }
}
struct MenuAppearance: Codable, Equatable {
    var sections = MenuSectionAppearance()
    var system = MenuSectionAppearance.system
    var valid: Bool { sections.valid && system.valid }
    func style(_ name: String?) -> MenuSectionAppearance { name == "System" ? system : sections }
}
final class MenuAppearanceStore: ObservableObject {
    static let shared = MenuAppearanceStore()
    static let key = "menu.appearance"
    @Published private(set) var value = MenuAppearance()
    @Published private(set) var problem: String?
    private let defaults: UserDefaults
    var changed: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            if let decoded = try? JSONDecoder().decode(MenuAppearance.self, from: data), decoded.valid { value = decoded }
            else { problem = "Saved appearance could not be read. Restore defaults to replace it." }
        }
    }
    func save(_ next: MenuAppearance, restoring: Bool = false) {
        guard problem == nil || restoring, next.valid else { return }
        do { let data = try JSONEncoder().encode(next); defaults.set(data, forKey: Self.key); value = next; problem = nil; changed?() }
        catch { problem = error.localizedDescription }
    }
}

extension MenuRowView {
    func drawDecoration(_ style: MenuSectionAppearance) {
        let isTitle = kind == .section
        let top = panelPart == .top, bottom = panelPart == .bottom
        let tint = Self.tint(for: panelSection ?? "")
        func area(_ scope: MenuSectionAppearance.Scope) -> NSRect? {
            guard scope != .none, scope == .full || isTitle else { return nil }
            return NSRect(x: 4, y: 0, width: bounds.width - 8, height: bounds.height - (isTitle ? style.gap : 0))
        }
        func shape(_ area: NSRect, full: Bool) -> NSBezierPath {
            var rect = area
            // Extend beyond intermediate rows so only the outer section corners round.
            if full && !top { rect.size.height += max(12, style.radius * 2) }
            if full && !bottom { rect.origin.y -= max(12, style.radius * 2); rect.size.height += max(12, style.radius * 2) }
            return NSBezierPath(roundedRect: rect, xRadius: style.radius, yRadius: style.radius)
        }
        if let rect = area(style.backgroundScope) {
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let color = style.greyBackground ? NSColor(white: style.greyLevel, alpha: 1) : tint
            color.withAlphaComponent(style.backgroundIntensity).setFill()
            shape(rect, full: style.backgroundScope == .full).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if let rect = area(style.borderScope), style.thickness > 0, !style.sides.isEmpty {
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let full = style.borderScope == .full
            let clips = NSBezierPath()
            let band = style.thickness + style.radius
            if style.sides.contains(.left) { clips.appendRect(NSRect(x: rect.minX, y: rect.minY, width: band, height: rect.height)) }
            if style.sides.contains(.right) { clips.appendRect(NSRect(x: rect.maxX-band, y: rect.minY, width: band, height: rect.height)) }
            if style.sides.contains(.top) && (!full || top) { clips.appendRect(NSRect(x: rect.minX, y: rect.maxY-band, width: rect.width, height: band)) }
            if style.sides.contains(.bottom) && (!full || bottom) { clips.appendRect(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: band)) }
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
    func binding<T>(_ path: WritableKeyPath<MenuSectionAppearance, T>) -> Binding<T> {
        Binding(get: { (system ? store.value.system : store.value.sections)[keyPath: path] }, set: { next in
            var value = store.value
            if system { value.system[keyPath: path] = next } else { value.sections[keyPath: path] = next }
            store.save(value)
        })
    }
    var style: MenuSectionAppearance { system ? store.value.system : store.value.sections }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MenuAppearancePreview(value: store.value).frame(height: 168).accessibilityLabel("Menu appearance preview")
            Picker("Section to customize", selection: $system) { Text("Rainbow sections").tag(false); Text("System").tag(true) }.pickerStyle(.segmented)
            if let problem = store.problem { Text(problem).foregroundStyle(.orange) }
            Group {
                HStack { Text("Border").font(.headline); Spacer(); Picker("Border area", selection: binding(\.borderScope)) { ForEach(MenuSectionAppearance.Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 200) }
                HStack { ForEach(MenuSectionAppearance.Side.allCases, id: \.self) { side in
                    Toggle(side.rawValue, isOn: Binding(get: { style.sides.contains(side) }, set: { enabled in var sides = style.sides; if enabled { sides.insert(side) } else { sides.remove(side) }; binding(\.sides).wrappedValue = sides }))
                } }.disabled(style.borderScope == .none)
                slider("Thickness", path: \.thickness, range: 0...6, suffix: "pt")
                slider("Line intensity", path: \.borderIntensity, range: 0...1)
                HStack { Text("Background").font(.headline); Spacer(); Picker("Highlight area", selection: binding(\.backgroundScope)) { ForEach(MenuSectionAppearance.Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 200) }
                Toggle("Use grey highlights", isOn: binding(\.greyBackground))
                if style.greyBackground { slider("Grey shade", path: \.greyLevel, range: 0...1) }
                slider("Highlight intensity", path: \.backgroundIntensity, range: 0...1)
                HStack { Text("Titles & shape").font(.headline); Spacer() }
                Toggle("Tint title text to its section color", isOn: binding(\.tintTitle))
                if style.tintTitle { slider("Title tint", path: \.titleIntensity, range: 0...1) }
                Toggle("Show title icons", isOn: binding(\.showIcon))
                slider("Corner radius", path: \.radius, range: 0...12, suffix: "pt")
                slider("Space above titles", path: \.gap, range: 0...8, suffix: "pt")
            }.disabled(store.problem != nil)
            HStack {
                Menu("Style presets") {
                    Button("Perch original") { replace(system ? .system : .init()) }
                    Button("Quiet") { var s = MenuSectionAppearance(); s.borderScope = .none; s.backgroundScope = .none; s.tintTitle = false; replace(s) }
                    Button("Outlined sections") { var s = MenuSectionAppearance(); s.borderScope = .full; s.sides = Set(MenuSectionAppearance.Side.allCases); s.backgroundScope = .full; s.radius = 6; s.thickness = 1; replace(s) }
                }
                Spacer()
                Button("Restore all defaults") { store.save(MenuAppearance(), restoring: true) }.help("Restore Perch’s original appearance for rainbow sections and System.")
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    func replace(_ style: MenuSectionAppearance) { var value = store.value; if system { value.system = style } else { value.sections = style }; store.save(value, restoring: true) }
    func slider(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Double>, range: ClosedRange<Double>, suffix: String = "%") -> some View {
        HStack {
            Text(label).frame(width: 145, alignment: .leading)
            Slider(value: binding(path), in: range).accessibilityLabel(label)
            Text(suffix == "%" ? "\(Int(style[keyPath: path] * 100))%" : String(format: "%.1f %@", style[keyPath: path], suffix)).monospacedDigit().frame(width: 65, alignment: .trailing)
        }
    }
}
final class MenuAppearancePreviewHost: NSView {
    var value = MenuAppearance() { didSet { needsLayout = true } }
    var items: [NSMenuItem] = []
    var rows: [MenuRowView] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        for (title, kind) in [("System", MenuRowView.Kind.section), ("CPU 12% · Memory 48%", .information), ("Sleep", .section), ("Keep awake", .toggle), ("Including with lid closed", .toggle), ("Settings…", .command)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let row = MenuRowView(item: item, kind: kind)
            // NSMenu takes ownership of its item views' frames. A preview retains
            // the model items directly and owns its own layout instead.
            items.append(item); rows.append(row); addSubview(row)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        var y = bounds.height
        for (i, row) in rows.enumerated() {
            row.panelSection = i < 2 ? "System" : "Sleep"
            row.panelPart = i == 0 || i == 2 ? .top : i == 1 || i == 5 ? .bottom : .middle
            row.appearanceOverride = value
            let height: CGFloat = row.kind == .section ? 22 + value.style(row.panelSection).gap : 24
            y -= height; row.frame = NSRect(x: 0, y: y, width: bounds.width, height: height); row.needsDisplay = true
        }
    }
}
struct MenuAppearancePreview: NSViewRepresentable {
    let value: MenuAppearance
    func makeNSView(context: Context) -> MenuAppearancePreviewHost { MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 540, height: 168)) }
    func updateNSView(_ view: MenuAppearancePreviewHost, context: Context) { view.value = value }
}
extension AppDelegate {
    @objc func appearanceSettings() {
        let view = NSHostingView(rootView: MenuAppearancePage())
        view.frame = NSRect(x: 0, y: 0, width: 572, height: 880)
        SettingsWindow.shared.show(.init(title: "Menu Appearance", detail: "Customize this Mac’s menu. Changes save immediately; the preview uses the same renderer as the menu.", view: view))
    }
}
