import AppKit
import Carbon

/// One global Carbon hot key. Registration is transactional: a replacement is
/// acquired before the working combination is released, and a failed change
/// leaves the previous shortcut active. Pressed events fire `action` once per
/// press; a held key never repeats it. All hot keys share one Carbon event
/// handler, so instances hold no Carbon handler of their own and deinit
/// simply releases the registration.
final class HotKey {
    private(set) var registered: Shortcut?
    private var reference: EventHotKeyRef?
    private var id: UInt32 = 0
    var action: (() -> Void)?
    var active: Bool { reference != nil }
    init() {}
    deinit { unregister() }

    func register(_ shortcut: Shortcut) throws { try Self.register([(self, shortcut)]) }
    func matches(_ shortcut: Shortcut) -> Bool { active && registered == shortcut }
    func unregister() {
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        Dispatcher.shared.remove(id)
        self.reference = nil; registered = nil
    }

    /// Register several shortcuts as one change: either every changed key is
    /// acquired or none is released. A disabled shortcut releases its key.
    static func register(_ changes: [(hotKey: HotKey, shortcut: Shortcut)]) throws {
        guard Dispatcher.shared.installed else { throw PerchError("Could not install the keyboard shortcut handler.") }
        var staged: [(HotKey, Shortcut, EventHotKeyRef, UInt32)] = []
        do {
            for (hotKey, shortcut) in changes where shortcut.enabled && !hotKey.matches(shortcut) {
                guard !shortcut.modifiers.isEmpty else { throw PerchError("Choose at least one modifier for \(shortcut.title).") }
                let id = Dispatcher.shared.allocate()
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers.carbonFlags, EventHotKeyID(signature: Dispatcher.signature, id: id), GetApplicationEventTarget(), 0, &reference)
                guard status == noErr, let reference else {
                    let retained = hotKey.registered.map { " The previous shortcut \($0.title) remains active." } ?? ""
                    throw PerchError("\(shortcut.title) is unavailable or already in use. Choose another combination (\(status))." + retained)
                }
                staged.append((hotKey, shortcut, reference, id))
            }
        } catch { for (_, _, reference, _) in staged { UnregisterEventHotKey(reference) }; throw error }
        for (hotKey, shortcut) in changes where !shortcut.enabled { hotKey.unregister() }
        for (hotKey, shortcut, reference, id) in staged {
            hotKey.unregister()
            hotKey.reference = reference; hotKey.registered = shortcut; hotKey.id = id
            Dispatcher.shared.add(hotKey, id: id)
        }
    }

    /// The process-wide Carbon handler. Registrations are looked up by their
    /// allocated id, so no hand-picked signatures can collide.
    private final class Dispatcher {
        static let shared = Dispatcher()
        static let signature: OSType = 0x50524348 // 'PRCH'
        private final class Weak { weak var hotKey: HotKey?; init(_ hotKey: HotKey) { self.hotKey = hotKey } }
        private var hotKeys: [UInt32: Weak] = [:]
        private var latch = HotKeyLatch()
        private var next: UInt32 = 0
        private var handler: EventHandlerRef?
        private init() {
            var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == Dispatcher.signature else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<Dispatcher>.fromOpaque(context).takeUnretainedValue().handle(id.id, released: GetEventKind(event) == UInt32(kEventHotKeyReleased))
            }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        var installed: Bool { handler != nil }
        func allocate() -> UInt32 { next = next == UInt32.max ? 1 : next + 1; return next }
        func add(_ hotKey: HotKey, id: UInt32) { hotKeys[id] = Weak(hotKey) }
        func remove(_ id: UInt32) { hotKeys[id] = nil; latch.release(id) }
        private func handle(_ id: UInt32, released: Bool) -> OSStatus {
            guard let hotKey = hotKeys[id]?.hotKey, hotKey.active else { return OSStatus(eventNotHandledErr) }
            if released { latch.release(id) } else if latch.press(id) { hotKey.action?() }
            return noErr
        }
    }
}
