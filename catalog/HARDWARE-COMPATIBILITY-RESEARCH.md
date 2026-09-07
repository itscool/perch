# Hardware compatibility research for distribution

Researched 2026-09-07 against Perch commit 23f4b85 (installed build 15). This is a research and implementation backlog, not a compatibility certification or authorization to publish. No hardware was switched, firmware updated, keyboard input captured, or third-party utility installed for this research.

## Assessment

Eight keyboard profiles and 21 monitor entries are a starter catalog. All eight keyboard entries are Logitech. The monitor catalog covers ASUS, BenQ, Dell and LG, but several Dell entries describe connection/HDR identities of the same retail model. Entry count is not model count or evidence of market coverage.

Perch has three different keyboard capabilities: native modifier changes, firmware/native Fn mode, and external navigation remapping. A navigation layout profile does not prove Fn control works. A known descriptor does not prove the private CoreGraphics sender metadata used by navigation is available. Monitor identity, command transport, input enumeration, and successful input switching likewise need separate support claims.

## Monitor research matrix

| Family or connection | Primary evidence | Consequence for Perch |
|---|---|---|
| Generic MCCS/DDC monitors | [ddcutil FAQ](https://www.ddcutil.com/faq/) | Capability replies are useful but can be incomplete or inaccurate. Prefer actual readback and user-confirmed behavior over a blanket capability promise. |
| USB-C destinations | [ddcutil FAQ](https://www.ddcutil.com/faq/) | No MCCS version defines a universal USB-C value for feature 0x60. Perch currently calls 27 “USB-C” in its generic map; treat this as a suggestion, not a standardized mapping. Apply exact model evidence or learn the port label. |
| LG alternate input control | [ddcutil LG model reports](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors) | Alternate source address 0x50 and feature 0xF4 are only one family of behavior. 27UN850-WY uses USB-C 0xD1; 32UD99-W uses USB-C 0xC0 and DisplayPort 0xE0; 29UM69G uses USB-C 0xE0 and DisplayPort 0xC0. Retain exact-model presets; do not infer them from shared EDID 7706. Some reports are incomplete or conflicting. |
| HDMI, DisplayPort and USB-C routes on Apple Silicon | [m1ddc](https://github.com/waydabber/m1ddc/blob/main/README.md) | Current upstream supports USB-C/DP Alt Mode and supported built-in HDMI ports. Test exact Mac/OS/route combinations rather than reuse old blanket “HDMI unsupported” statements. Perch vendors its routing code, not the full upstream behavior. |
| Docks, adapters and cables | [Lunar FAQ](https://lunar.fyi/faq), [MonitorControl troubleshooting](https://github.com/MonitorControl/MonitorControl/wiki/Monitor-Troubleshooting) | Video/EDID can work without usable DDC control. Diagnose a route, not an entire monitor model. Missing acknowledgment does not establish which component failed. Compare a direct connection with the same monitor/input where possible. |
| LG OnScreen Control | [LG troubleshooting](https://www.lg.com/us/support/help-library/lg-monitor-monitor-not-detected-when-using-on-screen-control--20153187900083), [LG OSC guide](https://www.lg.com/us/support/help-library/lg-monitor-how-to-install-onscreen-control-and-use-its-features--20155115803113) | LG also documents DDC/CI failures with connection hardware; firmware functions can require a USB data link. Public docs do not provide a universal retail-model query. OSC binary behavior has not been inspected or tested here. |
| USB monitor-control devices | [ddcutil USB support](https://www.ddcutil.com/usb/) | MCCS over USB HID is a separate transport, and some monitors use proprietary USB instead. Perch's current IOAV/I2C path does not establish support for these. USB-C video Alt Mode is not the same as USB HID monitor control. |
| Software KVM and multi-monitor setups | [display-switch](https://github.com/haimgel/display-switch) | Useful precedent for explicit per-monitor input assignments and connection-triggered workflows. Do not confuse input selection with USB peripheral switching; do not add KVM/power/PBP commands just because upstream exposes them. |

The LG wiki lists support reports for further families such as 27BN88Q-B, 27UK500-B, 27UL550-W, 27US500-W, 29WN600, 32GP750-B, 32GP850-B, 34WN750-B, 38BR85QC and 45GX950A-B. These are candidates for individually sourced manual presets, not evidence of their exact EDID IDs or local verification. Prioritize different protocol/code behavior over adding more aliases for the same map. Never expand partial reports into undocumented ports.

Our 27UN850-W result remains unresolved: the user corrected the initial success report to a brief response to HDMI 2; USB-C still did not work. Neither full direct-connection success nor adapter failure has been established. Do not promote this to a verified profile.

## Keyboard research matrix

| Family | Primary evidence | Consequence for Perch |
|---|---|---|
| Logitech direct USB/Bluetooth and receivers | [Solaar capabilities](https://github.com/pwr-Solaar/Solaar/blob/master/docs/capabilities.md), [device descriptors](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/descriptors.py) | Receiver product IDs and paired-device identities are different. Devices/firmware can expose different HID++ features despite similar names. Audit Unifying, Bolt and Lightspeed separately from direct Bluetooth; do not bulk-import receiver IDs as keyboards. |
| Logitech Fn inversion | [Solaar setting implementations](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py) | Perch already probes HID++ feature IDs 0x40A0/0x40A2/0x40A3 and host information. Audit feature/version, host and persistence behavior rather than equate the eight layout profiles with the entire supported Fn set. Probe only relevant keyboard devices. |
| Per-device remapping and receiver aggregation | [Karabiner device conditions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/device/) | Match concrete device properties and distinguish identical devices where possible. Karabiner's device-layer facilities do not prove our event-tap sender field is portable. Require observed source identification for external-only navigation. |
| QMK/VIA-class keyboards | [QMK keymap documentation](https://docs.qmk.fm/keymap), [layers](https://docs.qmk.fm/feature_layers) | Fn can be an internal firmware layer action, not a modifier delivered to macOS. A profile cannot make a host Fn preference control that firmware. Modified layouts also invalidate assumptions drawn from a stock model name. Do not flash or rewrite keymaps as ordinary setup. |
| Keychron stock Mac/Windows layouts | [Keychron QMK shortcuts](https://www.keychron.com/blogs/news/keychron-qmk-keyboard-shortcuts-table-100-96-80-75) | OS modes and layout variants deserve a dedicated setup path. Collect exact model/revision/transport/mode before creating presets. Vendor family membership is insufficient to assert native Fn control. |
| Apple keyboards and generic USB HID | Perch native Fn/modifier code; [Karabiner function-key guide](https://karabiner-elements.pqrs.org/docs/help/how-to/function-keys/) | High-priority validation targets beyond Logitech. Distinguish native Apple controls from software remapping. Recognizing standard Home/End usages can reduce manual work, but must not claim the source keyboard or stock physical layout without evidence. |

Solaar specifically notes that querying settings can require many interactions and can temporarily slow a device; it caches information. This supports Perch's event-driven discovery and bounded transactions, not frequent global probes. Copying Solaar's device count would not copy its receiver support or its protocol implementations.

## Prioritized implementation work

### Before making broad hardware-support claims

1. **Fix generic port naming.** Unknown or unprofiled VCP values must display “Input N” or an explicitly suggested name, not “detected USB-C.” Current static 27-to-USB-C and alternate port labels need this distinction in all UI paths.
2. **Make discovery non-destructive.** Explicit Detect currently can replace a draft with suggestions and clear selections. Preserve saved working mappings and confirmations; show proposed differences before replacing them. A generic scan must not overwrite a known USB-C code.
3. **Publish support per feature and route.** Separate identity, readable state, firmware Fn control, modifier swap, navigation source attribution, destination input and connection method. Never use one green “supported” label for all.
4. **Complete guided compatibility fallback.** Prefer reported capabilities, exact evidenced presets and previously confirmed settings. When these fail, offer one user-started input candidate at a time with cancel, clear recovery instructions and per-input confirmation. This full fallback wizard is not implemented in build 15. Do not perform automated sweeps or pretend disconnection proves the intended destination worked.
5. **Audit sender attribution.** Build 15 uses private CGEvent field 87. Descriptor/profile success is not runtime source success. Test built-in Fn+arrows, external keys and simultaneous keyboards; unsupported sources must retain native behavior with an actionable status.
6. **Improve evidence storage.** A registry connection path is not a cable fingerprint. Current historical confirmations are coarse: explicitly label them historical, and expire/invalidate as appropriate. Store model, protocol, direction and test method without asserting a new physical connection was verified.

### Coverage expansion after the above

- Validate Apple built-in/Magic keyboards and a generic wired full-size HID keyboard; ANSI/ISO/JIS, compact Fn+arrow variants and custom firmware layouts need separate coverage.
- Audit Logitech receiver addressing first; then add evidenced MX Keys Mini, K-series or other models from upstream descriptors only when transport and relevant usages/features are known. No IDs should be guessed from marketing names.
- Add Keychron/QMK setup guidance and representative exact descriptors; firmware Fn remains separate from native macOS Fn controls.
- Expand LG manual presets from complete model reports, then prioritize additional non-LG model families with demonstrably different input behavior. Existing ASUS/BenQ/Dell entries are not proof that all models from those brands work.
- Evaluate USB HID monitor control as a distinct future backend; do not add speculative writes to the restricted input adapter.

## Evidence and distribution gates

Each preset should carry a source permalink/revision, capture/review date, exact identity scope, transport, firmware or OS qualifications when known, per-feature confidence, and negative/partial results. A captured hardware descriptor and a real switch confirmation are different evidence types.

Minimum fixture matrix: missing/malformed capabilities; unsupported or mismatched readback; write accepted without response; delayed or reverted switch; unplug/reconnect; duplicate model IDs; multiple monitors; changed adapter; saved-map preservation; profile override/cancel; denied input permission; receiver exposing multiple devices; absent/private sender metadata. Hardware matrix should include one generic DDC monitor, one LG alternate model, one multi-input USB-C monitor, direct HDMI/DP/USB-C routes and an adapter route. Record what actually passed, not a universal certification.

For distribution, verify bundled code/data licenses and notices separately from factual compatibility research. Existing DDCControl-derived data already includes its license. Reading an upstream list is not authorization to copy all code or datasets without reviewing their terms. Homebrew publication, signing/distribution architecture and the whole-app 1.2 review remain separate work.

No app code or live device settings changed in this research pass. Follow-up implementation and physical validation remain necessary.
