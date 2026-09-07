import AppKit
import IOKit.hid
import IOKit.hidsystem

struct NavigationProbeKeyboard {
    let device: IOHIDDevice
    let id: UInt64
    let name: String
    let transport: String
    let identity: NavigationKeyboardIdentity

    /// Enumeration reads device metadata only; no device is opened or scheduled.
    static func connected() -> [NavigationProbeKeyboard] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [NavigationProbeKeyboard] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service), IOHIDDeviceConformsTo(device, 1, 6) else { continue }
            let builtIn = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "Built-In" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? NSNumber
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            guard NavigationDeviceScope.isExternal(builtIn: builtIn?.boolValue, transport: transport) else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS, id != 0 else { continue }
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "External keyboard"
            func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            let elements = IOHIDDeviceCopyMatchingElements(device, [kIOHIDElementUsagePageKey: 7] as CFDictionary, 0) as? [IOHIDElement] ?? []
            let usages = Set(elements.map { IOHIDElementGetUsage($0) }.filter { NavigationLearning.allowed($0) }).sorted()
            let identity = NavigationKeyboardIdentity(vendor: number(kIOHIDVendorIDKey), product: number(kIOHIDProductIDKey), version: number(kIOHIDVersionNumberKey), name: name, transport: transport, usages: usages)
            result.append(.init(device: device, id: id, name: name, transport: transport, identity: identity))
        }
        return result.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

/// Only instantiated when the user presses Start in Perch. There is no event
/// tap, exclusive grab, key injection, settings write, or input report callback.
final class NavigationProbeHID: NavigationProbeSource {
    let keyboard: NavigationProbeKeyboard
    private var opened = false
    private var value: ((UInt64, UInt32, UInt32, Int) -> Void)?
    private var failed: ((String) -> Void)?
    let learning: Bool
    init(keyboard: NavigationProbeKeyboard, learning: Bool = false) { self.keyboard = keyboard; self.learning = learning }
    static var hasAccess: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    func start(value: @escaping (UInt64, UInt32, UInt32, Int) -> Void, failed: @escaping (String) -> Void) throws {
        precondition(Thread.isMainThread)
        guard !opened else { return }
        guard Self.hasAccess else { throw AppError(message: "Enable Input Monitoring for Perch, then start the test again.") }
        self.value = value; self.failed = failed
        let device = keyboard.device
        let usages = learning ? NavigationLearning.usages : NavigationKey.allCases.map { $0.rawValue }
        let matches = usages.map { [kIOHIDElementUsagePageKey: 7, kIOHIDElementUsageKey: Int($0)] }
        IOHIDDeviceSetInputValueMatchingMultiple(device, matches as CFArray)
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            self.value = nil; self.failed = nil
            throw AppError(message: "Could not observe \(keyboard.name) (\(result)). Wake or reconnect it, then recheck keyboards.")
        }
        opened = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context else { return }
            let source = Unmanaged<NavigationProbeHID>.fromOpaque(context).takeUnretainedValue()
            guard source.opened else { return }
            guard result == kIOReturnSuccess else { source.failed?("Keyboard input became unavailable. Test stopped."); return }
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
            // Defense in depth: setup permits only function/navigation usages;
            // the diagnostic permits only the original four navigation usages.
            guard page == 7, source.learning ? NavigationLearning.allowed(usage) : NavigationKey(rawValue: usage) != nil else { return }
            guard IOHIDValueGetLength(value) > 0, IOHIDValueGetLength(value) <= MemoryLayout<CFIndex>.size else { return }
            source.value?(source.keyboard.id, page, usage, IOHIDValueGetIntegerValue(value))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let source = Unmanaged<NavigationProbeHID>.fromOpaque(context).takeUnretainedValue()
            source.failed?("Keyboard disconnected. Reconnect it, then recheck keyboards.")
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    func stop() {
        guard opened else { return }
        opened = false
        let device = keyboard.device
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        value = nil; failed = nil
    }
    deinit { stop() }
}
