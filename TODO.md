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

September 14 (evening) audit and repair. Seven parallel audits (transport, protocol and
security, switch state machine, input forwarding, concurrency, UX truthfulness, tests) and
live forensics are recorded in `work/kvm-audit-2026-09-14/`. Root causes found on the live
desk: the 20:49 install deleted the bundle the running Perch executed from (packaging now
keeps `Perch.previous-<version>.app` and never removes a bundle a process runs from);
macOS Local Network privacy restarted every desk flow about every 95 s because the bundle
was replaced ~40 times under a local signing identity (only a stable identity fixes that);
the two Macs ran incompatible builds with no version check, so the older one rejected
history revisions written under a newer validation rule and reconnected every 5 s.
Repairs in the working tree (desk protocol 2, both Macs must run it): versioned hello with a
named refusal; goodbye frames so peers log why a link closed; heads-only sync instead of a
full history replay; semantic rejections no longer close links; per-link liveness, one
dialer per pair, stale routes replaced by new ones, link-local addresses ignored, TCP
keepalive, peer-to-peer only while pairing; runtime stopped on quit with a flushed log.
Input: 3 s lease with 0.5 s heartbeats (survives 400 ms latency and a lost heartbeat in
the suite), the Mac with focus keeps its keys, clicks and cursor native and only reports
its pointer position, focus starts under the hand instead of a screen centre, automatic
starts never follow the editing selection and wait for a settling handoff, coalesced
handoff buffers, tap re-enabled automatically, no HID enumeration in the tap callback,
Perch's own hotkeys never forwarded, scroll phases and wheel notches carried, modifier
state synced on capture changes. Switch: cross-Mac verification actually runs (bounded to
1.5 s), per-route outcomes broadcast so every Mac holds the same optimistic state, a
release no longer orphans an executing lease, unrestorable recovery records are pruned,
display and journal work runs off the main thread with a 2 s away grace, destinations
reconnect their display and answer before the write, reads are generation-fenced.
UI: the Desk header states facts (what has control, what could not be confirmed), an
unconfirmed switch is "Active · unconfirmed" with one "Picture didn't move" undo, a failed
switch has one "Retry the switch", the menu never says Confirmed for an unconfirmed
switch, the Share row opens access setup when access is missing, and the never-mounted
recovery button panel is deleted. `./build.sh --no-bump` builds the same version on every
Mac. Physical two-Mac acceptance remains pending; the other Mac must be rebuilt.

September 15 (early) restructure. The tree was reorganized for maintainability
without behavior changes beyond those named here. `Sources/` is grouped by concern
(`Core`, `Entry`, `Menu`, `Settings`, `Desk`, `Input`, `Lid`, `Agent`, `Update`, `Native`);
tests live in `Tests/` and `Tools/perch_sources.py` resolves basenames for every check
tool. `Core` now holds the single implementations of previously duplicated solutions:
`PerchError`, `Subprocess`, `SecureFile`, `JSONStore`, `MainTimer`, `MonotonicClock`,
`Awake`, `Shortcut`/`HotKey`/`ShortcutRegistry` (one Carbon registrar with transactional
registration and held-key filtering; four shortcut types and three hand-rolled conflict
checks retired; wire and defaults formats unchanged), `AccessCheck`, `AdminShell` (one
quoter, one privileged-script escaper; two callers had not escaped newlines),
`CodeIdentity`, `DisplayIdentity`, `HIDDevices`/`HIDAttachmentObserver` (three copies of
the IOKit notification dance, one of which could deliver a callback after teardown),
`LaunchdJob` (a hung launchctl in lid maintenance now times out). The legacy monitor
stack (MonitorGroups/MonitorInputs UI, probe and tests) is deleted with its nine UI routes;
`main.swift` is a 13-line entry over a `ProcessRole` dispatcher (tested) and four
`AppDelegate` files. The Desk simulation, `KVMHandoff` and the lab-only controls moved
to `Tools/kvm-lab`; the app's Desk views talk to a `DeskBackend` protocol implemented by
`DeskRuntimeBackend`, and no view branches on "is this the demo" any more. The Desk page
was rebuilt (no dead band, wrapping computer cards, readable port chips, inline screen
actions, facts-only status rows). `MenuAppearance` is split into model, store, drawing
and page; settings pages pass a `poll:` to `SettingsWindow.show` and the window owns and
stops the timer (no page keeps its own repeating timer); read-only logs and reports
share `SettingsLogView`/`SettingsLogPage`. Memory leaks fixed: the desk transport's
unused path summary, un-cleared IOKit dispatch queues, orphaned page timers on re-show,
and the Carbon hotkey handler cycle. Stale tools repaired: check-sparkle,
check-setup-layout, check-dialog-ownership, check-shortcut-back, check-menu-tooltips,
check-app-bundle; `Tools/typecheck.sh` type-checks the whole tree in ~45 s without the
build lock. Verified: `./build.sh --no-bump` 2.0.203, `--self-test` 30 PASS, every
headless suite green (kvm 108, desk-network 13, lid-policy, dialog-contract 48 sites,
dialog-ownership incl. window-owned polling, kvm-lab 265, renders for desk default/busy/
empty and appearance, functional host builds). `--settings-self-test` and the functional
run need an AGENT MODE session and were not run. Installed to /Applications/Perch.app
(2.0.203, Developer ID); the running process is still the 2.0.202 build, executing from
`Perch.previous-2.0.202.app`, which is kept on disk. Committed and pushed to main as d7494cc. Physical two-Mac acceptance still pending.

