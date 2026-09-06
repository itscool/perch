# Keyboard controls (1.1)

The F1–F12 checkbox reads and changes the real macOS function-key setting. Perch also synchronizes supported Logitech keyboards' firmware Fn Lock with that setting at launch, connection, wake, and explicit changes/retry. It does not remap F-key events. Unsupported, sleeping, disconnected, or permission-denied devices remain amber with a named explanation under Settings → Keyboard settings. A checked macOS setting does not claim every external keyboard succeeded.

Logitech HID++ 2.0 Fn inversion features 0x40A0, 0x40A2, and 0x40A3 are supported. The multi-host variant uses the actual host reported by 0x1815; no guessing with host 0xff. Changes are read back. Bluetooth/direct USB devices and HID++ USB receiver slots are supported by the transport; receiver slots are checked for keyboard type before any Fn write. Physical validation is limited to hardware available locally; unsupported devices require their own Fn Lock or manufacturer utility.

macOS requires Input Monitoring for opening a Logitech HID device. Only **Perch** requests this, from its own keyboard setup page. The drag target is the signed Perch app, distinct from Perch Helper's Accessibility permission for scroll reversal. No root access, SIP changes, or permission grant to the development tool is needed.

Control/Command swapping now uses the native `HIDKeyboardModifierMappingPairs` property and the same global/current-host preferences as Keyboard Settings. Both left and right sides swap, independently for built-in and external groups. Other modifier mappings are preserved. No swap is enabled by default. Perch queries existing native settings, which may already differ from defaults. After the user selects a group setting, new devices in that group inherit it while Perch runs. macOS persists the device-specific choice independently of Perch. Unknown preference identities fail visibly instead of writing a guessed key. macOS can group identical models under the same preference identity.

Perch soft-links MachineSettings' read-only `createKeyForKeyboard` formatter to obtain exactly the same preference identity as Keyboard Settings, including older Apple `alt_handler_id` identities. Perch also soft-links IOKit’s `IOHIDEventSystemClientCreateWithType` to open a Passive (type 2) connection, as Keyboard Settings does. Apple documents this connection as allowing property reads/writes without event delivery or an entitlement. The previous Simple connection restricted modifier writes. Each keyboard retains its owning connection for the entire operation. Both soft-linked symbols are private compatibility dependencies and may change in a future macOS release; Perch never substitutes an admin/event-monitor client. The property and preference operations use IOHIDServiceClient and CFPreferences APIs. Modifier writes are read back before persisting; failed readback or persistence triggers rollback. Verified on the target macOS 26 system: built-in `0-0-0`, MX Keys `1133-45915-0`. No modifier keystrokes are intercepted by Perch 1.1's input helper.

Connection notifications and existing macOS-setting refreshes trigger coalesced, temporary work. The HID reply reader exists only during configuration and closes afterward. There is no new periodic keyboard scan or permanent HID input subscription. Hardware response waits run off both the menu thread and the input helper thread.

## Protocol and platform references

This is a small native Swift implementation, with no additional daemon or third-party runtime. Protocol facts were checked against these primary sources; no GPL source was incorporated:

- [Logitech HID++ implementations for macOS/USB/BLE](https://github.com/jlevere/hidpp) (MIT/Apache-2.0): framing, direct/receiver addressing, response matching, device type.
- [Solaar's Fn inversion support](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py): feature IDs, inversion polarity, active-host handling and the MX Keys S current-host firmware caveat.
- [Apple HIDEventSystemClient types](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/HID/Headers/HIDEventSystemClient.h): Passive versus Simple property access, entitlement and event-delivery boundaries.
- [Apple IOHIDKeyboardFilter](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDKeyboardFilter.mm): native modifier and function-key layers.
- The installed macOS SDK's IOHIDDevice, IOHIDServiceClient, IOHIDEventSystemClient and IOHIDLib headers document the public APIs and permission requirements.

Safe tests mock hardware requests, including all three features, host selection, unsupported devices, write/readback failures, reply identity and framing, and preserving unrelated modifier mappings. They do not toggle physical keyboard modes, grant access, or post global keys.

## Local validation

The signed 1.1 build received an MX Keys firmware readback confirming F1–F12 directly on 2026-09-05. Both native modifier groups remained unswapped. The safe release suites passed; post-install helper checks confirmed active process-event coverage, trusted/active scroll input, the unchanged signing requirement, unchanged safety configuration, and the existing root collector PID. Physical modifier delivery and other keyboard/receiver models still need user hardware testing.

Build 4 validated a same-state native property write and unchanged readback on both the built-in keyboard and MX Keys from the signed app. Both remained unswapped and no preferences were written during that diagnostic. This confirms the formerly failing write path; physical modifier delivery still requires a hardware check. The opt-in `--check-modifier-access` diagnostic performs only this same-state check and is excluded from startup and automated safe tests.
