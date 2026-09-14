# Perch work checklist

2.0 development, September 14, 2026. Public signed/notarized release 2.0.151 is built,
published and installed on disk. The currently running process may still be an earlier
same-version process until the user restarts Perch. The next source candidate adds Desk
warning isolation, narrow-window computer stacking, stale monitor-lease recovery, explicit
input-sharing restart, and cross-Mac optimistic direct-switch/preset state propagation.
Settings now has a top-level Logs section for Lid activity, CPU readings, Agent safety activity,
and Desk connection activity. Desk preset cards separately label the preset being edited and
the preset active on the displays.
The lid helper updated automatically to 2.0.131/helper version 5 while closed
on AC; saved protection resumed. Active app restart on 135 also preserved its
owned session after fixing a client claim/poll race. Background helpers and
collector report Ready. See LID-HELPER-MAINTENANCE-2.0.md for evidence and limits.
LG input switching still needs known physical starting ports for a bounded test.
Dated installation statements below are historical checkpoints. Categories are
known defects, features, QA, release and backlog; each is ordered independently.
This supersedes stale open-item wording in dated review checkpoints.

## Current continuation checkpoint

The requested normalized appearance fade and control regrouping are implemented.
All seven Light/Dark presets were reviewed with offscreen production rendering;
Ribbon and Horizon use different normalized fade distances, while Perch original
is unchanged. Candidate 2.0.146 is built, Developer ID signed and installed on
disk. The currently running 2.0.142 process was left in place so its live
session was not interrupted; restarting Perch will load 2.0.146.

Hotkeys now has a content-sized emergency editor and side-by-side countdown
shortcuts. Recognition displays pending changes under Import with an explicit
Apply confirmation. The shared feedback widget uses neutral progress for checks
and reserves orange for actionable failures. A monitor switch whose current
input cannot be read now uses the accepted target for desktop reconciliation;
a positive contradictory read cancels that fallback. Native desk acceptance
still requires a physical two-Mac test. The optimistic handoff and routing
state visual changes are committed and pushed at 209d2e2 (release metadata at
126ed52).

The current unreleased Desk candidate keeps actionable switching failures in a compact badge
beside the Desk title instead of expanding the canvas, stacks computer cards when the available
width is narrow, and exposes a safe direct-input takeover after stale/non-executing leases. A
hardware write is never interrupted while its validity window is active; an orphaned lease is
recoverable after that window. Direct port switches and preset switches broadcast accepted
runtime state so paired Perch instances can select the matching preset without replaying the
monitor command. Input sharing now has an explicit Restart input sharing action that rebuilds a
macOS-disabled event tap, plus Reconnect desk for peer/offline sharing failures. Unknown monitor
input no longer blocks KVM; it is shown as a check-picture note. Source/build verification is
complete; physical two-Mac acceptance remains pending.

## Known defects — fix before shipping; target zero

- [x] **Renaming a keyboard discarded known navigation layouts.** Model/transport
  and descriptor metadata now determine recognition independently of the editable
  product name. Saved matching, helper delivery and connected/saved UI use the
  same distinction. Renamed MX Keys and learned-layout regressions pass in 135.
- [x] **Lid restart claim competed with startup polling.** Separate claim transport,
  stale-callback fencing and immediate heartbeat renewal fix the observed 134
  failure. Powered closed-lid native restart passed on 135.
- [x] **Maintenance required unnecessary manual discovery.** Automatic bounded
  helper recovery, launch-time installed-helper maintenance and saved lid intent
  replace generic Repair/Resume. Security owns file protection; Reset Settings
  owns resets; Login Items approval opens at the failing Start at login action.
- [x] **Redundant permission Finder actions.** Exact drag/copy targets remain in
  permission setup. Finder reveal and its unused sibling handlers are removed.
- [ ] **Cross-Mac desktop handoff with unreadable monitor inputs.** Presets,
  port switches, retries and paired delegation converge on one path, and tests
  invalidate old desktop evidence before every switch. On the LG displays here,
  current-input readback is zero, so an accepted command now optimistically
  reconciles the local desktop; a positive contradictory read cancels that
  fallback and keeps the display attached. Sharing consent now starts a KVM
  focus automatically for an active preset with a remote mapped route, and a
  preset change replaces an old focus without requiring a hidden test action;
  the emergency shortcut still suppresses automatic restart. Input focus now
  renews through a separate authenticated heartbeat message, and motion events
  coalesce while key/button/scroll ordering remains strict. Complete the
  physical two-Mac edge-crossing, jitter, recovery and readback/control
  investigation before closing this defect. BetterDisplay remains optional and
  is not a runtime dependency.


Automated update/fault, packaging/dependency and passive performance work is now
recorded in AUTOMATED-QA-2.0.120.md. Real hardware/access acceptance below is not
replaced by injected helpers or a clean dependency-cache fixture.