September 15 (morning) launch repairs and manual Quit. Running the restructured build
exposed three defects, all fixed and covered by self-tests. Quit could hang forever: every
quit path (menu, Reset, update restart) called terminate from inside a main-queue block,
and the deferred reply was queued on that same serial queue; replies now use a run-loop
timer (`TerminationReply`). Helper install raced launchd: `launchctl bootstrap` ran 3 ms
after `bootout`, before launchd removed the old guardian, so the guardian stayed unloaded;
`LaunchdJob.replace(with:)` waits for the unload and retries. The switch from the local
certificate to Developer ID signing made the old helpers reject the new app until they
restarted, and macOS asks once to re-enable Perch under Accessibility (the old grant
belongs to the local certificate). Manual Quit now turns Perch off: when anything is on it
asks once, listing in plain words what stops and what is kept; it ends closed-lid mode,
stops the guardian and input helper and keeps them from starting at login, while an Agent
Kill Switch block stays enforced (Scott's choice). The next launch allows the helpers
again without re-copying the app. Restart for an update and Reset are unchanged. The root
lid helper and event collector stay loaded but no feature depends on them after Quit.
Native click-through of the Quit notice is pending. The Quit build is installed on disk;
the running Perch still executes the earlier 2.0.203 build from
`Perch.previous-2.0.203.app`, so the next Quit and reopen loads it.

September 15 (late morning) regressions and fixes, each pinned by a fast self-test.
Setup & status buttons did nothing and Reset Settings and task pages stopped refreshing:
the window-owned polling change removed the closure that had kept those page objects
alive, so they were freed as soon as they opened. `SettingsWindow.Page.owner` now holds
the page object while it is shown (dialog-ownership suite and
`runSettingsPageLifetimeTests`). Keep awake showed Needs attention because every lid
session ended within seconds to minutes with "Independent watchdog confirmation was
lost": the lid supervisor and its watchdog ran at thread priority 4 (launchd
ProcessType Background), where macOS delays timers by seconds, while they must exchange
leases within two to three seconds. Logs ruled out the clock, file checks, powerd
latency, trust evaluation, the recovery job and child processes. The supervisor job is
now Interactive and both processes leave background throttling at startup; lid helper
version 6 makes installed helpers update, which asks for admin approval once
(`runLidSchedulingTests`). Native acceptance pending: a lid session that stays armed
for an extended period after the helper update.

September 15 (afternoon) focused blind-spot review of the cleanup, three parallel reviewers
plus follow-ups; every fix has a fast headless test (self-test, dialog contract or suites).
Core and entry: the command runner no longer spins the caller's run loop (72 re-entrant
timer callbacks before, 0 after); the launchd unload wait keeps its 5 s deadline; helper
repair retries after a failure (30 s doubling to 10 min, never re-prompting for admin);
Quit stays available while a Settings dialog is open; update restarts and Reset defer
terminate through the run loop (`AppTermination.request()`, the only allowed terminate);
launch allows helpers before checking them. Desk and input: hotkey registration retries
after a failure; preset and sharing shortcut problems show on their own shortcut; a Desk
page without a running desk refuses visibly; Retry repeats the last port switch; Perch's
shortcut releases never reach the other Mac; monitor switches cannot block on the main
thread. Lid and Settings: saved closed-lid protection on external power retries an ended
session after 30 s (at most 3 times, never on battery); lid restart handoff results
arrive inside the terminate loop; failed saves no longer drop a pending sleep notice or
leave a stale countdown. New source guards: every self-shown page is retained, and every
setup stage and sidebar page resolves. Reported and left unchanged: in the worst case a
lid session start can block the supervisor about 2.9 s, but only when both of its system
commands time out, which already fails the start with a visible error.

September 15 (evening) stale permission entries after a publisher change. Perch now
records the publisher it ran under and, when that changes (or is unknown) while
Accessibility or Input Monitoring fails, removes exactly those dead entries for its own
bundle id with `tccutil reset <Service> local.scott.perch`: never All, never global,
never another app, so Local Network, Screen Recording and Full Disk Access grants are
untouched. It runs once per publisher off the main thread at launch; a refused or timed
out removal keeps the retry. Setup & status then explains that macOS needs those
permissions granted again and disappears once they are, since only the person can grant
them. `Sources/Core/PublisherChange.swift`, `Sources/Agent/PermissionRecovery.swift` and
`Tests/PublisherChangeTests.swift` (self-test). Not covered: agent tracking's Full Disk
Access, a separate identity in the system database with its own Setup step. This ships in
the next release; 2.0.204 is already public.

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
  replace generic Repair/Resume. Background-helper maintenance is Setup-owned;
  there is no optional administrator-protection page. If administrator ownership
  ever becomes a product prerequisite, it belongs in the relevant Setup stage.
  Reset Settings owns resets; Login Items approval opens at the failing Start at
  login action.
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
  coalesce while key/button/scroll ordering remains strict. September 14
  evening: the audited causes (version skew with no check, Local Network
  session restarts, deleted running bundle, dead verification path, 1 s lease
  on a blocking main thread, focus re-requests after every handoff) are fixed
  in source and covered headlessly; see the checkpoint above. Complete the
  physical two-Mac edge-crossing, jitter, recovery and readback/control
  investigation with both Macs on desk protocol 2 before closing this defect.
  BetterDisplay remains optional and is not a runtime dependency.


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

Perch 2.0.204 was published on September 15, 2026. Apple accepted the app and
the DMG; the GitHub release, stable Sparkle feed and SHA256SUMS checksums were
verified, and the `itscool/tap` Homebrew cask was updated and verified with
`brew info`. Native acceptance remains open.

Perch 2.0.205 was published on September 16, 2026. Apple accepted the app
(643e64b3-1eaf-4988-9a7c-218320f32858) and the DMG
(f34ceee0-aaae-4824-ab1d-5fa8deefe64a); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance of the Desk pointer fixes on
the physical two-Mac desk is still open.

Perch 2.0.218 was published on September 17, 2026. Apple accepted the app
(4f61cef9-323b-4882-b473-a9402652e6f6) and the DMG
(ed77773e-19e1-47e8-a950-bd37eb1c6da5); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: the one-pointer
desk input and the wiring rules on the live Desk page, on the physical two-Mac
desk.

Perch 2.0.221 was published on September 18, 2026. Apple accepted the app
(838458e1-2017-49f9-9862-e0d8c8637cc6) and the DMG
(5b9d8fc9-ac45-4ba2-ae0e-afea9e029052); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: the pointer
arriving at the edge it crossed, and the preset-scoped wire gestures, on the
live two-Mac desk.

Perch 2.0.225 was published on September 18, 2026. Apple accepted the app
(6a3b0077-2a65-4c21-865e-08d185371807) and the DMG
(a48b8dd3-9a39-462e-a9dc-dae2a6ec834b); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset switching
no longer sticking, the pointer arriving at the edge it crossed in both
directions, the hidden parked cursor, and the wire drag, all on the live two-Mac
desk.

Perch 2.0.251 was published on September 18, 2026. Apple accepted the app
(bf06d0ca-40c2-435e-9643-ce44cc1a8c54) and the DMG
(f62177a3-ce1a-4d8a-8fd5-9a9faaec7f8c); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: screen 1
returning from DisplayPort to USB-C through the Studio's hand-off, and keyboard
and mouse sharing across the two Macs.

Perch 2.0.262 was published on September 18, 2026. Apple accepted the app
(27d0dc15-042a-4726-bb06-1502ebc0b7e1) and the DMG
(d61eaa25-dcf1-4c07-a5c0-1ac1856ba15d); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: the pointer
crossing into the Studio and landing where it crossed, and the hidden cursor
that never flickers, both on the live two-Mac desk.

