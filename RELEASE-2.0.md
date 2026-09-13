# Perch 2.0 development

September 10, 2026. Developer ID 2.0.94 is now installed in /Applications and
running through LaunchServices. Apple accepted its notarization; the stapled app
passes strict nested signature verification and Gatekeeper as Notarized Developer ID.
Version 2.0 is the active development line. This record distinguishes implementation,
isolated QA and hardware acceptance.

## 2.0.94 installation and release checkpoint

- Installed the app from the verified signed DMG, replacing the running 1.2.87
  development instance via a graceful application termination and LaunchServices.
  Candidate source snapshot matches commit 466b2ec; later build-tool/documentation
  commits are not represented as compiled into this app.
- Before and after installation: the saved include-lid setting stayed enabled,
  SleepDisabled remained 0, and normal Keep Awake was present after relaunch.
  No active lid ownership record existed before replacement. The older helper was
  not reinstalled; publisher compatibility must be resolved through the queued
  helper-update flow before starting a new protected session.
- AGENT MODE was shown and then stopped. Native desktop inspection timed out, so
  this records process/version/signature verification, not a successful UI or
  physical lid test. No live permissions were reset or hardware tests triggered.
- The signed, notarized and stapled DMG passes hdiutil verification. The
  notarized-app Sparkle ZIP and appcast pass signature/version/archive-reference
  verification. The 2.0.94 GitHub release and public feed downloads are verified.
  The user approved retaining the recorded LG table. A real published-version
  update/restart remains QA, including protected-lid handoff and failed/retried
  installation.

## Pending setup corrections

September 12 native QA: the corrected-source fixture now passes 23/23 isolated
suites. Real picker cancellation/return, custom app exception creation/persistence,
sidebar keyboard navigation and setup return passed. A disposable Sparkle
failure/retry replaced and relaunched the app, claiming its exact saved identity.
That test exposed unreadable update-handoff/Desk files; both stores now use
after-login file protection while retaining owner-only modes. Pending lid-helper
updates now use attention colors, and active-session wording distinguishes the
helper's report from a guarantee that macOS will stay awake. These changes are
not installed. The Documents stall was subsequently traced to a pending TCC
folder-access prompt; disposable /Applications update/relaunch now passes.
Physical lid transfer remains untested. See NATIVE-QA-2.0.95.md and the follow-up
AUTOMATED-QA-2.0.96.md.

Local build packaging also fixes macOS Bash 3.2 aborting before Sparkle embedding
and final signing. Complete staged bundles must pass runtime-path, architecture,
framework-layout and nested-signature verification before replacing the output.
The same verification protects release and update packaging. This prevents a failed
build from leaving a new incomplete app at the output path; acceptance of the
reported other-Mac launch failure was confirmed fixed by Scott on September 12.

Verification: a full local build of 2.0.95 completed through the new packaging
gate with no compiler warnings. Disposable compiled Mach-O fixtures passed
relocation and rejected missing framework/rpath, broken or external links and
damaged nested signatures. Failed replacements preserve the previous build,
including a recoverable copy when rollback itself fails. Local/release arguments
passed under macOS Bash 3.2; dependency and release failure/retry tests passed.
The 2.0.95 candidate was not launched, installed, notarized or published.

Source fixes after 2.0.94 address permission recovery, consistent drag/copy paths,
external-window return, publisher-aware helper readiness, persistent setup views,
and explicit lid setup/resume. First use revisits missing required prerequisites.
Settings uses sidebar navigation without Close buttons; prerequisite pages opened
from the setup checklist offer Back to setup and retain that context on failure.
See SETUP-REVIEW-2.0.94.md for the per-finding changes and verification boundary.
The fix fixture has now been exercised under AGENT MODE; no
updated live app or public release is being claimed. 2.0.94's app and installer
are notarized and public, with verified anonymous downloads and update feed.

## Pending full Settings UX corrections

