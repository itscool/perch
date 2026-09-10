import AppKit
import ApplicationServices
import IOKit.hidsystem

// Transform existing events in place: horizontal scrolling and unrelated keys are untouched.
enum InputTransform {
    static func apply(_ event: CGEvent, type: CGEventType, trackpad: Bool, wheel: Bool, swap: Bool) {
        if type == .scrollWheel {
            // Trackpad gestures carry scroll or momentum phases. Continuous wheel drivers
            // without gesture phases remain wheels (continuous alone is not a device ID).
            let isTrackpad = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
            if isTrackpad ? trackpad : wheel {
                // Setting the line delta also rewrites pixel/fixed deltas on macOS.
                // Capture every original value before setting any of them.
                let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line == Int64.min ? Int64.max : -line)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point == Int64.min ? Int64.max : -point)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed)
            }
        }
        if swap && [.keyDown, .keyUp, .flagsChanged].contains(type) {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            switch key {
            case 59: event.setIntegerValueField(.keyboardEventKeycode, value: 55)
            case 55: event.setIntegerValueField(.keyboardEventKeycode, value: 59)
            case 62: event.setIntegerValueField(.keyboardEventKeycode, value: 54)
            case 54: event.setIntegerValueField(.keyboardEventKeycode, value: 62)
            default: break
            }
            let original = event.flags.rawValue
            // Aggregate modifiers plus left/right device-specific flags from IOLLEvent.h.
            let pairs: [(UInt64, UInt64)] = [(CGEventFlags.maskControl.rawValue, CGEventFlags.maskCommand.rawValue), (0x1, 0x8), (0x2000, 0x10)]
            var result = original
            for (control, command) in pairs {
                result &= ~(control | command)
                if original & control != 0 { result |= command }
                if original & command != 0 { result |= control }
            }
            event.flags = CGEventFlags(rawValue: result)
        }
    }
}

final class InputControls {
    var reverseTrackpad = UserDefaults.standard.bool(forKey: "reverseTrackpad")
    var reverseWheel = UserDefaults.standard.bool(forKey: "reverseWheel")
    var swapModifiers = false // v1.1 uses native per-keyboard modifier settings.
    let navigation = NavigationEngine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var configuredMask: CGEventMask = 0
    var wanted: Bool { reverseTrackpad || reverseWheel || swapModifiers || navigation.preferences.enabled || navigation.hasHeldKeys }
    var active: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func save() {
        UserDefaults.standard.set(reverseTrackpad, forKey: "reverseTrackpad")
        UserDefaults.standard.set(reverseWheel, forKey: "reverseWheel")
        UserDefaults.standard.set(swapModifiers, forKey: "swapModifiers")
    }
    @discardableResult
    func update(requestPermission: Bool = false, trusted: Bool? = nil) -> Bool {
        guard wanted else { stop(); return false }
        guard trusted ?? AXIsProcessTrusted() else {
            stop()
            if requestPermission {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            return false
        }
        var types: [CGEventType] = []
        if reverseTrackpad || reverseWheel { types.append(.scrollWheel) }
        if swapModifiers { types.append(.flagsChanged) }
        if swapModifiers || navigation.preferences.enabled || navigation.hasHeldKeys { types += [.keyDown, .keyUp] }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        if let tap, configuredMask == mask || navigation.hasHeldKeys {
            // The same verified state feeds the heartbeat; avoid asking
            // WindowServer twice on every unchanged maintenance tick.
            if CGEvent.tapIsEnabled(tap: tap) { return true }
            CGEvent.tapEnable(tap: tap, enable: true)
            return CGEvent.tapIsEnabled(tap: tap)
        }
        stop()
        configuredMask = mask
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controls = Unmanaged<InputControls>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controls.navigation.reset()
                if let tap = controls.tap, controls.wanted { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if event.getIntegerValueField(.eventSourceUserData) != KVMNativeEvent.eventTag {
                InputTransform.apply(event, type: type, trackpad: controls.reverseTrackpad, wheel: controls.reverseWheel, swap: controls.swapModifiers)
                controls.navigation.apply(event, type: type)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return active
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        navigation.reset()
    }
    deinit { stop() }
}

enum FunctionKeys {
    static func connection<T>(_ action: (io_connect_t) throws -> T) throws -> T {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { throw AppError(message: "This Mac does not expose function-key settings.") }
        defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let status = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &port)
        guard status == KERN_SUCCESS else { throw AppError(message: "Could not access function-key settings (\(status)).") }
        defer { IOServiceClose(port) }
        return try action(port)
    }
    static func read(_ port: io_connect_t) throws -> Bool {
        var value: Unmanaged<CFTypeRef>?
        let status = IOHIDCopyCFTypeParameter(port, kIOHIDFKeyModeKey as CFString, &value)
        guard status == KERN_SUCCESS, let number = value?.takeRetainedValue() as? NSNumber else { throw AppError(message: "Could not read function-key mode (\(status)).") }
        return number.boolValue
    }
    static func standard() throws -> Bool { try connection { try read($0) } }
    static func setStandard(_ standard: Bool) throws {
        try connection { port in
            let status = IOHIDSetCFTypeParameter(port, kIOHIDFKeyModeKey as CFString, NSNumber(value: standard ? 1 : 0))
            guard status == KERN_SUCCESS else { throw AppError(message: "Could not set function-key mode (\(status)).") }
            guard try read(port) == standard else { throw AppError(message: "macOS did not apply function-key mode.") }
        }
        CFPreferencesSetValue("com.apple.keyboard.fnState" as CFString, standard ? kCFBooleanTrue : kCFBooleanFalse, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw AppError(message: "Function-key mode changed, but could not be saved for the next login.")
        }
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.keyboard.fnstatedidchange"), object: nil, userInfo: ["state": standard], deliverImmediately: true)
    }
}