Perch 2.0.265 was published on September 18, 2026. Apple accepted the app
(66607098-2fd5-4f1d-92ad-08a357883790) and the DMG
(77a13bd9-d51f-491b-b8a9-d08cc3c9e461); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset 2
applying fully after preset 3, with the Studio taking screen 1 back from
DisplayPort, and then pointer sharing across the two Macs.

Perch 2.0.269 was published on September 20, 2026. Apple accepted the app
(4cba4d6c-cea8-4af3-a9ca-5624de5cbe73) and the DMG
(d77a33ed-b8ec-4edf-b452-0757c0d8fd95); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset 3 then
preset 2 applying fully with the Studio switching screen 1 back from
DisplayPort, then pointer sharing across the two Macs, and the new automatic
update check pulling the other Mac along.

Perch 2.0.273 was published on September 21, 2026. Apple accepted the app
(d4a52460-b7d9-468b-a41f-cfc5d3389769) and the DMG
(7d2c998e-a2ba-4a55-a682-617501d837aa); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset 3 then
preset 2 reporting success now that a reclaimed display is waited for, the wire
gestures on the live Desk page, and pointer sharing across the two Macs.

Perch 2.0.278 was published on September 21, 2026. Apple accepted the app
(e28c8ed3-f48e-40f4-b1d2-dbd04f8402a6) and the DMG
(20cf89ce-d58d-4857-b0a5-3dde16a78d6f); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset switching
reporting success on the live two-Mac desk, a Mac with none of its screens in
the preset driving the other Mac, and the automatic update announcement pulling
the Studio along.

Perch 2.0.283 was published on September 21, 2026. Apple accepted the app
(c332d66a-b498-430c-8404-cac0fd925db9) and the DMG
(ec13d65d-0db4-4feb-a638-c8cedb44212f); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. Native acceptance is still open: preset 2
registering as active on the live two-Mac desk now that a screen only one Mac
can see counts as showing it, and pointer sharing across the two Macs after
that.

Perch 2.0.291 was published on September 21, 2026. Apple accepted the app
(02d95e53-e16a-4816-b4ee-4c21303c3da4) and the DMG
(f58ea87e-29ab-4781-b9af-d4f704a15512); the GitHub release, stable Sparkle feed
and SHA256SUMS checksums were verified, and the `itscool/tap` cask was updated
and verified with `brew info`. This release raises the keyboard-and-mouse
sharing version to 2, so both Macs must run it before they will share again.
Native acceptance is still open: typing going where you last clicked across the
two Macs, the steadier pointer over Wi-Fi, and the hidden stopped cursor not
hovering anything underneath it.

Perch 2.0.295 was published on September 21, 2026. Apple accepted the app
(0767bc90-61ec-4783-bcf2-7ca4e32a86f9) and the DMG
(f5318172-e34f-419f-951a-f176648ab083); the GitHub release at v2.0.295, the
stable Sparkle feed and the SHA256SUMS checksums for the DMG, ZIP and appcast
were verified, and the `itscool/tap` cask was updated to 2.0.295 and confirmed
with `brew fetch` and `brew info`. Both Macs need this version, because the
sending Mac stamps each movement and the receiving Mac reads it. The open work
is reading the new pointer measurements from the live two-Mac desk to decide
which half of the input path moves off the main thread.

Perch 2.0.296 was published on September 24, 2026. Apple accepted the app
(81c7cb0d-b433-49e3-ac5f-4a0fe261206c) and the DMG
(613cdd41-af24-4378-906b-ca932a11566f); the GitHub release at v2.0.296, the
stable Sparkle feed and the SHA256SUMS checksums for the DMG, ZIP and appcast
were verified, and the `itscool/tap` cask was updated to 2.0.296 and confirmed
with `brew fetch` and `brew info`. Every Mac on the desk needs this version,
because the Macs stop trading control only once both of them have it. Native
acceptance is still open: re-measuring the pointer on the live two-Mac desk now
that the Macs no longer trade control with each other, reading input.capture,
input.smoothness and input.travel to find whether the remaining ~65 ms
95th-percentile travel variation is the network or the receiving Mac's main
thread.

Perch 2.0.297 was published on September 26, 2026. Apple accepted the app
(13330fc2-4405-488b-b99a-4a3e1834f59e) and the DMG
(e2cdd56f-e80a-497c-be0b-f36289da2eec); the GitHub release at v2.0.297, the
stable Sparkle feed and the SHA256SUMS checksums for the DMG, ZIP and appcast
were verified from the public URLs, and the `itscool/tap` cask was updated to
2.0.297 and confirmed with `brew fetch` and `brew info`. Every Mac on the desk
needs this version, because both ends have to agree before sharing moves onto
the cable. Native acceptance is open for the new wired path specifically: that
pinning the dial to the Thunderbolt bridge actually connects, that the move from
Wi-Fi onto the wire happens exactly once with the desk staying connected across
it, and what unplugging and replugging the cable does. The supporting
measurement is already taken on this desk: the peer handshake over Wi-Fi was
median 16.7 ms, 95th percentile 69.8 ms, worst 101.4 ms, and over Thunderbolt
median 0.9 ms, 95th percentile 1.2 ms, worst 1.3 ms, and Bonjour already
advertises the peer on bridge0 (interface 13) as well as en0.

Installation experience: prepare a branded DMG with an obvious app-to-Applications
layout, then the existing Setup & status first-launch journey. Ask for feature
permissions in context. Developer ID Application covers app/DMG signing; a future
PKG wizard additionally needs Developer ID Installer (not currently available).
A PKG for initial helper installation/repair remains a proposal, not implemented
or required by the current distribution plan. Verify fresh install, first
launch, existing-install replacement and uninstall/recovery as one journey.

## Backlog — optional future work, outside current release gates