The Desk inspector heading is fixed in installed candidate 2.0.118. A follow-up
screenshot exposed sidebar badges clipped by the scroll viewport despite correct
cell layout. Candidate 2.0.120 fixes the column width and verifies all clipping
ancestors with overlay and legacy scrollbars. Desk preset membership/use and card/name affordances are
reconciled. See DESK-CLARITY-AND-INSPECTOR-2.0.md for offscreen evidence and live
acceptance limits.

- [x] **Misleading readiness and stale recovery warnings.** Fresh armed lid
  protection and idle enabled sharing now distinguish ready from actively
  controlling a screen, without promising macOS cannot force sleep. Current
  failures retain attention; stale helper and remote failures clear when their
  evidence changes. Input recovery names the coordinator or conflicting changes,
  with targeted connection/status refresh. Monitor failures identify screens and
  offer read-only verification separately from retrying a switch. Installed in
  2.0.119; real two-Mac acceptance remains below. See RECOVERY-AND-DEVICE-FOLLOW-2.0.md.

- [x] **Preset cards grew when attention appeared.** Warning and In use indicators
  share the existing count/status line; offscreen production rendering verifies
  equal card heights. Included in 2.0.119.

- [x] **Desktop participation implementation.** Fresh, generation-matched input
  evidence now drives temporary desktop removal with independent guardian recovery.
  Real process-exit recovery on the secondary LG restored its mode and position.
  Unknown/unreadable inputs and the last usable screen remain connected. Both
  current helpers and actual cross-Mac control/readback remain integration QA.
  See DESKTOP-PARTICIPATION-GAP-2.0.md; LG readback remains the defect below.

- [x] **Record unexpected Desk connection loss.** The earlier real-Mac reset
  report is removed from current known defects at Scott's request because it no
  longer reproduces. Its root cause is not established. Candidate 2.0.120 adds
  per-computer Connection activity, bounded 24-hour/1,024-entry persistence,
  closure causes and durations. Expected local shutdown, redundant routes and
  pairing closure are distinct from unexpected loss. New reports can be tied to
  exact recorded events. See AUTOMATED-QA-2.0.120.md.

- [x] **Pointer sharing was hidden outside the Desk flow.** Scott confirmed
  sharing was off. The new Desk inspector owns session enable, per-computer
  readiness and start on the selected screen using the editing preset. Separate
  Input options contains tuning and optional keyboard host following. This fixes
  discoverability; real two-Mac pointer crossing after enabling remains QA.

- [x] **Enabled Lid activity and setup buttons ignored clicks.** Keep awake's
  seventh-row document outgrew its fixed height. The last two buttons painted
  outside parent bounds and could not receive native hits. SettingsTaskPage now
  grows before adding rows; 210 offscreen native hit targets pass. Actual events
  on Scott's other Mac remain acceptance. See DESK-SHARING-AND-LID-ROWS-2.0.md.

- [ ] **LG input control/readback.** Both monitors now return capability/family
  identity: UP850K (EF c024/A1 0074), and older UL850 (EF 5124, matching the
  earlier owner-identified 27UN850-W record). Both return zero for current input.
  K-W USB-C code/readback still needs physical verification. Alternate-channel
  Get VCP probes can change brightness; production reads now categorically reject
  that channel. Do not guess input state or copy a neighboring model’s profile.

- [x] **Desk cables, monitor setup and dragging were confusing or unstable.**
  Ports now live on monitor cards and computers connect by drag or port menu.
  Monitor setup owns the editable input profile; cable edits preserve physical
  screen identity and preset input choices. Stable drag coordinates and nearest
  valid-edge docking replace moving-view gesture feedback and repeated snaps.
  Identify toggles off and has generation-safe expiry. Source/isolated checks
  are recorded in DESK-CABLE-EDITOR-2.0.md; native acceptance remains pending.

- [x] **Desk joining showed unexplained device identifiers and stale network failures.**
  Discovery now requests name/role metadata; Invite/Join actions identify the Mac,
  explain both sides, and label the comparison code. Connection attempts prevent
  repeated local clicks. Discovery, listener, peer and pairing errors have separate
  recovery lifetimes; failed redundant routes do not obscure a working peer.
  Source and isolated TLS tests pass; native two-Mac acceptance remains pending.
  Included in the installed 2.0.110 candidate.
  See DESK-JOINING-AND-APPEARANCE-2.0.md.

- [x] **Normal lid timeout raised an unexpected-sleep dialog.** Normal helper or
  watchdog grace expiry stays in Lid activity and clears only the pending notice.
  Inactive saved intent alone does not trigger it. Unexpected protection loss uses
  a standalone acknowledgement with optional View lid activity, preserving the
  current Settings page. See LID-SLEEP-NOTICE-2.0.md; not installed.

- [x] **Reset choices required unnecessary subpage discovery; Setup could not resize.**
  Resets now has unchecked scopes and inline keyboard targets, one confirmation,
  partial results and failure-only retry. Contextual repair highlights its row and
  retains Back. Settings remembers a resizable size across pages/reopening;
  Setup uses added space. See RESET-CHECKLIST-AND-RESIZE.md. Prepared in 2.0.102;
  not installed.

