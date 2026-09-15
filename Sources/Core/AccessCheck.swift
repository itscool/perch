import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

/// The permission probes Perch relies on, each read the one way macOS answers
/// it. Reading never prompts; `promptForAccessibility` is the only call here
/// that shows a system dialog.
enum AccessCheck {
    /// Accessibility (AXIsProcessTrusted): event taps and window control.
    static var accessibility: Bool { AXIsProcessTrusted() }
    /// Accessibility that can also post events. Sharing input needs both.
    static var accessibilityWithPosting: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }
    /// Input Monitoring as CoreGraphics event taps see it.
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    /// Input Monitoring as IOKit HID clients see it (external keyboard control).
    static var hidListening: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    /// Everything keyboard and mouse sharing needs from this process.
    static var sharing: Bool { accessibilityWithPosting && inputMonitoring }

    /// Asks macOS to show its Accessibility prompt for this process.
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// System Settings panes Perch sends people to: one list of deep links.
enum SystemSettingsPane: String, CaseIterable {
    case accessibility = "com.apple.preference.security?Privacy_Accessibility"
    case inputMonitoring = "com.apple.preference.security?Privacy_ListenEvent"
    case fullDiskAccess = "com.apple.preference.security?Privacy_AllFiles"
    case keyboard = "com.apple.Keyboard-Settings.extension"

    var url: URL { URL(string: "x-apple.systempreferences:" + rawValue)! }
}
