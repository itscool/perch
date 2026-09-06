import AppKit

final class AppearanceAwareMenu: NSMenu {
    var appearanceChanged: (() -> Void)?
    override var appearance: NSAppearance? { didSet { appearanceChanged?() } }
}

enum MenuTitleColors {
    /// Native menu updates can run outside AppKit's drawing context. Give them
    /// concrete colors resolved from the menu, rather than the ambient thread.
    static func resolve(_ source: NSAttributedString, in appearance: NSAppearance) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        appearance.performAsCurrentDrawingAppearance {
            source.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: source.length)) { value, range, _ in
                if let color = value as? NSColor, let resolved = color.usingColorSpace(.sRGB) {
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
