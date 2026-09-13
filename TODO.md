# Perch work checklist

2.0 development, September 13, 2026. Developer ID 2.0.119 is installed on disk
in /Applications. The user's existing process was left running; Scott can
restart to load 2.0.119. The previous bundle is
retained at /Applications/.perch-previous-kqezxl6w/Perch.app.
Public/notarized remains 2.0.94; 2.0.119 is not notarized or published. The matching
input helper is required for Num Lock navigation; coordinated lid-helper/protocol 3
maintenance also remains. No helper, permission or hardware changes were made.
Dated installation statements below are historical checkpoints. Categories are
known defects, features, QA, release and backlog; each is ordered independently.
This supersedes stale open-item wording in dated review checkpoints.

## Known defects — fix before shipping; target zero

Sidebar readiness indicators and the clipped Desk inspector heading are fixed in
installed candidate 2.0.118. Desk preset membership/use and card/name affordances are
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

- [ ] **Windows remain on a screen handed to another computer.** Scott reports
  the losing Mac still keeps windows on the switched monitor. Perch changes
  monitor input and tracks readback, but has no desktop-participation handoff.
  A monitor may remain logically connected after changing input; waiting for a
  macOS disconnect event cannot solve that case. Investigate reversible software
  disconnect/reconnect tied to confirmed ownership, saved display configuration,
  last-visible-screen and closed-lid behavior, failed/partial switches, app crash,
  restart and network recovery. Preserve a control path for switching back. Do
  not introduce untested display disabling or bulk window movement. See
  DESKTOP-PARTICIPATION-GAP-2.0.md. This is not fixed in 2.0.116.

- [ ] **Repeated Desk disconnections between the real Macs.** Scott reports one
  Mac repeatedly failing its Desk connection. Read-only logs from local PID 98528
  on September 13 confirm 96 ready transitions in four minutes, peer resets,
  nearby-path timeouts and some TLS session closures. These logs establish real
  churn, not its root cause. Scott later reports the connection suddenly working
  better. Pairing lifecycle and redundant-route/error recovery improved between
  builds 106 and 110, and build 96 fixed synchronization stalls. These may explain
  improvement after upgrading, but no root cause for the reported resets has been
  established. Build 119 adds targeted retry and current-state error recovery. Continue with
  the affected Mac's exact error/recovery behavior;
  investigate lifecycle/reconnect/trust behavior without resetting membership,
  permissions or interrupting the user's testing. Loopback stability does not
  close this real-network defect. 2.0.115 does not claim to fix it.

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

- [ ] **Scott’s LG 27UP850-W / 27UP850K-W automatic identification.** The exact
  27UP850-W match now survives discovery into setup; guessed ports and swallowed
  inspection errors are fixed. The actual monitor's failed recognition still
  needs its reported identity/firmware/read result. No verified K-W-specific
  profile exists in the catalog; do not silently substitute the W variant.

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

## QA — implementation acceptance, with defects returned to the first section

- [ ] **2.0.119 recovery and device following, on both updated Macs.** Verify
  fresh armed lid status, real stopped/error/update states, named disconnected
  coordinator and conflicting edits, refreshed readiness without automatic
  capture, per-screen input checks/retries and recovery after fresh observations.
  Follow the illustrated keyboard and mouse setup using actual host buttons;
  cover Bluetooth and USB receivers, first input after a switch and safe local
  recovery. Check stable preset-card heights, In use versus editing, full card
  click areas and separate pencil/Play/port hover. Automated TLS/state and
  offscreen rendering checks pass; this does not close physical-network defects.

- [ ] **2.0.116 Desk sharing, port menu and lid rows:** on both updated Macs,
  enable sharing from Desk, confirm readiness, choose a screen and start control;
  cross an adjoining edge and recover with Ctrl–Opt–Esc. Check optional keyboard
  matching from either Mac. Verify one-off port switching leaves saved presets
  intact. In Keep awake, click Lid activity and Lid protection setup after Resume,
  including a smaller Settings window and scrolling to the last row. No live
  clicks or hardware operations were used for these source changes.

