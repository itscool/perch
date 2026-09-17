import AppKit
import Carbon
import Combine
import IOKit.hidsystem
import IOKit.pwr_mgt

/// Native boundary kept out of the portable session and its network tests.
/// Construction does not create a tap, request access, or post an event.
final class DeskInputAdapter: ObservableObject {
    static let sharingEnabledKey = "desk.shareOnThisMac"
    static var sharingEnabledByDefault: Bool {
        guard UserDefaults.standard.object(forKey: sharingEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: sharingEnabledKey)
    }
    let session: KVMInputSession
    var presetShortcut: ((UUID) -> Void)?
    /// Perch's own registered hotkeys (sharing, kill switch, lid countdown)
    /// act on the Mac whose keyboard was pressed, never on the remote one.
    var localShortcut: ((Int64, CGEventFlags) -> Bool)?
    @Published private(set) var accessProblem: String?
    /// A fact worth showing that does not stop sharing.
    @Published private(set) var note: String?
    private var tapDisables: [Double] = []
    private var keyRouter = DeskKeyRouter()
    private var remoteCapture = false
    private var displayCache: [String: CGDirectDisplayID] = [:]
    private var displayCacheAt: Double = -1
    @Published private(set) var keyboards: [NativeKeyboard] = []
    @Published private(set) var mice: [NativePointingDevice] = []
    @Published var pointerSpeed: Double = {
        let saved = UserDefaults.standard.double(forKey: "desk.inputPointerSpeed")
        return (0.25...4).contains(saved) ? saved : 1
    }() { didSet { UserDefaults.standard.set(pointerSpeed, forKey: "desk.inputPointerSpeed") } }
    private let attachmentObserver = HIDAttachmentObserver()
    private var attachmentChanged = true
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
    private var hiddenDisplays: [CGDirectDisplayID] = []
    private var cursorAssociated = true
    private var shownFocus: UUID?
    /// Whether control was already on this Mac at the last cursor update.
    private var controlWasLocal = false
    private var subscription: AnyCancellable?
    init(session: KVMInputSession) {
        self.session = session
        eventSource?.localEventsSuppressionInterval = 0
        session.ready = { [weak self] in self?.healthy == true }
        session.emit = { [weak self] event, location in self?.post(event, focus: location) }
        session.release = { [weak self] in self?.releasePosted() }
        session.attachedKeyboards = { [weak self] in
            guard let self else { return [] }
            let keyboardCounts = Dictionary(grouping: self.keyboards, by: \.preferenceKey).mapValues(\.count)
            let mouseCounts = Dictionary(grouping: self.mice, by: \.preferenceKey).mapValues(\.count)
            return Set((self.session.node.group.sharedKeyboards ?? []).filter { device in
                let counts = device.deviceKind == .mouse ? mouseCounts : keyboardCounts
                return device.bindings[self.session.node.localID].map { counts[$0] == 1 } == true
            }.map(\.id))
        }
        attachmentObserver.changed = { [weak self] in
            guard let self else { return }
            self.attachmentChanged = true; self.keyboardScanAt = 0
            self.refreshKeyboards()
        }
        session.keepAwake = { [weak self] in self?.declareActivity() }
        session.localPointerPosition = { [weak self] _ in
            // Report where this Mac's cursor actually is, on whichever desk
            // screen it sits. Returning nothing unless it happened to be on
            // the target screen is what left a first focus with no position
            // to use, and that is what fell back to a screen centre.
            guard let self, let location = CGEvent(source: nil)?.location else { return nil }
            return self.deskPosition(location)?.1
        }
        subscription = session.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateCursor() } }
    }
    deinit { stop() }
    func enable(_ enabled: Bool) {
        guard !SettingsWindow.shared.testing else { return }
        UserDefaults.standard.set(enabled, forKey: Self.sharingEnabledKey)
        if !enabled { stop(); return }
        attachmentObserver.start()
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
    /// Rebuild the native event tap and the input session after macOS disables
    /// the tap. Calling enable(true) alone cannot do that because the failed
    /// tap is still retained and the session is already marked enabled.
    func restart() {
        guard !SettingsWindow.shared.testing else { return }
        let shouldEnable = UserDefaults.standard.object(forKey: Self.sharingEnabledKey) == nil ||
            UserDefaults.standard.bool(forKey: Self.sharingEnabledKey)
        stop()
        if shouldEnable { enable(true) }
    }
    func stop() {
        session.setEnabled(false)
        attachmentObserver.stop()
        activity.close()
        healthy = false; healthTimer?.invalidate(); healthTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; lockObservers = []
        restoreCursor(); tapStartFailed = false; accessProblem = nil
    }
    var needsPermissionSetup: Bool {
        !AccessCheck.sharing
    }
    private func checkAccess() {
        refreshKeyboards()
        let console = CGSessionCopyCurrentDictionary() as? [String: Any]
        let issue: String?
        if !AccessCheck.accessibilityWithPosting { issue = "Allow Perch in System Settings → Privacy & Security → Accessibility. This is the Perch app’s access; Perch Helper’s existing access is separate." }
        else if !AccessCheck.inputMonitoring { issue = "Allow Perch in System Settings → Privacy & Security → Input Monitoring. If it is already enabled, reopen this copy from Finder and try again." }
        else if screenLocked || console?["CGSSessionScreenIsLocked"] as? Bool == true { issue = "The lock screen is active. Unlock this Mac to resume sharing." }
        else if console?[kCGSessionOnConsoleKey as String] as? Bool != true || console?[kCGSessionLoginDoneKey as String] as? Bool != true { issue = "This user session is inactive. Resume sharing after returning to it." }
        else if tapStartFailed { issue = "macOS could not start input sharing. Recheck access here, or reopen this copy from Finder and retry." }
        else if let tap, !CGEvent.tapIsEnabled(tap: tap), !reenableTap() { issue = "macOS keeps stopping input sharing on this Mac. Control is local; Perch retries automatically." }
        else { issue = nil }
        if accessProblem != issue { accessProblem = issue }
        healthy = issue == nil
        // The reason sharing cannot start is shown in Desk, but nothing
        // outside the app could see it. Record it once per change.
        PerchLog.note("input.access", issue ?? "this Mac can share input")
        // Secure keyboard entry (a password field, Terminal's Secure Keyboard
        // Entry) hides keystrokes from every event tap system-wide. That is a
        // fact to show, not a reason to drop the pointer or the lease.
        let secure = IsSecureEventInputEnabled() && session.enabled && issue == nil
        let text = secure ? "Secure keyboard entry is on in an app on this Mac. Keys stay here until it ends; the pointer still moves between Macs." : nil
        if note != text { note = text }
    }
    /// macOS disables a tap whose callback fell behind. Re-enable it at once;
    /// more than a few disables in ten seconds means this Mac cannot keep up.
    @discardableResult private func reenableTap() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        tapDisables = tapDisables.filter { now - $0 < 10 } + [now]
        guard tapDisables.count <= 3, let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }
    func refreshKeyboards() {
        guard !SettingsWindow.shared.testing, !scanningKeyboards, ProcessInfo.processInfo.systemUptime >= keyboardScanAt else { return }
        scanningKeyboards = true; keyboardScanAt = ProcessInfo.processInfo.systemUptime + 1
        keyboardGeneration += 1
        let generation = keyboardGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keyboards = NativeModifierKeys.keyboards().filter { !$0.builtIn && !$0.preferenceKey.isEmpty }
            let mice = NativeModifierKeys.mice()
            DispatchQueue.main.async {
                guard let self else { return }; self.scanningKeyboards = false
                if self.keyboardGeneration == generation { self.updateKeyboards(keyboards); self.updateMice(mice); self.attachmentChanged = false }
            }
        }
    }
    private func updateMice(_ values: [NativePointingDevice]) {
        if values.map({ $0.preferenceKey + "\0" + $0.name }).sorted() != mice.map({ $0.preferenceKey + "\0" + $0.name }).sorted() { mice = values }
    }
    private func updateKeyboards(_ values: [NativeKeyboard]) {
        if values.map({ $0.preferenceKey + "\0" + $0.name }).sorted() != keyboards.map({ $0.preferenceKey + "\0" + $0.name }).sorted() { keyboards = values }
    }
    private func receive(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenableTap() { healthy = false; session.stop() }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != KVMNativeEvent.eventTag else { return false }
        // Always leave the emergency shortcut available too. No network event
        // can invoke this path because injected events are tagged above.
        if type == .keyDown || type == .keyUp {
            switch keyRouter.route(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                                   autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, sharing: session.enabled,
                                   presets: session.node.group.presets, localShortcut: localShortcut) {
            case .emergencyStop: session.stopForLocalControl(); return false
            case .activatePreset(let preset): presetShortcut?(preset); return true
            case .consumed: return true
            case .local: return false
            case .forward: break
            }
        }
        guard session.capturing else { return false }
        if [.keyDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type),
           session.focus?.computer != session.node.localID,
           session.node.group.sharedKeyboards?.contains(where: { $0.follow && $0.bindings[session.node.localID] != nil }) == true {
            // Device enumeration never runs inside the tap callback: a slow
            // IOKit scan here is what makes macOS disable the tap. The
            // attachment observer already invalidated the cache; the throttled
            // background scan refreshes it.
            if attachmentChanged { attachmentChanged = false; keyboardScanAt = 0; refreshKeyboards() }
            session.publishKeyboardAttachments()
        }
        let flags = event.flags.rawValue & KVMInputEvent.flagMask
        var value: KVMInputEvent
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
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            value = .init(kind: .scroll, flags: flags,
                          x: continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2),
                          y: continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
            value.continuous = continuous
            value.phase = Int(clamping: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            value.momentum = Int(clamping: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            if ![0, 1, 2, 4, 8, 128].contains(value.phase) { value.phase = 0 }
            if !(0...3).contains(value.momentum) { value.momentum = 0 }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            // The coordinator converts target desktop points to desk millimetres.
            value = .init(kind: .motion, flags: flags, x: event.getDoubleValueField(.mouseEventDeltaX) * pointerSpeed, y: event.getDoubleValueField(.mouseEventDeltaY) * pointerSpeed)
            // While this Mac has focus its hardware cursor is the truth.
            if session.focusComputer == session.node.localID { value.absolute = deskPosition(event.location)?.1 }
        default: return false
        }
        return session.capture(value)
    }
    private func displayID(for localDisplay: String?) -> CGDirectDisplayID? {
        guard let localDisplay else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if now - displayCacheAt > 2 {
            displayCacheAt = now
            displayCache = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (String, CGDirectDisplayID)? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
                return (CFUUIDCreateString(nil, uuid) as String, id)
            })
        }
        return displayCache[localDisplay]
    }
    private func point(_ focus: KVMInputFocus) -> CGPoint? {
        let group = session.node.group
        guard let connection = group.connections.first(where: { $0.monitor == focus.monitor && $0.computer == session.node.localID }),
              let display = displayID(for: connection.localDisplay),
              let geometry = group.monitors.first(where: { $0.id == focus.monitor })?.geometry else { return nil }
        let bounds = CGDisplayBounds(display)
        // Quartz bounds already follow macOS rotation. Do not rotate twice.
        return CGPoint(x: bounds.minX + (focus.position.x - geometry.x) / geometry.displayedWidth * max(0, bounds.width - 1),
                       y: bounds.minY + (focus.position.y - geometry.y) / geometry.displayedHeight * max(0, bounds.height - 1))
    }
    /// Inverse of `point`: which desk screen a global Quartz point is on, and where.
    private func deskPosition(_ location: CGPoint) -> (UUID, KVMPoint)? {
        let group = session.node.group
        for connection in group.connections where connection.computer == session.node.localID {
            guard let display = displayID(for: connection.localDisplay),
                  let geometry = group.monitors.first(where: { $0.id == connection.monitor })?.geometry else { continue }
            let bounds = CGDisplayBounds(display)
            guard bounds.width > 1, bounds.height > 1, bounds.contains(location) || bounds.insetBy(dx: -1, dy: -1).contains(location) else { continue }
            let x = geometry.x + (location.x - bounds.minX) / (bounds.width - 1) * geometry.displayedWidth
            let y = geometry.y + (location.y - bounds.minY) / (bounds.height - 1) * geometry.displayedHeight
            return (connection.monitor, .init(x: min(geometry.right, max(geometry.x, x)), y: min(geometry.bottom, max(geometry.y, y))))
        }
        return nil
    }
    private func post(_ value: KVMInputEvent, focus: KVMInputFocus) {
        guard healthy, let point = point(focus), !SettingsWindow.shared.testing else { session.stop(); return }
        lastLocation = point
        _ = posted.apply(value, source: postedSource)
        emitNative(value, point: point)
    }
    private func releasePosted() {
        for event in posted.releaseAll() { emitNative(event, point: lastLocation) }
        restoreCursor(); shownFocus = nil
    }
    private func restoreCursor() {
        if !cursorAssociated {
            // Reattach macOS's hardware cursor only after the remote lease has
            // ended. Keeping it detached during remote control prevents local
            // pointer motion from fighting the desk's remote coordinate.
            _ = CGAssociateMouseAndMouseCursorPosition(1)
            cursorAssociated = true
        }
        setCursorHidden(false)
    }
    /// Hiding only the main display leaves the pointer drawn on every other
    /// screen, which is why the cursor stayed behind on the Mac that had just
    /// handed control away. Hide and show are reference counted per display,
    /// so show exactly the displays that were hidden, even if the screen
    /// arrangement changed while control was remote.
    private func setCursorHidden(_ hide: Bool) {
        guard hide != cursorHidden else { return }
        if hide {
            hiddenDisplays = activeDisplays()
            for display in hiddenDisplays { CGDisplayHideCursor(display) }
        } else {
            for display in hiddenDisplays { CGDisplayShowCursor(display) }
            hiddenDisplays = []
        }
        cursorHidden = hide
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [CGMainDisplayID()] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [CGMainDisplayID()] }
        return Array(ids.prefix(Int(count)))
    }

    private func updateCursor() {
        guard !SettingsWindow.shared.testing, session.active, let focus = session.focus else { restoreCursor(); shownFocus = nil; controlWasLocal = false; setRemoteCapture(false); return }
        setRemoteCapture(focus.computer != session.node.localID)
        if focus.computer != session.node.localID {
            if cursorAssociated {
                // Hiding alone leaves the native cursor position live. Detach
                // it for the duration of a remote lease so event deltas cannot
                // pull the local cursor back or reset it at the edge.
                _ = CGAssociateMouseAndMouseCursorPosition(0)
                cursorAssociated = false
            }
            setCursorHidden(true)
            shownFocus = nil; controlWasLocal = false
        } else {
            restoreCursor()
            // Place the pointer once, when control actually arrives from the
            // other Mac, and then leave it alone. Re-placing it whenever the
            // focused screen changes dragged the cursor back while this Mac
            // still had control, including when macOS moved it natively
            // between this Mac's own screens. The desk position is the single
            // baseline for a handover; the hardware cursor owns itself after.
            if !controlWasLocal { post(.init(kind: .motion), focus: focus) }
            shownFocus = focus.monitor; controlWasLocal = true
        }
    }
    private let activity = IdleActivitySignal()
    /// Both Macs in an active lease must count as "in use"; see IdleActivitySignal.
    private func declareActivity() { activity.declare(reason: "Perch desk input sharing") }
    /// Local apps never see the modifier releases that happen while keys are
    /// forwarded, nor the presses that happen before focus returns. Tell them.
    private func setRemoteCapture(_ remote: Bool) {
        guard remote != remoteCapture else { return }
        remoteCapture = remote
        guard !SettingsWindow.shared.testing, let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x37, keyDown: false) else { return }
        event.type = .flagsChanged
        event.flags = remote ? [] : CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.eventSourceUserData, value: KVMNativeEvent.eventTag)
        event.post(tap: .cghidEventTap)
    }
    private func emitNative(_ value: KVMInputEvent, point: CGPoint) {
        guard !SettingsWindow.shared.testing else { return }
        let event = builder.make(value, point: point, source: eventSource)
        event?.post(tap: .cghidEventTap)
    }
}