- [x] **Repair reset links lost their setup context.** Links now open the exact
  reset scope under Resets and provide a labeled Back to the original setup or
  feature page. Background-helper refresh preserves the page; keyboard layouts
  reload after returning from a reset. Changing sidebar destinations or closing
  ends that temporary return. Prepared in 2.0.101; not installed. See
  RESET-DISCOVERABILITY-2.0.md for the final acceptance boundary.

- [x] **Reset discovery and vague navigation labels.** Resets now owns preferences,
  saved keyboard layouts, menu appearance, scoped privacy and sleep/audio recovery.
  Setup/features name their destinations and link to this same reset home. Native
  scope/Back checks and 23/23 isolated suites passed. Prepared in 2.0.99; not
  installed. See RESET-DISCOVERABILITY-2.0.md.

- [x] **Update handoff and Desk files could not reopen after saving.** Corrected
  file-protection class while retaining atomic writes and owner-only modes.
  Round-trip/network regressions and a real disposable Sparkle restart/claim pass.
- [x] **Lid update attention and misleading active-session wording.** Queued
  helper updates use warning colors; active status explains the helper report
  and macOS limitation separately. Included in the uninstalled candidate.
- [x] **Disposable Sparkle installation stalled under Documents.** TCC logs
  identified a pending Documents-folder access prompt for Sparkle's Autoupdate
  process at the blocked rename. A disposable /Applications installation now
  completes replacement/relaunch and exact handoff claim. No privacy bypass or
  permission reset. Production permission/lid continuity remains QA.
- [x] **P1 — Desk edits could interrupt input authority under sustained load.**
  Sixteen authenticated fixture peers lost leases after about 61 seconds with
  concurrent configuration edits, even with optimization enabled. Repeated
  verification of trusted history and unchanged presentation updates consumed
  the shared executor. Cache validated heads, sort stored revision IDs, and
  publish only changed presentation values. Ingress/archive authentication and
  the one-second fail-closed expiry are unchanged. See AUTOMATED-QA-2.0.96.md.

- [x] **Local builds could abort before embedding Sparkle.** macOS Bash 3.2
  rejects empty optional arrays under `set -u`, leaving a compiled app that
  cannot load Sparkle. The sibling final-signing argument bug is also fixed.
  Builds now stage the complete app and verify runtime paths, framework layout,
  architectures and nested signatures before replacing the output. Release and
  update packaging use the same check. Remote launch acceptance is recorded below.

- [x] **Other-Mac build/launch acceptance.** Scott confirmed September 12 that
  the other Mac's build and launch fix works. Local builds need neither release
  credentials nor notarization. This accepts the reported Sparkle/dyld defect,
  not the new release's full physical feature QA.

Full static Settings UX review at cb44f87 found **one P1 and ten P2 issues**.
All are corrected in source, along with D1–D3. Details and the coverage ledger are
in SETTINGS-UX-REVIEW-2.0.94.md. Installed/public 2.0.94 predates these fixes;
native acceptance remains in QA below, not a claim of runtime success.

1. [x] **U1 / P1:** Validate emergency-shortcut conflicts against live Desk presets;
   preserve a working shortcut on failed registration and show actual readiness.
2. [x] **U2 / P2:** Reset labels and confirmation explicitly cover local layouts/preferences,
   retaining shared Desk arrangements, shortcuts and membership.
3. [x] **U3 / P2:** Allow navigation behavior to be disabled when saved layouts
   cannot be read; disabling must not require resetting the layout store.
4. [x] **U4 / P2:** Complete the setup recovery route for blocked agents with the
   existing Resume action and blocked-state explanation in Settings.
5. [x] **U5 / P2:** Preserve validation/save errors when adding an agent; rebuild the list
   only after a successful save.
6. [x] **U6 / P2:** Add an optional next-keyboard/relearn action after layout setup
   completes, without automatically restarting capture.
7. [x] **U7 / P2:** Make Desk input-name/code replacement editing retain incomplete
   drafts and explain invalid input without silently rejecting keystrokes.
8. [x] **U8 / P2:** Refresh pristine screen-name fields after a remote rename;
   retain and reconcile actual local drafts separately.
9. [x] **U9 / P2:** Show all meaningful arrangement differences before resolving
   a Desk conflict, including mappings, control routes and shortcuts.
10. [x] **U10 / P2:** Remove remaining instructions referring to nonexistent Back
    controls on direct-sidebar pages and their error/completion states.
11. [x] **U11 / P2:** Add the missing custom-app creation/removal path in navigation
    exceptions, preserving browser defaults and immediate saving.

**D1–D3 are also implemented:** direct Desk/input sidebar destinations, disabled
Appearance controls when their area is absent, and Ready/optional-review keyboard
access. Shared name fields all use the same remote-aware draft handling.

