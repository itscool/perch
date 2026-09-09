import AppKit
import IOKit.hid
import IOKit.hidsystem

struct KeyboardModeResult: Equatable {
    let name: String
    let detail: String
    let verified: Bool
    var needsAccess = false
    var standard: Bool? = nil
}

/// HID++ protocol facts: 0x40A0/0x40A2 Fn inversion, 0x40A3 host-specific
/// inversion, and 0x1815 host information. See KEYBOARDS.md for references.
/// This changes the keyboard's own mode. It never rewrites or posts key events.
enum KeyboardFnProtocol {
    typealias Request = (UInt8, UInt8, [UInt8]) throws -> [UInt8]
    static func feature(_ id: UInt16, request: Request) throws -> UInt8 {
        let reply = try request(0, 0, [UInt8(id >> 8), UInt8(id & 255)])
        guard let index = reply.first else { throw AppError(message: "Incomplete feature response.") }
        return index
    }
    static func apply(standard: Bool, request: Request) throws -> Bool {
        try configure(standard: standard, request: request).changed
    }
    /// A nil target is strictly a read: opening Perch never invents an Fn default.
    static func configure(standard: Bool?, request: Request) throws -> (standard: Bool, changed: Bool) {
        var index: UInt8 = 0
        var host: UInt8?
        for id: UInt16 in [0x40A3, 0x40A2, 0x40A0] {
            index = try feature(id, request: request)
            if index == 0 { continue }
            if id == 0x40A3 {
                let hosts = try feature(0x1815, request: request)
                guard hosts != 0 else { throw AppError(message: "Keyboard does not report the active host; Fn mode was not changed.") }
                let info = try request(hosts, 0, [])
                guard info.count >= 4, info[3] < 6 else { throw AppError(message: "Keyboard returned an invalid active host.") }
                host = info[3]
            }
            break
        }
        guard index != 0 else { throw AppError(message: "No supported Fn-lock control. Use the keyboard’s Fn Lock or manufacturer settings.") }
        let prefix = host.map { [$0] } ?? []
        func read() throws -> Bool {
            let reply = try request(index, 0, prefix)
            let offset = prefix.count
            guard reply.count > offset, host == nil || reply[0] == host!, reply[offset] <= 1 else {
                throw AppError(message: "Keyboard returned an invalid Fn mode.")
            }
            return reply[offset] == 0 // Inversion ON means media keys are primary.
        }
        let before = try read()
        if let standard, before != standard {
            _ = try request(index, 0x10, prefix + [standard ? 0 : 1])
            guard try read() == standard else { throw AppError(message: "Keyboard did not confirm the new Fn mode. Retry after waking it.") }
        }
        return (standard ?? before, standard.map { before != $0 } ?? false)
    }

    // Ignore unrelated reports, notifications, other software, and receiver slots.
    static func response(_ bytes: UnsafeBufferPointer<UInt8>, reportID: UInt32, device: UInt8, feature: UInt8, function: UInt8) -> Result<[UInt8], AppError>? {
        guard reportID == 0x10 || reportID == 0x11 else { return nil }
        let size = reportID == 0x10 ? 7 : 20
        let offset: Int
        if bytes.count == size && bytes[0] == reportID { offset = 1 }
        else if bytes.count == size - 1 { offset = 0 }
        else { return nil }
        guard bytes[offset] == device else { return nil }
        if bytes[offset+1] == 0xFF || bytes[offset+1] == 0x8F {
            guard bytes[offset+2] == feature, bytes[offset+3] == function else { return nil }
            return .failure(AppError(message: "Keyboard rejected the request (HID++ error \(bytes[offset+4]))."))
        }
        guard bytes[offset+1] == feature, bytes[offset+2] == function else { return nil }
        return .success(Array(bytes[(offset+3)...]))
    }
}

