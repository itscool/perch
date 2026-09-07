# Keyboard navigation research (2026-09-06)

Home/End and Page Up/Down support is authorized for 1.1. Implementation must preserve the existing native modifier and Fn settings and the independent scroll controls.

## Findings

macOS distinguishes moving the viewport from moving the insertion point. Home/End normally scroll to document ends; Command-Left/Right moves to line edges. Page Up/Down normally scrolls the viewport; Option-Page Up/Down also moves the insertion point. Shift-Page Up/Down already extends the selection in AppKit. These are defaults, not a promise that every app implements the same editing behavior. [Apple keyboard shortcuts](https://support.apple.com/en-us/102650), [Pages navigation shortcuts](https://support.apple.com/guide/pages/tanc0ffef022/mac).

The installed macOS 26.6.2 AppKit `StandardKeyBinding.dict` was read without modification. Its bindings confirm plain Home/End → `scrollToBeginningOfDocument:` / `scrollToEndOfDocument:`, plain Page Up/Down → `scrollPageUp:` / `scrollPageDown:`, Option-Page Up/Down → `pageUp:` / `pageDown:`, and Shift-Page Up/Down → selection variants.

The built-in keyboard emits these same navigation keys through Fn plus the four arrows. A CGEvent filter cannot reliably distinguish a dedicated external Home key from the built-in equivalent. Karabiner documents this limitation and uses device-level capture plus a virtual HID driver for reliable device-specific rules. Its Secure Event Input limitation also matters: an event-tap remapper should leave secure input alone. [Karabiner developer notes](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md), [device conditions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/device/), [architecture](https://karabiner-elements.pqrs.org/docs/help/advanced-topics/security/).

Apple's `DefaultKeyBinding.dict` offers a native, persistent approach without a Perch event callback, but applies to participating text systems across keyboards, requires app relaunch, and can be bypassed by custom text implementations. It cannot implement a reliable external-only switch. Apple's native HID usage remapping maps one key to another, not a key to a modifier chord with app exceptions. [Cocoa key bindings](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html), [TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html).

Prior art includes Karabiner's device/app conditions and Albatross's separation of native single-key maps from CGEvent chord/app maps. LinearMouse's maintainer documents private HID lookup and recent-device observation for pointing events; that does not establish reliable physical-keyboard identification for navigation keys. [Karabiner app conditions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/frontmost-application/), [Albatross](https://github.com/ysugimoto/Albatross), [LinearMouse discussion](https://github.com/linearmouse/linearmouse/discussions/200).

App exceptions are necessary. iTerm2 explicitly switches these keys between viewport scrolling and reporting to interactive programs. Zed already assigns Home/End to editing movements. Browsers need particular care because Command-Left/Right can become history navigation outside an editor; a universal remap must not claim to understand focus inside every web page. [iTerm2 settings](https://iterm2.com/documentation-preferences-profiles-keys.html), [Zed's macOS keymap](https://github.com/zed-industries/zed/blob/main/assets/keymaps/default-macos.json), [browser-specific prior art](https://github.com/vlasky/home-end-fix-for-macos-chrome).

## Implementation checks

- Optional, separately configurable Home/End and Page Up/Down modes; defaults off.
- External-only: the user requires built-in Fn+arrows to remain unchanged. Do not wire the candidate CGEvent transform globally.
- Preserve Shift selection, key repeats, matched key-up behavior, and unrelated modifier shortcuts.
- Respect configured app exceptions, secure input, and disabled/missing permission states.
- No per-keystroke process scan, file access, preference lookup, or app metadata lookup; no keyboard event subscription while both modes are off.
- Safe tests operate on unposted events and app-owned text views, without changing physical keyboard settings or sending keys to other apps.
- Validate permissions/signing and the background helper after installation; disclose any remaining physical-key checks.

## Build 8: read-only feasibility test

Settings → Keyboard settings → Test external navigation keys opens a page in the existing Settings window. Nothing begins until the user chooses a keyboard and presses Start. The test requires Input Monitoring for the signed Perch app, not the development terminal or Codex.

The adapter enumerates physical HID keyboard metadata, excludes built-in/virtual/unknown transports, and opens only the selected external device nonexclusively. `IOHIDDeviceSetInputValueMatchingMultiple` limits delivered values to keyboard-page Home, End, Page Up, and Page Down. The callback checks these usages again before reading a value. No full input-report callback, ordinary text storage, file logging, exclusive device grab, event posting, or keyboard-setting write is added.

The test stores only four bounded press/release states. It stops on all four completed keys, 30 seconds, cancellation, focus loss, disconnect, permission loss, Back, or window closure. Its timer exists only during the test. The normal menu/input helper/collector execution paths do not construct or run this diagnostic.

Mock tests cover device isolation, ignored typing, paired press/release, repeated/invalid values, late callbacks across restart, timeout and all cleanup paths. App-owned UI tests cover the existing window stack, focus loss, results and light/dark rendering. Candidate editing transforms are tested using unposted events only. These tests do **not** prove physical HID delivery, native suppression, key repeat, secure-input behavior or crash recovery of an eventual remapper.

Next hardware check: the user runs the test on MX Keys and verifies all four green rows. If direct delivery works, the proposed subsequent experiment is a short, explicitly initiated per-device mapping test. Apple's keyboard filter source drops an invalid mapped usage, but it is not yet established that raw navigation callbacks remain available after suppression on this keyboard. Production remapping must not be enabled until repeat, key-up, app exceptions, secure input, disconnect and crash recovery are proven. No suppression code is installed in build 8.
