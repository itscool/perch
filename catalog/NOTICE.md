# Perch catalog sources and changes

Reviewed September 10, 2026. These are editable JSON data files; the same source
form ships in Perch.app/Contents/Resources. Third-party data retains its stated
terms. This notice does not assign a license to the independent Perch app.

## Monitor inputs

monitor-profiles.json contains 93 profiles. Most input records derive from
DDCControl's database at revision 1c7c3f1603332574d48b68e46dcf3d46e788de12:
https://github.com/ddccontrol/ddccontrol-db/tree/1c7c3f1603332574d48b68e46dcf3d46e788de12

The corresponding upstream XML permalink is retained in each profile's evidence.
DDCControl database contributors retain their copyrights. The derived database
records are distributed under GNU GPL version 2; ddccontrol-COPYING.txt contains
the full terms. Perch contributors converted selected input-source records from
XML to JSON, added source/confidence fields and independently documented monitor
observations on September 6–7, 2026. The JSON is the preferred editable form used
by Perch; no generated binary database or DDCControl executable is shipped.
LG input facts also cite ddcutil's public input-source documentation and m1ddc;
user-observed mappings are distinguished from upstream evidence.

## MSI input profiles

msi-input-profiles.json contains 23 selected firmware/identity/input combinations
from msigd's model/protocol research. Source reviewed September 10, 2026:
https://github.com/couriersud/msigd/tree/737a84fcfeb487226309e0cd585a05a08db6014a

This revision is the review snapshot, not a claim that the earlier extraction
recorded this exact revision. msigd contributors retain their copyrights. The
imported data subset is distributed under GNU GPL version 2; msigd-LICENSE.txt
ships with the app. Perch contributors selected supported ASCII identities,
omitted unhandled/read-only entries, and converted them to editable JSON on
September 7, 2026. Perch's native transport uses protocol facts; msigd's C++
program and its HID/USB libraries are not compiled or bundled.

## LG firmware names — redistribution review unresolved

lg-firmware-families.json contains 162 model-family identifiers extracted from
LG OnScreen Control 7.20. The file records the package SHA-256 and research date;
LG-IDENTITY-RESEARCH.md records the official download and method. No LG executable
is bundled. There is no recorded redistribution grant for the extracted table.
The public release must resolve that basis or omit/replace the table. This is a
provenance gap, not a conclusion that functional facts are copyrightable or that
the extraction was unlawful. Never describe the table as certified LG support.

## Keyboards and agents

keyboard-profiles.json contains 28 Perch-authored hardware profiles with source
links and explicit observation/verification fields. Manufacturer/device facts
and public compatibility references are not a claim that upstream driver code
was copied. No Solaar, Karabiner or other keyboard driver is bundled.

agents.json contains eight Perch-authored recognition records. It stores official
product/project references and executable/bundle matching facts, not vendor
applications. Preserve user choices when revising matches. vendor-protocol-research.json
and the research Markdown files are development references, not runtime catalogs.

## Maintenance

Review agent recognition monthly against official sources and whenever a match
changes. Review monitor/keyboard profiles when an issue or upstream change merits
it; avoid silently substituting a vendor-wide guess. Every changed operational
profile needs provenance, a review date, its identity/transport scope and an
honest evidence level. Keep confirmed local input mappings ahead of suggestions.
Pin imported source revisions and update this notice and the release inventory
when data is added. A descriptor match is not a physical switching or key-delivery
test. Validate ambiguity, unsupported devices and partial results before promotion.
