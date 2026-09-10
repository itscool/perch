import AppKit
import Carbon
import Combine

/// Native boundary kept out of the portable session and its network tests.
/// Construction does not create a tap, request access, or post an event.
final class DeskInputAdapter: ObservableObject {
    let session: KVMInputSession
    var presetShortcut: ((UUID) -> Void)?
    @Published private(set) var accessProblem: String?
    @Published private(set) var keyboards: [NativeKeyboard] = []
    @Published var pointerSpeed: Double = {
        let saved = UserDefaults.standard.double(forKey: "desk.inputPointerSpeed")
        return (0.25...4).contains(saved) ? saved : 1
    }() { didSet { UserDefaults.standard.set(pointerSpeed, forKey: "desk.inputPointerSpeed") } }
    private var keyboardScanAt: Double = 0
    private var scanningKeyboards = false
    private var keyboardGeneration = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: Timer?
    private var healthy = false
    private var tapStartFailed = false
    private let eventSource = CGEventSource(stateID: .privateState)
    private var posted = KVMInputHeld()
    private let postedSource = UUID()
    private var lastLocation: CGPoint = .zero
    private var builder = KVMNativeEvent()
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var screenLocked = false
    private var cursorHidden = false
    private var shownFocus: UUID?
    private var subscription: AnyCancellable?
    init(session: KVMInputSession) {
        self.session = session
        eventSource?.localEventsSuppressionInterval = 0
        session.ready = { [weak self] in self?.healthy == true }
        session.emit = { [weak self] event, location in self?.post(event, focus: location) }
        session.release = { [weak self] in self?.releasePosted() }
        session.attachedKeyboards = { [weak self] in
            guard let self else { return [] }
            let counts = Dictionary(grouping: self.keyboards, by: \.preferenceKey).mapValues(\.count)
            return Set((self.session.node.group.sharedKeyboards ?? []).filter { keyboard in
                keyboard.bindings[self.session.node.localID].map { counts[$0] == 1 } == true
            }.map(\.id))
        }
        subscription = session.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateCursor() } }
    }
    deinit { stop() }
    func enable(_ enabled: Bool) {
        guard !SettingsWindow.shared.testing else { return }
        if !enabled { stop(); return }
        tapStartFailed = false
        session.setEnabled(true)
        if healthTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.checkAccess()
                if self.session.enabled && self.healthy && self.tap == nil { self.enable(true) }
            }
            healthTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        checkAccess()
        guard healthy else { return }
        if tap == nil {
            let types: [CGEventType] = [.keyDown,.keyUp,.flagsChanged,.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.scrollWheel]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let adapter = Unmanaged<DeskInputAdapter>.fromOpaque(context).takeUnretainedValue()
                return adapter.receive(event, type: type) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            guard let tap else { tapStartFailed = true; healthy = false; accessProblem = "macOS could not start input sharing. If Perch already has access, open this copy from Finder and try again."; return }
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.session.stop() })
            }
            for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
                lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.screenLocked = locked
                    if locked { self?.healthy = false; self?.session.stop() }
                })
            }
        }
    }
    func stop() {
        session.setEnabled(false)
        healthy = false; healthTimer?.invalidate(); healthTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; lockObservers = []
        restoreCursor(); tapStartFailed = false; accessProblem = nil
    }
    private func checkAccess() {
        refreshKeyboards()
        let console = CGSessionCopyCurrentDictionary() as? [String: Any]
        let issue: String?
        if !AXIsProcessTrusted() || !CGPreflightPostEventAccess() { issue = "Allow Perch in System Settings → Privacy & Security → Accessibility. This is the Perch app’s access; Perch Helper’s existing access is separate." }
        else if !CGPreflightListenEventAccess() { issue = "Allow Perch in System Settings → Privacy & Security → Input Monitoring. If it is already enabled, reopen this copy from Finder and try again." }
        else if screenLocked || console?["CGSSessionScreenIsLocked"] as? Bool == true || IsSecureEventInputEnabled() { issue = "Secure keyboard entry or the lock screen is active. Use the keyboard connected to this Mac, then choose a screen to resume sharing." }
        else if console?[kCGSessionOnConsoleKey as String] as? Bool != true || console?[kCGSessionLoginDoneKey as String] as? Bool != true { issue = "This user session is inactive. Resume sharing after returning to it." }
        else if tapStartFailed { issue = "macOS could not start input sharing. Recheck access here, or reopen this copy from Finder and retry." }
        else if let tap, !CGEvent.tapIsEnabled(tap: tap) { issue = "macOS stopped input sharing. Turn sharing off and on here to retry; control is local." }
        else { issue = nil }
        if accessProblem != issue { accessProblem = issue }
        healthy = issue == nil
    }
    func refreshKeyboards() {
        guard !SettingsWindow.shared.testing, !scanningKeyboards, ProcessInfo.processInfo.systemUptime >= keyboardScanAt else { return }
        scanningKeyboards = true; keyboardScanAt = ProcessInfo.processInfo.systemUptime + 1
        keyboardGeneration += 1
        let generation = keyboardGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keyboards = NativeModifierKeys.keyboards().filter { !$0.builtIn && !$0.preferenceKey.isEmpty }
            DispatchQueue.main.async {
                guard let self else { return }; self.scanningKeyboards = false
                if self.keyboardGeneration == generation { self.updateKeyboards(keyboards) }
            }
        }
    }
    private func updateKeyboards(_ values: [NativeKeyboard]) {
        if values.map({ $0.preferenceKey + "\0" + $0.name }).sorted() != keyboards.map({ $0.preferenceKey + "\0" + $0.name }).sorted() { keyboards = values }
    }
    private func receive(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { healthy = false; session.stop(); return false }
        guard event.getIntegerValueField(.eventSourceUserData) != KVMNativeEvent.eventTag else { return false }
        // Always leave the emergency shortcut available too. No network event
        // can invoke this path because injected events are tagged above.
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53,
           event.flags.contains([.maskControl, .maskAlternate]) { session.stop(); return false }
        if type == .keyDown, session.enabled,
           let preset = session.node.group.presets.first(where: { preset in
               let shortcut = preset.shortcut
               return DeskShortcutKey.code(shortcut.key).map { Int64($0) == event.getIntegerValueField(.keyboardEventKeycode) } == true &&
                   event.flags.contains(.maskControl) == shortcut.control && event.flags.contains(.maskAlternate) == shortcut.option &&
                   event.flags.contains(.maskCommand) == shortcut.command && event.flags.contains(.maskShift) == shortcut.shift
           }) { if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { presetShortcut?(preset.id) }; return true }
        if IsSecureEventInputEnabled() { healthy = false; session.stop(); return false }
        guard session.capturing else { return false }
        if type == .keyDown, session.focus?.computer != session.node.localID,
           session.node.group.sharedKeyboards?.contains(where: { $0.follow && $0.bindings[session.node.localID] != nil }) == true {
            // Before the first key on an arriving physical keyboard can go to
            // the old computer, reconcile its passive attachment properties.
            // No permission requests, event-device opening or settings writes.
            keyboardGeneration += 1; keyboardScanAt = ProcessInfo.processInfo.systemUptime + 1
            updateKeyboards(NativeModifierKeys.keyboards().filter { !$0.builtIn && !$0.preferenceKey.isEmpty })
            session.publishKeyboardAttachments()
        }
        let flags = event.flags.rawValue & KVMInputEvent.flagMask
        let value: KVMInputEvent
        switch type {
        case .keyDown, .keyUp:
            value = .init(kind: type == .keyDown ? .keyDown : .keyUp, code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), flags: flags, repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            value = .init(kind: .modifiers, code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), flags: flags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            value = .init(kind: [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type) ? .buttonDown : .buttonUp,
                          code: UInt16(clamping: event.getIntegerValueField(.mouseEventButtonNumber)), flags: flags,
                          clickCount: min(3, max(0, Int(event.getIntegerValueField(.mouseEventClickState)))))
        case .scrollWheel:
            value = .init(kind: .scroll, flags: flags, x: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2), y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            // The coordinator converts target desktop points to desk millimetres.
            value = .init(kind: .motion, flags: flags, x: event.getDoubleValueField(.mouseEventDeltaX) * pointerSpeed, y: event.getDoubleValueField(.mouseEventDeltaY) * pointerSpeed)
        default: return false
        }
        return session.capture(value)
    }
    private func point(_ focus: KVMInputFocus) -> CGPoint? {
        let group = session.node.group
        guard let connection = group.connections.first(where: { $0.monitor == focus.monitor && $0.computer == session.node.localID }),
              let display = NSScreen.screens.compactMap({ screen -> CGDirectDisplayID? in
                  guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                        let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), CFUUIDCreateString(nil, uuid) as String == connection.localDisplay else { return nil }; return id
              }).first,
              let geometry = group.monitors.first(where: { $0.id == focus.monitor })?.geometry else { return nil }
        let bounds = CGDisplayBounds(display)
        // Quartz bounds already follow macOS rotation. Do not rotate twice.
        return CGPoint(x: bounds.minX + (focus.position.x - geometry.x) / geometry.displayedWidth * max(0, bounds.width - 1),
                       y: bounds.minY + (focus.position.y - geometry.y) / geometry.displayedHeight * max(0, bounds.height - 1))
    }
    private func post(_ value: KVMInputEvent, focus: KVMInputFocus) {
        guard healthy, !IsSecureEventInputEnabled(), let point = point(focus), !SettingsWindow.shared.testing else { session.stop(); return }
        lastLocation = point
        _ = posted.apply(value, source: postedSource)
        emitNative(value, point: point)
    }
    private func releasePosted() {
        for event in posted.releaseAll() { emitNative(event, point: lastLocation) }
        restoreCursor(); shownFocus = nil
    }
    private func restoreCursor() {
        if cursorHidden { CGDisplayShowCursor(CGMainDisplayID()); cursorHidden = false }
    }
    private func updateCursor() {
        guard !SettingsWindow.shared.testing, session.active, let focus = session.focus else { restoreCursor(); shownFocus = nil; return }
        if focus.computer != session.node.localID {
            if !cursorHidden { cursorHidden = CGDisplayHideCursor(CGMainDisplayID()) == .success }
            shownFocus = nil
        } else {
            restoreCursor()
            if shownFocus != focus.monitor { shownFocus = focus.monitor; post(.init(kind: .motion), focus: focus) }
        }
    }
    private func emitNative(_ value: KVMInputEvent, point: CGPoint) {
        guard !SettingsWindow.shared.testing else { return }
        let event = builder.make(value, point: point, source: eventSource)
        event?.post(tap: .cghidEventTap)
    }
}
