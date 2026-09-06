import AppKit

final class AppearanceAwareMenu: NSMenu {
    var appearanceChanged: (() -> Void)?
    override var appearance: NSAppearance? { didSet { appearanceChanged?() } }
}

enum MenuTitleColors {
    /// Resolve only status hints outside AppKit's drawing context. Native command
    /// text keeps its system color so the menu controls its contrast and vibrancy.
    static func resolve(_ source: NSAttributedString, in appearance: NSAppearance) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        appearance.performAsCurrentDrawingAppearance {
            source.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: source.length)) { value, range, _ in
                guard let color = value as? NSColor else { return }
                if color == .labelColor || color == .controlTextColor {
                    // Preserve AppKit's native control color and vibrancy. Baking
                    // labelColor into RGB makes enabled menu commands look dim.
                    result.addAttribute(.foregroundColor, value: NSColor.controlTextColor, range: range)
                } else if let resolved = color.usingColorSpace(.sRGB) {
                    result.addAttribute(.foregroundColor, value: resolved, range: range)
                }
            }
        }
        return result
    }
}

extension AppDelegate {
    func setMenuTitle(_ item: NSMenuItem, _ source: NSAttributedString) {
        menuTitleSources[item] = source
        applyMenuTitle(item, source)
    }

    private func applyMenuTitle(_ item: NSMenuItem, _ source: NSAttributedString) {
        if item.view == nil, let plain = menuPlainTitles[item], source.string == plain {
            // In particular, ordinary Settings/Resume titles need no attributed
            // string. Let AppKit own their enabled/disabled/selected appearance.
            if item.attributedTitle != nil { item.attributedTitle = nil }
            if item.title != plain { item.title = plain }
            return
        }
        // Custom toggle rows already draw in their own effective appearance.
        let text = item.view == nil ? MenuTitleColors.resolve(source, in: menu.effectiveAppearance) : source
        guard item.attributedTitle?.isEqual(to: text) != true else {
            item.view?.needsDisplay = true
            return
        }
        item.attributedTitle = text
        if let view = item.view {
            view.setFrameSize(NSSize(width: max(430, ceil(text.size().width) + 45), height: 24))
            view.needsDisplay = true
        }
    }

    func refreshMenuAppearance() {
        // Reuse the semantic originals, including titles whose text never changes.
        for (item, source) in menuTitleSources { applyMenuTitle(item, source) }
    }
}