private final class KeyboardHIDSession {
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>
    let loop = CFRunLoopGetCurrent()!
    let deadline = ProcessInfo.processInfo.systemUptime + 12
    var address: UInt8 = 0xff
    var software: UInt8 = UInt8.random(in: 1...15)
    var feature: UInt8 = 0
    var function: UInt8 = 0
    var reply: Result<[UInt8], AppError>?
    init(service: io_service_t) throws {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw AppError(message: "Keyboard disconnected.") }
        self.device = device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw AppError(message: "Could not open keyboard (\(result)). Check Perch’s Input Monitoring access.") }
        self.buffer = .allocate(capacity: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, reportID, report, length in
            guard let context, result == kIOReturnSuccess, length >= 0, length <= 64 else { return }
            let session = Unmanaged<KeyboardHIDSession>.fromOpaque(context).takeUnretainedValue()
            if let response = KeyboardFnProtocol.response(UnsafeBufferPointer(start: report, count: length), reportID: reportID, device: session.address, feature: session.feature, function: session.function) {
                session.reply = response
                CFRunLoopStop(session.loop)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
    func request(_ feature: UInt8, _ function: UInt8, _ payload: [UInt8], timeout: Double = 0.65) throws -> [UInt8] {
        guard ProcessInfo.processInfo.systemUptime < deadline, payload.count <= 16 else { throw AppError(message: "Keyboard setup timed out. Wake the keyboard and retry.") }
        software = software % 15 + 1
        self.feature = feature; self.function = function | software; reply = nil
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11; bytes[1] = address; bytes[2] = feature; bytes[3] = self.function
        for (offset, byte) in payload.enumerated() { bytes[4+offset] = byte }
        let sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, bytes, bytes.count)
        guard sent == kIOReturnSuccess else { throw AppError(message: "Keyboard communication failed (\(sent)). Wake or reconnect it, then retry.") }
        let until = min(deadline, ProcessInfo.processInfo.systemUptime + timeout)
        while reply == nil && ProcessInfo.processInfo.systemUptime < until {
            CFRunLoopRunInMode(.defaultMode, max(0, until - ProcessInfo.processInfo.systemUptime), false)
        }
        guard let reply else { throw AppError(message: "Keyboard did not reply. Wake or reconnect it, then retry.") }
        return try reply.get()
    }
    func apply(standard: Bool?, name: String, receiver: Bool) -> [KeyboardModeResult] {
        var results: [KeyboardModeResult] = []
        // A receiver exposes up to six paired devices. Query type before changing
        // anything, so a paired mouse or headset can never receive an Fn write.
        for slot: UInt8 in receiver ? [1,2,3,4,5,6] : [0xff] {
            address = slot
            do {
                let ping = try request(0, 0x10, [0,0,0xA7], timeout: receiver ? 0.25 : 0.65)
                guard ping.count >= 3, ping[0] >= 2, ping[2] == 0xA7 else { continue }
                let nameFeature = try KeyboardFnProtocol.feature(0x0005, request: { try self.request($0,$1,$2) })
                if receiver {
                    guard nameFeature != 0, try request(nameFeature, 0x20, []).first == 0 else { continue }
                }
                var displayName = name
                if receiver { displayName += " · keyboard \(slot)" }
                do {
                    let mode = try KeyboardFnProtocol.configure(standard: standard, request: { try self.request($0,$1,$2) }).standard
                    results.append(.init(name: displayName, detail: mode ? "✓ F1–F12 directly · confirmed by keyboard" : "✓ Hold Fn for F1–F12 · confirmed by keyboard", verified: true, standard: mode))
                } catch { results.append(.init(name: displayName, detail: "⚠ " + error.localizedDescription, verified: false)) }
            } catch {
                if !receiver { results.append(.init(name: name, detail: "⚠ " + error.localizedDescription, verified: false)) }
            }
        }
        if results.isEmpty { results.append(.init(name: name, detail: "⚠ No compatible awake keyboard replied. Wake it and retry; some keyboards require their own Fn Lock.", verified: false)) }
        return results
    }
}

enum ExternalKeyboardModes {
    static func property(_ service: io_service_t, _ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
    static func keyboards(standard: Bool?, only names: Set<String>? = nil) -> [KeyboardModeResult] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else {
            return [.init(name: "External keyboards", detail: "⚠ Could not enumerate connected keyboards.", verified: false)]
        }
        defer { IOObjectRelease(iterator) }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 { services.append(service) }
        defer { services.forEach { IOObjectRelease($0) } }
        var results: [KeyboardModeResult] = []
        var handledReceivers: Set<UInt32> = []
        for service in services {
            let usages = property(service, "DeviceUsagePairs") as? [[String: Int]] ?? []
            let keyboard = (property(service, "PrimaryUsagePage") as? Int) == 1 && (property(service, "PrimaryUsage") as? Int) == 6
                && usages.contains { $0["DeviceUsagePage"] == 1 && $0["DeviceUsage"] == 6 }
            guard keyboard else { continue }
            let transport = property(service, "Transport") as? String ?? ""
            guard transport != "Virtual", property(service, "Built-In") as? Bool != true else { continue }
            let name = property(service, "Product") as? String ?? "External keyboard"
            let vendor = property(service, "VendorID") as? Int ?? 0
            // Apple keyboard Fn modes are queried/set through their native HID
            // services by NativeFunctionKeys, not the Logitech firmware protocol.
            if vendor == 0x05AC { continue }
            guard vendor == 0x046D else {
                results.append(.init(name: name, detail: "⚠ Automatic Fn control is not supported. Match this keyboard’s Fn Lock or manufacturer setting manually.", verified: false)); continue
            }
            let location = property(service, "LocationID") as? UInt32 ?? 0
            let isReceiver = name.localizedCaseInsensitiveContains("receiver")
            var endpoint = service
            if isReceiver {
                guard location != 0, handledReceivers.insert(location).inserted else { continue }
                if let sibling = services.first(where: { candidate in
                    (property(candidate, "VendorID") as? Int) == vendor && (property(candidate, "LocationID") as? UInt32) == location &&
                    ((property(candidate, "DeviceUsagePairs") as? [[String:Int]]) ?? []).contains { [0xFF00, 0xFF43].contains($0["DeviceUsagePage"] ?? 0) }
                }) { endpoint = sibling }
            }
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
                results.append(.init(name: name, detail: "⚠ Enable Input Monitoring for Perch to configure this keyboard’s Fn mode.", verified: false, needsAccess: true)); continue
            }
            do {
                let session = try KeyboardHIDSession(service: endpoint)
                results += session.apply(standard: names == nil || names!.contains(name) ? standard : nil, name: name, receiver: isReceiver)
            } catch { results.append(.init(name: name, detail: "⚠ " + error.localizedDescription, verified: false)) }
        }
        return results
    }
}
