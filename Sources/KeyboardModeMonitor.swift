import AppKit
import IOKit
import IOKit.hidsystem

/// Runs only on setting/device changes and explicit retry. HID reports are opened
/// for the bounded transaction then closed; there is no idle input subscription.
final class KeyboardModeMonitor: NSObject {
    var results: [KeyboardModeResult] = []
    var modifierErrors: [String] = []
    var busy = false
    var onChange: (() -> Void)?
    var started = false
    private var lastStandard: Bool?
    private var pending: DispatchWorkItem?
    private var again = false
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var knownDevices: Set<String> = []
    private var connectionError: String?
    var warning: Bool { results.contains { !$0.verified } || !modifierErrors.isEmpty }
    var needsAccess: Bool { results.contains { $0.needsAccess } }
    func start() {
        guard !started else { return }; started = true
        port = IONotificationPortCreate(kIOMainPortDefault)
        if let port {
            IONotificationPortSetDispatchQueue(port, .main)
            let context = Unmanaged.passUnretained(self).toOpaque()
            let callback: IOServiceMatchingCallback = { context, iterator in
                guard let context else { return }
                let monitor = Unmanaged<KeyboardModeMonitor>.fromOpaque(context).takeUnretainedValue()
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                monitor.queue()
            }
            let a = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), callback, context, &added)
            let r = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), callback, context, &removed)
            if a != KERN_SUCCESS || r != KERN_SUCCESS { connectionError = "Keyboard connection monitoring is unavailable. Recheck keyboards after connecting one." }
            callback(context, added); callback(context, removed)
        } else { connectionError = "Keyboard connection monitoring is unavailable. Recheck keyboards after connecting one." }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: NSNotification.Name("com.apple.keyboard.fnstatedidchange"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activated), name: NSApplication.didBecomeActiveNotification, object: nil)
        queue()
    }
    @objc private func changed() { queue() }
    @objc private func activated() {
        if needsAccess && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted { queue() }
        else { onChange?() }
    }
    func observeStandard(_ standard: Bool) {
        guard started, lastStandard != standard else { return }
        lastStandard = standard; queue()
    }
    func queue() {
        guard started else { return }
        pending?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.run() }
        pending = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: job)
    }
    private func run() {
        pending = nil
        guard !busy else { again = true; return }
        busy = true; onChange?()
        let known = knownDevices
        // A temporary thread owns the HID reply run loop. It never runs on the
        // menu thread or the input helper's event-tap thread.
        Thread.detachNewThread { [weak self] in
            autoreleasepool {
                let standard = try? FunctionKeys.standard()
                var failures: [String] = []
                let keyboards = NativeModifierKeys.keyboards()
                var ids = Set(keyboards.map { "\(IOHIDServiceClientGetRegistryID($0.service))" })
                for keyboard in keyboards {
                    let id = "\(IOHIDServiceClientGetRegistryID(keyboard.service))"
                    if !known.contains(id), let intent = UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(keyboard.builtIn)) as? Bool {
                        do { try NativeModifierKeys.set(intent, on: keyboard) } catch { failures.append(error.localizedDescription); ids.remove(id) }
                    }
                }
                let result = standard.map { ExternalKeyboardModes.keyboards(standard: $0) } ?? [.init(name: "macOS", detail: "⚠ Could not read macOS function-key mode.", verified: false)]
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.busy = false
                    if self.again { self.again = false; self.run(); return }
                    self.lastStandard = standard; self.knownDevices = ids
                    self.results = result; self.modifierErrors = failures + (self.connectionError.map { [$0] } ?? [])
                    self.onChange?()
                }
            }
        }
    }
    deinit {
        pending?.cancel()
        if added != 0 { IOObjectRelease(added) }; if removed != 0 { IOObjectRelease(removed) }
        if let port { IONotificationPortDestroy(port) }
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
