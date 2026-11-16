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
    /// ⌃⌥⌘V, when no other Perch shortcut holds it (`DeskBringOverShortcut`).
    var bringOverShortcut: () -> Shortcut? = { nil }
    /// Bring over the newest copy, for the Mac typing goes to.
    var bringOver: (() -> Void)?
    @Published private(set) var accessProblem: String?
    /// Why this Mac cannot share, for the other Macs.
    private var shareReason: KVMShareReason?
    /// A fact worth showing that does not stop sharing.
    @Published private(set) var note: String?
    private var tapRecovery = DeskTapRecovery()
    private var nextTapRetry: Double = 0
    private var keyRouter = DeskKeyRouter()
    private var remoteCapture = false
    private var displayCache: [String: CGDirectDisplayID] = [:]
    private var displayCacheAt: Double = -1
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
    private var clicks = DeskClickCounter()
    private var scrolling = DeskScrollGesture()
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var screenLocked = false
    /// Whether control was already on this Mac at the last cursor update.
    private var controlWasLocal = false
    /// The real cursor. Parking and movement from other Macs go through it alone.
    private let cursor: DeskCursorSystem = NativeDeskCursor()
    private var parking = DeskCursorParking()
    private var handover = DeskPointerHandover()
    private var smoothness = DeskMotionSmoothness()
    /// The same measure on the sending side: how evenly this Mac's own mouse
    /// reaches Perch. A pointer that stutters on the other Mac is either late
    /// leaving here or late arriving there, and these two numbers say which.
    private var capturedSmoothness = DeskMotionSmoothness()
    private var travel = DeskTravelJitter()
    private var nextParkingSummary: Double = 0
    private var subscription: AnyCancellable?
    init(session: KVMInputSession) {
        self.session = session
        eventSource?.localEventsSuppressionInterval = 0
        session.ready = { [weak self] in self?.healthy == true }
        session.readyReason = { [weak self] in self?.shareReason }
        session.emit = { [weak self] event, location in self?.post(event, focus: location) }
        session.release = { [weak self] in self?.releasePosted() }
        session.keepAwake = { [weak self] in self?.declareActivity() }
        session.localPointerPosition = { [weak self] _ in
            // Report where this Mac's cursor actually is, on whichever desk
            // screen it sits. Returning nothing unless it happened to be on
            // the target screen is what left a first focus with no position
            // to use, and that is what fell back to a screen centre.
            guard let self, let location = CGEvent(source: nil)?.location else { return nil }
            return self.deskPosition(location)?.1
        }
        session.focusChanged = { [weak self] in self?.updateCursor() }
        subscription = session.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateCursor() } }
    }
    deinit { stop() }
    func enable(_ enabled: Bool) {
        guard !SettingsWindow.shared.testing else { return }
        UserDefaults.standard.set(enabled, forKey: Self.sharingEnabledKey)
        if !enabled { stop(); return }
        tapStartFailed = false
        session.setEnabled(true)
        if healthTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                // macOS turned the tap off too often in a row: rebuild it after a
                // pause, by itself (PERCH.md rule 4).
                if self.tapRecovery.rebuildDue(at: now) {
                    PerchLog.record("input.access", "Rebuilding this Mac's input capture after macOS kept turning it off")
                    self.restart(); return
                }
                // A tap macOS would not create is tried again every few seconds.
                if self.tapStartFailed, self.session.enabled, now >= self.nextTapRetry {
                    self.nextTapRetry = now + DeskTapRecovery.startRetry
                    self.tapStartFailed = false
                }
                self.checkAccess()
                if self.session.enabled && self.healthy && self.tap == nil { self.enable(true) }
            }
            healthTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        checkAccess()
        guard healthy else { return }
        if tap == nil {
            let types: [CGEventType] = [.keyDown,.keyUp,.flagsChanged,.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.scrollWheel]
            // Media keys (system-defined events) and trackpad gestures too.
            let extra = DeskGestures.types.union([DeskMediaKey.eventType])
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) } | extra.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
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
                    if locked { self?.healthy = false; self?.session.stop("this Mac's screen locked") }
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
        activity.close()
        healthy = false; healthTimer?.invalidate(); healthTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; lockObservers = []
        parking.end(cursor); tapStartFailed = false; accessProblem = nil
    }
    var needsPermissionSetup: Bool {
        !AccessCheck.sharing
    }
    private func checkAccess() {
        let console = CGSessionCopyCurrentDictionary() as? [String: Any]
        let reason: KVMShareReason?
        if !AccessCheck.accessibilityWithPosting { reason = .needsAccessibility }
        else if !AccessCheck.inputMonitoring { reason = .needsInputMonitoring }
        else if screenLocked || console?["CGSSessionScreenIsLocked"] as? Bool == true { reason = .locked }
        else if console?[kCGSessionOnConsoleKey as String] as? Bool != true || console?[kCGSessionLoginDoneKey as String] as? Bool != true { reason = .inactiveSession }
        else if tapStartFailed { reason = .captureFailed }
        else if tapRecovery.rebuilding { reason = .captureRestarting }
        else if let tap, !CGEvent.tapIsEnabled(tap: tap), !reenableTap() { reason = .captureRestarting }
        else { reason = nil }
        // Worded once for every Mac (`KVMInputStatus`); the other Macs hear the
        // reason itself with this Mac's polls.
        shareReason = reason
        let issue = reason.map(KVMInputStatus.here)
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
        // While it holds keys meant for another Mac, that Mac shows a popup.
        let app = secure ? (console?["kCGSSessionSecureInputPID"] as? Int).flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.localizedName } : nil
        session.secureInput(secure, app: app)
    }
    /// macOS disables a tap whose callback fell behind. Re-enable it at once;
    /// after too many in a row, rebuild it after a pause (`DeskTapRecovery`).
    @discardableResult private func reenableTap() -> Bool {
        guard tapRecovery.disabled(at: ProcessInfo.processInfo.systemUptime), let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }
    private func receive(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenableTap() { healthy = false; session.stop("macOS turned off this Mac's input capture") }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != KVMNativeEvent.eventTag else { return false }
        // Trackpad gestures act on the Mac whose trackpad made them; while the
        // pointer is on another Mac they are ignored here (Scott, November 16).
        if DeskGestures.types.contains(type.rawValue) { return DeskGestures.ignored(pointerElsewhere: pointerElsewhere) }
        // Volume, brightness and play/pause follow the pointer (Scott, November 16).
        if type.rawValue == DeskMediaKey.eventType {
            guard session.capturing, let key = DeskMediaKey(event) else { return false }
            return session.capture(.init(kind: key.down ? .mediaDown : .mediaUp, code: key.code, repeated: key.repeated && key.down))
        }
        // Always leave the emergency shortcut available too. No network event
        // can invoke this path because injected events are tagged above.
        if type == .keyDown || type == .keyUp {
            switch keyRouter.route(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                                   autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, sharing: session.enabled,
                                   presets: session.node.group.presets, localShortcut: localShortcut, bringOver: bringOverShortcut()) {
            case .emergencyStop: session.stopForLocalControl(); return false
            case .activatePreset(let preset): presetShortcut?(preset); return true
            case .bringOver: bringOver?(); return true
            case .consumed: return true
            case .local: return false
            case .forward: break
            }
        }
        guard session.capturing else { return false }
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
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            value = .init(kind: .motion, flags: flags, x: dx, y: dy)
            // The same movement in millimetres of the screen it was made on, so
            // it covers the same distance on every screen (Scott, November 16).
            value.mm = screenScale(at: event.location).map { DeskMotionScale.millimetres(dx: dx, dy: dy, scale: $0) }
            // Whether a button is down, said every time: a drag never crosses to
            // another Mac, and a move with none down releases a lost one.
            value.dragging = type != .mouseMoved
            // While this Mac has focus its hardware cursor is the truth.
            if session.focusComputer == session.node.localID { value.absolute = deskPosition(event.location)?.1 }
        default: return false
        }
        if value.kind == .motion, session.focusComputer != session.node.localID,
           let summary = capturedSmoothness.arrived(at: ProcessInfo.processInfo.systemUptime) {
            PerchLog.record("input.capture", "This Mac's own mouse, on its way out: " + summary)
        }
        let captured = session.capture(value)
        // A parked cursor does not move; any that does is put back.
        if captured, value.kind == .motion, parking.parked {
            parking.reset(from: event.location, cursor)
            summarizeParking()
        }
        return captured
    }
    private func displayID(for localDisplay: String?, fresh: Bool = false) -> CGDirectDisplayID? {
        guard let localDisplay else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if fresh || now - displayCacheAt > 2 {
            displayCacheAt = now
            displayCache = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (String, CGDirectDisplayID)? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
                return (CFUUIDCreateString(nil, uuid) as String, id)
            })
        }
        return displayCache[localDisplay]
    }
    private func point(_ focus: KVMInputFocus, fresh: Bool = false) -> CGPoint? {
        let group = session.node.group
        guard let connection = group.connections.first(where: { $0.monitor == focus.monitor && $0.computer == session.node.localID }),
              let display = displayID(for: connection.localDisplay, fresh: fresh),
              let geometry = group.monitors.first(where: { $0.id == focus.monitor })?.geometry else { return nil }
        let bounds = CGDisplayBounds(display)
        // Quartz bounds already follow macOS rotation. Do not rotate twice.
        return CGPoint(x: bounds.minX + (focus.position.x - geometry.x) / geometry.displayedWidth * max(0, bounds.width - 1),
                       y: bounds.minY + (focus.position.y - geometry.y) / geometry.displayedHeight * max(0, bounds.height - 1))
    }
    /// Millimetres per point on the desk screen under a global Quartz point.
    private func screenScale(at location: CGPoint) -> KVMPoint? {
        let group = session.node.group
        for connection in group.connections where connection.computer == session.node.localID {
            guard let display = displayID(for: connection.localDisplay),
                  let geometry = group.monitors.first(where: { $0.id == connection.monitor })?.geometry else { continue }
            let bounds = CGDisplayBounds(display)
            guard bounds.width > 1, bounds.height > 1, bounds.insetBy(dx: -1, dy: -1).contains(location) else { continue }
            return DeskMotionScale.scale(bounds: bounds, geometry: geometry)
        }
        return nil
    }
    /// Whether the pointer is on, or on its way to, another Mac.
    private var pointerElsewhere: Bool {
        guard session.capturing else { return false }
        return (session.handoffTarget?.computer ?? session.focusComputer).map { $0 != session.node.localID } ?? false
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
    /// Movement from another Mac is added to the live cursor, exactly like this
    /// Mac's own mouse, and keys, clicks and scrolling land where the cursor really
    /// is. Placing them at a position converted from desk millimetres is what let a
    /// click land somewhere the cursor was not.
    private func post(_ value: KVMInputEvent, focus: KVMInputFocus) {
        guard healthy, !SettingsWindow.shared.testing else { session.stop("input capture on this Mac is not healthy"); return }
        // Media keys are posted as macOS's own system-defined key events.
        if value.kind == .mediaDown || value.kind == .mediaUp {
            if !SettingsWindow.shared.testing { DeskMediaKey.post(code: value.code, down: value.kind == .mediaDown, repeated: value.repeated) }
            return
        }
        // Typing goes where the last click was, which need not be where the
        // pointer is. It never moves, shows or un-parks the cursor.
        if KVMInputRouting.typing(value.kind) {
            _ = posted.apply(value, source: postedSource)
            emitNative(value, point: cursor.location)
            return
        }
        // Control can arrive together with the movement that caused it, before
        // the cursor update runs. The first event then continues from the entry
        // point rather than from this Mac's parked cursor.
        let arriving = !handover.placed
        let here = arriving ? handover.base(entry: point(focus), live: cursor.location) : cursor.location
        var value = value
        // Movement in millimetres becomes points of the screen it lands on here.
        if value.kind == .motion, let mm = value.mm, let scale = screenScale(at: here) {
            let points = DeskMotionScale.points(mm: mm, scale: scale)
            value.x = points.x; value.y = points.y
        }
        let point = value.kind == .motion
            ? DeskCursorParking.moved(from: here, dx: value.x, dy: value.y, displays: cursor.displays)
            : here
        // Arriving: put the cursor where it belongs while still hidden, then show it.
        if arriving { cursor.warp(to: point); parking.end(cursor) }
        lastLocation = point
        // Clicks are counted here, where the pointer is: the sending Mac's
        // cursor stands still while parked, so two quick clicks on two
        // different things there counted as a double-click.
        if value.kind == .buttonDown { value.clickCount = clicks.down(value.code, at: ProcessInfo.processInfo.systemUptime, point: point, interval: NSEvent.doubleClickInterval) }
        else if value.kind == .buttonUp { value.clickCount = clicks.count(value.code) }
        if value.kind == .scroll { scrolling.posted(value) }
        _ = posted.apply(value, source: postedSource)
        emitNative(value, point: point)
        guard value.kind == .motion else { return }
        let arrivedAt = ProcessInfo.processInfo.systemUptime
        if let summary = smoothness.arrived(at: arrivedAt) {
            PerchLog.record("input.smoothness", "Pointer on this Mac: " + summary)
        }
        if let summary = travel.arrived(sent: value.sentAt, at: arrivedAt) {
            PerchLog.record("input.travel", "Movement from the other Mac: " + summary)
        }
        if let position = deskPosition(point)?.1 { session.reportPointer(position) }
    }
    /// Put the cursor where control arrives, once, just inside the edge it crossed.
    private func place(at focus: KVMInputFocus) {
        guard healthy, !SettingsWindow.shared.testing else { session.stop("input capture on this Mac is not healthy"); return }
        // The display list is cached for two seconds; a screen that has just
        // come back is looked up afresh before giving up.
        guard let point = point(focus) ?? point(focus, fresh: true) else { session.stop("this Mac could not find the screen control arrived on among its displays"); return }
        lastLocation = point
        handover.placedPointer()
        // Warp as well as posting the movement: a posted event moves the cursor,
        // but not before the next delivered event reads where the cursor is.
        cursor.shortenWarpPause()
        cursor.warp(to: point)
        emitNative(.init(kind: .motion), point: point)
    }
    /// Releases what this Mac posted. Whether the cursor shows is decided by
    /// `updateCursor` alone: un-parking here showed it at every handoff.
    private func releasePosted() {
        for event in posted.releaseAll() { emitNative(event, point: lastLocation) }
        // A scroll still under way is ended, so no app is left mid-gesture.
        for event in scrolling.endings() { emitNative(event, point: lastLocation) }
    }
    private func updateCursor() {
        let local = session.node.localID
        let step = SettingsWindow.shared.testing ? .free
            : DeskCursorStep.decide(handoffTo: session.handoffTarget?.computer, active: session.active, focus: session.focus?.computer, local: local)
        switch step {
        case .free:
            // Sharing stopped or a handoff fell through: whatever hid the cursor,
            // it must be back on screen.
            parking.end(cursor); cursor.show(); controlWasLocal = false; handover.left(); setRemoteCapture(false)
        case .hold:
            // On its way here: still hidden if it was parked, until placed.
            break
        case .park:
            setRemoteCapture(true)
            if !parking.parked { nextParkingSummary = 0 }
            parking.begin(cursor)
            controlWasLocal = false; handover.left()
        case .here:
            setRemoteCapture(false)
            guard let focus = session.focus else { return }
            // Place the pointer once, when control arrives from the other Mac, and
            // then leave it alone. A delivered event may already have placed it and
            // moved on; placing again would drag it back to the edge it came in by.
            // Move it while it is still hidden, then show it.
            if !controlWasLocal, !handover.placed { place(at: focus) }
            parking.end(cursor)
            cursor.show()
            controlWasLocal = true
        }
    }
    /// Every few seconds while parked, record how many resets ran and how far the
    /// cursor got before each. Near-zero drift means the reset is holding.
    private func summarizeParking() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextParkingSummary else { return }
        let first = nextParkingSummary == 0
        nextParkingSummary = now + DeskMotionSmoothness.window
        guard !first else { return }
        let summary = parking.takeSummary()
        PerchLog.record("input.parking", String(format: "Pointer on another Mac: parked cursor reset %d times, drifting at most %.0f points before a reset", summary.resets, summary.worstDrift))
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
        // Modifiers held on this Mac's own keyboard apply too: Command on this
        // keyboard with a click from the other Mac's mouse is a Command-click.
        let local = CGEventSource.flagsState(.hidSystemState).rawValue & KVMInputEvent.flagMask
        let event = builder.make(value, point: point, source: eventSource, localFlags: local)
        event?.post(tap: .cghidEventTap)
    }
}

