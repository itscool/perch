import Foundation

/// Model/layout identity survives reconnects. No serial number or transient
/// registry ID is persisted, and USB/Bluetooth layouts remain independent.
struct NavigationKeyboardIdentity: Codable, Hashable {
    let vendor: Int
    let product: Int
    let version: Int
    let name: String
    let transport: String
    let usages: [UInt32]
    var canRemember: Bool {
        (1...65535).contains(vendor) && (1...65535).contains(product) && !name.isEmpty && name.utf8.count <= 256 &&
        NavigationDeviceScope.isExternal(builtIn: false, transport: transport) && usages.count <= NavigationLearning.usages.count &&
        usages == Set(usages).sorted() && usages.allSatisfy { NavigationLearning.allowed($0) }
    }
}

struct NavigationKeyboardProfile: Codable, Equatable {
    let identity: NavigationKeyboardIdentity
    // Home, End, Page Up, Page Down. nil means the user marked a key absent.
    let keys: [UInt32?]
    var valid: Bool {
        let present = keys.compactMap { $0 }
        return identity.canRemember && keys.count == 4 && Set(present).count == present.count &&
            present.allSatisfy { NavigationLearning.allowed($0) && identity.usages.contains($0) }
    }
    var hasHomeEnd: Bool { valid && keys[0] != nil && keys[1] != nil }
    var hasPageKeys: Bool { valid && keys[2] != nil && keys[3] != nil }
}

enum NavigationLearning {
    // Function/navigation keys only. Letters, digits, keypad typing, modifiers,
    // Return/Escape and consumer controls never enter the setup callback.
    static let usages: [UInt32] = Array(0x3A...0x52) + Array(0x68...0x73)
    static func allowed(_ usage: UInt32) -> Bool { usages.contains(usage) }
}

enum KeyboardNavigationProfiles {
    static let key = "keyboard.navigationProfiles.v1"
    static let changed = Notification.Name("PerchNavigationProfilesChanged")
    static func read(defaults: UserDefaults = .standard) throws -> [NavigationKeyboardProfile] {
        guard let object = defaults.object(forKey: key) else { return [] }
        guard let data = object as? Data, data.count <= 131_072, let records = try? JSONDecoder().decode([NavigationKeyboardProfile].self, from: data),
              records.count <= 64, Set(records.map { $0.identity }).count == records.count, records.allSatisfy({ $0.valid }) else {
            throw AppError(message: "Saved keyboard profiles could not be read. Reset the saved profiles in navigation setup.")
        }
        return records
    }
    static func save(_ record: NavigationKeyboardProfile, defaults: UserDefaults = .standard) throws {
        guard record.valid else { throw AppError(message: "This keyboard’s key layout could not be saved. Recheck the keyboard and try again.") }
        var records = try read(defaults: defaults)
        records.removeAll { $0.identity == record.identity }
        guard records.count < 64 else { throw AppError(message: "Saved keyboard profiles are full. Reset an unused profile before adding another.") }
        records.append(record)
        let data = try JSONEncoder().encode(records)
        guard data.count <= 131_072 else { throw AppError(message: "The saved keyboard profiles are too large. Reset an unused profile first.") }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func reset(_ identity: NavigationKeyboardIdentity?, defaults: UserDefaults = .standard) throws {
        if let identity {
            let records = try read(defaults: defaults).filter { $0.identity != identity }
            defaults.set(try JSONEncoder().encode(records), forKey: key)
        } else { defaults.removeObject(forKey: key) }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

struct BundledNavigationProfile: Codable {
    let name: String
    let vendor: Int
    let product: Int
    let transports: [String]
    let deviceNames: [String]
    let keys: [UInt32?]
    let verification: String
    let verifiedOn: String
    let evidence: [String]
    func matches(_ identity: NavigationKeyboardIdentity) -> Bool {
        vendor == identity.vendor && product == identity.product && transports.contains(identity.transport) &&
        deviceNames.contains(identity.name) && ["key-delivery", "documented-hid-layout"].contains(verification) && !evidence.isEmpty &&
        NavigationKeyboardProfile(identity: identity, keys: keys).valid
    }
}

enum BundledNavigationProfiles {
    struct Catalog: Codable { let schemaVersion: Int; let profiles: [BundledNavigationProfile] }
    // Read once, outside the input path. Missing/invalid data leaves devices
    // unrecognized; it never falls back to a brand-name or wildcard match.
    static let entries: [BundledNavigationProfile] = {
        guard let url = Bundle.main.url(forResource: "keyboard-profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 131_072,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1,
              catalog.profiles.count <= 128 else { return [] }
        return catalog.profiles
    }()
}

struct KeyboardRegistrationStatus: Equatable {
    let name: String
    let profile: NavigationKeyboardProfile?
    let detail: String
    var needsSetup: Bool { profile == nil }
    static func assess(_ identity: NavigationKeyboardIdentity, saved: [NavigationKeyboardProfile], bundled: [BundledNavigationProfile] = BundledNavigationProfiles.entries) -> Self {
        if let profile = saved.last(where: { $0.identity == identity && $0.valid }) {
            let detail = profile.keys.allSatisfy { $0 == nil } ? "✓ Recognized · no navigation keys" : "✓ Recognized · saved navigation layout"
            return .init(name: identity.name, profile: profile, detail: detail)
        }
        if let known = bundled.first(where: { $0.matches(identity) }) {
            return .init(name: identity.name, profile: .init(identity: identity, keys: known.keys), detail: "✓ Recognized · bundled \(known.name) layout" + (known.verification == "key-delivery" ? "" : " · documented, not hardware-tested"))
        }
        return .init(name: identity.name, profile: nil, detail: "⚠ Unrecognized navigation layout · set up this keyboard")
    }
}
