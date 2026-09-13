# Native QA checkpoint — September 12, 2026

Source baseline: af2817b plus the corrections recorded here. The isolated test
bundle compiles the current sources with separate preferences, storage and IPC
names. Installed/public 2.0.94 was not replaced, restarted or changed. No live
permission resets, monitor writes, sleep commands, Panic, helper installation,
notarization or publication were performed. AGENT MODE was shown during desktop
work and stopped afterward. The September 10 session stopped when the Mac locked;
desktop testing resumed September 12 after Scott said ready.

## Findings and corrections

1. **P1 — saved update handoff and Desk archive could become unreadable.**
   Complete-unless-open file protection allowed creation but reopening failed
   with EPERM on this Mac. Both stores now use after-first-authentication file
   protection, retaining atomic writes and owner-only permissions. The corrected
   handoff round-trip, symlink/oversize rejection and real process-restart claim
   passed. The Desk loopback network suite also passed storage reopening and sync.
   No live files were reset and no old-version migration was introduced.
2. **P2 — lid helper update lacked attention styling.** Keep awake now uses the
   warning color for a pending helper update and its action. While installation
   runs, the action loses its attention tint and remains disabled. Closed-lid
   completion stays disabled with an explanation; its warning remains readable.
   Other stopped/error states for requested protection also use warning text.
   Setup links distinguish finishing an update from initial helper setup.
3. **P2 — active-session wording sounded like a detected failure.** The blanket
   “continued sleep prevention cannot be verified” copy is replaced by the
   helper's reported active session, observed detail and explicit limitation:
   macOS can still force sleep. Setup remains Unverified rather than claiming
   guaranteed hardware behavior. Successful helper-update copy says the session
   resumed and directs unexpected-sleep investigation to Lid activity. This
   source trace does not establish the user's current protection state.
4. **QA guard — stalled session checks could hang indefinitely.** The subprocess
   guard now fails closed after five seconds. Standalone guard tests cover absent
   session, refusal, successful checker and timeout without any app/UI launch.
5. **Regression maintenance.** Obsolete Back/completion expectations now match
   the accepted sidebar/setup routes. A helper path assertion compares normalized
   paths instead of URL directory-slash representation. These were test defects,
   not reasons to restore redundant controls.

## Coverage ledger

| Journey | Evidence | Remaining boundary |
| --- | --- | --- |
| All 26 sidebar destinations | Real clicks opened every root on September 10; no redundant content Close/Done. Captured AX states. | Root visits do not certify all child/error journeys. |
| App exceptions | Toggle persisted across leaving/reopening. Real native picker Cancel returned to responsive parent; reopened picker added Calculator, visible immediately and retained after returning. | Only disposable preferences changed. |
| Agent app/executable pickers | Real native app picker Escape and executable picker Cancel returned to responsive parent. Subsequent actions worked. | Actual target creation/removal and global shortcut testing were not performed against live helpers. |
| Setup → Keep awake → setup | Real checklist link opened Keep awake with Back to setup; Back restored checklist. Queued-update warning rendered orange. | No helper installation or actual lid control. Enabled/busy update styling also covered in isolated AppKit tests. |
| Keyboard navigation | Sidebar Down selected next page; Tab focused first enabled control; Space opened layout page. Known MX Keys layout displayed Ready. | Isolated launch's permission state is not evidence of production access. Full keyboard and spoken VoiceOver acceptance remains open. |
| Desk editing | Real Desk-name field edit saved; actual loopback TLS peers, simulated displays/commands. | Two physical Macs, real monitor switching and input routing remain open. |
| Functional regressions | Latest source: **23/23 passed**, including AppKit, lid timing/ownership/recovery, update identity, helper IPC and monitor groups. Value-model tests passed. | Native tests use injected hardware/time/permissions where appropriate. |
| Desk networking | Real loopback TLS suite passed, including 16 members, storage reopening, synchronization/conflicts and offline/partial operation. | Does not establish router discovery or physical multi-Mac performance. |
| Sparkle cancellation/tamper | Real update dialog dismissal preserved old build. Modified ZIP was rejected as improperly signed; no handoff started. | Public feed and production permissions were not changed. |
| Sparkle failed handoff/retry | Injected preparation failure kept old app running with Retry. In /private/tmp, retry replaced build 1 with 2, relaunched, and the new process claimed the exact saved identity. | Lid transport was simulated; active physical protection continuity still needs coordinated acceptance. |
| Idle performance | Read-only installed 2.0.94, 30 seconds: app approximately 0.146% CPU/57.5 MiB/3.05 interrupt wakeups per second; two user helpers approximately 0.171%/12.4 MiB/1.03 and 0.028%/9.8 MiB/0.99. | Short baseline during other work; no sustained-memory, busy-input or root-helper cost conclusion. |

## Open installation issue

A disposable Sparkle update under Documents stalled at “Installing update…”
after the old app terminated. Sampling showed Sparkle's installer blocked in
`renamex_np`. A concurrent dependency preparation also temporarily blocked in
directory rename. The updater processes were stopped without touching the live
app. A fresh /private/tmp fixture completed the same failure/retry/update route.
The cause of the Documents-location stall is unresolved: location/access is a
hypothesis, not a proven diagnosis. Do not disable verification or reset privacy
permissions to make the test pass. Acceptance in the actual /Applications
installation remains open.

One earlier retry observation was invalidated because the UI inspection tool
automatically reopened the old app during replacement. It is excluded from
acceptance. The successful temporary-folder run let Sparkle own relaunch and
verified the completion file, build and event log afterward.

## Still needed

- Actual corrected-build installation and the other Mac's clean build/launch.
- Actual /Applications Sparkle update, interruption, permission continuity and
  protected-lid transfer; investigate the Documents-folder stall separately.
- Physical lid/power boundary, failure, watchdog/reboot and wake-notice sequences.
- Two-Mac Desk discovery, shared monitor presets and keyboard/mouse routing.
- Broader dynamic/child-dialog keyboard journeys and spoken VoiceOver.
- Sustained workload/memory measurements, native collector and clean-account
  lifecycle acceptance. Destructive actions require a disposable environment.

No claim of release-wide QA completion or zero remaining issues is made.
