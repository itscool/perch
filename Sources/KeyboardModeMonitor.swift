import AppKit
import IOKit
import IOKit.hidsystem

/// Reads on setting/device changes, explicit retry, and while the menu is open. HID reports are opened
/// for the bounded transaction then closed; there is no idle input subscription.
final class KeyboardModeMonitor: NSObject {
    var results: [KeyboardModeResult] = []
    var modifierErrors: [String] = []
    var registrations: [KeyboardRegistrationStatus] = []
    var registrationError: String?
    private var navigationRevision = 1
    private var appliedNavigationRevision = 0
    var busy = false
    private var applying = false
    var blocksFunctionKeyChanges: Bool { working || applying || reapplyExternal || (started && navigationRevision != appliedNavigationRevision) }
    var onChange: (() -> Void)?
    var started = false
    var working: Bool { busy || pending != nil }
    private var lastStandard: Bool?
    private var lastPresentationRead = Date.distantPast
    var registrationPending: Bool { started && navigationRevision != appliedNavigationRevision }
    func readForPresentation() {
        guard started, !working, Date().timeIntervalSince(lastPresentationRead) >= 2 else { return }
        lastPresentationRead = Date(); queryOnly = true; queue()
    }
    private var pending: DispatchWorkItem?
    private var again = false
    private var reapplyExternal = false
    private var queryOnly = false
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var knownDevices: Set<String> = []
    private var connectionError: String?
    var registrationNeedsSetup: Bool { registrationError != nil || registrations.contains { $0.needsSetup } }
    var warning: Bool { registrationNeedsSetup || results.contains { !$0.verified } || !modifierErrors.isEmpty }
    var attentionHint: String { registrationNeedsSetup ? "⚠ Keyboard setup needed" : warning ? "⚠ Review keyboards" : "" }
    var attentionDetail: String {
        if let registrationError { return registrationError }
        let unknown = registrations.filter { $0.needsSetup }.map { $0.name }
        return unknown.isEmpty ? "Function keys and separate Control/Command swaps for built-in and external keyboards." : "Identify navigation keys on \(unknown.joined(separator: ", ")) if you want to change Home/End or Page Up/Down behavior. Fn and Control/Command settings are independent."
    }
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
                monitor.queue(navigationChanged: true)
            }
            let a = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), callback, context, &added)
            let r = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), callback, context, &removed)
            if a != KERN_SUCCESS || r != KERN_SUCCESS { connectionError = "Keyboard connection monitoring is unavailable. Recheck keyboards after connecting one." }
            callback(context, added); callback(context, removed)
        } else { connectionError = "Keyboard connection monitoring is unavailable. Recheck keyboards after connecting one." }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: NSNotification.Name("com.apple.keyboard.fnstatedidchange"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activated), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(profilesChanged), name: KeyboardNavigationProfiles.changed, object: nil)
        queue()
    }
    @objc private func changed() { queue() }
    @objc private func woke() { queue(reapplyExternal: true, navigationChanged: true) }
    @objc private func profilesChanged() { queue(navigationChanged: true) }
    @objc private func activated() {
        if needsAccess && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted { queue(reapplyExternal: true) }
        else { queue() }
    }
    func observeStandard(_ standard: Bool) {
        guard started, lastStandard != standard else { return }
        lastStandard = standard; queue()
    }
    func queue(reapplyExternal: Bool = false, navigationChanged: Bool = false) {
        guard started else { return }
        if navigationChanged { navigationRevision &+= 1; queryOnly = false }
        if reapplyExternal { queryOnly = false }
        self.reapplyExternal = self.reapplyExternal || reapplyExternal
        pending?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.run() }
        pending = job
        onChange?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: job)
    }
    func recheck() {
        guard started, !working else { return }
        queue(navigationChanged: true)
        queryOnly = true
    }
    private func run() {
        pending = nil
        guard !busy else { again = true; return }
        busy = true
        applying = reapplyExternal || navigationRevision != appliedNavigationRevision
        onChange?()
        let known = knownDevices
        let forceExternal = reapplyExternal
        let readOnly = queryOnly
        queryOnly = false
        let revision = navigationRevision
        let scanNavigation = revision != appliedNavigationRevision
        reapplyExternal = false
        // A temporary thread owns the HID reply run loop. It never runs on the
        // menu thread or the input helper's event-tap thread.
        Thread.detachNewThread { [weak self] in
            autoreleasepool {
                let standard = try? FunctionKeys.standard()
                var failures: [String] = []
                let keyboards = NativeModifierKeys.keyboards()
                var registrations: [KeyboardRegistrationStatus]?
                var registrationError: String?
                if scanNavigation {
                    let devices = NavigationProbeKeyboard.connected()
                    do {
                        let profiles = try KeyboardNavigationProfiles.read()
                        registrations = devices.map { KeyboardRegistrationStatus.assess($0.identity, saved: profiles) }
                        let found = Set(devices.map { $0.name })
                        for keyboard in keyboards where !keyboard.builtIn && !found.contains(keyboard.name) {
                            registrations?.append(.init(name: keyboard.name, profile: nil, detail: "⚠ Device identity unavailable · review keyboard setup"))
                        }
                    } catch { registrationError = error.localizedDescription; registrations = [] }
                }
                var ids = Set(keyboards.map { "\(IOHIDServiceClientGetRegistryID($0.service))" })
                for keyboard in keyboards {
                    let id = "\(IOHIDServiceClientGetRegistryID(keyboard.service))"
                    if !readOnly, !known.contains(id), let intent = UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(keyboard.builtIn)) as? Bool {
                        do { try NativeModifierKeys.set(intent, on: keyboard) } catch { failures.append(error.localizedDescription); ids.remove(id) }
                    }
                }
                let desired = readOnly ? nil : NativeFunctionKeys.externalIntent()
                let newNames = Set(keyboards.filter { !$0.builtIn && !known.contains("\(IOHIDServiceClientGetRegistryID($0.service))") }.map { $0.name })
                let result = NativeFunctionKeys.externalAppleModes(keyboards: keyboards, desired: forceExternal || scanNavigation ? desired : nil)
                    + ExternalKeyboardModes.keyboards(standard: desired, only: forceExternal ? nil : newNames)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.busy = false; self.applying = false
                    if self.again { self.again = false; self.run(); return }
                    self.lastStandard = standard
                    // A read-only preview must not consume the connection event
                    // that still needs to apply a remembered device choice.
                    if !readOnly { self.knownDevices = ids }
                    self.results = result; self.modifierErrors = failures + (self.connectionError.map { [$0] } ?? [])
                    if let registrations {
                        self.registrations = registrations; self.registrationError = registrationError
                        self.appliedNavigationRevision = revision
                    }
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