/// What to do when macOS turns the input tap off, as it does when the tap's
/// callback falls behind. A few times in a row it is turned straight back on.
/// More than that, and re-enabling only fails again, so the tap is rebuilt from
/// scratch after a short pause. Before, the count of failures was also fed by the
/// quarter-second health check, so it never fell and sharing stayed off on that
/// Mac for good, while the status said Perch was retrying.
struct DeskTapRecovery {
    static let window: Double = 10
    static let limit = 3
    /// The pause before a rebuild, and before trying a tap macOS refused to create.
    static let pause: Double = 5
    static let startRetry: Double = 5
    private(set) var disables: [Double] = []
    private(set) var rebuildAt: Double?
    var rebuilding: Bool { rebuildAt != nil }
    /// The tap was found off. True: turn it back on now. False: wait for the rebuild.
    mutating func disabled(at now: Double) -> Bool {
        if rebuildAt != nil { return false }
        disables = disables.filter { now - $0 < Self.window } + [now]
        guard disables.count > Self.limit else { return true }
        rebuildAt = now + Self.pause
        return false
    }
    /// Whether the rebuild is due now. It happens once, and the count starts over.
    mutating func rebuildDue(at now: Double) -> Bool {
        guard let at = rebuildAt, now >= at else { return false }
        rebuildAt = nil; disables = []
        return true
    }
}

