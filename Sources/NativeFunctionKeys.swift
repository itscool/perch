import Foundation
import IOKit.hidsystem

/// The global macOS preference remains the built-in keyboard's setting. External
/// keyboards keep their own live native mode plus (for Logitech) firmware Fn Lock.
/// Perch remembers only explicit external choices; startup without one is read-only.
enum NativeFunctionKeys {
    static let externalIntentKey = "functionKeys.external"
    static func externalIntent(in defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: externalIntentKey) as? Bool
    }
    static func mode(_ keyboard: NativeKeyboard) -> Bool? {
        withExtendedLifetime(keyboard.connection) {
            (IOHIDServiceClientCopyProperty(keyboard.service, kIOHIDFKeyModeKey as CFString) as? NSNumber)?.boolValue
        }
    }
    static func set(_ standard: Bool, on keyboard: NativeKeyboard) throws {
        try withExtendedLifetime(keyboard.connection) {
            guard let previous = mode(keyboard) else { throw AppError(message: "Could not read \(keyboard.name)’s native Fn mode. No change was made.") }
            guard previous != standard else { return }
            guard IOHIDServiceClientSetProperty(keyboard.service, kIOHIDFKeyModeKey as CFString, NSNumber(value: standard ? 1 : 0)), mode(keyboard) == standard else {
                _ = IOHIDServiceClientSetProperty(keyboard.service, kIOHIDFKeyModeKey as CFString, NSNumber(value: previous ? 1 : 0))
                throw AppError(message: "\(keyboard.name) did not confirm the native Fn setting. Review Keyboard settings.")
            }
        }
    }
    /// Injected operations let safe tests exercise the actual preservation and
    /// rollback workflow without ever touching a physical keyboard or preferences.
    static func changeBuiltIn(_ desired: Bool, readGlobal: () throws -> Bool,
                              writeGlobal: (Bool) throws -> Void,
                              restoreExternal: () throws -> Void) throws {
        let previous = try readGlobal()
        guard desired != previous else { return }
        do {
            try writeGlobal(desired)
            try restoreExternal()
        } catch {
            let original = error
            do { try writeGlobal(previous); try restoreExternal() }
            catch { throw AppError(message: "Could not preserve keyboard Fn settings or fully restore them. Review both keyboard groups in Perch. \(error.localizedDescription)") }
            throw AppError(message: "Fn settings were restored because the other keyboard group could not be preserved. \(original.localizedDescription)")
        }
    }
    static func setBuiltIn(_ desired: Bool) throws {
        let external = NativeModifierKeys.keyboards().filter { !$0.builtIn }
        let saved = try external.map { keyboard -> (NativeKeyboard, Bool) in
            guard let mode = mode(keyboard) else { throw AppError(message: "Could not preserve \(keyboard.name)’s Fn mode. Reconnect it and retry.") }
            return (keyboard, mode)
        }
        try changeBuiltIn(desired, readGlobal: FunctionKeys.standard, writeGlobal: FunctionKeys.setStandard) {
            var failures: [String] = []
            for (keyboard, mode) in saved {
                do { try set(mode, on: keyboard) } catch { failures.append(error.localizedDescription) }
            }
            if !failures.isEmpty { throw AppError(message: failures.joined(separator: "\n")) }
        }
    }
    static func externalAppleModes(keyboards: [NativeKeyboard], desired: Bool?) -> [KeyboardModeResult] {
        keyboards.filter { !$0.builtIn && $0.vendor == 0x05AC }.map { keyboard in
            do {
                if let desired { try set(desired, on: keyboard) }
                guard let mode = mode(keyboard) else { throw AppError(message: "Native Fn mode is unavailable.") }
                return KeyboardModeResult(name: keyboard.name, detail: mode ? "✓ F1–F12 directly · native setting confirmed" : "✓ Hold Fn for F1–F12 · native setting confirmed", verified: true, standard: mode)
            } catch { return .init(name: keyboard.name, detail: "⚠ " + error.localizedDescription, verified: false) }
        }
    }
}