The subsequent full static review’s U1–U11 and D1–D3 are implemented in source:
current Desk/emergency shortcut conflict handling and retained working registration,
explicit local reset scope, recovery while layout storage is damaged, the missing
Resume route, retained add-agent errors, next-keyboard setup, complete shared Desk
field drafts and conflict details, route-neutral navigation copy, custom app
exceptions, direct Desk/input sidebar pages, contextual Appearance controls, and
Ready/optional-review keyboard permission state. The main menu design is retained.

Pure draft/conflict value tests and the source ownership gate passed. Native
regressions passed; bounded real-route acceptance is recorded in NATIVE-QA-2.0.95.md.
These corrections are not included in installed/public 2.0.94. See
SETTINGS-UX-REVIEW-2.0.94.md for the complete disposition and evidence boundary.

## Implemented

- Desk input sessions run over existing mutually authenticated, pinned TLS links.
  The desk owner arbitrates one transient focus. It must remain connected; there
  is no competing coordinator or persisted input-capture grant after restart.
- Enable sharing separately on each Mac for the current session. Desk settings
  shows app-owned Accessibility/Input Monitoring requirements, linked recovery,
  named screen destinations and a saved pointer-speed control. Setup & status
  reports optional, enabled-but-inactive, active and unavailable separately.
- Real monitor input readback gates control. Visibility challenges are bounded
  by the requesting process's monotonic clock; delayed replies do not become
  fresh merely by arriving. Typing does not rely on a cached preset badge.
- Pointer movement crosses touching screen edges, with target desktop-coordinate
  scaling and the configured physical geometry. Ambiguous corners, gaps and
  unassigned/unverified targets stop at the edge. Ordinary keys, five mouse
  buttons, double-click state, drag state and two-axis scrolling are routed.
- Sources may be different computers for keyboard and mouse. Per-source held
  key/button state prevents one keyboard releasing another's key. Handoffs first
  release old input, then install grants on all participants before delivery.
- Prepare-time input is bounded to 64 events per source; initial delivery waits
  for all participants and is bounded to 256 events. Timeout, overflow, changed
  configuration or lost readiness discards pending input and returns locally.
  A stale-session stop cannot cancel a newer grant. Events are never persisted.
- One-second renewable input leases are tied to outstanding challenges, not
  remote clocks. Expired/replayed input and unsupported native event fields are
  rejected. The transport and event rate are bounded. Injected events carry an
  origin marker so they are not captured or transformed a second time.
- Ctrl–Opt–Esc returns local control. Native cursor visibility is restored on
  cleanup. Preset activation stops the old input session before monitor writes;
  enabled sharing resumes only after the selected picture confirms.
- Shared keyboard definitions synchronize with the desk. Each host attachment
  is explicitly confirmed; duplicate native identities are unavailable. Both
  detach/arrival message orders are handled. The first key on an observed new
  attachment waits for its destination rather than typing on the old computer.
- Strong-serial monitor suggestions are wired into Add screen, with Identify and
  explicit confirmation. Duplicate/colliding identities never silently merge.
- Invalid desk/preset name edits retain their local draft and explain that the
  previous name is saved; users can erase a field before entering its replacement.

## Findings corrected during development

