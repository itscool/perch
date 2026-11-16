import Foundation

/// Shared explanations for the same controls in menus and Settings.
/// State updates add context; they do not replace the control's purpose.
enum ControlHelp {
    static let display = "Turn off connected displays now. Move the mouse or press a key to wake them."
    static let audio = "Silence the current sound output without changing its volume."
    static let trackpad = "Reverse the trackpad’s vertical scroll direction from its macOS setting. Horizontal scrolling and the mouse wheel are unchanged."
    static let wheel = "Reverse the mouse wheel’s vertical scroll direction from its macOS setting. Horizontal scrolling and the trackpad are unchanged."
    static let builtInModifiers = "Exchange Control and Command on the built-in keyboard. External keyboards are unchanged."
    static let externalModifiers = "Exchange Control and Command on external keyboards, also after they reconnect. The built-in keyboard is unchanged."
    static let builtInFn = "Use F1–F12 without holding Fn on the built-in keyboard; hold Fn for media controls. External keyboards are unchanged."
    static let externalFn = "Use F1–F12 without holding Fn on supported external keyboards; hold Fn for media controls. The built-in keyboard is unchanged."
    static let homeEnd = "Move to the start or end of the current line with Home/End on external keyboards. Built-in Fn+arrows and apps in your exceptions keep their normal behavior."
    static let pageKeys = "Move the text cursor by a page with Page Up/Down on external keyboards, instead of only scrolling the view. Built-in Fn+arrows and apps in your exceptions are unchanged."
    static let keyboardSetup = "Open keyboard settings to review access and learn or manage navigation keys."
    static let awake = "Keep the Mac from sleeping when idle; the displays can still turn off. Turning this off also stops keep-awake with the lid closed, and any caffeinate command keeping the Mac awake."
    static let idleLock = "Keep the Mac from locking or starting the screen saver while you’re away, until you turn this off. Its screens stay on. Closing the lid and locking it yourself still work. It doesn’t keep the Mac awake; Keep awake does."
    /// Sleep disabled in macOS by something other than Perch.
    static let lidOutside = "Sleep was turned off outside Perch, with no limit: on battery with the lid closed the Mac stays awake, even in a bag. Turn this on and Perch takes it over, with its 60-second battery limit."
    static let lid = "Keep working with the lid closed. On power it stays awake; on battery it sleeps 60 seconds after the lid closes. While on, Sleep in the Apple menu does nothing."
    static let login = "Open Perch when you sign in."
    static let settings = "Open Perch settings. Setup lists anything that needs doing."
    static let about = "Show Perch’s version and build information."
    static let quit = "Quit Perch and turn off its features. If anything is on, Perch lists what stops first. Your settings are kept."

    static func adding(_ detail: String?, to purpose: String) -> String {
        guard let detail else { return purpose }
        let context = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? purpose : purpose + "\n\n" + context
    }
}
