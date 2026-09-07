import AppKit
import Carbon
import IOKit.hidsystem

/// Exact sender matches only. Unknown/virtual/built-in senders pass through.
/// Field 87 is private CoreGraphics metadata; never guess from timing or the
/// last active keyboard. A missing field degrades to native behavior.
final class NavigationEngine {
    struct Held {
        let sender: UInt64
        let source: Int64
        let mapping: NavigationTransform.Mapping
    }
    var preferences = NavigationPreferences()
    var devices: [UInt64: [Int64: Int64]] = [:]
    var builtInSenders = Set<UInt64>()
    var excluded = false
    var unidentified = false
    var observed = false
    private var held = [Held?](repeating: nil, count: 64)
    var hasHeldKeys: Bool { held.contains { $0 != nil } }
    static let senderField = CGEventField(rawValue: 87)!
    func apply(_ event: CGEvent, type: CGEventType) {
        guard type == .keyDown || type == .keyUp else { return }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        // Numeric fast rejection; ordinary text isn't inspected or retained.
        guard NavigationEventDevices.virtualKeys.contains(key) else { return }
        let sender = UInt64(bitPattern: event.getIntegerValueField(Self.senderField))
        if let index = held.firstIndex(where: { $0?.sender == sender && $0?.source == key }), let press = held[index] {
            press.mapping.apply(to: event)
            if type == .keyUp { held[index] = nil }
            return
        }
        guard preferences.enabled, !excluded, type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        guard sender != 0 else { if NavigationTransform.index(key) != nil { unidentified = true }; return }
        guard let canonical = devices[sender]?[key] else {
            if !builtInSenders.contains(sender) && NavigationTransform.index(key) != nil { unidentified = true }
            return
        }
        observed = true; unidentified = false
        guard let mapping = NavigationTransform.mapping(key: canonical, flags: event.flags, homeEnd: preferences.homeEnd, pageUpDown: preferences.pageUpDown),
              let slot = held.firstIndex(where: { $0 == nil }) else { return }
        held[slot] = Held(sender: sender, source: key, mapping: mapping)
        mapping.apply(to: event)
    }
    func reset() { for i in held.indices { held[i] = nil }; observed = false; unidentified = false }
}

enum NavigationEventDevices {
    static let usageKeys: [UInt32: Int64] = [
        0x3A:122,0x3B:120,0x3C:99,0x3D:118,0x3E:96,0x3F:97,0x40:98,0x41:100,0x42:101,0x43:109,0x44:103,0x45:111,
        0x46:105,0x47:107,0x48:113,0x49:114,0x4A:115,0x4B:116,0x4C:117,0x4D:119,0x4E:121,0x4F:124,0x50:123,0x51:125,0x52:126,
        0x68:105,0x69:107,0x6A:113,0x6B:106,0x6C:64,0x6D:79,0x6E:80,0x6F:90
    ]
    static let virtualKeys = Set(usageKeys.values)
    static func mapping(_ profile: NavigationKeyboardProfile) -> [Int64: Int64]? {
        guard profile.valid else { return nil }
        var result: [Int64:Int64] = [:]
        for (index, usage) in profile.keys.enumerated() {
            guard let usage else { continue }
            guard let key = usageKeys[usage], result[key] == nil else { return nil }
            result[key] = [115,119,116,121][index]
        }
        return result
    }
    static func read(profiles: [NavigationKeyboardProfile]) -> [UInt64: [Int64:Int64]] {
        // The menu app already verified descriptors during registration. The
        // helper needs only Passive service metadata and its Accessibility tap;
        // it never opens raw keyboard devices or asks for Input Monitoring.
        var result: [UInt64: [Int64:Int64]] = [:]
        for keyboard in NativeModifierKeys.keyboards() where !keyboard.builtIn {
            let transport = IOHIDServiceClientCopyProperty(keyboard.service, "Transport" as CFString) as? String ?? ""
            guard NavigationDeviceScope.isExternal(builtIn: keyboard.builtIn, transport: transport) else { continue }
            let product = (IOHIDServiceClientCopyProperty(keyboard.service, "ProductID" as CFString) as? NSNumber)?.intValue ?? 0
            let version = (IOHIDServiceClientCopyProperty(keyboard.service, "VersionNumber" as CFString) as? NSNumber)?.intValue
            let matches = profiles.filter { profile in
                let identity = profile.identity
                return profile.valid && identity.vendor == keyboard.vendor && identity.product == product && identity.name == keyboard.name && identity.transport == transport && (version == nil || version == identity.version)
            }
            let maps = matches.compactMap { mapping($0) }
            guard let map = maps.first, maps.allSatisfy({ $0 == map }) else { continue }
            let id = (IOHIDServiceClientGetRegistryID(keyboard.service) as? NSNumber)?.uint64Value ?? 0
            if id != 0 { result[id] = map }
        }
        return result
    }

}

/// Metadata scans happen only on connection/configuration changes; event callbacks
/// perform no I/O, preferences access, app lookup, allocation, or event posting.
final class NavigationRuntime: NSObject {
    let engine: NavigationEngine
    private var profiles: [NavigationKeyboardProfile] = []
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var started = false
    init(engine: NavigationEngine) { self.engine = engine; super.init() }
    func configure(_ preferences: NavigationPreferences, profiles: [NavigationKeyboardProfile]) {
        let changed = self.profiles != profiles || engine.preferences != preferences
        self.profiles = profiles
        engine.preferences = preferences
        if preferences.enabled && !started { start() }
        else if !preferences.enabled && started { stop() }
        else if changed && started { queue() }
        if started && changed { appChanged() }
    }
    private func start() {
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        port = IONotificationPortCreate(kIOMainPortDefault)
        if let port {
            IONotificationPortSetDispatchQueue(port, .main)
            let callback: IOServiceMatchingCallback = { context, iterator in
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                guard let context else { return }
                Unmanaged<NavigationRuntime>.fromOpaque(context).takeUnretainedValue().queue()
            }
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), callback, context, &added)
            IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), callback, context, &removed)
            callback(context, added); callback(context, removed)
        }
        queue()
    }
    @objc private func appChanged() {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { engine.excluded = true; return }
        engine.excluded = engine.preferences.excludedApps.contains(id)
    }
    @objc private func woke() { engine.reset(); queue() }
    private func queue() {
        guard started else { return }
        revision &+= 1; let generation = revision
        engine.devices = [:]
        pending?.cancel()
        let profiles = self.profiles
        let job = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .utility).async {
                let devices = NavigationEventDevices.read(profiles: profiles)
                let builtIn = Set(NativeModifierKeys.keyboards().filter { $0.builtIn }.compactMap { (IOHIDServiceClientGetRegistryID($0.service) as? NSNumber)?.uint64Value })
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.started, self.revision == generation else { return }
                    self.engine.devices = devices; self.engine.builtInSenders = builtIn
                }
            }
        }
        pending = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: job)
    }
    private func stop() {
        started = false; revision &+= 1; pending?.cancel(); pending = nil
        engine.devices = [:]
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if let port { IONotificationPortDestroy(port) }; port = nil
    }
    deinit { stop() }
}