- [ ] **Shared clipboard, then file transfer.** Decided with Scott on September
  21, 2026, replacing a single entry that mixed three projects.

  **What it does.** Copy on one Mac of the desk, paste on another. Nothing is
  sent when you copy: the paste asks the Mac that holds the keyboard's last
  copied content for it. Pushing every copy would send far more, far more often,
  than anyone asked for. Only Macs already paired in the desk take part.

  **Stage 1, plain and rich text and images.** They share one path: pasteboard
  data, bounded, chunked, with a size cap and progress for anything large.
  **Stage 2, files**, separately, because its problems are not transfer problems:
  where a received file lands, permissions and sandboxing, partial writes, name
  collisions, resume, and file promises rather than plain data.

  **Transport.** The desk's existing authenticated TLS 1.3 channel with pinned
  peer identities carries it. Add an authenticated manifest over the content so
  reassembly cannot be altered, and reject corruption, replay, reordering and
  missing chunks; negotiate one versioned format and refuse anything else. A
  second encryption layer of per-chunk keys derived with HKDF belongs here only
  if the goal is protection independent of the transport: decide that explicitly
  rather than adding failure modes for their own sake, and if it is adopted, bind
  transfer ID, direction, chunk index, lengths and format into the authenticated
  context with unique nonces, using an established library.

  **Compression before encryption leaks length** (the CRIME family). Compress
  only above a threshold and pad to size buckets; treat that as a rule, not an
  assessment. Keep contents, filenames and types out of logs, and out of what a
  packet's shape reveals: one envelope for every kind.

  **Limits and refusals.** Size caps per kind, decompression limits, bounded
  memory, cancellation, cleanup on failure, rate limiting, and an honest refusal
  when the other Mac says no. Never send anything a password manager marked
  concealed, and never anything transient.

  **Parked, deliberately.** Nearby Bluetooth or peer-to-peer Wi-Fi as a second
  transport, and split-key schemes whose reconstruction needs two channels. That
  is research, it would hold the useful feature hostage, and multiple ports on
  one network are not independent paths. If it is ever revisited: evaluate
  established constructions, define the single-channel observer threat model and
  the fail-closed behaviour, never broadcast secrets in discovery, and never
  label unauthenticated discovery as verified.
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

## Checkpoint: desk input diagnostics and the two-VM verdict (September 16, 2026)

The two-VM lab reached its limit. With a preset genuinely active on both guests
(each display adapter switched to input 17), 200 pointer crossings were attempted
in both directions at four speeds and none arrived; the cursor probe showed the
driving Mac still tracking its own input every time. Typing, chords and repeats
pass, but only ever on one machine, because control never changed hands. The run
cannot say why, and two readings survive it: the lab never granted
`kTCCServicePostEvent`, which alone would keep Perch's tap unhealthy and block
sharing silently; against that, perch-b posted 54 Perch-tagged modifier events in
pairs one session tick apart, which only happens when remote capture changes.
The earlier claim that those 54 events crossed the link is not supported.

Done in response:

- `PerchLog` (Core) records the access-health verdict, every named reason the
  automatic start declines, and each change of which Mac holds control, under
  unified-log subsystem `local.scott.perch`. `note` de-duplicates polled
  verdicts; `record` keeps repeated events, so a collapsing lease is visible.
- `Tools/desk-lab/prepare.py` now grants `kTCCServicePostEvent`, and the lab
  collects Perch's decisions by subsystem predicate instead of grepping for
  "perch", which previously matched Apple's own subsystems.
- `Tests/DeskDiagnosticsTests.swift` pins the flood-prevention and bounding
  behaviour; registered in `--self-test`.

Verification is complete. Xcode 27 arrived that day with its licence unaccepted,
which blocked every build, and the documented Command Line Tools fallback could
not stand in because it ships no SwiftUI macro plugin, so all `@State` failed to
expand. Once the licence was accepted and the active developer directory pointed
back at Xcode, `./build.sh --no-bump` succeeded and `--self-test` passed with 40
PASS lines and no failures, one more suite than before this work.
`Tools/typecheck.sh` and `Tools/check-desk-network.py` both pass. Eight warnings
remain, all in files this work did not touch.

Sharing coverage should now return to the physical two-Mac desk; the lab keeps
what it genuinely earned (link, restart, toggle, install and permission paths).

## Checkpoint: desk cursor handover (September 16, 2026)

Scott reported this from the real two-Mac desk, repeatedly and over a long
period, before it was acted on. Three symptoms: the cursor stayed visible on
the Mac that had just handed control away; it reset rather than continuing
from where it already was, growing more unstable starting with the Mac that
owned it; and control went virtual even when the two Macs shared no desk
space. Three separate causes, all now fixed.

- **Left behind, corrected.** This first fix hid the cursor on every display,
  but Apple's header says the hide call ignores its display argument, so it
  changed nothing. The likely cause is that macOS ignores a background app's
  hide request unless a private window-server setting is set first. Version 1
  below leaves the cursor visible; version 2 adds hiding properly.
- **Resetting.** The hardware cursor was re-placed whenever the focused screen
  changed. That dragged it back while this Mac still had control, including
  when macOS moved it natively between that Mac's own screens. The desk
  position is now the single baseline for a handover: the pointer is placed
  once, when control arrives from the other Mac, and the hardware cursor owns
  itself from then on.
- **Switching mice teleported to the screen centre.** Picking up the mouse
  attached to the other Mac sends a focus request carrying no position, and the
  handler turned a missing position straight into the middle of the target
  screen. Control now continues from where the pointer already is, moved only
  as far as it must to land on the new screen.
- **Perch no longer invents a pointer position at all.** The screen centre is
  gone as a fallback. A first focus uses the asking Mac's own cursor wherever
  it sits on the desk, rather than only when it happened to be on the target
  screen. With no pointer known anywhere, control waits and says so in plain
  terms instead of teleporting the cursor somewhere the person never put it.
  The desk-network harness now supplies a pointer the way the native adapter
  does, because the product no longer makes one up on its behalf.
- **No shared desk space.** Readiness only required the active preset to name
  another Mac, never that two screens actually meet. `KVMEdge.sharesDeskSpace`
  now decides from the monitor arrangement, and `KVMEdge.touching` requires an
  overlapping edge rather than a shared corner. Without one, Perch says so in
  plain terms and leaves the pointer alone.

Verified: `./build.sh --no-bump` clean, `--self-test` 42 PASS and no failures,
`Tools/check-desk-network.py` still passes in full including pointer boundary
handoff and the sixteen-member traversal, and the KVM, native input and
monitor command checks pass. `runDeskSharedSpaceTests` pins the arrangement
rules and `runDeskHandoverTests` pins where control lands on a switch. The cursor behaviour itself still needs acceptance on the physical
two-Mac desk, since no headless test can observe a hardware cursor.

## Checkpoint: local builds keep receiving releases (September 16, 2026)

A Mac testing local builds is now still offered each release. Every build carries
the update feed and public key from Release/config.json. Local builds and releases
share one always-increasing build number through `Tools/build_number.py`:
`./build.sh` records its number in an untracked counter and leaves Info.plist
alone, and a release reserves the next number above the last release, the last
local build and the installed app. `Tools/install-candidate.py` replaces hand-typed
installs; it refuses a build without update settings, signed differently or not
moving forward, and never removes a copy a running Perch uses. The Homebrew cask
is marked `auto_updates`, so a plain `brew upgrade` leaves Perch to its own updater
while `brew upgrade --cask perch` still upgrades it.

