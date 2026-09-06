import AppKit

extension AppDelegate {
    func setMenuTitle(_ item: NSMenuItem, _ source: NSAttributedString) {
        guard menuTitleSources[item]?.isEqual(to: source) != true else {
            // State or enabled status can change independently of the wording.
            item.view?.needsDisplay = true
            return
        }
        menuTitleSources[item] = source
        (item.view as? MenuRowView)?.text = source
    }
    func refreshMenuAppearance() {
        for item in menu.items { item.view?.needsDisplay = true }
    }
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for candidate in menu.items {
            guard let row = candidate.view as? MenuRowView else { continue }
            row.hover = false
            row.keyboardHighlight = candidate === item
        }
    }
    func beginMenuKeyboardHandling() {
        endMenuKeyboardHandling()
        // Only Perch-local key events, only while this menu is open. No global
        // keyboard monitor, event tap, Accessibility grant or idle callback.
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.menuOpen, [36, 49, 76].contains(event.keyCode),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let row = self.menu.highlightedItem?.view as? MenuRowView else { return event }
            _ = row.activate()
            return nil
        }
    }
    func endMenuKeyboardHandling() {
        if let menuKeyMonitor { NSEvent.removeMonitor(menuKeyMonitor) }
        menuKeyMonitor = nil
    }
}
