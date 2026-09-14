import SwiftUI
import Carbon

/// All shortcut editors use the Desk layout. Adapters retain each feature's
/// validation, persistence and registration policy; this view only edits values.
struct SettingsShortcutEditor<Key: Hashable>: View {
    let title: String
    var enabled: Binding<Bool>?
    @Binding var key: Key
    let choices: [(String, Key)]
    @Binding var modifiers: UInt32
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
            ForEach([(controlKey, "Ctrl"), (optionKey, "Opt"), (cmdKey, "Cmd"), (shiftKey, "Shift")], id: \.0) { flag, name in
                Toggle(name, isOn: Binding(get: { modifiers & UInt32(flag) != 0 }, set: { on in
                    var value = modifiers
                    if on { value |= UInt32(flag) } else { value &= ~UInt32(flag) }
                    modifiers = value
                })).accessibilityLabel(title + " " + name)
            }
        }.fixedSize()
    }
}

