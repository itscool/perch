import Foundation
import IOKit.hidsystem

enum ModifierKeyMap {
    static let source = "HIDKeyboardModifierMappingSrc", destination = "HIDKeyboardModifierMappingDst"
    static let pairs: [(UInt64, UInt64)] = [(0x7000000E0,0x7000000E3), (0x7000000E3,0x7000000E0), (0x7000000E4,0x7000000E7), (0x7000000E7,0x7000000E4)]
    static func swapped(_ mapping: [[String:UInt64]]) -> Bool? {
        let destinations = Dictionary(mapping.map { ($0[source] ?? 0, $0[destination] ?? 0) }, uniquingKeysWith: { _, last in last })
        if pairs.allSatisfy({ destinations[$0.0] == $0.1 }) { return true }
        if pairs.allSatisfy({ destinations[$0.0] == nil || destinations[$0.0] == $0.0 }) { return false }
        return nil
    }
    static func setting(_ swapped: Bool, in original: [[String:UInt64]]) -> [[String:UInt64]] {
        var result = original.filter { entry in !pairs.contains { $0.0 == entry[source] } }
        // Identity mappings aren't needed; preserve Caps Lock, Option, Fn, etc.
        if swapped { result += pairs.map { [source:$0.0, destination:$0.1] } }
        return result
    }
}

struct NativeKeyboard {
    let service: IOHIDServiceClient
    let name: String
    let builtIn: Bool
    let preferenceKey: String
    let mapping: [[String:UInt64]]
    var swapped: Bool? { ModifierKeyMap.swapped(mapping) }
}

enum NativeModifierKeys {
    static let property = "HIDKeyboardModifierMappingPairs"
    // The formatter also handles older Apple keyboards' alt_handler_id keys.
    // Soft-link this read-only identity helper; all setting I/O uses public APIs.
    private static let formatter: (@convention(c) (IOHIDServiceClient) -> Unmanaged<CFString>?)? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/MachineSettings.framework/MachineSettings", RTLD_LAZY), let symbol = dlsym(library, "createKeyForKeyboard") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (IOHIDServiceClient) -> Unmanaged<CFString>?).self)
    }()
    static func intentKey(_ builtIn: Bool) -> String { builtIn ? "modifierSwap.builtIn" : "modifierSwap.external" }
    static func keyboards() -> [NativeKeyboard] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.compactMap { service in
            guard IOHIDServiceClientConformsTo(service, 1, 6) != 0 else { return nil }
            func value(_ key: String) -> AnyObject? { IOHIDServiceClientCopyProperty(service, key as CFString) }
            guard (value("Transport") as? String) != "Virtual" else { return nil }
            // Ask the same formatter as Keyboard Settings; don't guess the key
            // from VID/PID because legacy Apple Bluetooth keyboards differ.
            let suffix = formatter?(service)?.takeUnretainedValue() as String?
            let key = suffix.map { "com.apple.keyboard.modifiermapping." + $0 } ?? ""
            let saved = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? [[String:UInt64]] ?? []
            let current = value(property) as? [[String:UInt64]] ?? saved
            return NativeKeyboard(service: service, name: value("Product") as? String ?? "Keyboard", builtIn: (value("Built-In") as? NSNumber)?.boolValue == true, preferenceKey: key, mapping: current)
        }
    }
    static func set(_ swapped: Bool, on keyboard: NativeKeyboard) throws {
        guard !keyboard.preferenceKey.isEmpty else { throw AppError(message: "macOS did not provide a settings identity for \(keyboard.name). Use Keyboard Settings for this keyboard.") }
        let next = ModifierKeyMap.setting(swapped, in: keyboard.mapping)
        guard next != keyboard.mapping else { return }
        let key = keyboard.preferenceKey as CFString
        let previous = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        // Use macOS's modifier layer, not UserKeyMapping or a Perch event tap.
        guard IOHIDServiceClientSetProperty(keyboard.service, property as CFString, next as CFArray) else {
            throw AppError(message: "macOS could not apply the modifier swap to \(keyboard.name).")
        }
        CFPreferencesSetValue(key, next.isEmpty ? nil : next as CFArray, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            _ = IOHIDServiceClientSetProperty(keyboard.service, property as CFString, keyboard.mapping as CFArray)
            CFPreferencesSetValue(key, previous, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            throw AppError(message: "Could not save \(keyboard.name)’s modifier setting. The live change was rolled back.")
        }
        if let applied = IOHIDServiceClientCopyProperty(keyboard.service, property as CFString) as? [[String:UInt64]], ModifierKeyMap.swapped(applied) != swapped {
            throw AppError(message: "\(keyboard.name) has not confirmed the modifier swap. Review Keyboard Settings.")
        }
    }
    static func applyGroup(_ swapped: Bool, builtIn: Bool) -> [String] {
        var failures: [String] = []
        for keyboard in keyboards() where keyboard.builtIn == builtIn {
            do { try set(swapped, on: keyboard) } catch { failures.append(error.localizedDescription) }
        }
        return failures
    }
}
