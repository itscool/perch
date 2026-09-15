import AppKit
import SwiftUI

/// The Menu Appearance settings page.
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
            if let error = store.presetProblem { SettingsFeedback(text: error) }
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
            if let problem = store.problem { SettingsFeedback(text: problem) }
            Group {
                HStack(spacing: 12) {
                    AppearanceMixedToggle(title: "Edge to edge", value: both && style.isEdgeToEdge != otherStyle.isEdgeToEdge ? nil : style.isEdgeToEdge) { next in edit { $0.edgeToEdge = next } }
                        .frame(height: 22).fixedSize(horizontal: true, vertical: false).help("Remove the decoration margin. Full-width bands have square corners and no left/right borders. Turning this off restores your saved sides and radius.")
                    AppearanceMixedToggle(title: "Fade left", value: both && (style.fadeLeft == true) != (otherStyle.fadeLeft == true) ? nil : style.fadeLeft == true) { next in edit { $0.fadeLeft = next } }.frame(height: 22).fixedSize(horizontal: true, vertical: false).disabled(neither { $0.isEdgeToEdge })
                    AppearanceMixedToggle(title: "Fade right", value: both && (style.fadeRight == true) != (otherStyle.fadeRight == true) ? nil : style.fadeRight == true) { next in edit { $0.fadeRight = next } }.frame(height: 22).fixedSize(horizontal: true, vertical: false).disabled(neither { $0.isEdgeToEdge })
                    Spacer(minLength: 0)
                }
                slider("Fade distance", path: \.fadeFraction, range: 0...1, suffix: "")
                    .disabled(neither { $0.isEdgeToEdge && ($0.fadeLeft == true || $0.fadeRight == true) })
                    .help("0 means no fade; 1 fades across the entire width. Applies to each selected edge.")
                Text("Border").font(.headline).padding(.top, 4)
                HStack(spacing: 10) {
                    scopePicker("Border area", path: \.borderScope)
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
                HStack { scopePicker("Highlight area", path: \.backgroundScope); Spacer(minLength: 0) }
                HStack(spacing: 8) {
                    toggle("Use grey highlights", path: \.greyBackground).frame(width: 145, alignment: .leading)
                        .disabled(neither { $0.backgroundScope != .none })
                    valueSlider("Grey highlight shade", path: \.greyLevel, range: 0...1)
                        .disabled(neither { $0.greyBackground && $0.backgroundScope != .none })
                }
                slider("Highlight intensity", path: \.backgroundIntensity, range: 0...1).disabled(neither { $0.backgroundScope != .none })
                Text("Titles").font(.headline).padding(.top, 4)
                if system {
                    AppearanceMixedToggle(title: "Show System title", value: both && (style.showTitle != false) != (otherStyle.showTitle != false) ? nil : style.showTitle != false) { next in edit { $0.showTitle = next } }.frame(height: 22)
                } else {
                    slider("Space above titles", path: \.gap, range: 0...8, suffix: "pt")
                }
                HStack(spacing: 12) {
                    toggle("Tint title text to its section color", path: \.tintTitle).frame(width: 275, alignment: .leading)
                    valueSlider("Title tint", path: \.titleIntensity, range: 0...1).disabled(neither { $0.tintTitle })
                }
                toggle("Show title icons", path: \.showIcon)
                HStack(spacing: 12) {
                    toggle("Tint icons to their section color", path: \.iconTinted).frame(width: 275, alignment: .leading)
                    valueSlider("Icon tint", path: \.iconTintStrength, range: 0...1).disabled(neither { $0.showIcon && $0.iconTinted })
                }.disabled(neither { $0.showIcon })
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
        HStack(spacing: 8) {
            Text(label).frame(width: 145, alignment: .leading)
            Picker(label, selection: selection(path)) {
                if mixed(path) { Text("Mixed").tag(nil as MenuSectionAppearance.Scope?).disabled(true) }
                ForEach(MenuSectionAppearance.Scope.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.labelsHidden().frame(width: 130)
        }

    }
    func valueSlider(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Double>, range: ClosedRange<Double>, suffix: String = "%") -> some View {
        HStack(spacing: 8) {
            Slider(value: binding(path), in: range, step: suffix == "%" || suffix.isEmpty ? 0.01 : 0.1).accessibilityLabel(label).accessibilityValue(mixed(path) ? "Mixed" : String(style[keyPath: path]))
            Text(mixed(path) ? "Mixed" : suffix == "%" ? "\(Int(style[keyPath: path] * 100))%" : suffix.isEmpty ? String(format: "%.2f", style[keyPath: path]) : String(format: "%.1f %@", style[keyPath: path], suffix)).monospacedDigit().frame(width: 65, alignment: .trailing)
        }
    }
    func slider(_ label: String, path: WritableKeyPath<MenuSectionAppearance, Double>, range: ClosedRange<Double>, suffix: String = "%") -> some View {
        HStack {
            Text(label).frame(width: 145, alignment: .leading)
            valueSlider(label, path: path, range: range, suffix: suffix)
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
