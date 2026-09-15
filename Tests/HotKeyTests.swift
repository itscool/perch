import AppKit
import Carbon

/// Registration, conflict detection, transactional replacement and release
/// for the shared Carbon registrar. Nothing presses a key, so no hotkey fires.
func runHotKeyTests() throws {
    _ = NSApplication.shared
    func check(_ value: Bool, _ message: String) throws { if !value { throw PerchError(message) } }
    // Wire formats captured before the shared type replaced the per-feature ones.
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    for (value, json) in [(Shortcut(), #"{"enabled":true,"key":53,"modifiers":6400}"#),
                          (Shortcut(key: UInt32(kVK_F12), modifiers: [.shift, .command], enabled: false), #"{"enabled":false,"key":111,"modifiers":768}"#)] {
        try check(String(data: try encoder.encode(value), encoding: .utf8) == json, "Shortcut wire format changed: \(json)")
        try check(try decoder.decode(Shortcut.self, from: Data(json.utf8)) == value, "Shortcut no longer reads its saved format")
    }
    try check(String(data: try encoder.encode(KVMShortcut(key: "F8", shift: true)), encoding: .utf8) == #"{"command":true,"control":true,"key":"F8","option":true,"shift":true}"#, "Desk shortcut wire format changed")
    try check(String(data: try encoder.encode(CountdownShortcuts()), encoding: .utf8) == #"{"decrease":{"enabled":true,"key":27,"modifiers":6400},"increase":{"enabled":true,"key":24,"modifiers":6400}}"#, "Countdown shortcut wire format changed")
    try check(Shortcut.Modifiers(NSEvent.ModifierFlags([.control, .command])) == [.control, .command] && Shortcut.Modifiers(CGEventFlags([.maskAlternate, .maskShift])) == [.option, .shift], "Modifier flag conversion changed")
    try check(Shortcut(key: 3).matches(keyCode: 3, flags: [.maskControl, .maskAlternate, .maskCommand]) && !Shortcut(key: 3).matches(keyCode: 3, flags: [.maskControl, .maskCommand]) && !Shortcut(key: 3, enabled: false).matches(keyCode: 3, flags: [.maskControl, .maskAlternate, .maskCommand]), "Key event matching changed")
    try check(ShortcutKey.desk.map(\.name) == (1...20).map { "F\($0)" } && ShortcutKey.emergency.first?.name == "Esc" && ShortcutKey.countdown.prefix(2).map(\.name) == ["+", "−"] && ShortcutKey.code(named: "S") == UInt32(kVK_ANSI_S) && ShortcutKey.name(UInt32(kVK_Escape)) == "Esc", "Offered key subsets changed")

    let registry = ShortcutRegistry()
    registry.provide("a") { [ShortcutClaim(owner: "action A", shortcut: Shortcut(key: 1)), ShortcutClaim(owner: "off", shortcut: Shortcut(key: 2, enabled: false))] }
    registry.provide("b") { [ShortcutClaim(owner: "action B", shortcut: Shortcut(key: 1, modifiers: .standard))] }
    try check(registry.conflicts(with: Shortcut(key: 1), excluding: "a").map(\.owner) == ["action B"] && registry.conflicts(with: Shortcut(key: 1), excluding: "b").map(\.owner) == ["action A"], "Registry did not exclude the asking source")
    try check(registry.conflicts(with: Shortcut(key: 2), excluding: "b").isEmpty && registry.conflicts(with: Shortcut(key: 1, enabled: false), excluding: "b").isEmpty, "Disabled shortcuts were reported as conflicts")
    try check(registry.problem(with: Shortcut(key: 1), excluding: "b") == "⌃⌥⌘? is already used by action A. Choose another combination." || registry.problem(with: Shortcut(key: 1), excluding: "b")?.contains("action A") == true, "Conflict sentence changed")
    try check(registry.owns(keyCode: 1, flags: [.maskControl, .maskAlternate, .maskCommand], excluding: "b") && !registry.owns(keyCode: 1, flags: [.maskControl, .maskAlternate, .maskCommand], excluding: nil) == false, "Registry key ownership changed")

    let first = HotKey()
    let second = HotKey()
    let test = Shortcut(key: UInt32(kVK_F12), modifiers: [.control, .option, .shift, .command])
    try first.register(test)
    try check(first.active && first.matches(test), "Global shortcut did not register.")
    var conflictDetected = false
    do { try second.register(test) } catch { conflictDetected = true }
    try check(conflictDetected, "Shortcut collision was not detected.")
    let other = Shortcut(key: UInt32(kVK_F11), modifiers: test.modifiers)
    try second.register(other)
    do { try first.register(other); throw PerchError("Replacement collision was not detected.") }
    catch { try check(first.matches(test), "Failed replacement released the working shortcut.") }
    second.unregister()
    try first.register(other)
    try check(first.matches(other), "Valid replacement did not become active.")
    // A pair changes together: a refused member leaves both previous keys active.
    try second.register(test)
    do { try HotKey.register([(first, Shortcut(key: UInt32(kVK_F10), modifiers: test.modifiers)), (second, other)]); throw PerchError("Pair collision was not detected.") }
    catch { try check(first.matches(other) && second.matches(test), "Failed pair replacement changed a working shortcut.") }
    try HotKey.register([(first, Shortcut(key: UInt32(kVK_F10), modifiers: test.modifiers)), (second, Shortcut(key: UInt32(kVK_F9), modifiers: test.modifiers, enabled: false))])
    try check(first.registered?.key == UInt32(kVK_F10) && !second.active, "Pair replacement did not apply or release the disabled member.")
    do { try first.register(Shortcut(key: UInt32(kVK_F8), modifiers: [])); throw PerchError("Modifier-less shortcut was registered.") } catch { try check(first.registered?.key == UInt32(kVK_F10), "Rejected shortcut replaced the working one.") }
    first.unregister()
    try second.register(test)
    second.unregister()
    try check(!first.active && !second.active, "Shortcut unregister failed.")
    var released = HotKey(); try released.register(test); released = HotKey(); try released.register(test); released.unregister()
    print("PASS: global shortcut registration, conflict detection, and release; no hotkey fired")
}
