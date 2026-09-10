import AppKit
import Carbon

struct PanicShortcut: Codable, Equatable {
    var key: UInt32 = UInt32(kVK_Escape)
    var modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    var enabled = false
    static let keys: [(String, UInt32)] = [("Esc", UInt32(kVK_Escape)), ("F6", UInt32(kVK_F6)), ("F7", UInt32(kVK_F7)), ("F8", UInt32(kVK_F8)), ("F9", UInt32(kVK_F9)), ("F10", UInt32(kVK_F10)), ("F11", UInt32(kVK_F11)), ("F12", UInt32(kVK_F12)), ("P", UInt32(kVK_ANSI_P))]
    var title: String {
        var value = ""
        for (flag, symbol) in [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")] {
            if modifiers & UInt32(flag) != 0 { value += symbol }
        }
        return value + (Self.keys.first { $0.1 == key }?.0 ?? "?")
    }

}

final class PanicHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    var active: Bool { reference != nil }
    let signature: UInt32
    init(signature: UInt32 = 0x50524348) {
        self.signature = signature
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let owner = Unmanaged<PanicHotKey>.fromOpaque(context).takeUnretainedValue()
            guard status == noErr, id.signature == owner.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            owner.action?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: PanicShortcut) throws {
        unregister()
        guard shortcut.enabled else { return }
        guard handler != nil else { throw AppError(message: "Could not install the panic keyboard handler.") }
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw AppError(message: "That shortcut is unavailable or already in use. Choose another combination (\(status)).") }
    }
    func unregister() { if let reference { UnregisterEventHotKey(reference) }; reference = nil }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
}

func runPanicHotKeyTests() throws {
    _ = NSApplication.shared
    let first = PanicHotKey()
    let second = PanicHotKey()
    let test = PanicShortcut(key: UInt32(kVK_F12), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), enabled: true)
    try first.register(test)
    guard first.active else { throw AppError(message: "Global panic shortcut did not register.") }
    var conflictDetected = false
    do { try second.register(test) } catch { conflictDetected = true }
    guard conflictDetected else { first.unregister(); second.unregister(); throw AppError(message: "Shortcut collision was not detected.") }
    first.unregister()
    try second.register(test)
    second.unregister()
    guard !first.active && !second.active else { throw AppError(message: "Shortcut unregister failed.") }
    print("PASS: global shortcut registration, conflict detection, and release; no hotkey fired")
}
