import Foundation

enum PerchVersion {
    /// Legacy bundles stored only major.minor; new bundles store all three
    /// components for native consumers such as Sparkle. Never append twice.
    static func display(version: String, build: String) -> String {
        let release = version.split(separator: ".").prefix(2).joined(separator: ".")
        return release + "." + build
    }
    static let current = display(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
}
