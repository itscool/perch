import AppKit

extension AppDelegate {
    static func applicationMenu(quitTarget: AnyObject, quitAction: Selector) -> NSMenu {
        let main = NSMenu(), app = NSMenu(title: "Perch")
        let root = NSMenuItem(title: "Perch", action: nil, keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit Perch", action: quitAction, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command; quit.target = quitTarget
        app.addItem(quit); root.submenu = app; main.addItem(root)
        return main
    }
    func installApplicationMenu() {
        NSApp.mainMenu = Self.applicationMenu(quitTarget: self, quitAction: #selector(quit))
    }
    // Custom status-menu views do not supply AppKit's ordinary key-equivalent
    // dispatch. Route the displayed shortcut through the same command action.
    func handleMenuShortcut(_ event: NSEvent) -> Bool {
        guard menuOpen, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "q",
              let item = menu.items.first(where: { $0.keyEquivalent == "q" }),
              let row = item.view as? MenuRowView else { return false }
        return row.activate()
    }
    func handleMenuActivation(_ event: NSEvent) -> Bool {
        guard menuOpen, [36, 49, 76].contains(event.keyCode),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        // Native highlightedItem may still name the previous keyboard selection
        // after the mouse enters a custom row. Activate what we actually show.
        if let row = menu.items.compactMap({ $0.view as? MenuRowView }).first(where: { $0.highlighted }) {
            _ = row.activate()
        }
        // Consume even when the selection disappeared or became disabled: native
        // fallback must not dispatch the stale selection instead.
        return true
    }

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
            guard let self else { return event }
            if self.handleMenuShortcut(event) { return nil }
            return self.handleMenuActivation(event) ? nil : event
        }
    }
    func endMenuKeyboardHandling() {
        if let menuKeyMonitor { NSEvent.removeMonitor(menuKeyMonitor) }
        menuKeyMonitor = nil
    }
}
