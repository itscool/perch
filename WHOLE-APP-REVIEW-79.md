# Whole-app review checkpoint — September 9, 2026

Scope: backlog item 9, on source after build 78. Current release notes were read
first. Build 77 remains installed; build 79 is a prepared candidate. This is a
source, isolated-test and limited native-lab review, not release acceptance.
Findings were reported during the review before their fixes. The established
menu layout and previous user acceptance are retained.

## Prioritized findings

1. **P1 — Launch-job changes could outlive their recovery record. Fixed.**
   The guardian disabled a selected user's launch job before saving its label,
   and ignored a failed save. A crash or storage failure in that gap could leave
   launch eligibility disabled without a record for Resume. Resume also released
   blocking before saving that decision, so restart could restore the older
   locked state. `AgentJobRecovery` now durably reserves recovery before disable,
   saves the unlocked decision before enable, and retains uncertain/failed jobs
   for retry. Failed prerequisite saves issue no external command. Recovery
   errors explain the remaining state; successful retry clears that error.
   Injected-command tests cover ordering, failed saves, interrupted recovery,
   ambiguous command results and partial enable. No live launch job was changed.
2. **P2 — Child dialogs and refreshes lost keyboard focus and text selection.
   Fixed in the shared host.** A hidden native text-field probe reproduced lost
   focus after an alert. The host now remembers focus before taking alert
   ownership, retains existing page controls during refresh, restores selection,
   and matches stable control identifiers when a page is rebuilt. Back does not
   overwrite parent history with a removed child's state. Regression checks cover
   alert return, ordinary child Back, same-view refresh and replacement pages.
3. **P2 — Accessible labels lacked scope, and permission setup had a mouse-only
   drag action. Fixed in the reviewed controls.** Keyboard groups, agent shortcut
   and privacy selectors, monitor/connection/group editors and repeated removal
   buttons now have explicit names and stable identifiers. The permission file
   control accepts Space/Return and an accessibility press to copy its exact path;
   visible instructions explain the system file-picker route. Dragging remains
   available. Tests inject a clipboard sink, so they neither overwrite the live
   clipboard nor grant permissions. These improvements do not establish complete
   keyboard-only or spoken VoiceOver acceptance.
4. **P2 — Collector setup could claim Ready while its installation needed repair
   or a replacement event session was pending. Fixed.** Setup & status and the
   collector page now share a readiness rule: supported installed configuration,
   no pending replacement, fresh helper status, connected recent events and an
   active health check. Tests cover stale/disconnected/repaired/pending states.
   The optional CPU identity upgrade is still distinct from a required repair.
5. **P2 — Custom executable selection bypassed catalog safeguards against shared
   runtimes. Fixed for new selections.** The catalog rejected generic executable
   identities more broadly than the custom picker. Both now use one rule for
   known shells, runtimes and versioned interpreter names. This avoids treating
   unrelated programs using, for example, Ruby or Python as one agent root.
   Existing saved choices remain intact. Tests cover rejected generic names and
   accepted specific agent names. This is a conservative name safeguard, not a
   guarantee that arbitrary custom executables are correctly classified.
6. **P3 — Legacy monitor guidance remains dense. Deferred to KVM replacement.**
   The current monitor page puts lengthy feedback in a small nested scroll area
   and combines input mapping, observed state and cycling options. The text is
   scrollable, but the next step is less discoverable than on the other pages.
   Do not recreate that layout in the coordinated KVM flow. Ordinary selections
   autosave; connection-definition drafts still have a justified Save/Cancel
   transaction. No monitor command or new cycling feature was added in this pass.

## Journey coverage

The construction gate checks all 58 sites in `Tools/dialog-routes.json`. The
following is the broader journey ledger; a construction count is not proof of
58 physically exercised dialogs. Source review included callbacks, persistence,
readiness, exit behavior and the consequences of errors, not only labels.

