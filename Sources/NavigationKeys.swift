import AppKit

struct NavigationPreferences: Codable, Equatable {
    var homeEnd = false
    var pageUpDown = false
    var excludedApps: [String] = NavigationPreferences.defaultExceptions.map { $0.1 }
    var enabled: Bool { homeEnd || pageUpDown }

    // These apps often implement their own navigation behavior.
    static let defaultExceptions: [(String, String)] = [
        ("Terminal", "com.apple.Terminal"), ("iTerm2", "com.googlecode.iterm2"),
        ("Ghostty", "com.mitchellh.ghostty"), ("Warp", "dev.warp.Warp-Stable"),
        ("Alacritty", "org.alacritty"), ("kitty", "net.kovidgoyal.kitty"),
        ("Visual Studio Code", "com.microsoft.VSCode"), ("VSCodium", "com.vscodium"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"), ("Windsurf", "com.exafunction.windsurf"),
        ("Zed", "dev.zed.Zed"), ("Xcode", "com.apple.dt.Xcode"),
        ("Safari", "com.apple.Safari"), ("Google Chrome", "com.google.Chrome"),
        ("Firefox", "org.mozilla.firefox"), ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Brave", "com.brave.Browser"), ("Arc", "company.thebrowser.Browser"),
        ("Opera", "com.operasoftware.Opera"), ("Vivaldi", "com.vivaldi.Vivaldi"),
        ("Finder", "com.apple.finder"), ("Screen Sharing", "com.apple.ScreenSharing"),
        ("Windows App", "com.microsoft.rdc.macos"), ("Parallels Desktop", "com.parallels.desktop.console"),
        ("VMware Fusion", "com.vmware.fusion")
    ]
}

/// Shared mapping rules for the runtime and unposted-event tests.
/// No event posting, app lookup, or preference access.
/// Normal arrows and combinations using Control/Option/Command are untouched.
enum NavigationTransform {
    struct Mapping: Equatable {
        let key: Int64
        let character: UniChar
        let add: CGEventFlags
        let remove: CGEventFlags
        func apply(to event: CGEvent) {
            event.setIntegerValueField(.keyboardEventKeycode, value: key)
            event.flags = event.flags.subtracting(remove).union(add)
            var value = character
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
        }
    }
    static func index(_ key: Int64) -> Int? {
        switch key { case 115: return 0; case 119: return 1; case 116: return 2; case 121: return 3; default: return nil }
    }
    static func mapping(key: Int64, flags: CGEventFlags, homeEnd: Bool, pageUpDown: Bool) -> Mapping? {
        guard flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty else { return nil }
        if homeEnd && (key == 115 || key == 119) {
            return Mapping(key: key == 115 ? 123 : 124, character: key == 115 ? 0xF702 : 0xF703,
                           add: .maskCommand, remove: [.maskSecondaryFn, .maskNumericPad])
        }
        // Shift+Page already performs selection in macOS. Adding Option would
        // select a different chord, so leave it and all modified shortcuts alone.
        if pageUpDown && !flags.contains(.maskShift) && (key == 116 || key == 121) {
            return Mapping(key: key, character: key == 116 ? 0xF72C : 0xF72D,
                           add: .maskAlternate, remove: .maskSecondaryFn)
        }
        return nil
    }
}
