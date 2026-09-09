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
    private var presentationReadActive = false
    private var hasSnapshot = false
    private var desiredBuiltIn: Bool?
    var blocksFunctionKeyChanges: Bool {
        applying || reapplyExternal || desiredBuiltIn != nil || registrationPending ||
        (busy && !presentationReadActive) || (pending != nil && (!queryOnly || !hasSnapshot))
    }
    struct Scan {
        var known: Set<String>
        var forceExternal: Bool
        var readOnly: Bool
        var scanNavigation: Bool
        var builtIn: Bool?
    }
    struct Result {
        var standard: Bool?
        var results: [KeyboardModeResult] = []
        var failures: [String] = []
        var ids: Set<String> = []
        var registrations: [KeyboardRegistrationStatus]?
        var registrationError: String?
    }
    private let scan: (Scan) -> Result
    init(scan: @escaping (Scan) -> Result = KeyboardModeMonitor.scanHardware) {
        self.scan = scan; super.init()
    }
    var onChange: (() -> Void)?
    var started = false
    var working: Bool { busy || pending != nil }
    private var lastStandard: Bool?
    private var lastPresentationRead = Date.distantPast
    var registrationPending: Bool { started && navigationRevision != appliedNavigationRevision }
    func readForPresentation() {
        guard started, !working, Date().timeIntervalSince(lastPresentationRead) >= 2 else { return }
        lastPresentationRead = Date(); queue(readOnly: true)
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
    func queue(reapplyExternal: Bool = false, navigationChanged: Bool = false, readOnly: Bool = false) {
        guard started else { return }
        let wasBlocking = blocksFunctionKeyChanges
        if navigationChanged { navigationRevision &+= 1 }
        queryOnly = (pending == nil ? readOnly : queryOnly && readOnly) && !reapplyExternal
        self.reapplyExternal = self.reapplyExternal || reapplyExternal
        pending?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.run() }
        pending = job
        if wasBlocking || blocksFunctionKeyChanges { onChange?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: job)
    }
    func recheck() {
        guard started, !working else { return }
        queue(navigationChanged: true, readOnly: true)
    }
    func setBuiltIn(_ desired: Bool) {
        guard started else { return }
        desiredBuiltIn = desired
        queue()
    }
    private func run() {
        pending = nil
        guard !busy else { again = true; return }
        let request = Scan(known: knownDevices, forceExternal: reapplyExternal, readOnly: queryOnly,
                           scanNavigation: navigationRevision != appliedNavigationRevision, builtIn: desiredBuiltIn)
        let revision = navigationRevision
        let wasBlocking = blocksFunctionKeyChanges
        busy = true
        applying = request.forceExternal || request.scanNavigation || request.builtIn != nil
        presentationReadActive = request.readOnly && hasSnapshot && !applying
        queryOnly = false; reapplyExternal = false; desiredBuiltIn = nil
        if wasBlocking || blocksFunctionKeyChanges { onChange?() }
        let scan = self.scan
        // Reads and user changes share one worker; a click during a routine
        // read queues the desired value instead of racing its HID transaction.
        Thread.detachNewThread { [weak self] in
            let result = autoreleasepool { scan(request) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let wasBlocking = self.blocksFunctionKeyChanges
                self.busy = false; self.applying = false; self.presentationReadActive = false
                if self.again { self.again = false; self.run(); return }
                let failures = result.failures + (self.connectionError.map { [$0] } ?? [])
                var changed = self.results != result.results || self.modifierErrors != failures || self.lastStandard != result.standard
                self.lastStandard = result.standard; self.hasSnapshot = true
                if !request.readOnly { self.knownDevices = result.ids }
                self.results = result.results; self.modifierErrors = failures
                if let registrations = result.registrations, self.navigationRevision == revision {
                    changed = changed || self.registrations != registrations || self.registrationError != result.registrationError
                    self.registrations = registrations; self.registrationError = result.registrationError
                    self.appliedNavigationRevision = revision
                }
                if changed || wasBlocking || self.blocksFunctionKeyChanges { self.onChange?() }
            }
        }
    }
    static func scanHardware(_ request: Scan) -> Result {
        var output = Result()
        if let desired = request.builtIn {
            do { try NativeFunctionKeys.setBuiltIn(desired) }
            catch { output.failures.append(error.localizedDescription) }
        }
        output.standard = try? FunctionKeys.standard()
        let keyboards = NativeModifierKeys.keyboards()
        if request.scanNavigation {
            let devices = NavigationProbeKeyboard.connected()
            do {
                let profiles = try KeyboardNavigationProfiles.read()
                output.registrations = devices.map { KeyboardRegistrationStatus.assess($0.identity, saved: profiles) }
                let found = Set(devices.map { $0.name })
                for keyboard in keyboards where !keyboard.builtIn && !found.contains(keyboard.name) {
                    output.registrations?.append(.init(name: keyboard.name, profile: nil, detail: "⚠ Device identity unavailable · review keyboard setup"))
                }
            } catch { output.registrationError = error.localizedDescription; output.registrations = [] }
        }
        output.ids = Set(keyboards.map { "\(IOHIDServiceClientGetRegistryID($0.service))" })
        for keyboard in keyboards {
            let id = "\(IOHIDServiceClientGetRegistryID(keyboard.service))"
            if !request.readOnly, !request.known.contains(id), let intent = UserDefaults.standard.object(forKey: NativeModifierKeys.intentKey(keyboard.builtIn)) as? Bool {
                do { try NativeModifierKeys.set(intent, on: keyboard) } catch { output.failures.append(error.localizedDescription); output.ids.remove(id) }
            }
        }
        let desired = request.readOnly ? nil : NativeFunctionKeys.externalIntent()
        let newNames = Set(keyboards.filter { !$0.builtIn && !request.known.contains("\(IOHIDServiceClientGetRegistryID($0.service))") }.map { $0.name })
        output.results = NativeFunctionKeys.externalAppleModes(keyboards: keyboards, desired: request.forceExternal || request.scanNavigation ? desired : nil)
            + ExternalKeyboardModes.keyboards(standard: desired, only: request.forceExternal ? nil : newNames)
        return output
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
