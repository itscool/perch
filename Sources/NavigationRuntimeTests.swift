import AppKit

func runNavigationRuntimeTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let engine = NavigationEngine()
    engine.preferences.homeEnd = true; engine.preferences.pageUpDown = true
    engine.devices = [900:[115:115,119:119,116:116,121:121]]
    func event(_ key: CGKeyCode, _ sender: Int64, down: Bool = true, repeating: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil,virtualKey: key,keyDown: down)!
        event.flags = []
        event.setIntegerValueField(NavigationEngine.senderField,value: sender)
        event.setIntegerValueField(.keyboardEventAutorepeat,value: repeating ? 1 : 0)
        return event
    }
    for sender: Int64 in [0,901,999] {
        let e = event(115,sender); engine.apply(e,type: .keyDown)
        try check(e.getIntegerValueField(.keyboardEventKeycode) == 115, "Unknown/built-in source was remapped")
    }
    let e = event(115,900); engine.apply(e,type: .keyDown)
    try check(e.getIntegerValueField(.keyboardEventKeycode) == 123 && e.flags.contains(.maskCommand), "Known external Home wasn't mapped")
    engine.preferences.homeEnd = false; engine.excluded = true; engine.devices = [:]
    let repeating = event(115,900,repeating: true); engine.apply(repeating,type: .keyDown)
    let up = event(115,900,down: false); engine.apply(up,type: .keyUp)
    try check(repeating.getIntegerValueField(.keyboardEventKeycode) == 123 && up.getIntegerValueField(.keyboardEventKeycode) == 123 && !engine.hasHeldKeys, "A changed setting/app/device broke matched repeat/key-up")
    engine.preferences.homeEnd = true; engine.devices = [900:[115:115]]
    let excluded = event(115,900); engine.apply(excluded,type: .keyDown)
    try check(excluded.getIntegerValueField(.keyboardEventKeycode) == 115, "Excluded app was remapped")
    engine.excluded = false
    let orphan = event(115,900,repeating: true); engine.apply(orphan,type: .keyDown)
    try check(orphan.getIntegerValueField(.keyboardEventKeycode) == 115, "A repeat with no mapped down was changed")
    for key: CGKeyCode in [0,1,2,36,53,55,59,123,124] {
        let e = event(key,900); engine.apply(e,type: .keyDown)
        try check(e.getIntegerValueField(.keyboardEventKeycode) == key, "Unrelated input was changed")
    }
    let shifted = event(115,900); shifted.flags = [.maskShift,.maskAlphaShift]; engine.apply(shifted,type: .keyDown)
    try check(shifted.flags.contains(.maskShift) && shifted.flags.contains(.maskAlphaShift), "Selection/Caps Lock lost")
    engine.reset(); try check(!engine.hasHeldKeys, "Reset retained held keys")
    let old = Data("{\"timestamp\":0,\"pid\":1,\"trusted\":true,\"active\":false}".utf8)
    try check(try JSONDecoder().decode(InputHelperStatus.self,from: old).navigationDevices == nil, "Old helper status compatibility lost")
    print("PASS: external sender isolation; built-in/unknown fail-open; paired repeats/releases across changes; app exceptions; no posted events or physical remapping")
}
