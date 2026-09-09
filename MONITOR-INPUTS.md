# Monitor input switching (1.1)

**Product direction changed September 8, 2026:** standalone cycling is being
replaced by a [coordinated Perch KVM experience](KVM-PLAN.md). That replacement is
planned, not implemented. This document describes the existing implementation
and transport evidence for possible reuse. Keyboard testing remains in scope.

The Display section offers Cycle monitor input. Settings → Monitor inputs owns setup; the optional shortcut runs while the menu app is open. No destination-device signal is required. The control path is native and on demand, with bounded requests and no new monitor polling timer.

## Detection and compatibility

Perch reads connected monitor metadata, uses documented model/firmware profiles where available, and reads capability/current-input replies where supported. Standard DDC/CI input selection uses VCP 0x60. LG alternate commands and model-specific input codes are supported. Generic EDID names may describe several retail models; an identity is not sufficient evidence to guess a mapping.

The local LG 27UN850-W reported generic LG HDR 4K/GSM7706 metadata and firmware family 27UL850-RTK. The owner confirmed USB-C input code 209, not 210. Direct connections worked where an HDMI adapter path did not. This does not certify every input direction, adapter, or related model. Physical switching tests must be user initiated.

The embedded catalog has 93 monitor profiles. Operational LG mappings require evidence, and unsupported firmware identities are not promoted to working profiles. Model & inputs offers explicit presets and custom codes. Compatibility testing is available after the defined method fails; each click tests one candidate, with visual confirmation before adding it to the editor. Applying the validated list saves it.

Connected-port occupancy and the monitor's actual selected input are distinct from macOS display-online status. They remain unknown without reliable device evidence. Opening guided identification sends no command; it appears only when current-input detection fails. A remembered Mac-port association is not treated as current selection.

DDC routing uses vendored MIT-licensed m1ddc code inside a restricted native adapter. The adapter exposes only supported operations, validates packets and bounds deadlines. See [profile provenance](catalog/DEVICE-PROFILES.md), [hardware research](catalog/HARDWARE-COMPATIBILITY-RESEARCH.md), and [m1ddc](https://github.com/waydabber/m1ddc).

## Validation and release scope

Safe tests cover routing, request failure/retry, cycle order, unknown current input, packet corruption, capabilities, saved/unchecked inputs, restore/Undo, fallback visibility and one-window navigation. Test adapters send no physical switch commands. Hardware testing remains limited to available devices; broader certification and Homebrew/distribution belong to [1.2](V1.2-REVIEW.md).

## USB and NEC connections (1.1)

Open **Perch Settings → Monitor inputs → USB / NEC connection…** in the protocol selector. Associate the selected display with its USB control interface or explicit NEC IPv4/serial address, then check it before saving. No subnet scan runs. USB enumeration reads metadata only; the selected monitor is opened on demand. No keyboard interfaces are opened or seized.

- MSI: USB 1462:3fa4, firmware identity pair checked against 23 bundled input profiles on every operation. Only identity and input-source commands are exposed. Perch input numbers 1–4 translate to MSI wire values 0–3. Unknown firmware and the upstream read-only model are refused.
- USB MCCS: monitors such as supported Eizo models exposing usage page 0x80 and a scalar input-source feature (0x82/0x60). Ambiguous/shared feature reports are refused to avoid altering other settings. Input labels may require manual setup.
- NEC: TCP 7142 at an explicitly entered IPv4 address, or a selected /dev/cu. serial device at 9600 baud; monitor IDs 1–26. Reads model C217 and input 0060, changes only input 0060. Replies are bounded and checked for framing, checksum, address, opcode and status. The checked model is saved and rechecked before later operations.

The configured control route can still be used after switching away from this Mac's video input. It is not replaced silently with DDC if unavailable. No extra idle timer is added. Transport success still needs readback or user confirmation. Protocol fixture tests pass; these new transports have **not been physically validated on MSI, Eizo or NEC hardware here**.

Protocol references: https://github.com/couriersud/msigd (identity/input packet facts), https://github.com/NECDisplaySolutions/necpdsdk (NEC protocol), https://www.ddcutil.com/usb/ (USB MCCS). This is a restricted native implementation, not a bundled copy of those utilities.

## Immediate settings and current input

Checkboxes, ordering, shortcut choices and validated input lists save immediately. Done closes the page. Unchecking an input removes it from the cycle but retains its definition. Cycle input now is a separate explicit hardware action.

Restore detected replaces custom inputs with a reliable detected/profile list and clears cycle selections. Undo restore recovers the previous configuration. If no reliable replacement is returned, settings remain unchanged. Manual text edits are validated together with Use this input list.

Read current input uses the configured protocol. Only a known code is accepted. If readback fails, guided identification becomes available: the user explicitly tests known inputs and visually confirms which shows this Mac. Opening identification sends no command. The confirmed Mac-port association is saved separately from current state; it is never treated as proof that the monitor remains on that input. macOS online status alone cannot establish the selected source.

When neither current readback nor a session position is known, cycling stops with setup guidance. Last-command cycling remains an explicit fallback and cannot notice arbitrary switches elsewhere without reliable readback.

Current-input limitations are documented in primary project reports, including https://github.com/waydabber/m1ddc/issues/49 and https://github.com/tyvsmith/streamcontroller-lg-monitor-control . macOS connection metadata is not used to claim which monitor-side HDMI socket is currently selected.
