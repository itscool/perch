import IOKit

/// Observes attachment changes only. Does not open devices or request input access.
final class DeskAttachmentObserver {
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    var changed: (() -> Void)?
    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let callback: IOServiceMatchingCallback = { context, iterator in
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            guard let context else { return }
            Unmanaged<DeskAttachmentObserver>.fromOpaque(context).takeUnretainedValue().changed?()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let first = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), callback, context, &added)
        let last = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), callback, context, &removed)
        guard first == KERN_SUCCESS, last == KERN_SUCCESS else { stop(); return }
        while case let service = IOIteratorNext(added), service != 0 { IOObjectRelease(service) }
        while case let service = IOIteratorNext(removed), service != 0 { IOObjectRelease(service) }
    }
    func stop() {
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if let port { IONotificationPortDestroy(port); self.port = nil }
    }
    deinit { stop() }
}
