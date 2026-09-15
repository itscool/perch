import SwiftUI

/// All shortcut editors use the Desk layout. Adapters retain each feature's
/// validation, persistence and registration policy; this view only edits values.
struct SettingsShortcutEditor<Key: Hashable>: View {
    let title: String
    var enabled: Binding<Bool>?
    @Binding var key: Key
    let choices: [(String, Key)]
    @Binding var modifiers: Shortcut.Modifiers
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let enabled { Toggle(title, isOn: enabled).font(.headline) }
            else { Text(title).font(.headline) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { keyPicker; modifierControls }.fixedSize()
                VStack(alignment: .leading, spacing: 8) { keyPicker; modifierControls }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var keyPicker: some View {
        Picker("Key", selection: $key) {
            ForEach(choices, id: \.1) { Text($0.0).tag($0.1) }
        }.frame(width: 100).accessibilityLabel(title + " key")
    }
    private var modifierControls: some View {
        HStack(spacing: 8) {
            ForEach(Shortcut.Modifiers.editable, id: \.modifier.rawValue) { entry in
                Toggle(entry.short, isOn: Binding(get: { modifiers.contains(entry.modifier) }, set: { on in
                    var value = modifiers
                    if on { value.insert(entry.modifier) } else { value.remove(entry.modifier) }
                    modifiers = value
                })).accessibilityLabel(title + " " + entry.name)
            }
        }.fixedSize()
    }
}