| Area / entry routes | User journey and behavior reviewed | Evidence / remaining limit |
| --- | --- | --- |
| Settings root and Setup & status | First use, optional versus required setup, missing/stale helpers, feature status, repair and return | Source, setup model cases, light/dark fixtures; clean-account grants remain open |
| Keyboard settings and details | Built-in versus external scope, unavailable/denied/granted access, fresh observations, immediate saves, recheck and recovery | Source, protocol/readiness/menu tests, fixtures; prior physical-key acceptance retained |
| Navigation keys | Learn, successful completion, timeout/cancel, relearn, forget profile, app exceptions, returning to parent | Isolated input/probe/registration and shared-window tests; no live key remapping |
| Input controls / macOS permission handoff | Correct helper identity, missing versus denied access, ready state, explicit repair, drag or keyboard path, return | Source, readiness/focus/accessibility tests, layout measurement; OS grants unchanged |
| Agent Kill Switch / agent editor | Add app/executable, reject broad identities, remove entries, shortcut edit/test/result/Back, saved versus incomplete edits | Catalog tests, production shortcut-flow fixtures and shared host; user accepted original Back fix |
| Recognition and catalog | Import, validation, review suggestions, preserve explicit choices, cancellation and error results | Source and isolated catalog cases; no downloaded catalog or external publication |
| Collector and Maintenance | Missing/repair/receiving/ready, administrator handoff, helper-specific grants, replacement-session wait | Shared readiness cases and rendered pages; native identity migration/FDA acceptance remains item 8 |
| Keep Awake / lid activity | Preference versus active session, paused recovery, explanation eligibility, acknowledgement, logs, queued helper maintenance | Source and injected lifecycle/log tests; real OS sleep/wake order and active restart remain items 5–7 |
| Display inputs / groups / connection editors | Add/remove destinations, member selection, draft validation, autosave boundaries, identify/failure/cancel/results, requested versus observed state | Source, simulated monitor/group tests and renders; physical cycling retired in favor of KVM |
| Privacy/system/settings reset | Distinct scopes, explicit confirmation, partial failures, retry, saved choices and Back | Source and mock executor/storage tests only; destructive end-to-end tests excluded |
| Restart, errors, About and shared alerts/pickers | Pending ownership, cancelled picker, result Back, Escape, completion and usable parent, restart recovery | Isolated workers/handoff tests plus limited real native lab; no live app restart or installation |
| Menu action entry points | Current availability, cached refresh behavior, command dispatch and tooltip ownership/content | Existing menu regression suite passes; build 78 tooltip wording still needs native hover acceptance |

## Security and scope review

Inspected process identity and same-user signal checks, descendant tracking,
launch-job restoration, privacy-reset scope and worker argument handling,
helper IPC identity/size limits, lid helper owner/signature checks, override
journaling, restart code pinning, collector installation boundaries and collector
identity metadata. The recovery ordering issue above was the concrete new P1.
Existing injected tests exercise invalid identities, stale replies, bounded
messages and restart/lease failure paths. Same-user tracking is not a security
boundary against hostile code running as that user, and observed descendants are
not a promise to stop unobserved, remote or root work.

No additional privilege or persistent system setting was introduced. Recovery
persistence adds file/directory synchronization at critical launch-job transitions;
ordinary polling is unchanged. Signed local builds do not establish distribution
readiness, clean-install compatibility, or independent watchdog/reboot acceptance.

The grouping review retained feature choices under their feature, repair under
Maintenance, and Setup & status as the summary. No main-menu redesign, mandatory
wizard or development Updates page was added. Keep system-wide reset scope
explicit. Replace the monitor workflow through the KVM plan rather than building
more standalone cycling controls. Performance measurement and distribution remain
separate backlog tasks, not implied passes from this review.

## Verification and honest limits

- Baseline build-78 isolated run: 19/20. One deferred-menu retry fixture assumed
  a 20 ms main-queue completion; it now waits for a bounded queue marker. No new
  production menu defect was established from that failure.
- Production build 79 compiled without warnings; strict executable/app signatures
  and ZIP integrity/version checks passed. It was packaged, not installed.
- Final updated isolated run: **21/21 suites passed**. This includes new recovery
  tests and hidden focus/accessibility tests. The run used AGENT MODE and isolated
  storage, mock permissions/monitor mutations and injected power operations.
- Harmless native dialog lab, with AGENT MODE: real confirmation/Escape,
  informational Back, native file-picker cancellation and a working parent
  action afterward. This used the production shared window, not live Perch
  actions. No claim that every production route received native input.
- Plain Tab and Option-Tab in that lab did not establish an observed focus change.
  The cause was not determined, and system keyboard navigation settings were not
  changed. Complete keyboard-only navigation and spoken VoiceOver remain an
  explicit acceptance task; AX labels and hidden responder tests alone cannot
  close it.
- Inspected generated light/dark input, collector, keyboard, monitor, agent and
  Maintenance pages. Updated permission text fits its native label bounds
  (96/135 pt and 128/134 pt). Status-color calculations pass in light, dark and
  both high-contrast appearances: minimum 5.72:1 light and 7.81:1 dark against the
  tested backgrounds. This does not certify every control or another monitor's
  calibration. The user already traced the prior invisible-control report to
  monitor contrast.
- The review skill now checks recovery-write ordering, focus/selection restoration,
  stable identities, scoped field names and real keyboard alternatives to drag.

No live permission reset, Panic, hardware change, sleep/reboot/failure injection,
helper installation or public release was performed. The safe review and fixes
are complete for this checkpoint; residual accessibility and hardware acceptance
remain visible in TODO.md rather than being declared complete.
