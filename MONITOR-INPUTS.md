# Monitor input hotkey: feasibility and next steps

Requested 2026-09-06 as the last feature before the formal 1.2 review. Desired behavior: a configurable hotkey switches a connected external monitor to a chosen input, with a connection guard and consistent setup/unsupported/error states.

## Feasibility

Lunar and BetterDisplay demonstrate input-source switching on macOS through DDC/CI. Common input selection uses VCP 0x60, but monitor firmware, the Mac's display interface, cables/adapters/docks, and vendor-specific commands affect support. Apple Silicon support must be checked on the actual machine/connection rather than inferred from an old compatibility table. [Lunar](https://lunar.fyi/), [Lunar FAQ](https://lunar.fyi/faq), [BetterDisplay input-source discussion](https://github.com/waydabber/BetterDisplay/discussions/1266), [BetterDisplay integration](https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI).

Detecting that the monitor is attached to this Mac is different from proving a device is connected/active on another input. Reading the currently selected input does not establish destination signal presence. Do not claim that guarantee unless this monitor exposes reliable information for it. Some monitors stop accepting DDC after switching away, which may affect switching back; confirm actual behavior during a user-initiated test.

Confirmed behavior: require the monitor to be connected to this Mac; destination-device presence is optional information, never a prerequisite. Automatically detect the monitor and reported inputs first, allow manual correction second, and let the user choose the subset and order cycled by each hotkey press. Query the current input at activation when supported; otherwise expose the unavailable reading and require a deliberate fallback rather than silently guessing. Monitor model/connection details are still pending. No display input has been switched or DDC command sent during this research.

`m1ddc` is a small MIT-licensed native reference that supports USB-C/DisplayPort Alt Mode and supported built-in HDMI ports on Apple Silicon. Its current CLI explicitly includes standard input selection and alternate LG commands, plus stable monitor-selection identifiers. This is a promising integration reference to inspect after the monitor details are known, not an installed dependency. [m1ddc source and usage](https://github.com/waydabber/m1ddc).

## Implementation requirements

- Prefer a small native, on-demand DDC transaction; no new polling loop, and no monitor I/O on the keyboard callback or UI thread.
- Identify the selected physical monitor stably, revalidate connection at activation, and avoid writes when unsupported or absent. Keep the shortcut off until configured and check conflicts with other Perch shortcuts.
- Show recognized/supported, needs setup, unavailable and failed states consistently. Keep setup in the shared Settings window and provide a visible manual action alongside the shortcut.
- Bound timeouts and retries; distinguish a confirmed switch from a command merely sent. Treat unknown source-presence data as unknown.
- Cycle only the user-selected input list in its configured order, wrapping at the end. When the actual current input is outside the list, select the first configured input. Do not skip an input merely because destination signal presence cannot be read. Failed writes must not advance a stored cycle position as if confirmed.
- Review source licenses before incorporating existing implementations. Test selection/routing/timeouts/disconnection with mocks; real switching must be an explicit user action because it can remove the current display.

Homebrew/distribution work belongs to the 1.2 review scope, recorded separately in `V1.2-REVIEW.md`.


## Build 10 implementation and verification

Connected display detected: LG HDR 4K, EDID manufacturer GSM (0x1e6d), model 0x7706. The DDCControl database documents that this ID is shared across LG variants. Metadata discovery and two bounded read-only queries were performed; no input-selection command was sent. Standard current input returned zero (treated as unavailable), capabilities were unavailable, and LG alternate current input was unavailable. The UI offers an explicitly suggested LG alternate profile rather than claiming to have detected the physical ports. Actual switching remains a user action/test.

The main menu now has Cycle monitor input and Monitor input settings. The shared Settings window provides a display picker, automatic detection, checkboxes and ordering arrows, a manual input editor, explicit unknown-state fallback, and a configurable shortcut that defaults off. A fresh query and UUID selection precede each switch. No destination device is required. A failed write leaves the cycle position unchanged; transport acceptance is labeled only as a command sent. The shortcut is active while the menu app runs.

IOAV routing is vendored from MIT-licensed m1ddc; a separate restricted adapter exposes no arbitrary monitor commands. Each request runs on a serial worker in a short-lived process, with an 8-second child deadline and a 9-second parent wait. No new timer polls the monitor. Hotplug/wake refreshes only metadata. Packets are bounded and validate header, command, feature, status, length and checksum; zero current input is unknown. Read failures do not implicitly authorize a switch.

Safe tests exercise the production controller with an injected fake adapter, including failure then retry and order advancement only after accepted commands; pure tests cover protocol frames, truncation/corruption, capability parsing, manual codes and wraparound. App-owned light/dark renders and Settings Back/lifetime checks are included. No physical switch has been tested. Catalog source/confidence details and licensing are in catalog/DEVICE-PROFILES.md. Distribution and formal review remain 1.2 work.
