import Foundation

/// Shared explanations for the same controls in menus and Settings.
/// State updates add context; they do not replace the control's purpose.
enum ControlHelp {
    static let display = "Turn off connected displays now. Move the mouse or press a key to wake them. Keep awake can keep the Mac working while displays are off."
    static let monitor = "Switch the selected display or group to the next configured input. This may hide this Mac; the monitor’s own controls can bring it back."
    static let audio = "Silence the current sound output without changing its volume. Turn this off to restore sound."
    static let trackpad = "Reverse the trackpad’s vertical scroll direction from its macOS setting. Horizontal scrolling and the mouse wheel are unchanged."
    static let wheel = "Reverse the mouse wheel’s vertical scroll direction from its macOS setting. Horizontal scrolling and the trackpad are unchanged."
    static let builtInModifiers = "Exchange Control and Command on the built-in keyboard. External keyboards are unchanged."
    static let externalModifiers = "Exchange Control and Command on connected external keyboards. Remember this choice when they reconnect; the built-in keyboard is unchanged."
    static let builtInFn = "Use F1–F12 without holding Fn on the built-in keyboard; hold Fn for media controls. Turn this off to reverse that behavior. External keyboards are unchanged."
    static let externalFn = "Use F1–F12 without holding Fn on supported external keyboards; hold Fn for media controls. Turn this off to reverse that behavior. The built-in keyboard is unchanged."
    static let homeEnd = "Move to the start or end of the current line with Home/End on external keyboards. Built-in Fn+arrows and apps in your exceptions keep their normal behavior."
    static let pageKeys = "Move the text cursor by a page with Page Up/Down on external keyboards, instead of only scrolling the view. Built-in Fn+arrows and apps in your exceptions are unchanged."
    static let keyboardSetup = "Open keyboard settings to review access and learn or manage navigation keys. Completed layouts are saved automatically."
    static let awake = "Prevent idle sleep while allowing displays to turn off. Turning this off also ends lid protection and stops your active caffeinate sessions."
    static let idleLock = "Keep your Mac from locking or starting its screen saver while you are away from it. It stays unlocked until you turn this off. Closing the lid, locking it yourself and your organization’s own lock still work, and this does not keep the Mac awake: Keep awake does that."
    /// Sleep disabled in macOS by something other than Perch.
    static let lidOutside = "Sleep was turned off outside Perch, with no limit: on battery with the lid closed the Mac stays awake, even in a bag. Turn this on and Perch takes it over, with its 60-second battery limit."
    static let lid = "Keep working with the lid closed. On power it stays awake; on battery it sleeps 60 seconds after the lid closes. While on, Sleep in the Apple menu does nothing."
    static let login = "Open the Perch menu app when you sign in to macOS. Background controls have their own startup behavior."
    static let settings = "Open Perch settings to change features or review setup. Setup & status brings missing steps and repair options together."
    static let about = "Show Perch’s version and build information."
    static let quit = "Quit Perch and turn off its features. If anything is on, Perch lists what stops first. Your settings are kept."

    static func adding(_ detail: String?, to purpose: String) -> String {
        guard let detail else { return purpose }
        let context = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? purpose : purpose + "\n\n" + context
    }
}