- [ ] **2.0.115 monitor setup:** verify computer/port control choices and saved
  protocol default labels; run Detect input profile locally and through another
  Mac on the same build. Exercise unavailable display, unknown profile, timeout,
  and concurrent edits without losing prior working settings. Native and remote
  callback acceptance remains pending; pure policy and offscreen checks pass.

- [ ] **Direct Desk preset and connector acceptance.** Actual SwiftUI body hit
  regions, hover, sockets versus input choices, rewiring/cancel, screen exclusion,
  selected-route emphasis, small windows/overflow, resize and peer edits. Native
  socket dispatch, 24 preset/subset combinations, 105 portable KVM checks and real
  TLS loopback/16-peer tests pass with injected hardware. The current real-network
  disconnection report remains a known defect above.

- [ ] **Latest settings, keypad and geometry acceptance.** Confirm sidebar icons,
  new Hotkeys and inline-name routes, stable permission disclosures, and wire
  endpoints after resize/scroll/peer edits. Enter 27/32-inch diagonal on the real
  panels; check automatically detected ratio and rotation. Update the matching
  input helper before testing Num Lock navigation, two external keyboards and
  physical repeats/modifiers; no permission/helper changes were made by this task.

- [ ] **New countdown integration and appearance acceptance.** App 2.0.106 is installed;
  complete coordinated helper/protocol 3 maintenance. Check physical configurable
  +/− shortcuts, actual helper/watchdog deadline delivery and return to normal
  protection; policy combinations and timing are already tested with virtual time.
  Cancel → Finished 0:00 and selective Light/Dark preview/batch editing passed
  native fixtures. Check overlay behavior across actual lock/wake/restart, and
  keyboard/VoiceOver interaction with previews, mixed values and preset management.
  Do not repeat all unit-test durations physically. See LID-COUNTDOWN-2.0.md.

- [ ] **Setup recovery acceptance before the next release.** Source fixes cover
  all seven review findings plus the lid-menu setup dead end. The ownership gate
  and isolated native regression suites passed under AGENT MODE. Real checklist
  navigation, Back to setup, picker return and queued-update warning rendering
  passed. Remaining: real permission recovery,
  menu/window return, repeated input setup and explicit lid helper setup/resume.
  Check contextual Back to setup, ordinary sidebar navigation without Close,
  and return from nested repair failures.
  Installed/public 2.0.94 still contains the defects. Evidence and scope:
  SETUP-REVIEW-2.0.94.md.

- [ ] **Full Settings correction acceptance.** The compiled native fixture and
  bounded child journeys passed under AGENT MODE. Remaining real routes: shortcut
  collision/replacement, app add/remove failures, completed layout → next keyboard,
  Desk names/codes and incoming edits/conflict choice, both new sidebar pages,
  Ready → lost permission recovery, and Appearance inactive controls. The pure
  draft/conflict models, source gate, picker cancellation/reopen, connection-code
  validation/save/reopen and Desk child close/Escape/sidebar return passed.
  Hardware/access transitions and broader production journeys remain. See the
  full review ledger and AUTOMATED-QA-2.0.96.md.


1. [ ] **Accept the latest release candidate on both Macs.** Check persistent navigation, direct menu
   entry, same-category return from children, validation/discard, Back/Close,
   small-screen scrolling, keyboard focus and sidebar behavior during operations.
   Check the new tooltip content (78+) and shared Esc labels. The original Back,
   tooltip-ownership and flicker fixes remain accepted; do not reopen without a
   new failure. The local replacement is recorded separately in RELEASE-1.2.md. Desk child Close/Escape, immediate name saving, preset Play with injected monitor commands and Appearance controls were exercised; broader journeys remain.