Verified: `Tools/check-build-number.py`, `Tools/check-install-candidate.py`,
`Tools/check-app-bundle.py` and the four release checks pass; `./build.sh` made
local build 206 with Info.plist untouched and update settings present;
`--self-test` 42 PASS. Running: Perch 2.0.205, the release. On disk: 2.0.206, the
local build, which takes effect on the next restart. Native acceptance still open:
the next release being offered in-app on this Mac.

## Checkpoint: desk input version 1 (September 16, 2026)

Rebuilt on the design agreed with Scott and the macOS technique Deskflow and Lan
Mouse use: one pointer, owned by the desk coordinator, fed by every keyboard and
mouse in the desk. Version 1 keeps the cursor visible.

- The Mac without the pointer parks its cursor at the centre of the screen it
  left and puts it back after every movement read (`DeskCursorParking`), with
  macOS's post-warp pause shortened. Nothing is detached or hidden. Centre, not
  edge: at an edge macOS clamps movement and every nudge risks bouncing back.
- The Mac showing the pointer adds movement from another Mac to its live cursor,
  and keys, clicks and scrolling land where the cursor really is. Posted movement
  carries its movement values. It reports its live position, so the coordinator
  follows the real cursor.
- Using a device on another Mac never moves control. The follow-device section
  of Desk settings, `KVMKeyboardFollow` and attachment buffering are removed.
- Handoffs finish within a round trip: a peer polls straight after preparing and
  briefly polls fast until the grant arrives, and answered poll challenges are
  discarded so they cannot fill the lease's table. The crossing cooldown now
  ignores only a bounce back into the screen just left, because fast handoffs let
  a quick swipe reach the next edge inside it.
- Smoothness is logged every five seconds while in use: `input.smoothness` on the
  Mac showing the pointer and `input.parking` on the parked Mac.

Verified: `./build.sh` local build 208 with no warnings in changed files;
`--self-test` 43 PASS including `runDeskCursorTests`;
`Tools/check-desk-network.py` 13 PASS, with devices on either Mac feeding the
pointer and a handoff measured at 28 ms on loopback; `Tools/check-kvm.py` pins
the challenge discard; native input, monitor command and app bundle checks pass.
Running: 2.0.206. On disk: 2.0.208, taking effect on the next restart. Still open:
native acceptance on the physical two-Mac desk, and version 2, hiding.

## Checkpoint: desk wiring, clear preset and reset desk (September 17, 2026)

Scott reported new wires not connecting. Cause: a wire drawn to an input no
computer owned saved the preset route, but nothing claimed the input, and wires
only draw for claimed inputs, so it stayed invisible. Rebuilt on his rules
(`DeskWireOutcome`): an unconnected input draws a new wire from either side; a
connected input detaches when dragged and moves to the input it is dropped on;
a drag from a computer always makes a new connection, claiming the input and
replacing another computer's connection and routes on it; either end dropped in
empty space removes the wire. Neither reset existed: each preset now has a
Clear button and the Desk toolbar has Reset desk, both confirmed first. Reset
removes screens, inputs and routes on every Mac, keeps paired Macs and preset
names. Canvas polish: outlines draw inside their frames and screen edges land on
whole points, so selection and touching screens no longer clip outlines.

His extra DisplayPort input is left over from an older setup: adding a screen
with a monitor profile only adds inputs, so a mix of LG and standard input codes
leaves duplicates. Reset desk, or remove the extra input in its port menu.

The Desk profile, control path and wiring suite was never run by any tool; it
is now in `--self-test`, and its desktop ownership test was repaired (the sample
desk's USB-C inputs carry no input code).

Verified: `./build.sh` local build 215; `--self-test` 46 PASS including
`desk wiring rules`; `Tools/kvm-lab/check.py` 268 checks; `render-desk-canvas.py`
native dispatch for drawing, moving and removing wires; `check-kvm.py`,
`check-desk-network.py` and `check-dialog-contract.py` pass. Running: 2.0.208.
On disk: 2.0.215, taking effect on the next restart. Still open: native
acceptance of the wiring on the live Desk page, and MX Keys for Business and MX
Keys Mini profiles, which need each keyboard's product ID from the device.

Follow-up the same day: the extra DisplayPort was a bug. Desk history shows Home
LG New set up with LG codes (HDMI 144/145, DisplayPort 208, USB-C 209), then at
revision 69 switched to the monitor's reported inputs (HDMI 17/18, DisplayPort 1
15, no USB-C) and the standard protocol. Changing a screen's input list only
added and recoded same-name inputs, so it kept `DisplayPort` 208 beside
`DisplayPort 1` 15, and kept the MacBook Pro's USB-C at LG code 209 under the
standard protocol. `DeskMonitorConfiguration.apply` now replaces the list: inputs
carry over by name, or by kind when each side has one ("DisplayPort" to
"DisplayPort 1"), with cables and routes; unused leftovers are removed; a change
of protocol that would strand an input in use is refused, naming it. Pinned by
`runDeskInputListTests`, which replays that history. Build 217: `--self-test` 47
PASS, lab 268, render and `check-kvm.py` pass; on disk 2.0.217, running 2.0.208.
Scott's desk repairs once he chooses Home LG New's LG profile again (all of
27UN850, 27UP850, 40WP95C, 38BR85QC and 45GX950A use those codes).

## Checkpoint: preset-scoped wires, pointer arrival, active vs editing (September 17, 2026)

Scott on 2.0.218: crossing to the other screen sometimes hopped the pointer to
the middle vertically before carrying on. Cause: control can arrive in the same
batch as the movement that caused it, before the cursor update runs, so that
movement was added to this Mac's parked cursor at the screen centre.
`DeskPointerHandover` makes the first event after control arrives continue from
the entry point, and `place` now warps as well as posting, so the next event
reads the placed position instead of the parked one. Pinned in
`runDeskCursorTests`.

Grabbing a wire at a monitor input now changes the preset being edited, as Scott
chose. A cable can only be in one input, so when the wire is dropped on an input
that computer is not already connected to, the cable moves and the presets that
used it follow rather than pointing at an empty input; when it is already
connected there, only the edited preset changes. A wire dropped in empty space
leaves the edited preset, and the cable is unplugged only once no preset uses it.

Active and editing are no longer two colours of the same line: the preset being
edited is the drawn teal line, and what is on the displays now is a green glow
behind the line and its sockets. Purple is retired; both states together read as
a teal line inside a green glow.

Verified: build 220, `--self-test` 47 PASS, lab 268, render, `check-kvm.py`,
`check-desk-network.py`, `check-dialog-contract.py`. Running: 2.0.218. On disk:
2.0.220. Native acceptance of all three on the live two-Mac desk still open.

