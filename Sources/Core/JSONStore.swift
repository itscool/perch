import Foundation

/// Codable values in UserDefaults, bounded and never trusted blindly.
extension UserDefaults {
    /// Decode a saved value, or nil when it is missing, oversized or unreadable.
    func codable<T: Decodable>(_ type: T.Type, forKey key: String, maximumBytes: Int = 65_536) -> T? {
        guard let data = data(forKey: key), data.count <= maximumBytes else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    /// True when a value is stored under the key but cannot be decoded as `type`.
    func hasUnreadable<T: Decodable>(_ type: T.Type, forKey key: String, maximumBytes: Int = 65_536) -> Bool {
        guard let data = data(forKey: key) else { return false }
        return data.count > maximumBytes || (try? JSONDecoder().decode(type, from: data)) == nil
    }
    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        set(try JSONEncoder().encode(value), forKey: key)
    }
}