2. [ ] **First use and access repair.** Blocked-access startup notice,
   already-enabled recovery, scoped Automation errors and helper-specific guidance;
   Setup & status must agree with feature pages. Normal launch and Restart already
   restored keyboard access. Do not reset live grants to manufacture a failure.
3. [ ] **Local replacement detection and restart notice.** Test actual newer-copy
   replacement, one notice per run, deferral while interacting, dismissal, manual
   restart and failed/partial replacement. Build 80 implementation and isolated
   tests are complete; see APP-REPLACEMENT-REVIEW.md.
4. [ ] **Saved lid intent and wake explanations.** Stopped protection retains the
   choice without silently rearming. Verify Resume, sequence-specific explanation
   only when requested, acknowledgement and View lid activity. Confirm actual
   sleep/wake notification order and the 24-hour/1024-entry log contract.
5. [ ] **Active-session restart and separate helper maintenance.** Successful
   transfer, expired/unclaimed cleanup, unchanged grace deadlines and visible
   queued update/open-lid completion. Inactive restart passed; installation of
   build 77 did not exercise active-session handoff.
6. [ ] **Lid integration edges and recovery.** Pure decision coverage now has
   a headless virtual-clock suite: generated lid/power/authorization sequences,
   exact expiry/stability boundaries, repeated power changes, unknown sensors,
   watchdog, restart and command failures. See LID-POLICY-TESTS.md. Do not repeat
   the unit matrix physically or wait through real durations to test policy.
   Remaining integration checks concern real event delivery/order, independent
   recovery when both supervisors disappear, reboot recovery, actual OS sleep
   and restoration. Powered close/open, short grace/replug, full 60-second expiry,
   menu-process-loss cleanup and explicit disable already have recorded passes.
7. [ ] **Native event-collector acceptance.** Install the current
   launcher through coordinated maintenance; test Full Disk Access attribution,
   event delivery, combined CPU accounting, restart/PID reuse and reboot.
   Only the current fixed launcher is supported. This launcher is separate from
   the optional direct Endpoint Security collector in Backlog.
8. [ ] **Keyboard and spoken VoiceOver acceptance.** Implementation is complete
   for the reviewed settings set, including the new sidebar. Finish spoken
   VoiceOver, standard text-editing shortcuts in the new SwiftUI fields, broader
   production-route/dynamic-list journeys and coordinated OS
   permission/authorization handoffs. See ACCESSIBILITY-REVIEW-81.md and
   SETTINGS-SIDEBAR-82.md. Metadata and harmless-lab input are not full acceptance.
   September 12: real sidebar arrow navigation, Tab focus and Space activation
   passed in the isolated Settings fixture; spoken VoiceOver remains open.
9. [ ] **Performance and memory.** A read-only 30-second installed 1.2.87 baseline
   passed (30/30 healthy, combined app/helpers excluding observer about 1.23% CPU);
   this does not measure the new input adapter. Idle, open menu, input activity, process bursts
   and recovery; wakeups, event backlog, sustained memory growth and combined
   collector CPU. Optimized 16-peer sustained input/edit checks now run without
   native input or hardware, measuring delivery, queue sizes, latency and RSS.
   Five minutes delivered 211,328/211,328 events. A separate run continued input
   after edits stopped; RSS stayed within 32 KiB over the final 90 seconds.
   See AUTOMATED-QA-2.0.96.md; bounded fixture measurements do not establish
   physical network latency, a leak-free lifetime or release-wide cost.
10. [ ] **Sparkle acceptance after implementation.** Signed feed/archive delivery,
    bad signatures, interruption, cancellation, retry, replacement, permission
    continuity, active lid handoff, helper compatibility and external Homebrew
    replacement. See DISTRIBUTION.md for install-on-quit and identity requirements.
    September 12: native cancellation, bad ZIP signature rejection, failed
    simulated handoff and successful retry/replacement/relaunch passed. Physical
    lid transfer and public update permissions remain. A severed download and
    slow-download cancellation retained build 1; retry in /Applications replaced
    it with build 2 and claimed the saved identity. Documents stall diagnosed as
    pending folder access. These are disposable apps with an injected lid client.