## Checkpoint: stuck switching, both-direction arrival, hidden parked cursor (September 18, 2026)

Scott on 2.0.221: about half of preset switches stuck on Switching with nothing
he could do. Cause found in the decision log and the code: when a monitor write
fails, the control Mac hands that monitor to another Mac cabled to it and sends
no result of its own; the receiving Mac's handler returned silently whenever it
could not take it (most often an unmatched display, which his desk has), so the
request waited for the 45 s timeout. Repairs: a handover goes only to a Mac whose
cable to that monitor is matched; a Mac that cannot take one always answers with
a named refusal; a handover that is not answered within 20 s fails that screen;
an unanswered request fails after 12 s naming the Macs that did not answer, which
is before anything has been written; the 45 s timeout names the screens it waited
for. `switch.begin`, `switch.finish`, `switch.failed` and `switch.delegate` now
go to the decision log. Pinned in `check-desk-network.swift`.

Pointer arrival was fixed in one direction only, because the Mac whose own
hardware drives the pointer never goes through the delivered-event path. The
session now reports a focus change the instant it happens, so the pointer is
placed before either a delivered event or local hardware moves the parked cursor.

Version 2 of the cursor, as Scott asked: the parked cursor is hidden while the
pointer is on another Mac (`SetsCursorInBackground` then `CGDisplayHideCursor`,
shown again on unpark, balanced and restored if Perch exits), so it no longer
looks like it is hovering over that Mac's controls.

Canvas: a picked-up wire now hangs from the connector of the preset being edited,
so the drag shows the cable in hand instead of disappearing, and the same input's
wires in other presets stay on screen while one is being moved.

Switching to a preset this Mac has no input in was already allowed, and the
two-node harness covers it; readiness only requires the control Macs and the
destinations to be online.

Verified: build 224, `--self-test` 47 PASS, lab 268, render, `check-kvm.py`,
`check-desk-network.py`, `check-dialog-contract.py`. Running: 2.0.221. On disk:
2.0.224. Native acceptance on the live two-Mac desk still open.

## Checkpoint: screen lock reporting (September 18, 2026)

Scott: the other Mac still locks when idle. Measured on this Mac, read-only:
the HID idle clock climbed steadily while untouched and Perch's null-event
signal returned it to zero, so the technique works on macOS 26. On the other Mac
the clock stays under 30 s with Prevent idle lock on, and no configuration
profile carries maxInactivity, idleTime, askForPassword or loginWindowIdleTime,
so its locks are not idle timeouts Perch can hold off and not a profile we can
read. Rather than guess again, `ScreenLockLog` records every lock and unlock with
the facts: how long the Mac had actually been idle, whether that is even long
enough to be an idle lock (under 55 s it is not), whether Prevent idle lock is on
and when it last reported activity or was refused, whether a desk session was
interrupted, and how long the screen stayed locked. `IdleClock` reads the idle
time read-only. Pinned in `runIdleLockWordingTests`. Read it with
`log show --last 2h --info --predicate 'subsystem == "local.scott.perch"'`,
filtering on `screen.`.

Verified: build 226, `--self-test` 47 PASS, `check-dialog-contract.py`,
`check-lid-policy.py`. Running: 2.0.221. On disk: 2.0.226. Open: read the log on
the Mac that locks and name the cause.

## Checkpoint: why sharing will not start (September 18, 2026)

Scott: "kvm not working", and asked whether the desk should carry its own
protocol version instead of forcing app versions to match. It already does:
`KVMDeskProtocol.version` is 2 and is checked in the hello, independently of the
app version, so 2.0.221 and 2.0.225 pair. His block was different, and the log
named it wrongly: with his rebuilt two-screen desk (Home Screen 1 on the MacBook
via USB-C, Home screen 2 on the Studio via HDMI 2, side by side and touching),
the Studio's HDMI 2 cable has no matched display, so that screen is left out of
the arrangement and `sharesDeskSpace` returned false, which reported "these
screens do not sit next to each other" about two screens that are. `KVMEdge`
now returns the actual reason: the screen and Mac whose display is not matched,
a preset that shows one Mac everywhere, or a genuine gap. Pinned in
`runDeskSharedSpaceTests` with his exact desk. Share on this Mac is also off
(`desk.shareOnThisMac` 0), which the log states separately.

Still open, and worth doing: the input session is fenced by
`KVMInputConfiguration.revision`, a hash of the desk configuration, not by a
version. Any change to what goes into that hash between releases stops sharing
silently instead of naming a version mismatch. Give the input session its own
version, carried with the grant, and name a mismatch the way the desk protocol
does.

Verified: build 228, `--self-test` 47 PASS, `check-kvm.py`,
`check-desk-network.py`, kvm-lab 268. Running: 2.0.221. On disk: 2.0.228.

## Checkpoint: matching the cable that is showing (September 18, 2026)

Scott, on his live desk: the Studio really is on Home screen 2's HDMI 2, the
preset switch works and the picture moves, yet Perch kept that cable at "display
matching pending" and refused to share the pointer. Cause: matching compared
what both Macs see (`DeskPendingCableResolver` needs another Mac reporting the
same vendor/model/serial), and two Macs can never see one monitor at the same
time — while it shows HDMI 2 the MacBook's output is gone. So that cable could
never match, whatever he did. `DeskShowingCableResolver` matches from the input
the screen is showing instead: the computer on that input is the one feeding the
screen, so the single display it reports that nothing else uses is that screen.
It never guesses between two, never takes a display another input uses, and
validates before saving. `KVMShowingInput.effective` is now the one rule for
"what is this screen showing", shared by desktop reconciliation and matching.
The port menu also gained "Match this cable's display on <Mac>…", because until
now a connected-but-unmatched cable had no action at all. Pinned in
`runDeskInputListTests`.

Verified: build 230, `--self-test` 47 PASS, `check-kvm.py`,
`check-desk-network.py`, kvm-lab 268, `check-dialog-contract.py`. Running:
2.0.228. On disk: 2.0.230. Next: version the input session and name a mismatch,
as Scott asked, and his preset 3 DisplayPort switch.

## Checkpoint: input version, plain words, per-input command (September 18, 2026)

Sharing now carries its own version (`KVMInputProtocol.version`), separate from
the app version and the desk protocol, as Scott asked. It is part of the
configuration hash, so a change to that recipe is a version difference rather
than a silent mismatch; it rides in every grant, and a grant without one (an
older Perch) reads as version 0 and is refused. Macs announce their version on
connection and every five seconds, and a difference is named on the Mac that
sees it, while the desk, its presets and monitor switching keep working. It
clears itself when the versions agree. Pinned in `check-desk-network.swift` and
`check-kvm.swift`.