- [x] Fresh-Mac builds failed fetching Sparkle when Python lacked issuer
  certificates. Downloads now use system curl with HTTPS and checksum verification;
  missing/corrupt caches repair automatically. Toolchain and local signing checks
  run before version allocation or app writes. `./build.sh --check-dependencies`
  prepares pinned dependencies without signing/notarization credentials. Fresh
  Sparkle download, clean Swift package resolution and failure/repair tests passed.

- [x] Desk omitted the retained LG firmware-ID-to-profile lookup. Explicit setup
  inspection now carries identity to local/remote profile suggestions, preserves
  manual choices and offers the owner-evidenced USB-C 209 profile. Isolated
  transaction tests and native fixture clicks passed; new live hardware
  acceptance remains part of the protocol QA below. Duplicate refresh errors in
  the Add screen dialog are also removed. Installed in 2.0.94; physical monitor acceptance remains open.

These fixes are included in the installed 2.0.94 app:

1. [x] About opened a Settings shell with unavailable navigation. It now uses
   the independent native modeless About panel.
2. [x] Desk default F1–F3 shortcuts could not register because the runtime used
   the emergency shortcut's smaller key list. All offered F1–F20 keys now map
   explicitly; failed registration leaves no partially active preset set.
3. [x] Lid helper installation rejected Sparkle's legitimate framework links.
   The installer now permits only the pinned relative links, verifies nested
   signatures, and rejects redirected/extra links. Publisher mismatch queues
   a helper update rather than claiming the old helper is current.

2.0 additionally fixes setup-summary overflow, stale shared-keyboard rows,
standard text-editing shortcuts and input handoff/ordering failures described in
RELEASE-2.0.md. They are included in the installed app; hardware acceptance remains open.

The latest corrected-source checkpoint passed 23/23 isolated regression suites;
bounded real native journeys are recorded in NATIVE-QA-2.0.95.md. Actual hardware and broader native QA
remain open; this is not a claim that untested behavior is defect-free.

## Features

- [x] **Follow mouse computer buttons as well as keyboard buttons.** Shared
  illustrated setup, three numbered steps, per-Mac device matching and visible
  destination. Passive attachment monitoring and kind-aware signed configuration
  use the existing host-following protocol. Ambiguous devices remain unmatched;
  actual Bluetooth/USB receiver behavior is not yet accepted. Installed in 2.0.119.

- [x] **Switch a single monitor from its port menu.** Switch to this input uses
  the paired leased protocol and fresh read-before-write check, permits an
  unassigned port, preserves all presets and returns shared input locally. Remote
  one-off switching requires both Macs on 2.0.116. Injected hardware / real TLS
  tests cover one target only and stale-edit cancellation, including recovery
  into the next preset switch.

- [ ] **Working KVM handoff with optimistic reconciliation.** Make the normal
  path feel successful immediately after the accepted monitor command:
  show the selected preset as pending, run bounded post-switch reads through
  every safe channel (standard `0x60`, exact-model LG candidates and paired Mac
  observers), and promote the handoff as soon as fresh evidence confirms it.
  Do not depend on BetterDisplay at runtime. If no readback arrives after an
  accepted command, use that accepted target for KVM and desktop reconciliation;
  a fresh read that contradicts it cancels the fallback and keeps the desktop
  attached. Cover delayed, missing, zero, conflicting and reverted reads plus
  peer loss in unit and native fixtures, then validate both LGs physically.

- [ ] **Finish the simplified Desk preset graph.** Replace the single computer
  connector plus vertical monitor input toggles with three clearly numbered
  preset connectors on every computer. Keep monitor connectors physical and
  allow each preset route to be changed by wiring the numbered computer port to
  a monitor input; changing the selected preset should only change the editing
  context, never the physical monitor cards. Show every preset number on its
  route, highlight the selected preset separately from the currently active
  routing, and make an incomplete preset explicit without a second hidden
  editor or redundant preset-input panel. Preserve the existing physical port
  menu for one-off switching.

- [x] **Monitor control paths, defaults and fresh profile detection.** Control
  choices are scoped to the physical monitor and show computer/port labels;
  protocol overrides retain a separately recorded default. Monitor setup can
  request fresh local/remote detection and apply verified profiles or reported
  ports without replacing concurrent edits. Known firmware families without
  verified input mappings are not presented as guessed profiles. Fresh reads
  already skipped unchanged preset inputs; 13 production-policy checks now
  protect that behavior, including no write or settling delay. Included in
  2.0.115; see MONITOR-CONTROL-AND-DETECTION-2.0.md.

- [x] **Direct Desk preset choices and attached cable connectors.** Half-circle
  sockets sit on device edges with hover feedback. Occupied-input drags pick up
  the existing cable and commit atomically or cancel unchanged. Visible choices
  above sockets select the editing preset; highlighted wires/computers and preset
  numbers show its routes. Unchanged excludes a monitor from switching and shared
  input. Preset attention stays on the preset card; both Add controls are inside
  the canvas. See DESK-DIRECT-PRESETS-2.0.md. Installed in 2.0.114; manual acceptance
  remains, and both Macs need the new version for partial-preset execution.

