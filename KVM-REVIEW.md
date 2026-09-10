# KVM foundation and native desk review

September 9, 2026. First implementation milestone; **not live KVM**. Main Perch
remains at source version 1.2.84. The separate Desk Preview is a simulation and
uses its own storage. The separately signed preview was installed at `/Applications/Perch Desk Preview.app` and opened through LaunchServices. Its installed direct dropdowns and tinted/outlined inline editor were inspected; the preview was left open after ending AGENT MODE. No live permissions, input events, monitor settings, sleep
policy, helper installation or public publishing were exercised for this work.

## Implemented boundaries

- Group configuration: 1-member setup draft, up to 16 grouped computers and 16
  physical screens; independent input ports with optional computer/local-display
  mapping; three presets; validation and explicit incomplete setup.
- Monitor identity proposals reject known missing/colliding serials and never
  automatically merge physical monitors. Physical geometry includes rotation,
  scaled coordinate conversion and unique touching-edge traversal. Gaps, corners
  and unassigned targets do not silently teleport input.
- Signed configuration graph: pinned externally established roster/epoch,
  parent dependencies, concurrent heads, explicit conflict resolution, offline
  catch-up, scoped receipts, stale-epoch/unknown-member rejection. Bounded wire
  framing handles split/coalesced messages and rejects invalid lengths/floods.
- Handoff state machine: serialized requests, participant input release, fresh
  visible-input evidence, exact session/request binding, timeout/disconnect/
  invalidation fencing. Picture-only routes can commit without an input owner.
- Native prototype: direct manipulation, two connection/preset lists, compact
  edit/Play cards, immediate persistence, incomplete/offline/failure/conflict
  recovery, physical identity correction, inline grouped editors and scoped X.
- Main Settings host: stable sidebar pages hide redundant Back/Close content
  controls, retain valid keyboard focus and Escape/window closing, and keep
  scoped temporary-operation exits. The main status menu is not redesigned.

## Findings corrected during this iteration

| Priority | Finding | Correction / evidence |
| --- | --- | --- |
| P1 | A stale or partially successful handoff could otherwise route input to an unseen destination. | Separate signed configuration, live transaction and fresh observed routes; wrong-session, partial and expired evidence tests. |
| P2 | A preset's preview selection could be confused with activation. | Card selects editing; compact Play activates; independent Active badge. Native Play followed by selecting a different card retained the first preset's input destination. |
| P2 | Unassigned computer mapping was conflated with absence of a monitor input. | Optional computer binding; picture-only switching allowed; no operational None; required real input choices before activation. Native unassigned-input selection and simulated activation passed. |
| P2 | An offline preset initially remained clickable without explaining readiness first. | Readiness derives from current members/assignments before Play; contextual explanation. Headless before-click/reconnect checks. |
| P2 | Adding an online computer left a stale waiting-for-offline status string. | Derive state from current values instead of maintaining a second status copy; targeted journey check. The redundant status bar was subsequently removed. |
| P2 | Naming or reselecting an unchanged mapping unnecessarily changed route state. | Ignore identical mapping writes and preserve physical input codes across label edits; active arrangement comparison ignores cosmetic names. |
| P2 | Returning from an editor could retain an unrelated error in another sheet. | Scope transient messages to the opened task; close confirmations to the inline editor. |
| P3 | Back-button navigation and a permanent status bar repeated existing sidebar/Active state. | No redundant root Back/Close; no preview status footer; temporary X/Escape only in the prototype. |
| P3 | Expanded connection fields visually lost their owning row. | Direct mapping dropdown; row and expanded fields share one restrained background and outline. |
| P3 | Expanding a connection introduced a scrollbar that narrowed the whole inspector. | Owned native overlay scroll view, permanent 16-point margin and thin rectangular thumb. Native expand, scroll to lower choices, collapse while scrolled, continuous field typing and child-sheet X/Escape return passed in the isolated lab. |
| P3 | The right pane hid some of the three preset choices behind excessive spacing. | Compact connection rows and three consistently labeled input pickers. |

## Evidence

- `Tools/check-kvm.py`: **66 checks passed**, including 16-replica conflict and
  convergence simulation, rejected 17th devices, tampering/revocation boundary,
  arbitrary framing, coordinate transforms, picture-only and failed handoffs.
- `Tools/kvm-lab/check.py`: **26 checks passed**, including durable save/reopen,
  no invented active state, rollback on invalid edits, direct mapping, label
  changes, first use, removal/correction and failure/retry.
- Full isolated app suite after the Settings host change: **23/23 passed** under
  AGENT MODE. This includes sidebar root/child/operation focus and cancellation.
- Native walkthroughs under AGENT MODE: preset success/failure/retry; editing a
  different preset while one remains active; naming and return; adding a third
  member; offline handling and explicit conflict resolution; tile rotation;
  X opening removal confirmation and leaving it; real input-only menu choices;
  unassigned picture-only activation; nested correction exit before the inline
  redesign; inline editor expansion. Headless checks are not substituted for
  native click evidence where this paragraph says native.
- Swift compilations used warnings-as-errors for the portable core and native
  preview. The complete isolated Perch build succeeded. Dialog contract retains
  all 60 construction sites. The settings-flow-review skill was updated and its
  structure validated; the small new evaluation scenarios were assessed locally,
  not by an independent agent.

## Open implementation and acceptance

1. Pairing/device identity in Keychain, authenticated transport, Bonjour/nearby
   discovery and explicit-address entry. Discovery must never establish trust.
2. Membership/epoch authority, revocation distribution, durable production
   history/checkpoints, authenticated receipts and network reconnect. The current
   graph accepts an already-established trust roster; it does not establish one.
3. A fenced distributed live coordinator, real monitor control/readback and
   input capture/suppression/forwarding/release adapters. The prototype simulates
   outcomes; it cannot prove a picture or key recipient on another computer.
4. Production Settings integration and old-monitor-settings migration. Existing
   cycling remains until the replacement is ready. Import detected input choices
   and propose strong identity matches to reduce manual setup; ambiguous cases
   still require confirmation.
5. Real two/three-Mac hardware/network acceptance; native drag/keyboard/VoiceOver,
   small-screen/light-theme/16-screen interaction, held keys, sleep/disconnect and
   partial physical failures. Headless geometry and group-size tests do not close
   those physical/accessibility checks.

The plan remains KVM-PLAN.md. Public signing/feed/notarization for Sparkle remain
separate release work in DISTRIBUTION.md; no public update channel was enabled.
