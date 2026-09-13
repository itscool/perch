# Desk joining and appearance — September 13, 2026

Source changes after 5266bb9. Installed/running app remains 2.0.106;
public/notarized remains 2.0.94. No live UI, network discovery, permission,
hardware, installation or publication operations were used for this work.

## Findings and resolution

| Priority / journey | Finding | Correction and evidence |
| --- | --- | --- |
| P2 / discover a Mac | Browser used plain Bonjour discovery while expecting TXT metadata. Missing metadata became `Perch <UUID prefix>` on an unexplained button. | Request Bonjour with TXT records. Read bounded human-readable name, advertised Invite/Join role and desk name. Fallback says Unnamed Mac; identity still requires signed hello and code approval. Metadata extraction/role tests pass. |
| P2 / start and approve | Device buttons named neither action nor role. Port, identifier and confirmation code were easy to confuse. | Explicit Invite/Join actions and instructions on both devices, local name, a labeled comparison code and addresses confined to Connect by address. Local repeated clicks are prevented while connecting. |
| P2 / recover networking | Every waiting/failed callback overwrote one sticky generic problem, even if a connection recovered or an alternate route worked. | Listener, discovery, pairing and peer failures are separate. Ready clears only the matching transport status; authenticated trust clears that peer’s connection failure. Offline/online state gates peer warnings. Unrelated storage/protocol errors survive network recovery. Discovery failure is scoped to finding new Macs. |
| P2 / complete and leave | Pairing completion could notify the sheet before clearing the operation’s pending link. | Clear pairing state before publishing completion; closing the completed sheet preserves the trusted connection. Tests verify completion then close. |
| Design / choose an appearance | Existing samples were too similar and preset names overlapped palette names. | Six treatments: Perch original, Quiet, Signal, Soft tiles, Outline, Ribbon. Eight independent palettes: Rainbow, Graphite, Coast, Dusk, Woodland, Mineral, Jewel, Sorbet. Original values preserved exactly. |

The metadata correction follows Apple’s documented
[Bonjour descriptor with TXT records](https://developer.apple.com/documentation/network/nwbrowser/descriptor-swift.enum/bonjourwithtxtrecord(type:domain:)).
The specific network failure seen on Scott’s Mac was not captured; the sticky-error
path is a verified source defect, not proof that every observed network warning
had that cause. Real permission/reachability failures remain visible.

## Verification and remaining acceptance

- `Tools/check-desk-network.py`: passed real TLS loopback with temporary identities
  and files, including new role/metadata, repeated-click, waiting/recovery,
  unrelated-error preservation, completion/close and redundant-route checks.
  Existing two-sided approval, signed sync, offline conflict, revocation,
  monitor commands with injected hardware and 16-peer checks also pass.
- `Tools/render-menu-appearance.py`: passed model/serialization/stable preset-ID
  checks; produced inspected Light/Dark comparison PNGs using production drawing
  code without windows. Previews use the first four sections in actual order.
  New presets meet 4.5:1 for title text on the preview’s backgrounds. The exact
  user-defined original is preserved; its Light Audio title measures 4.10:1 on
  that fixture. This is not certification for arbitrary user settings, monitor
  calibration or macOS translucency.
- Full app/functional host compilation passed; no native GUI suite was run
  while Scott owns the desktop.
- Real Bonjour advertisement updates, actual two-Mac first-use/retry, and native
  layout/interaction remain acceptance work. No new build is installed here.
- Settings-flow skill now covers device roles, distinct identifiers/codes, scoped
  recovery and appearance alternatives that differ in composition.