- [x] **Settings consolidation and setup readiness.** Sidebar status icons,
  anchored permission disclosures, one Hotkeys page, inline Desk/preset names,
  removed Scrolling/Displays/Desk-settings wrapper pages, and plural Displays
  menu heading. Isolated source/native-control checks pass; installation recorded above.
- [x] **External Num Lock navigation.** Default off; per-identified-external-device
  Num Lock/Clear toggle, balanced repeats/releases across preference changes,
  native operators/number-mode punctuation, unknown/built-in passthrough. Needs
  matching input helper. Physical keyboard and LED behavior remain QA; Perch
  does not synchronize hardware LEDs or promise Windows Insert behavior in every app.
- [x] **Physical panel estimates and wire layout.** Reported physical millimetres
  remain stored. Diagonal inches uses detected native mode/reported panel ratio;
  manual ratio is fallback only. Existing exact dimensions are not overwritten
  by discovery. Saved wires use live layout anchors; active wire targets refresh
  after layout/scrolling and membership/connector changes.

- [x] **Distinct appearance compositions and broader palettes.** Perch original,
  Quiet, Signal, Soft tiles, Outline, Ribbon and Horizon differ in geometry, fill, borders,
  spacing and typography. Palettes are independently selectable: Rainbow, Graphite,
  Coast, Dusk, Woodland, Mineral, Jewel and Sorbet. Only Coast deliberately repeats
  three hues; new color ranges assign nine section colors. Source after 2.0.106,
  not installed; visual acceptance remains pending while Desk is manually tested.

- [x] **Appearance preview order.** Compact samples now use the first four main-
  menu sections: System, Agent Kill Switch, Display, Audio. Source follow-up after
  2.0.106; not installed.

- [x] **Running version in the menu.** The Perch section title includes the cached
  running version, shared with About. Its
  canonical section identity keeps the existing palette/icon/group behavior.
  About also describes the current Desk/input and local Mac features, with one
  restrained brand line. Installed in 2.0.106; compile checked, visual acceptance deferred during manual Desk testing.

- [x] **Desk screen-details grouping.** One subtle theme-adaptive background and
  thin border surrounds the details panel. Expanded connection editors retain
  stronger emphasis; the fixed content width and overlay scrollbar are unchanged.
  Installed in 2.0.106; compile checked, visual acceptance deferred during manual Desk testing.

- [x] **Perch countdown.** Manual +/− five-minute adjustments, shared 20-minute
  remaining-time cap, configurable Ctrl–Opt–Cmd +/− shortcuts, repeat filtering,
  helper/watchdog enforcement, frozen finished overlay after lid opening, and
  fresh five-minute restart. Power changes preserve the deadline. The ordinary
  one-minute undocking grace stays unchanged. Expected completion is log-only.
  App installed in 2.0.106; requires coordinated helper protocol/version 3 update.
  See LID-COUNTDOWN-2.0.md for acceptance and limits.
- [x] **Appearance presets and separate light/dark menus.** Exact Perch original,
  Graphite/Coast/Dusk options, named saved pairs, clickable Light/Dark previews,
  Edit both with mixed values and property-only changes, optional System title and no icon indentation when icons are hidden.
- [x] **Desk fits smaller windows.** Remove the minimum canvas scale and excessive
  page width; fit all physical screens while preserving arrangement and inverse
  drag coordinates. Compact screens retain selection, tooltips and context actions.

- [x] **One home for setup and recovery.** Permissions, background-helper repair,
  lid-helper maintenance and collector setup are grouped beneath Setup. Keyboard,
  scrolling, sharing, sleep and agent pages link directly to those stages, without
  embedding duplicate setup controls. Everyday choices stay with their topics.
  Setup stages preserve one checklist and its return path. All six stages and the
  Keep awake/agent repair links passed native clicks; 23/23 isolated suites passed.
  The final helper-success color regression is checked separately. Source is
  prepared in 2.0.98, not installed. See SETUP-CONSOLIDATION-2.0.md.

1. [x] **Persistent Settings navigation (build 82).** One window with a left
   category list, direct access to stable pages, Setup & status as home, stable
   geometry, keyboard navigation and explicit draft discard. Tests and operational
   confirmations retain their own interaction scope. See SETTINGS-SIDEBAR-82.md.
2. [x] **Sparkle updater integration.** Pinned 2.9.6, signed feed/archive/identity,
   Updates sidebar, saved checking preference, native installation, exact-identity
   lid handoff and visible failure/retry. Real signed disposable installation and
   mock handoff/retry passed. Public signing/hosting and live acceptance remain
   below. SPARKLE-REVIEW.md; DISTRIBUTION.md.
