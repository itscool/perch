import Foundation

struct MonitorProfile: Codable {
    let name: String
    let vendor: UInt32
    let model: UInt32
    let alternate: Bool
    let confidence: String
    let inputs: [MonitorInput]
    let evidence: [String]
    var valid: Bool {
        !name.isEmpty && vendor > 0 && model > 0 && !evidence.isEmpty && inputs.count >= 2 && inputs.count <= 16 &&
        inputs.allSatisfy { $0.valid } && Set(inputs.map { $0.code }).count == inputs.count && ["community-documented","suggested"].contains(confidence)
    }
}
enum MonitorProfiles {
    struct Catalog: Codable { let schemaVersion: Int; let profiles: [MonitorProfile] }
    static let entries: [MonitorProfile] = {
        guard let url = Bundle.main.url(forResource:"monitor-profiles",withExtension:"json"),
              let data = try? Data(contentsOf:url), data.count <= 131072,
              let catalog = try? JSONDecoder().decode(Catalog.self,from:data), catalog.schemaVersion == 1,
              catalog.profiles.count <= 256, catalog.profiles.allSatisfy({ $0.valid }) else { return [] }
        return catalog.profiles
    }()
    static func match(_ display: MonitorDescriptor) -> MonitorProfile? {
        let matches = entries.filter { $0.vendor == display.vendor && $0.model == display.model }
        return matches.count == 1 ? matches[0] : nil
    }
}
