import AppKit
import Foundation

struct CatalogEntry: Codable {
    let target: AgentTarget
    let category: String
    let note: String
    let sources: [String]
}
struct AgentCatalog: Codable {
    let schemaVersion: Int
    let reviewedOn: String
    let entries: [CatalogEntry]
    static let installed = SafetyFiles.base.appendingPathComponent("agents.json")
    static func read(_ url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        guard data.count < 256_000 else { throw AppError(message: "Catalog is too large.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    func validate() throws {
        let generic = Set(["sh","bash","zsh","fish","node","python","python3","bun","ruby","osascript","launchd","Perch","PerchGuard"])
        guard schemaVersion == 1, entries.count <= 150, reviewedOn.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { throw AppError(message: "Unsupported catalog format.") }
        var ids = Set<String>()
        for entry in entries {
            let t = entry.target
            guard ids.insert(t.id).inserted, !t.id.isEmpty, t.id.count < 120, !t.name.isEmpty, t.name.count < 100,
                  ["app","cli"].contains(t.kind), !t.match.isEmpty, t.match.count < 160,
                  !t.match.contains("/"), !t.match.contains("*"), !t.match.contains("\n"), !t.match.contains("\0"),
                  t.match != "local.scott.perch", !generic.contains(t.match),
                  !entry.sources.isEmpty, entry.sources.allSatisfy({ URL(string: $0)?.scheme == "https" }) else {
                throw AppError(message: "Invalid catalog entry: \(t.name). Catalogs can contain only named apps/agent executables, never commands or generic runtimes.")
            }
        }
    }
    static var cachedRevision: FileRevision?
    static var cachedCatalog: Self?
    static var checkedCatalog = false
    static func available() -> Self? {
        let revision = FileRevision.read(installed)
        if checkedCatalog && revision == cachedRevision { return cachedCatalog }
        cachedRevision = revision; checkedCatalog = true
        cachedCatalog = try? read(installed)
        return cachedCatalog
    }
    static func install(from url: URL) throws {
        let catalog = try read(url)
        try SafetyFiles.write(catalog, to: installed)
    }
    func suggestions(for current: SafetyConfiguration) -> SafetyConfiguration {
        var result = current
        for entry in entries where !result.targets.contains(where: { $0.id == entry.target.id }) {
            var target = entry.target
            target.enabled = true // New targets are checked by default; existing choices are preserved.
            result.targets.append(target)
        }
        return result
    }
}

extension AppDelegate {
    @objc func importAgentCatalog() {
        let panel = NSOpenPanel()
        panel.title = "Import agent catalog"
        panel.allowedContentTypes = [.json]
        guard SettingsWindow.shared.open(panel) == .OK, let url = panel.url else { return }
        do {
            try AgentCatalog.install(from: url)
            let alert = NSAlert()
            alert.messageText = "Agent catalog updated"
            alert.informativeText = "New candidates are checked by default. Your existing on/off choices are preserved."
            SettingsWindow.shared.run(alert)
        } catch { showError(error) }
    }
    @objc func reviewCatalogChanges() {
        guard let catalog = AgentCatalog.available() else { showError(AppError(message: "No valid agent catalog is installed.")); return }
        var config = SafetyConfiguration.load()
        let updates = catalog.entries.filter { entry in config.targets.contains { $0.id == entry.target.id && ($0.kind != entry.target.kind || $0.match != entry.target.match) } }
        let alert = NSAlert()
        alert.messageText = "Review catalog updates"
        alert.informativeText = updates.isEmpty ? "No matching rules have changed for your existing targets. New candidates can be enabled in Safety settings. Catalog reviewed: \(catalog.reviewedOn)." : "These existing targets have updated matching rules:\n\n" + updates.map { entry in
            let old = config.targets.first { $0.id == entry.target.id }!
            return "\(old.name): \(old.match) → \(entry.target.match)"
        }.joined(separator: "\n") + "\n\nApply these definitions while preserving your on/off selections?"
        alert.addButton(withTitle: updates.isEmpty ? "OK" : "Cancel")
        if !updates.isEmpty { alert.addButton(withTitle: "Apply Updates") }
        guard SettingsWindow.shared.run(alert) == .alertSecondButtonReturn else { return }
        for entry in updates {
            if let index = config.targets.firstIndex(where: { $0.id == entry.target.id }) {
                var target = entry.target
                target.enabled = config.targets[index].enabled
                config.targets[index] = target
            }
        }
        do { try config.save() } catch { showError(error) }
    }
}

func runCatalogTests() throws {
    let entry = CatalogEntry(target: .init(id: "catalog:test", name: "Test Agent", kind: "cli", match: "test-agent"), category: "agent", note: "fixture", sources: ["https://example.com/docs"])
    let catalog = AgentCatalog(schemaVersion: 1, reviewedOn: "2026-09-04", entries: [entry])
    try catalog.validate()
    let original = SafetyConfiguration()
    let merged = catalog.suggestions(for: original)
    guard merged.targets.last?.enabled == true, Array(merged.targets.dropLast()) == original.targets else { throw AppError(message: "Catalog changed active selections.") }
    var optedOut = merged
    optedOut.targets[optedOut.targets.count - 1].enabled = false
    guard catalog.suggestions(for: optedOut) == optedOut else { throw AppError(message: "Catalog overrode an explicit opt-out") }
    let bad = CatalogEntry(target: .init(id: "bad", name: "Shell", kind: "cli", match: "zsh"), category: "bad", note: "", sources: ["https://example.com"])
    do { try AgentCatalog(schemaVersion: 1, reviewedOn: "2026-09-04", entries: [bad]).validate(); throw AppError(message: "Generic shell catalog entry accepted.") }
    catch let error as AppError { if error.message == "Generic shell catalog entry accepted." { throw error } }
    print("PASS: catalog validation; generic shells rejected; new candidates checked; existing selections preserved")
}