| Priority | Trigger | Correction / evidence |
| --- | --- | --- |
| P1 | Input and monitor messages shared an acknowledgement name | Distinct input wire prefix; real TLS handoff tests |
| P1 | Typing during preparation could fall through to the local app | Bounded handoff buffer; test sends down/up before the grant |
| P1 | A source could receive its grant before the destination installed it | All-participant installation barrier and bounded delivery buffer |
| P1 | First key after keyboard arrival could target the old host | Fresh attachment reconciliation and destination-bound buffering; both network ordering cases covered |
| P1 | A delayed expiry stop could cancel a newer input session | Session-scoped expiry stops; explicit local recovery remains global |
| P1 | Posting movement alone loses drag and double-click behavior | Native constructor tests exercise held buttons, release and click count |
| P1 | A harmless rename could interrupt remote typing | Routing-only configuration fingerprint; real TLS rename-while-sharing regression |
| P1 | UUID-keyed dictionaries could hash differently on different Macs | Canonical string-key encoding for routing fingerprints |
| P1 | Add keyboard saved but the open child list stayed unchanged | Observe the group model in the child, including remote edits |
| P1 | Main-menu preset entry bypassed input cleanup | All preset entry points use the shared handoff method |
| P2 | Late background keyboard enumeration could overwrite a newer observation | Scan generations discard older results; unchanged lists do not redraw |
| P1 | An eighth setup check exceeded seven allocated native rows | Data-driven scrollable overview and final-row navigation regression |
| P2 | Hosted text fields lacked standard application editing shortcuts | Native responder-chain Edit commands shared by app and fixture |
| P2 | Erasing a saved name could snap the old text back into the field | Separate invalid local draft, immediate valid save |

## Evidence

- `Tools/check-kvm.py`: 98 portable checks, including replay/expiry rejection,
  160,000 synthetic held-key observations with bounded retained state, geometry,
  identity collisions, signed edits and both keyboard arrival orders.
- `Tools/check-desk-network.py`: real TLS on loopback with temporary identities;
  two-sided pairing, durable signed changes, conflicts, reconnection, revocation,
  monitor transactions, input in both directions, prepare-time typing, first key
  after keyboard movement, lost visibility, and a full 16-computer/16-screen
  arrangement. All 16 sources deliver to focus; traversal reaches three hosts.
- `Tools/check-input-native.py`: native event construction only. Double clicks,
  drags/releases, auxiliary buttons, modifiers, repeats, scroll axes and origin
  markers pass. No event is posted and no event tap is created by this check.
- Full isolated app regression: 23/23 suites pass, including AppKit settings,
  setup-summary row capacity and final-row navigation. Native fixtures cannot
  activate this input adapter.
- Real native fixture clicks: Add keyboard immediately adds its card; rename and
  Follow persist across Close/reopen; invalid desk-name drafts remain editable;
  Command-A replacement, Undo, Redo and Escape now dispatch correctly with the
  production application Edit menu. No real desk or hardware was changed.
- Read-only 30-second installed 1.2.87 baseline: 30/30 healthy observations,
  about 1.23% combined app/helper CPU excluding the observer, no growing measured
  footprints. This is not a 2.0 input-activity performance result. Passive keyboard
  enumeration measured 2.063 ms median / 3.411 ms p95 on this Mac, not a universal
  device/driver guarantee.
- Hardware calls, capture/posting and permission prompts are deliberately outside
  these tests. Tests are not evidence of real pointer latency or successful
  password entry on another Mac.

## Remaining acceptance and limits

Use controlled two-/three-Mac tests for actual pointer speed, Retina/rotation,
mouse buttons and drag, first key after physical Bluetooth host selection,
keyboard/mouse on separate hosts, event-tap coexistence, unavailable permissions,
secure-entry transitions, real monitor readback timing and recovery under load.
Some drivers retain a keyboard attachment after a hardware host switch. Such a
switch cannot be inferred from idle input or a model name. Broad VoiceOver,
keyboard-only navigation, lid edge cases and release-install lifecycle remain in
TODO.md. Native gestures and system-defined media events are not forwarded by
this standard-key/mouse adapter and require local controls.