3. [x] **Coordinated Perch KVM implementation, replacing monitor cycling.** Support named groups
   of 2–16 computers; pairing authorizes individual membership. One intuitive
   group setup is editable from any member and stays synchronized, including
   monitor identities, mappings, arrangements and shared shortcuts. Up to three
   presets (default Ctrl–Opt–Cmd–F1/F2/F3), physical layout including rotation,
   and pointer-boundary handoff independent of input-device attachment. Handle
   offline catch-up, concurrent edits, revocation and per-host prerequisites. Monitor-only grouping, authenticated synchronization and real preset switching
   preceded the 2.0 input implementation. Support hotkeys,
   optional same-keyboard host-button detection, one monitor, either/both of two,
   and mixed arrangements, with up to 16 distinct physical monitors per group.
   Establish shared physical identity across computers using serial/model
   evidence and visual confirmation when ambiguous; retain per-host input maps.
   Track observed versus requested input; handle competing
   requests, sleeping peers and partial failures. No legacy migration is required.
   Preserve the monitor profile/API/protocol library and use it to replace the old monitor pages, switching groups, cycling shortcuts and guidance
   with one Desk workflow, reusing low-level monitor transports. Detailed order: KVM-PLAN.md.
   **Monitor-only milestone implemented in 1.2.87:** mutual TLS discovery/joining,
   two-sided approval, pinned membership, durable signed synchronization, offline
   conflict recovery and revocation; real monitor adapters, two-phase reservations,
   mapped-peer fallback and readback; production Desk/sidebar/menu integration.
   Matching remains explicit: displays with identical specs are never auto-merged.
   Strong-serial suggestions now supplement manual shared-screen confirmation;
   weak or conflicting identity still requires explicit matching. See KVM-LIVE-REVIEW.md for evidence limits.
   **2.0 implementation:** opt-in session input routing, shared keyboard host
   following with explicit per-host attachment confirmation, three-computer
   pointer traversal, fresh input readback, native event construction, local
   recovery, and strong-serial monitor suggestions. Sixteen real TLS fixture
   members exercise synchronization and routing. See RELEASE-2.0.md for limits.
   Secure-entry/locked-session input is not supported by this event-tap adapter;
   a local keyboard is required. Physical latency, lock/unlock, real mouse/button
   behavior and host-button observations remain QA gates, not passed tests.
4. [x] **Menu Appearance (1.2.87).** Immediate-save rainbow and separate System
   controls for border sides/scope/thickness/intensity, colored or grey backgrounds,
   title/full/none highlights, corner radius, title tint/icons and spacing.
   Includes shared-renderer preview, style presets and Restore defaults. Native
   checkbox changes, independent System values, scrolling and Restore passed.
5. [x] **Production Sparkle release feed.** Public key, stable HTTPS feed and
   signed/notarized release artifacts are configured and published for 2.0.94.
   Anonymous downloads, checksums and the public feed were verified. Real updater
   installation/restart and failure recovery remain QA below.

## QA — concrete integration checks, ordered by prerequisites

General UI/UX refinement is permanently outside release QA pass/fail gates at
Scott's request. Do not recreate a broad "accept all settings/appearance" gate.
Concrete functional defects remain defects. Older dated UI acceptance notes are
historical evidence, not additional open release requirements.

1. [ ] **Two-Mac Desk and desktop handoff.** Both current apps/helpers; joining,
   reconnect/conflicts, actual monitor identification, verified input switching,
   partial failures and manual changes. Accept automatic desktop removal/return,
   unplug/replug and guardian relaunch. A real two-process recovery test restored
   the secondary LG's original mode and position. Unknown LG readback remains a
   defect above, not a successful handoff. See DESKTOP-PARTICIPATION-GAP-2.0.md.
2. [ ] **Two-Mac shared input.** Actual boundary crossing, keyboard/mouse computer
   buttons, first key, modifiers/drag/scroll, rotation/scaling, lost access,
   lock/unlock and emergency return. Secure entry remains local. TLS and
   16-peer fixtures pass; they do not simulate physical receiver behavior.
3. [ ] **Physical helper integration.** External Num Lock; countdown hotkeys and
   helper event delivery; real sleep/wake, independent recovery and reboot.
   Complete the queued helper-version-4 update first, including its new protected
   replacement/timeout/reboot recovery path. Do not repeat the
   exhaustive virtual-time policy matrix or previously accepted unrelated fixes.
4. [ ] **Protected-session update continuity.** Real active lid deadline/identity
   handoff, permissions, interrupted/expired transfer and helper mismatch; include
   the administrator-authorized closed-lid helper replacement and its independent guard.
   Signed isolated Sparkle cancellation/corruption/retry/relaunch scenarios pass
   with injected lid state. See AUTOMATED-QA-2.0.120.md.
5. [ ] **Performance and collector lifecycle.** Controlled idle/open-menu/input/
   process-burst workloads, complete helper/collector CPU accounting, and collector
   restart/reboot attribution. The current collector is installed, byte-for-byte
   executable-matched and delivering healthy events. Bounded 16-peer endurance
   and passive sampling pass; sustained physical workloads remain.
