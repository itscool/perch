import Foundation

/// Persists the appearance and user presets in UserDefaults and tells the
/// menu when they change. Unreadable saved values are reported, never replaced.
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
        if defaults.data(forKey: Self.presetsKey) != nil {
            if let saved = defaults.codable([MenuAppearancePreset].self, forKey: Self.presetsKey), saved.allSatisfy({ $0.appearance.valid }) { presets = saved }
            else { presetProblem = "Saved presets could not be read. They have been kept unchanged." }
        }
        if defaults.data(forKey: Self.key) != nil {
            if let decoded = defaults.codable(MenuAppearance.self, forKey: Self.key), decoded.valid { value = decoded }
            else { problem = "Saved appearance could not be read. Open Reset Settings → Menu appearance to replace it." }
        }
    }
    func save(_ next: MenuAppearance, restoring: Bool = false) {
        guard problem == nil || restoring, next.valid else { return }
        do { try defaults.setCodable(next, forKey: Self.key); value = next; problem = nil; changed?() }
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
    func clearPresetError() { if !defaults.hasUnreadable([MenuAppearancePreset].self, forKey: Self.presetsKey) { presetProblem = nil } }
    func removePreset(_ id: UUID) { guard presetProblem == nil else { return }; writePresets(presets.filter { $0.id != id }) }
    private func writePresets(_ next: [MenuAppearancePreset]) {
        do { try defaults.setCodable(next, forKey: Self.presetsKey); presets = next; presetProblem = nil }
        catch { presetProblem = error.localizedDescription }
    }
}
