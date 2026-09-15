import Foundation

enum LGFirmwareProfiles {
    struct Family: Decodable {
        let extended: Bool
        let id: UInt16
        let name: String
        let inputProfile: String?
    }
    struct Catalog: Decodable { let schemaVersion: Int; let families: [Family] }
    static let entries: [Family] = {
        guard let url = Bundle.main.url(forResource:"lg-firmware-families",withExtension:"json"),
              let data = try? Data(contentsOf:url), data.count <= 131072,
              let catalog = try? JSONDecoder().decode(Catalog.self,from:data), catalog.schemaVersion == 1,
              catalog.families.count <= 256,
              Set(catalog.families.map { "\($0.extended):\($0.id)" }).count == catalog.families.count else { return [] }
        return catalog.families
    }()
    static func family(identity: UInt16?, extended: UInt16?) -> Family? {
        guard let identity, identity & 0x4000 != 0 else { return nil }
        let usesExtended = identity & 0x8000 != 0
        guard let code = usesExtended ? extended : (identity >> 8) & 0x3f else { return nil }
        return entries.first { $0.extended == usesExtended && $0.id == code }
    }
    static func inputs(identity: UInt16?, extended: UInt16?) -> MonitorProfile? {
        guard let name = family(identity:identity,extended:extended)?.inputProfile else { return nil }
        return MonitorProfiles.entries.first { $0.vendor == 7789 && $0.name == name && $0.confidence != "suggested" }
    }
}
