# Device profile provenance

Keyboard profiles require exact VID/PID, name and transport matching, plus required descriptor usages. The saved user layout overrides the bundled layout. Bluetooth receiver IDs are not treated as keyboard model IDs.

The current catalog has 28 keyboard profiles, with per-entry evidence and confidence. Bundled layout knowledge is not a guarantee of private CoreGraphics source metadata or actual key delivery on every macOS/driver combination.

There are 93 monitor profiles spanning EDID matches and explicit model presets; automatic=false entries require deliberate selection. Documented model-specific input codes take priority over generic capabilities. No profile enables a shortcut or switches an input automatically. Some EDID IDs span hardware variants; destination signal presence is not inferred.

Separate catalogs contain 162 LG firmware-family identities (only evidenced operational mappings are enabled) and 23 MSI firmware mappings. Native MSI USB, USB MCCS and NEC LAN/serial paths have packet/identity fixture coverage, not broad real-device certification. See [HARDWARE-SUPPORT.md](HARDWARE-SUPPORT.md).

The monitor input data was extracted from the DDCControl database (per-entry source revision URLs are in the JSON). Its GPL-2.0-or-later license is included as `ddccontrol-COPYING.txt`, also copied into the app. The editable JSON is the source form of the data; no DDCControl executable/code is linked into Perch.

Review these catalogs when adding hardware or investigating incompatibility. Keep evidence and confidence with each entry. For 1.2, review versioned external catalog updates, distribution and license notices; do not silently promote a documentary entry to hardware-tested.

## Monitor control confirmation and retail presets

Six additional manual retail-model presets cover LG 27UN850-W/WY, 27UP850-W, 27UP85NP-W, 32UD99-W, 29UM69G, and 40WP95C-W. These retain different USB-C/DisplayPort codes from the ddcutil model-specific reports; they are never inferred from the shared GSM7706 identity. Entries with automatic=false and no EDID model deliberately carry no product match. Exact names or explicit preset selection are required. Sources: https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors .

The owner confirmed LG 27UN850-W USB-C switching using code 209, not 210. Other directions, models and adapter paths are not thereby certified.

Transport write success is not a successful switch. Perch reads back the requested input after an explicit cycle; missing replies lead to per-input user confirmation and adapter/dock troubleshooting. Previous confirmations are scoped to display identity, registry connection path, protocol and cycle codes, and labeled historical rather than proof of current state. A connection path is not a physical cable fingerprint. No idle polling or automatic test switches are introduced.
