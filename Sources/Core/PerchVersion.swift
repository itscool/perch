import Foundation

enum PerchVersion {
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    /// The always-increasing build number local builds and releases share, so
    /// two Macs can say which of them is newer.
    static let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
}