11. [ ] **Desk monitor-only acceptance — next.** Join the two real Macs; verify
    cross-Mac edits, restart/reconnect and conflict recovery, identify/match screens,
    map actual ports, and use all presets in both directions. Test one/two screens,
    mixed arrangements, offline control hosts, partial failure and competing
    commands. Test Bonjour/nearby Wi-Fi and explicit routed addresses. Then accept 2.0 keyboard/mouse sharing: Control here, pointer boundary handoff,
    rotation/Retina scaling, separate input hosts, modifiers, buttons/drag/scroll,
    host-selection first key, access loss, lock/unlock and Ctrl–Opt–Esc recovery.
    Local keyboards are required for secure entry. Validate reused DDC/USB MCCS/MSI USB/
    NEC LAN/serial and LG identification on available hardware. Catalog research
    is not certified support. Retired standalone cycling has no separate QA gate.
12. [ ] **Destructive action acceptance in a separately authorized disposable
    environment.** Actual Panic/privacy reset must not target the live workspace.

## Release — signing, packaging and distribution

1. [x] **Public signing identity.** Developer ID Application for team S42F8BV6J2
   is available and a hardened, timestamped release build succeeds. New publisher
   helper compatibility is explicit; no development-certificate migration.
2. [x] **Distribution build pipeline.** Developer ID build, production Sparkle
   Keychain key/config, branded DMG, signing, notarization submission/stapling,
   archive/feed verification and draft-to-public GitHub publishing are implemented.
   Apple notarization credentials (Keychain profile Perch) were validated on
   September 10; the 2.0.94 app was accepted, stapled and passed Gatekeeper
   assessment (Notarized Developer ID), and is installed in /Applications. The
   DMG is accepted/stapled, and the signed Sparkle ZIP/appcast are published.
   Anonymous public downloads/checksums and the stable feed passed verification.
   The top-level `./release.sh --output FOLDER --publish` prepares its Python
   tooling and delegates the full resumable flow to Tools/release-all.py. Real update/restart
   acceptance remains QA.
   Direct distribution currently targets Apple silicon/macOS 26+; Homebrew cask
   draft follows verified public artifacts. See Release/README.md.
3. [x] **Dependency and catalog release review.** Audit completed September 10;
   missing BoringSSL/MSI notices fixed, NEC attribution added, catalog provenance
   and maintenance documented, and 22 bundled resources checked automatically.
   Scott approved retaining and distributing the LG firmware-family table on
   September 10. Publication checks bind that decision to the exact resource
   hash; this does not claim legal clearance. See Release/DEPENDENCY-REVIEW.md.
4. [ ] **Release QA: clean install and lifecycle.** Clean Mac/account grants,
   helpers/collector, login startup, upgrade, rollback and uninstall; no reliance
   on this development Mac's grants/jobs. Verify Gatekeeper and supported systems.
5. [ ] **Next corrected release and optional Homebrew cask.** The
   signed 2.0.119 candidate is prepared and installed locally with a source snapshot and draft notes.
   Notarization, final DMG/ZIP/appcast and checksums follow physical acceptance
   and authorization through the resumable release command. The 2.0.94 public assets
   and checksums are already complete. Homebrew cask preparation remains open.
   Notarization and publication still require their explicit authorization.
6. [ ] **Publish only after explicit approval** of the concrete release, relevant
   QA passing and zero known defects. Commit/push is not public release approval.

Installation experience: prepare a branded DMG with an obvious app-to-Applications
layout, then the existing Setup & status first-launch journey. Ask for feature
permissions in context. Developer ID Application covers app/DMG signing; a future
PKG wizard additionally needs Developer ID Installer. Verify fresh install, first
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
