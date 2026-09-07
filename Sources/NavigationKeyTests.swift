import AppKit

func runNavigationKeyTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let preferences = NavigationPreferences()
    try check(!preferences.enabled, "Navigation remapping was enabled without a user choice")
    for key: Int64 in [115, 119, 116, 121] {
        for shift in [false, true] {
            let flags: CGEventFlags = shift ? [.maskShift, .maskSecondaryFn, .maskAlphaShift] : [.maskSecondaryFn, .maskAlphaShift]
            let mapping = NavigationTransform.mapping(key: key, flags: flags, homeEnd: true, pageUpDown: true)
            if key == 116 || key == 121 {
                try check(shift ? mapping == nil : mapping?.key == key, "Page selection or direction was changed")
            } else {
                try check(mapping?.key == (key == 115 ? 123 : 124), "Home/End moved to the wrong edge")
            }
            for down in [false, true] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
                event.flags = flags
                event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
                event.setIntegerValueField(.eventSourceUserData, value: 987)
                mapping?.apply(to: event)
                try check(event.flags.contains(.maskShift) == shift && event.flags.contains(.maskAlphaShift), "Navigation lost selection or Caps Lock flags")
                try check(event.type == (down ? .keyDown : .keyUp) && event.getIntegerValueField(.keyboardEventAutorepeat) == 1 && event.getIntegerValueField(.eventSourceUserData) == 987, "Navigation changed event identity, key direction or repeat")
                if let mapping {
                    try check(event.flags.contains(key == 115 || key == 119 ? .maskCommand : .maskAlternate), "Navigation chord modifier was missing")
                    try check(!event.flags.contains(.maskSecondaryFn), "Fn leaked into the translated chord")
                    var character: UniChar = 0, count = 0
                    event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &count, unicodeString: &character)
                    try check(count == 1 && character == mapping.character, "Navigation retained the original function-key character")
                }
            }
        }
        for modifier: CGEventFlags in [.maskControl, .maskCommand, .maskAlternate, [.maskCommand,.maskShift]] {
            try check(NavigationTransform.mapping(key: key, flags: modifier, homeEnd: true, pageUpDown: true) == nil, "An existing modified shortcut was replaced")
        }
        try check(NavigationTransform.mapping(key: key, flags: [], homeEnd: false, pageUpDown: false) == nil, "Disabled navigation changed a key")
    }
    for key: Int64 in [0, 36, 53, 55, 59, 123, 124, 125, 126] {
        try check(NavigationTransform.mapping(key: key, flags: [], homeEnd: true, pageUpDown: true) == nil, "Typing, arrows, or modifier keys were changed")
    }
    try check(NavigationTransform.mapping(key: 115, flags: [], homeEnd: false, pageUpDown: true) == nil && NavigationTransform.mapping(key: 116, flags: [], homeEnd: true, pageUpDown: false) == nil, "Independent navigation switches affected each other")
    print("PASS: optional navigation modes; line/page direction; Shift selection, key-up, repeats and flags; unrelated typing/arrows/shortcuts preserved; unposted events only")
}