6. [ ] **Clean account lifecycle.** Fresh grants, startup, helpers, real install,
   update, rollback and uninstall in a disposable account/Mac. Dependency repair,
   source builds, bundle/rpath and packaging fixtures pass; existing live grants
   do not establish clean-install behavior.
7. [ ] **Destructive actions in a disposable environment only.** Live Panic and
   privacy resets remain outside this task's authorization.

## Release — signing, packaging and distribution

1. [x] **Public signing identity.** Developer ID Application for team S42F8BV6J2
   is available and a hardened, timestamped release build succeeds. New publisher
   helper compatibility is explicit; no development-certificate migration.
2. [x] **Distribution build pipeline.** Developer ID build, production Sparkle
   Keychain key/config, branded DMG, signing, notarization submission/stapling,
   archive/feed verification and draft-to-public GitHub publishing are implemented.
   Apple notarization credentials (Keychain profile Perch) were validated on
   September 10; the 2.0.94 app was accepted, stapled and passed Gatekeeper
   assessment (Notarized Developer ID), and was installed in /Applications at that release. The
   DMG is accepted/stapled, and the signed Sparkle ZIP/appcast are published.
   Anonymous public downloads/checksums and the stable feed passed verification.
   The top-level `./release.sh --output FOLDER --publish` prepares its Python
   tooling and delegates the full resumable flow to Tools/release-all.py. Real update/restart
   acceptance remains QA.
   Direct distribution currently targets Apple silicon/macOS 26+. The verified
   2.0.151 release is public; Homebrew tap `itscool/tap` carries the matching
   cask. See Release/README.md.
3. [x] **Dependency and catalog release review.** Audit completed September 10;
   missing BoringSSL/MSI notices fixed, NEC attribution added, catalog provenance
   and maintenance documented, and 22 bundled resources checked automatically.
   Scott approved retaining and distributing the LG firmware-family table on
   September 10. Publication checks bind that decision to the exact resource
   hash; this does not claim legal clearance. See Release/DEPENDENCY-REVIEW.md.
4. [ ] **Release QA: clean install and lifecycle.** Clean Mac/account grants,
   helpers/collector, login startup, upgrade, rollback and uninstall; no reliance
   on this development Mac's grants/jobs. Verify Gatekeeper and supported systems.
5. [x] **2.0.151 release and Homebrew cask.** The signed, notarized and stapled
   DMG/ZIP/appcast/checksum set is published at GitHub v2.0.151. The matching
   cask is published in `itscool/homebrew-tap` and passes Homebrew style/fetch
   checks. Native hardware acceptance remains open in QA; the public release was
   explicitly authorized before those tests were complete.
6. [x] **Publish with explicit approval.** Scott explicitly authorized cutting
   this release on September 14, including notarization, GitHub publication and
   the Homebrew tap. Future releases still require their own explicit approval.

Installation experience: prepare a branded DMG with an obvious app-to-Applications
layout, then the existing Setup & status first-launch journey. Ask for feature
permissions in context. Developer ID Application covers app/DMG signing; a future
PKG wizard additionally needs Developer ID Installer (not currently available).
A PKG for initial helper installation/repair remains a proposal, not implemented
or required by the current distribution plan. Verify fresh install, first
launch, existing-install replacement and uninstall/recovery as one journey.

## Backlog — optional future work, outside current release gates

