# Device profile provenance

Keyboard profiles require exact VID/PID, name and transport matching, plus required descriptor usages. The saved user layout overrides the bundled layout. Bluetooth receiver IDs are not treated as keyboard model IDs.

Eight keyboard entries: the user-tested Bluetooth MX Keys layout, and documented-layout entries for MX Keys S, Craft, G915 TKL, G213, G512, G815 and K845. Documentary entries are labeled as such, not as tested hardware. Identity facts are cited individually to Solaar or the original input-switcher project; MX Keys S layout is also linked to Logitech. These entries do not guarantee private CoreGraphics keyboard sender metadata on every macOS/driver combination.

The 15 monitor entries use exact packed EDID manufacturer/product identities. Fourteen contain community-documented input enumerations for ASUS, BenQ, Dell and LG; the shared LG GSM7706 entry contains explicitly labeled suggestions for alternate LG input control. Runtime capability replies take precedence. Profiles never enable a shortcut or switch a monitor automatically. Some model IDs span multiple hardware variants, and no destination-device presence is inferred.

The monitor input data was extracted from the DDCControl database (per-entry source revision URLs are in the JSON). Its GPL-2.0-or-later license is included as `ddccontrol-COPYING.txt`, also copied into the app. The editable JSON is the source form of the data; no DDCControl executable/code is linked into Perch.

Review these catalogs when adding hardware or investigating incompatibility. Keep evidence and confidence with each entry. For 1.2, review versioned external catalog updates, distribution and license notices; do not silently promote a documentary entry to hardware-tested.

## Monitor control confirmation and retail presets

Six additional manual retail-model presets cover LG 27UN850-W/WY, 27UP850-W, 27UP85NP-W, 32UD99-W, 29UM69G, and 40WP95C-W. These retain different USB-C/DisplayPort codes from the ddcutil model-specific reports; they are never inferred from the shared GSM7706 identity. Entries with automatic=false and no EDID model deliberately carry no product match. Exact names or explicit preset selection are required. Sources: https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors .

The 27UN850-W local result is incomplete: a brief switch to HDMI 2 was observed, but USB-C switching remains unconfirmed. Neither all inputs nor the adapter failure is marked verified.

Transport write success is not a successful switch. Perch reads back the requested input after an explicit cycle; missing replies lead to per-input user confirmation and adapter/dock troubleshooting. Previous confirmations are scoped to display identity, registry connection path, protocol and cycle codes, and labeled historical rather than proof of current state. A connection path is not a physical cable fingerprint. No idle polling or automatic test switches are introduced.

Update 2026-09-07: the owner subsequently confirmed LG 27UN850-W USB-C switching works using 209, not 210. This supersedes the earlier unresolved USB-C result above. Exact-model mapping is supported by this local report; other models, all directions, and adapter paths are not thereby certified.