Scott: "if a cable is connected, how would a person know it is also unmatched?"
They would not. Matching is now automatic from the showing input, and every
message about it is in plain words: "Perch has not seen this screen from that
Mac yet. Switch to this input once and Perch will pick it up."

His DisplayPort report, with facts from `PerchDisplay` on the Studio: the screen
is an LG UP850K, `lgIdentity` 0xC024, and its capabilities advertise
`60(11 12 0F 00)`, so HDMI 1/2 and DisplayPort answer the standard command,
while USB-C appears only under LG's own command. It also reports no current
input at all, which is why every switch is "accepted without readback". One
command per screen cannot serve both, so `KVMConnection.inputProtocol` now sets
the command for a single input, used by preset and one-off switches, with a
picker in Edit port. Pinned in `runDeskInputListTests`.

Verified: build 233, `--self-test` 47 PASS, `check-kvm.py`,
`check-desk-network.py`, kvm-lab 268, render, `check-dialog-contract.py`.
Running: 2.0.228. On disk: 2.0.241. Open: confirm on the live desk that
DisplayPort switches with the standard command before publishing.

Scott asked for that screen to be set up correctly from the start, as our own
profile beside the ones found online. `catalog/monitor-profiles.json` gains
"LG 27UP850-W · UP850K firmware", confidence `locally-tested`, matched by EDID
product 23741 or the reported model UP850K: HDMI 1 = 17, HDMI 2 = 18,
DisplayPort = 15 on the standard command, USB-C = 209 on LG's own, and readback
recorded as unavailable. Its evidence lines quote the capability string this
desk reported and what was observed. A profile input can now carry its own
command (`MonitorInput.command`), which setting a screen up applies to that
connection, so a fresh setup of this model needs no hand editing. Recorded in
`catalog/HARDWARE-SUPPORT.md` and re-digested in `Release/dependencies.json`.

## Checkpoint: both LG screens proven, lock fix, repeat for unconfirmable monitors (September 18, 2026)

Hardware tests on this desk with `PerchDisplay`, run from the MacBook with Scott
watching: LG's own command switches both screens with LG's documented codes.
Home Screen 1 (UP850K, EDID 23741): DisplayPort 208 moves it off USB-C, after
which the MacBook loses the display entirely and only the Studio can switch it
back. Home screen 2 (UL850, EDID 30471, previously mistaken for a 27UN850):
HDMI 2 145 and USB-C 209 both work from the MacBook, which keeps its USB-C link
while HDMI 2 shows. Neither reports its current input. Both catalog profiles are
now confirmed LG-command profiles matched by EDID product; my earlier "standard
codes" theory was wrong and is gone. Public sources: ddcutil's LG page and
BetterDisplay discussion 2270.

The new write logging found two causes of flaky switching. The desktop recovery
lock was taken non-blocking, so a switch arriving during the once-a-second
display bookkeeping was refused as "busy" and handed to the other Mac; background
callers now wait up to 2 s. And the Studio's hand-off for screen 1 reports
"Command sent" while the panel often ignores it, so a monitor that cannot report
its input now gets the command once more after 1.2 s (never after the lease
ends, never when the monitor reports a different input). Shortcut presses,
refusals and registrations are logged; the preset shortcuts work from the
MacBook's keyboard.

Verified: build 250, `--self-test` 47, `check-monitor-command.py` 16,
`check-kvm.py`, `check-desk-network.py`, kvm-lab 268, `check-dialog-contract.py`.
Running: 2.0.249. On disk: 2.0.250. Open: the Studio needs this build; then 3 → 1
must bring screen 1 back to USB-C, and sharing gets its first fair test.

## Checkpoint: why sharing handed control straight back (September 18, 2026)

With switching working from both Macs, every crossing to the Studio was undone
within 14 ms. Logging every path that ends control (`input.end`) named it: the
Studio itself asked to stop. The desk recorded the Studio's display for Home
screen 2 as `CD3AF695`, and `PerchDisplay list` on the Studio no longer has that
ID, so the Studio could not find the screen control arrived on and gave it back.
Desk history shows these macOS display IDs drifting: `1DAE75B3` was the Studio's
Home LG Old via HDMI 2 at revision 53 and later recorded against Home Screen 1
via DisplayPort. macOS renames displays when a monitor is replugged, switched or
changes mode, and Perch only checked an ID when it first matched it.

Screens now remember what they physically are (`KVMMonitor.identity`: EDID
vendor, model, serial), learned from any Mac that sees the screen under its
recorded ID. Each Mac's display ID is kept as a cache: when a Mac's current list
lacks the recorded ID, `DeskIdentityCableResolver` finds the display with that
identity among its unused displays and updates the record. A screen a Mac cannot
currently see keeps its record, and identical monitors without serials are
never guessed between. Any Mac heals with a peer's reported list, so this Mac
can repair the Studio's stale record before the Studio updates. Pinned in
`runDeskInputListTests` with this desk's shape.

Verified: build 254, `--self-test` 47, `check-kvm.py`, `check-desk-network.py`,
kvm-lab 268, render, `check-dialog-contract.py`. Running: 2.0.253. On disk:
2.0.254. Open: restart here, show preset 2, confirm the Studio's record heals
and the pointer crosses.

## Checkpoint: finding the monitor at the moment of a command (September 18, 2026)

After 2.0.262 the records were right (Home screen 2's HDMI 2 now holds the
Studio's real display `1DAE75B3`), but preset 2 never became active: screen 1,
left on DisplayPort by preset 3, has to be sent back to USB-C by the Studio, and
the Studio's DisplayPort record for it was correctly empty because the Studio
had never reported seeing it. With no candidate the hand-off never happened,
screen 1 failed, and a preset with a failed screen is not active, so sharing
refused on both Macs. The executing Mac now reads its own displays at the moment
of the command (`DeskLiveDisplays`, CoreGraphics in-process) and finds the
monitor by its identity, and a Mac cabled to a monitor with a known identity
can take a hand-off without any recorded display. Pinned in
`runDeskInputListTests` and `check-desk-network.swift`.

Verified: build 263, `--self-test` 47, `check-desk-network.py`,
`check-kvm.py`, kvm-lab 268, `check-dialog-contract.py`,
`check-monitor-command.py`. Running: 2.0.262. On disk: 2.0.263. Needs to reach
the Studio, which is the Mac that takes screen 1 back.

## Checkpoint: end of September 18 — where sharing stands

Switching presets works from both Macs' keyboards. Sharing still does not start,
because preset 2 is never active: every 3 → 2 switch left screen 1 failed. From
the logs on 2.0.265: the MacBook cannot reach screen 1 while it shows
DisplayPort, the hand-off goes to the Studio, and the Studio's write failed with
"Invalid monitor identity" — the monitor tool was handed an empty display,
because the Studio's live lookup at that instant found nothing.

Root of the whole day: the Studio's two display IDs were swapped in the desk.
`CD3AF695` is the Studio's DisplayPort view of Home Screen 1 (LG ULTRAFINE, model
23740 over DisplayPort, 23741 over USB-C, serial 175682), and `1DAE75B3` is its
HDMI view of Home screen 2 through the USB-C-to-HDMI adapter (model 30470 over
HDMI, 30471 over USB-C, serial 353740). The desk had them the other way round.
As of revision 121 all four records are right, repaired by Perch itself: screen 1
DisplayPort = Studio `CD3AF695`, USB-C = MacBook `0A7A7FD4`; screen 2 HDMI 2 =
Studio `1DAE75B3`, USB-C = MacBook `9B219105`.