/// Trackpad gestures: rotate (18), begin and end gesture (19, 20), gesture
/// (29), magnify (30), swipe (31), smart magnify (32) and pressure (34).
enum DeskGestures {
    static let types: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32, 34]
    /// Ignored on this Mac while the pointer is on another: before, a pinch
    /// zoomed and a swipe switched Spaces on the hidden Mac underneath.
    static func ignored(pointerElsewhere: Bool) -> Bool { pointerElsewhere }
}

/// Volume, brightness, play/pause and the other media keys: macOS's
/// system-defined key events, subtype 8, the key in the top half of data1.
struct DeskMediaKey: Equatable {
    static let eventType: UInt32 = 14
    let code: UInt16
    let down: Bool
    let repeated: Bool
    init?(data1: Int) {
        let code = (data1 & 0xFFFF_0000) >> 16, flags = data1 & 0xFFFF, state = (flags & 0xFF00) >> 8
        guard (0...31).contains(code), state == 0x0A || state == 0x0B else { return nil }
        self.code = UInt16(code); down = state == 0x0A; repeated = flags & 0x1 == 1
    }
    init?(_ event: CGEvent) {
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return nil }
        self.init(data1: ns.data1)
    }
    static func data1(code: UInt16, down: Bool, repeated: Bool) -> Int {
        (Int(code) << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeated ? 1 : 0)
    }
    /// Post it here, tagged so Perch's own tap leaves it alone.
    static func post(code: UInt16, down: Bool, repeated: Bool) {
        guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00)),
                                             timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                             data1: data1(code: code, down: down, repeated: repeated), data2: -1)?.cgEvent else { return }
        event.setIntegerValueField(.eventSourceUserData, value: KVMNativeEvent.eventTag)
        event.post(tap: .cghidEventTap)
    }
}

/// Pointer speed matched across Macs: movement travels the same physical
/// distance whichever screen it is on, from each screen's own scale.
enum DeskMotionScale {
    /// Millimetres per point of a screen, from its bounds in points and its
    /// size on the desk.
    static func scale(bounds: CGRect, geometry: KVMGeometry) -> KVMPoint? {
        guard bounds.width > 1, bounds.height > 1, geometry.displayedWidth > 0, geometry.displayedHeight > 0 else { return nil }
        return KVMPoint(x: geometry.displayedWidth / bounds.width, y: geometry.displayedHeight / bounds.height)
    }
    static func millimetres(dx: Double, dy: Double, scale: KVMPoint) -> KVMPoint { KVMPoint(x: dx * scale.x, y: dy * scale.y) }
    static func points(mm: KVMPoint, scale: KVMPoint) -> KVMPoint { KVMPoint(x: mm.x / scale.x, y: mm.y / scale.y) }
}