- [ ] **Shared KVM clipboard and file transfer.** Copy/paste plain and rich text,
  images and files between explicitly trusted Desk members. All payload types
  use bounded chunked transfers, compression before encryption when beneficial,
  and authenticated encryption. Derive a separate per-chunk key from fresh
  authenticated transfer/session secrets using a reviewed KDF (e.g. HKDF,
  https://www.rfc-editor.org/rfc/rfc5869); bind transfer ID, direction, chunk
  index, lengths and format into authenticated context, with safe unique nonces.
  Use an established cipher/library, not a different homemade algorithm per
  chunk. Peers negotiate the same versioned format, authenticate the complete
  manifest and reassembled content, and reject corruption, replay, missing or
  reordered chunks. Include cancellation/resume, size/decompression limits,
  bounded memory, cleanup and explicit trust/sharing controls. Keep contents
  and filenames out of logs and expose unobtrusive progress for larger transfers.
  Encrypt clipboard type, filename and other application metadata inside a
  uniform transfer envelope so packet contents do not identify text/image/file.
  Assess bounded padding/batching for size/timing leakage, without promising
  invisible traffic. Nearby discovery (Bluetooth/peer-to-peer Wi-Fi where
  supported) may bootstrap an authenticated out-of-band pairing/fingerprint
  check for the main network channel. Do not broadcast encryption secrets in
  discovery advertisements. Use authenticated ephemeral key agreement and
  forward secrecy; a network transcript alone must not reveal content keys.
  Explore genuinely independent transports (LAN/routed network plus nearby
  Bluetooth/peer-to-peer Wi-Fi), including an optional split-key/secret-sharing
  or encrypted-fragment scheme whose reconstruction needs both channels. Define
  the single-channel observer threat model, fallback when one transport vanishes,
  fail-closed behavior for a mode requiring both, and limits if both channels or
  an endpoint are compromised. Evaluate established constructions rather than
  inventing byte-omission cryptography; multiple ports on one network do not count
  as independent paths. This is research, not a promised security guarantee.
  Let users choose manual verification or automatic pairing. Define what supplies
  identity assurance in automatic mode (existing trust/account credentials or
  explicitly unverified first contact), show verified/unverified state honestly,
  and never label unauthenticated nearby discovery as verified. Existing trusted
  peers should reconnect without repeated manual codes.
  Nearby proximity alone is not authentication. Review compression
  side channels and whether padding is warranted before implementing the protocol.

- [ ] **Multiple saved Desk groups for traveling computers.** A Mac may belong to
  different groups at Home, Work or other places and return without re-pairing.
  Preserve separate membership/trust, monitors, connections, layouts, presets and
  synchronization history for each group. Provide an obvious active-group switch;
  familiar authenticated peers/displays may suggest the relevant group, with a
  clear choice when both are reachable or the location is ambiguous. Network name
  alone must not grant trust. Stop input sharing and release old-group control
  before activating another group; offline edits must stay with their own group.
  Define behavior when several members travel, a member is revoked at one place,
  or both groups are reachable through routed networks/VPNs. First establish the
  multi-group model and intuitive switching flow; automatic selection is optional.

- [ ] **Laptop display participation in Desk topology.** Decide how a MacBook's
  built-in panel appears alongside shared external monitors, including mirrored
  mode, clamshell mode, lid transitions, sleep/wake and a laptop moving between
  Desk groups. Keep the internal panel scoped to its owning Mac unless an
  explicit, supported handoff is defined; never infer that a closed or missing
  panel is an available remote screen. Make its geometry and availability clear
  in presets without letting it destabilize external monitor routing.

1. [ ] **Direct process events.** Investigate a minimal native Endpoint Security
   collector replacing eslogger. Requires Apple's restricted Endpoint Security
   entitlement, separate from user-granted Full Disk Access. EVENT-COLLECTOR.md.
2. [ ] **Native lid research.** Find a supported third-party assertion that
   prevents closed-lid sleep on battery and automatically expires. Identified
   private options require Apple-internal power entitlements; Endpoint Security
   approval does not grant them. Optional simplification of helper/watchdog
   recovery; current guarded implementation still requires QA above.
3. [ ] **Thermal alerts.** Notify on high macOS thermal pressure using the public
   API already read by Perch. Define useful thresholds and quiet notification
   behavior. No special Apple feature entitlement is needed.
4. [ ] **Temperature readings.** Find a reliable CPU/GPU temperature sensor source
   and hardware coverage before displaying degrees. Separate from thermal alerts;
   do not infer numerical temperatures from qualitative pressure.
5. [ ] **Swap-rate metrics.** Show how quickly macOS swaps memory, with clear units
   and sampling semantics, distinct from current swap usage.

6. [ ] **Windows and Linux KVM members.** Extend Perch groups to mixed operating
   systems. Keep group membership, authentication and handoff messages portable;
   Apple peer-to-peer discovery is an optional Mac transport. Implement native
   input capture/injection and monitor control per platform, with suitable
   permissions, discovery/connectivity alternatives and mixed-platform QA.

7. [ ] **VM adapters.** Treat virtual machines as workspace destinations alongside
   physical computers. Choose the initial hypervisor (Parallels, Fusion or UTM)
   with the user before implementing discovery, console selection and input
   routing. Preserve native guest input ownership and handle stopped/locked guests
   explicitly. Deferred by the user; not part of this release.

## Completed evidence and ongoing maintenance

Build 81's 22/22 isolated suites passed; its production build was warning-free.
Build 82 evidence is recorded in SETTINGS-SIDEBAR-82.md. Version 1.2.84 passed
23/23 isolated suites; Desk integration also passed 23/23 suites, 66 portable
KVM checks, 26 model journeys and real TLS/monitor-coordinator fixtures; Sparkle fixture evidence is in SPARKLE-REVIEW.md. Whole-app review fixes,
local replacement detection/restart and keyboard/accessibility implementation
are complete at their stated boundaries; pending QA above remains explicit.

User-confirmed: flicker resolved; CPU colors correct; password entry works;
physical external keyboard behavior works; original Back/menu interaction fixes
accepted on 77. External Fn access recovered without grant changes. Quit/Command-Q
has recorded installed dispatch evidence; shortcut detection and Add app/executable
work. Existing shortcuts are preserved; new installs default to Ctrl–Opt–Cmd–Esc.

Continue updating the settings-flow skill for confirmed lessons; review the agent
catalog monthly against official sources while preserving user choices and
reviewing changed matches. Commit and push completed work. No uncoordinated live
permission reset, Panic, hardware change, sleep/reboot/failure injection or public
publication is authorized by this checklist.