Secure password entry, lock-screen control, logged-out sessions and FileVault
preboot are not supported. The adapter stops on secure-entry/session state and
lock notifications; it does not disable macOS protection or install a virtual HID
driver. Lock notifications/session lock hints are platform-dependent and still
need physical acceptance. Apple documents session information and event-tap
access; the Karabiner maintainers also describe secure-input capture limitations:
[Apple session information](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPMultipleUsers/Concepts/FastUserSwitching.html),
[Apple event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[Karabiner implementation notes](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md).

The Sparkle release pipeline remains prepared. Public release still requires the
`Perch` notarization credential profile (read-only check still reports missing),
production signing authorization when prompted, successful Apple notarization,
and resolution of the LG table provenance issue in Release/DEPENDENCY-REVIEW.md.
Windows/Linux, VM adapters, direct Endpoint Security, and native lid/thermal
research remain the separately agreed backlog.

## 2.0.96 candidate — September 12

A Developer ID build passed strict nested signing and bundled Sparkle checks with
no compiler warnings. It is prepared locally, not installed, notarized or
published. Its source snapshot is retained by the release pipeline. The source
fix removes redundant trusted-history work and unchanged UI publication that
caused Desk input leases to expire during optimized 16-peer concurrent edits.
Authentication still runs at ingress, and the one-second expiry is unchanged.
See AUTOMATED-QA-2.0.96.md for regression, endurance and native update evidence.
Correction-specific draft notes are in Release/notes-2.0.96.md. Use the staged
release CLI with that same --notes path when packaging, finishing and publishing
this prepared candidate; the one-command wrapper currently uses Release/notes.md.
Continue only after physical acceptance and explicit notarization/publication
authorization. The prepared candidate need not be rebuilt.

## Setup consolidation — candidate 2.0.98

Setup now owns Background helpers, Keyboard access, Scrolling & navigation,
Shared input access, Lid protection and Agent tracking. Feature pages retain
ordinary controls and link directly to their prerequisite stage. Checklist
identity and return context survive navigation between stages. No installation,
permission change or sharing activation occurs merely by entering Setup.

The 2.0.97 native fixture passed all six stage returns plus feature → Setup and
shared Input Monitoring navigation. All 23 isolated suites passed. The 2.0.98
candidate adds a small correction so a successful helper result is not itself
colored as needing attention; its targeted regression is recorded in
SETUP-CONSOLIDATION-2.0.md. Release notes in Release/notes.md include these changes,
so the normal one-command release workflow uses the correct notes for this
candidate. 2.0.98 supersedes the prepared 2.0.96/97 candidates; installed/public
2.0.94 remains unchanged. Notarization and publication require explicit approval.

## Reset discovery — candidate 2.0.99

Resets is an independent sidebar destination covering saved preferences, learned
keyboard layouts, menu appearance, Perch privacy, sleep/audio and all-app privacy.
Setup and feature reset links lead to that same home. Navigation and instruction
disclosures use destination/Show/Hide names; actual review of proposed changes
keeps its meaning. Ordinary editing and operational confirmations remain intact.

All 23 isolated suites passed. Native fixture clicks passed all six reset scopes
and Back plus setup/appearance entry links. Only injected/disposable writes were
performed; no live reset, permission, helper or sleep operation was exercised.
See RESET-DISCOVERABILITY-2.0.md. Candidate 2.0.99 supersedes prepared 2.0.98;
installed/public 2.0.94 remains unchanged. No notarization/publication is included.

## Contextual reset recovery — candidate 2.0.101

Repair links open the exact scope inside Resets, with a labeled Back that retains
the original setup/feature page and checklist. Lid repair excludes unrelated
audio changes; background repair uses Perch-only permissions. Keyboard layouts
and appearance use the same scoped return, while the System privacy command
opens all-app privacy beneath the Resets index. No reset is executed on entry.

Background-helper status refresh updates its existing page; keyboard layouts
reload saved profiles on return. Privacy failure/retry/results retain the return
route. Explicit sidebar navigation or closing ends the temporary context.
Developer ID signed 2.0.101 supersedes prepared 2.0.99/100; installed/public
2.0.94 remains unchanged. Final test/native evidence is recorded in
RESET-DISCOVERABILITY-2.0.md. No notarization or publication was performed.
