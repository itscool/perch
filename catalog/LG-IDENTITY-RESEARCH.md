# LG OnScreen Control identity investigation

2026-09-07. Static inspection only. No LG software installed or executed, no monitor queries sent, no permissions changed, no Perch runtime changes.

## Artifact and provenance

LG's Korean support page links the macOS OnScreen Control 7.20 package:
https://www.lge.co.kr/support/solutions-20153030707801

Download linked by that page:
https://gscs-b2c.lge.com/downloadFile?fileId=o5c4WDQ8adFwdpgbJzDXFw

ZIP SHA-256: `d2891a3b1b5413d1d55ecb9da6182f374e6d2fb2151d3c56a1efcb7d341e68c0`.
Package: `OSC_V7.20_signed.pkg`. pkgutil reports LG Electronics Developer ID Installer (`5SKT5H4CPQ`) and trusted notarization. Extracted with pkgutil --expand-full, not installer. Research artifacts remain in `/private/tmp/perch-osc-research`; proprietary binaries are not included in this repository.

## Findings

1. The bundled SDK's `SMonitorDDCCISDKInternals::GetModelName` calls `CEDID::GetModelNumber`. Static ARM64 inspection shows the latter checking the 0xFC monitor-name descriptors. This ordinary display-name path still depends on EDID and does not solve a generic LG HDR 4K name.
2. The main app has a distinct proprietary ID path. ARM64 Objective-C metadata identifies `getMonitorId` at 0x10000f838 and `getMonitorExtendId` at 0x10000f984. The methods construct Get VCP requests for 0xEF and 0xA1, respectively, with DDC source 0x51, then read and validate replies. These are identification reads in the inspected code, not input switching or firmware-write commands. Transport initialization and all model-specific preconditions have not been fully traced.
3. The app contains the model string `27UN850-L2L` and its firmware service URL. The `isFWUpdateSupported::` method (0x10005ed20) maps ID fields to model strings. A branch returning that string at 0x10005f2cc is reached through the extended-ID path: first argument bit 15 selects that path, bit 14 is required, and the second argument equals 0x1D. This is a static observation of a firmware-model lookup, not proof of the values returned by this user's monitor or a retail-suffix mapping. Do not infer all 27UN850 variants or input codes from it.
4. This disproves a blanket assertion that LG only uses the generic EDID identity. It establishes a concrete additional investigation path. It does not yet establish working automatic identification in Perch.

Independent firmware research also mentions model-name opcode 0xAF, extended identity 0xA1, and a vendor-side model query. That research concerns other LG hardware; these are leads, not commands to sweep or assume portable:
https://gist.github.com/shinyquagsire23/7ddd17d1569acb21920683866570cb35

A separate USB HID transport has public precedent on a particular LG device:
https://gist.github.com/shinyquagsire23/f6b2adef253c6c3ab557a4852bf3abad

## Next implementation boundary

Trace the ordinary (non-updater) ID reader and its transport prerequisites, then implement only bounded, validated identity reads in Perch's restricted display adapter. Keep the raw identity fields separate from EDID IDs and retail names. A known response may identify a firmware family; it must not silently overwrite a user-confirmed input mapping. Unknown, unsupported, ambiguous or malformed responses retain manual model selection. No proprietary library needs to be bundled or run merely to reproduce a understood read protocol.

A live read test through Perch is still needed before claiming identification works on 27UN850-W. No live probe was performed during this investigation.

## Implemented identity lookup (2026-09-07)

The signed Perch display helper performed one authorized read-only inspection on the local 27UN850-W. VCP EF returned 0x5124, decoded by OSC's lookup as 27UL850-RTK. The high-bit extended query was unnecessary. This demonstrates that the firmware family is not necessarily the retail model. The local owner independently confirmed USB-C 209. That evidence now links this identity to the operational 27UN850-W input profile; it is not a claim that OSC itself supplied code 209.

The bundled catalog contains 162 extracted family identifiers. Only families with a corresponding evidenced input profile receive an operational mapping. Remaining identifiers improve the displayed identity but do not invent port codes. Existing saved mappings win. EF/A1 reads occur only during explicit setup inspection, never in idle monitoring.

OSC also exposes firmware/update, calibration and USB-related internals. Those are not evidence of a universal connected-input query and have not been enabled as control commands.
