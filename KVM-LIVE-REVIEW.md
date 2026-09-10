# Desk runtime and Menu Appearance — implementation review

September 9, 2026. Version 1.2.87 installed local test build. No physical monitor
switching, sleep changes, permission resets, panic or publication during review.

## Boundaries and evidence

- TLS 1.3 mutual identities use Apple Network.framework and a pinned Apple
  swift-certificates dependency. Production device secrets stay in Keychain.
- Both screens must confirm the same session-bound comparison before joining.
  Discovery never grants trust. One desk owner signs membership changes;
  established members synchronize directly and preserve conflicting revisions.
- Real loopback peers passed two-sided approval, durable cross-peer edits and
  receipts, pinned reconnect, offline conflict resolution and removed-peer denial.
  These use temporary identities and files, without Keychain or Bonjour.
- Monitor-only preparation reserves control connections before switching, rejects
  conflicting/unprepared/stale requests and delegates a failed DDC source path to
  a mapped peer while retaining the original control lease. Only fresh readback
  confirms a result. Two-screen outcomes, fallback, expiry and competing requests
  passed over real TLS with all hardware calls injected.
- The existing DDC, USB, NEC network/serial, LG and profile libraries serve Desk.
  No old monitor preferences are imported. Production navigation/menu replaces
  cycling with Desk and three presets; old isolated controller fixtures remain.
- Appearance stores System and rainbow section settings separately. The preview
  uses MenuRowView, including border sides/scope, grey or colored highlights,
  intensity, radius, title tint/icons and spacing. Original defaults are retained.

## Journey ledger

| Route | Saving / exit | Evidence boundary |
| --- | --- | --- |
| Desk first use | Explicit setup enables networking and creates Keychain identity; ordinary edits save immediately | Source and loopback; native acceptance pending |
| Add computer / invite / join | Two-sided comparison, bounded invitation, X ends unapproved connection | TLS tests passed; native approval presentation pending |
| Add screen / shared identity | Explicit physical match and connected input; no inferred merging | Source; native mapping and hardware identification pending |
| Connections / monitor control | Inline edits; valid route changes save; no input command until Play | Source; native scrolling/draft behavior pending |
| Preset card / Play / shortcut | Editing and activation distinct; monitor-only operation, contextual results | Two-screen/failure/delegation/expiry tests passed; native and hardware pending |
| Conflict / membership change | Both arrangements retained; explicit choice; revoked identities cannot return | Real loopback tests passed; native review presentation pending |
| Remove computer / screen / connection | Destructive action scoped to named target and explained; X abandons | Source; native cancellation pending |
| Menu Appearance / System / presets / restore | Immediate save; independent scopes; same-renderer preview | Persistence, renderer, native checkbox/scope/scroll/Restore passed |
| Sidebar and temporary sheets | Stable pages use sidebar; scoped X/Escape for temporary work | Existing host suite plus native sidebar return and child X/Escape passed |

## Native evidence

Under AGENT MODE, the isolated production UI host used two real TLS peers and
injected monitor commands. Clicks expanded connection editing and opened Monitor
control; its X returned to a responsive parent. Play confirmed both simulated
screens. Desk-name edits survived Escape and returning through the sidebar.
Appearance native checks covered a border checkbox, separate System values,
scrolling to the bottom and Restore. The first pass found overlapping sample rows
because NSMenu owned their frames; a preview-owned layout plus a geometry
regression check fixed it. The corrected screenshot was inspected.
These are focused paths, not an assertion that every dialog/VoiceOver path passed.

## Physical acceptance still required

Two real Macs: approve membership on both screens, map the actual monitor ports,
use each preset in both directions, verify actual input readback, then unplug or
sleep a peer and retry. Repeat with two screens and a partial failure. Nearby
Wi-Fi, routed-network reachability and real DDC/USB/NEC support need their actual
hardware; loopback success does not certify them. Keyboard/mouse forwarding is
explicitly deferred. Production Sparkle feed publication remains separate.

Text-entry evidence: typed Desk-name changes were saved and survived Escape.
The fixture did not select all text with Cmd+A (it omits the normal application
menu); replacement-selection and standard editing shortcuts remain native QA
for the production SwiftUI fields rather than being counted as passes.
