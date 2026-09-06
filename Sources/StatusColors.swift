import AppKit

// Small status text needs more contrast than the system accent swatches provide
// on light surfaces. Keep semantic colors dynamic, including Increased Contrast.
enum StatusColors {
    static let success = adaptive("success", light: 0x20743C, dark: 0x82D69B)
    static let warning = adaptive("warning", light: 0x825000, dark: 0xF1BE70)
    static let critical = adaptive("critical", light: 0xAD2434, dark: 0xFF929B)
    static let information = adaptive("information", light: 0x246775, dark: 0x85C8D3)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Perch.status.\(name)")) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let highContrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let rgb = isDark ? dark : light
            let base = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                               green: CGFloat((rgb >> 8) & 255) / 255,
                               blue: CGFloat(rgb & 255) / 255, alpha: 1)
            return highContrast ? base.blended(withFraction: 0.22, of: isDark ? .white : .black) ?? base : base
        }
    }
}