Later the same evening, Scott: preset 3 → 2 does move screen 1 from DisplayPort
back to USB-C, yet Perch still records it as failed. The log explains it: the
Studio reports screen 1 over DisplayPort correctly (`CD3AF695`, model 23740,
serial 175682), but the Studio's desktop handoff lets go of that display before
the command, believing screen 1 is about to show the MacBook. With the display
gone the Studio cannot command the monitor, and its lookup at command time finds
nothing ("Invalid monitor identity": an empty display reached the monitor tool).
The monitor then loses its DisplayPort signal and LG's automatic input switching
moves it to USB-C about 14 s later (this Mac saw screen 1 return at 16:06:57
after the 16:06:43 command). The command fails, the screen still switches.

Next session, in order:
1. A command for a monitor must first take back any display of that monitor
   this Mac's desktop handoff let go of, found by identity through the recovery
   journal, then look the display up; never after.
2. Never pass an empty display to the monitor tool: decline with what the Mac
   saw, and log the live list it searched.
3. For monitors that cannot report their input, count the destination Mac
   seeing the screen again as confirmation, so a switch finished by the
   monitor's own input switching is not recorded as failed.
4. Then sharing in preset 2, and the version-aware update check so the Studio
   stops needing manual updates.

Running: 2.0.265 on both Macs (this Mac confirmed; the Studio announces sharing
version 1).

## Checkpoint: commanding a screen this Mac let go of (September 20, 2026)

The three repairs for the September 18 diagnosis. A command now runs on the
executing Mac's queue in this order: take back the recorded display, and if the
monitor still cannot be found, take back everything the desktop handoff had let
go of and look again by identity; then, if there is still no display, fail with
what the Mac can actually see instead of handing the monitor tool an empty
identifier ("Invalid monitor identity"). A delegate declines only when it has no
record and no identity to look for.

Scott also asked for the manual update of the other Mac to end. Macs now tell
each other which Perch they run (`DeskDeviceMessage.running`), announced with
each display refresh and answered on first contact. A Mac that hears of a newer
build looks for the published update once per build heard about
(`DeskUpdateNudge`), so a Mac on an unpublished local build never makes the
other check repeatedly, and only published releases are ever installed. Pinned
in `runDeskInputListTests`.

Still open from that diagnosis: counting "the destination Mac sees the screen
again" as confirmation for monitors that cannot report their input, so a switch
finished by the monitor's own input switching is not recorded as failed.

Verified: build 267, `--self-test` 47, `check-kvm.py`, `check-desk-network.py`,
kvm-lab 268, `check-dialog-contract.py`, `check-monitor-command.py`. Running:
2.0.265. On disk: 2.0.267.

## Checkpoint: a display does not come back instantly (September 20, 2026, evening)

Scott moved the Studio's cable for Home screen 2 from the USB-C-to-HDMI adapter
to DisplayPort; Perch re-found that screen by serial on its own (`08E7D12A`), and
both Macs now run 2.0.269 with every record correct. Switching still reported
failure while the picture visibly changed, and Scott named the contradiction:
"the studio tried and DID get the display change even if it was supposedly told
it wasn't there".

Cause: taking a handed-away display back starts driving that output again, and
the monitor switches to it by itself, but macOS does not list the display again
for about a second. Perch resolved and commanded inside that gap, hit a display
that had not finished arriving, and reported "The selected monitor is not
connected to this Mac" — for a switch that had already happened.
`DeskLiveDisplays.waitFor` now waits up to 3 s for the display to appear, before
resolving and before commanding, and logs how long it waited.

Also, because diagnosing this needed commands run on the other Mac: Macs now ask
each other for their recent desk decisions (`DeskDeviceMessage.decisionsRequest`
/ `.decisions`, `PerchLog.recent`), automatically whenever a switch fails and at
most once every 20 s. The other Mac's lines land in this Mac's log under
`from.<Mac name>`, so a desk can be diagnosed from wherever someone is sitting.

Verified: build 271, `--self-test` 47, `check-kvm.py`, `check-desk-network.py`,
kvm-lab 268, `check-dialog-contract.py`. Running: 2.0.269 on both Macs. On disk
here: 2.0.271. Both changes need to reach the Studio.

## Checkpoint: checking what the tool sees, and driving a Mac with no screens (September 21, 2026)

The cross-Mac decision sharing worked first time: the Studio's own lines arrive
in this Mac's log under `from.HQ-KP40Y76PT6`, and they showed the Studio waiting
3.1 s for a display that never came while this Mac's write failed as "not
connected" for a screen it had just listed. Cause: the check and the command
had different views. Perch asked CoreGraphics in this process, then the separate
display tool performed the write with its own enumeration. `DeskLiveDisplays`
now asks the tool itself (`asTool(sees:)`, with the tool reporting each
display's serial), and waits on that same view before resolving and commanding.

Scott: "if i'm on pc 1, and i switch to a preset which is only both pc 2, pc 1
input should still work to solely drive pc 2's displays". `KVMEdge.drivesAnother`
now allows exactly that: a Mac with no screen of its own in the preset keeps
sharing enabled and drives the Mac that is on screen, while the Mac showing
everywhere still gets the honest refusal. Ctrl-Opt-Cmd-Esc remains the way back.
Pinned in `runDeskSharedSpaceTests`.

Verified: build 275, `--self-test` 47, `check-kvm.py`, `check-desk-network.py`,
kvm-lab 268, `check-dialog-contract.py`, `check-monitor-command.py`,
`check-app-bundle.py`. Running: 2.0.273 on both Macs. On disk here: 2.0.275.

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
