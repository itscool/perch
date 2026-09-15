import Foundation
import IOKit
import IOKit.hid

/// Read-only IORegistry enumeration. Services handed to `body` are released
/// when it returns, so callers never track `IOObjectRelease` themselves.
enum IOServices {
    /// Runs `body` with every service matching `className`, or returns nil
    /// when IOKit refuses the query.
    static func withMatching<T>(_ className: String, _ body: ([io_service_t]) throws -> T) rethrows -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 { services.append(service) }
        defer { services.forEach { IOObjectRelease($0) } }
        return try body(services)
    }

    static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// The service's own property table, or nil when it cannot be read.
    static func properties(_ service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    /// The registry entry ID, stable for the life of the service.
    static func registryID(_ service: io_service_t) -> UInt64? {
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS, id != 0 else { return nil }
        return id
    }
}

/// HID devices as the registry lists them. Metadata only: no device is
/// opened, scheduled or asked for input reports.
enum HIDDevices {
    static let className = "IOHIDDevice"
    static func withAll<T>(_ body: ([io_service_t]) throws -> T) rethrows -> T? { try IOServices.withMatching(className, body) }
}

/// Reports HID devices arriving or leaving, on the main queue. This observes
/// attachment only; it never opens a device and needs no Input Monitoring.
/// `changed` closures must capture their owner weakly: the observer outlives
/// nothing and stops itself when released.
final class HIDAttachmentObserver {
    var changed: (() -> Void)?
    private(set) var active = false
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0

    /// Starts observing. Returns false when IOKit refuses, in which case the
    /// owner keeps rescanning on its own triggers.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return active }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let callback: IOServiceMatchingCallback = { context, iterator in
            HIDAttachmentObserver.drain(iterator)
            guard let context else { return }
            Unmanaged<HIDAttachmentObserver>.fromOpaque(context).takeUnretainedValue().changed?()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let first = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching(HIDDevices.className), callback, context, &added)
        let last = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching(HIDDevices.className), callback, context, &removed)
        guard first == KERN_SUCCESS, last == KERN_SUCCESS else { stop(); return false }
        // Arming returns the devices already present; they are not changes.
        Self.drain(added); Self.drain(removed)
        active = true
        return true
    }

    /// Stops observing. The port's dispatch source is cancelled before the
    /// port is destroyed, so no callback can run after this returns.
    func stop() {
        active = false
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if let port { IONotificationPortDestroy(port); self.port = nil }
    }

    deinit { stop() }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }
}
