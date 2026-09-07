# Device profile provenance

Keyboard profiles require exact VID/PID, name and transport matching, plus required descriptor usages. The saved user layout overrides the bundled layout. Bluetooth receiver IDs are not treated as keyboard model IDs.

Eight keyboard entries: the user-tested Bluetooth MX Keys layout, and documented-layout entries for MX Keys S, Craft, G915 TKL, G213, G512, G815 and K845. Documentary entries are labeled as such, not as tested hardware. Identity facts are cited individually to Solaar or the original input-switcher project; MX Keys S layout is also linked to Logitech. These entries do not guarantee private CoreGraphics keyboard sender metadata on every macOS/driver combination.

The 15 monitor entries use exact packed EDID manufacturer/product identities. Fourteen contain community-documented input enumerations for ASUS, BenQ, Dell and LG; the shared LG GSM7706 entry contains explicitly labeled suggestions for alternate LG input control. Runtime capability replies take precedence. Profiles never enable a shortcut or switch a monitor automatically. Some model IDs span multiple hardware variants, and no destination-device presence is inferred.

The monitor input data was extracted from the DDCControl database (per-entry source revision URLs are in the JSON). Its GPL-2.0-or-later license is included as `ddccontrol-COPYING.txt`, also copied into the app. The editable JSON is the source form of the data; no DDCControl executable/code is linked into Perch.

Review these catalogs when adding hardware or investigating incompatibility. Keep evidence and confidence with each entry. For 1.2, review versioned external catalog updates, distribution and license notices; do not silently promote a documentary entry to hardware-tested.
