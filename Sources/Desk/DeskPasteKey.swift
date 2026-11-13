import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘V pastes from the desk: once the newest copy is on this Mac's clipboard,
/// Perch presses ⌘V in the app in front.
enum DeskPasteKey {
    /// Wait for ⌃ and ⌥ of ⌃⌥⌘V to be let go, so the app sees ⌘V and not
    /// ⌃⌥⌘V. Held ⌘ does not matter: the press carries ⌘ anyway.
    static func ready(_ held: CGEventFlags) -> Bool { held.intersection([.maskControl, .maskAlternate]).isEmpty }
    /// How long to wait for the keys to be let go before pressing anyway, with
    /// only ⌘ in the press.
    static let patience = 1.0

    /// Press ⌘V once the keys are let go. On the Mac where typing goes, ⌃⌥
    /// may be held on another Mac's keyboard; its key-ups arrive through the
    /// desk, which is why the whole session's keys are asked, not this
    /// keyboard's.
    static func paste(held: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) },
                      press: @escaping () -> Void = pressCommandV,
                      after: @escaping (Double, @escaping () -> Void) -> Void = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
                      waited: Double = 0) {
        if ready(held()) || waited >= patience { press(); return }
        after(0.02) { paste(held: held, press: press, after: after, waited: waited + 0.02) }
    }

    /// ⌘V, tagged as Perch's own so Perch's keyboard capture never forwards it.
    static func pressCommandV() {
        let key = keyTypingV()
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: KVMNativeEvent.eventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    /// The key that types "v" with ⌘ held in the current keyboard layout, so
    /// ⌘V is ⌘V on Dvorak, AZERTY or a layout whose ⌘ keys are QWERTY. The
    /// US key when the layout cannot be read.
    static func keyTypingV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return fallback }
            let command = UInt32((cmdKey >> 8) & 0xFF)
            for code in UInt16(0)..<128 {
                var dead: UInt32 = 0, length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), command, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, characters.count, &length, &characters)
                if status == noErr, length == 1, characters[0] == UniChar(118) { return CGKeyCode(code) }
            }
            return fallback
        }
    }
}
