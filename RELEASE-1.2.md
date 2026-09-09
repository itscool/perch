# Perch 1.2 — local preview

September 9, 2026, build 80 candidate; build 77 installed. This is a local build for trying the implemented 1.2 changes; the whole-app review and physical acceptance checks remain open in [V1.2-REVIEW.md](V1.2-REVIEW.md). The previous release is [1.1](RELEASE-1.1.md).

## Build 80: restart into a newer installed copy

Perch detects when a newer signed version replaces the app at its current path.
The Perch section of the main menu then shows the running and on-disk versions
and offers Restart Perch. The first detection in each run also offers Restart
now or Later; it waits while a menu or Settings interaction is active. Dismissing
it leaves the menu offer available without repeated prompts in that run.

Checks run in the background and reuse unchanged results. A partial installation,
older version or unverifiable app does not produce a restart offer. Background
completion does not insert rows into an open menu or disable unrelated controls.
Restart uses the existing verified worker and bounded lid handoff, with visible
progress/errors in App settings. No downloading or installation is added.

All 22 isolated suites pass, including file-replacement, numeric-version,
verification-retry, dismissal and menu-stability cases. Live replacement and
active-session restart acceptance remain separate. This candidate includes
builds 78–79 and has not been installed. Production compilation was warning-free;
strict signatures and ZIP integrity/version checks pass. See APP-REPLACEMENT-REVIEW.md.

## Build 79: whole-app review fixes

Launch-job recovery is saved before changing eligibility, and Resume saves its
release decision before enabling jobs. Failed saves stop the dependent operation;
uncertain or failed jobs retain recovery records for retry. No live launch jobs
were changed during verification.

Settings retain keyboard focus and text selection across child dialogs, Back and
page refreshes. Reviewed editable/repeated controls have scoped accessible names.
Permission setup offers a keyboard copy-path action alongside dragging. Collector
setup and Setup & status agree about readiness, including required repair and
replacement-session waits. Custom executable selection and catalog validation
share conservative safeguards against general-purpose runtimes.

The final isolated suite passes 21/21. A harmless native lab passed confirmation,
Escape, informational Back, picker cancellation and parent reuse under AGENT
MODE. Full keyboard-only/VoiceOver and hardware acceptance remain open. See
WHOLE-APP-REVIEW-79.md for prioritized findings, coverage and exclusions. Build 79
includes build 78's tooltip/shared Esc changes. It has not been installed. Production compilation completed without warnings; strict executable/app signatures and ZIP integrity/version checks passed.

## Build 78: consistent action help

The user confirmed build 77's menu interaction fixes work. All 21 menu action
rows now require help at construction, including privacy reset, Resume, Mute,
Start at login and About. Refreshes preserve the action's purpose and add relevant
availability or repair context; healthy Settings help no longer becomes empty.
Panic help describes the menu confirmation instead of implying an immediate click.
Matching Settings controls share explanations, and ordinary Settings action lists
reuse their visible descriptions for hover and accessibility help. Menu layout,
commands, permissions and hardware behavior are unchanged. System metric help is
retained. This build also includes the shared Esc label below.

Production and the full isolated app compile without warnings. Strict app/helper
signatures and the build 78 ZIP integrity/version checks pass. Hidden tooltip ownership,
tracking, accessibility and menu activation regression checks pass. No visible
menu, Settings flow, permission or hardware operation was used for this content
pass. Native acceptance of the new wording remains separate from the accepted
build 77 hover repair. See TOOLTIP-REVIEW.md for coverage and exclusions.

## Follow-up in source: one shortcut label

The user confirmed build 77's Back fix works. Shortcut labels now use the same
shared formatter and Esc key name in Settings, test prompts and menus; the
menu-only Escape-to-Esc rewrite is removed. This spelling change is not yet in
the installed build 77. Hidden shortcut-flow tests and the 58-site dialog
contract check pass.

## Build 77: consistent Back through alert results

App-owned alerts return through completion callbacks in the ordinary event loop.
Shortcut preparation, results and cleanup no longer start successive native
modal loops in the same Settings window. Back and X share alert ownership;
the parent restores before the next step. Native file pickers remain unchanged.
Return to Setup & status stops cleanly when an invalid draft refuses Back,
instead of repeatedly navigating on the main thread.

New-machine configuration already uses Control–Option–Command–Escape, now covered
by regression checks. Its main-menu label is `⌃⌥⌘Esc`. Existing combinations and
enablement are preserved.

Hidden tests dispatch the actual shared Back after shortcut success/timeout,
preparation cancellation, result X and repeated cleanup/parent transitions,
without injecting alert responses or opening native windows. The whole-set
static audit and build gate cover every app-owned alert. Native click acceptance
remains open; the reported AppKit event failure was not physically reproduced.
Build 77 was installed with user authorization and launched through LaunchServices.
Saved preferences and shortcut configuration were unchanged; compatible root lid
helpers were retained. The lid session was inactive, so installation did not
exercise active-session restart handoff.

Production and final full isolated compilation completed without warnings.
Hidden ownership, shortcut-Back and menu regression checks pass; the native lab
compiles. Strict signature and ZIP version/integrity checks pass. The full
visible suite and physical Back replay were not run during this static pass.

## Build 76: menu tooltip and interaction ownership

The user confirmed that flickering is resolved and the discussed physical
external-keyboard behaviors work. A separate report describes Panic help
appearing over other menu rows.

Custom menu rows now own their tooltips; native menu items no longer register a
second tooltip for those rows. Tracking refresh removes only Perch's own hover
area. Return/Space follows the visible highlight after moving between keyboard
and mouse navigation, and consumes activation when selection becomes hidden or
disabled. Deferred commands are discarded if their action or target changes
before dispatch. Native popup help, shortcut labels, accessibility help and the
existing menu layout are retained.

Hidden tests pass for help ownership, replacement/clearing, tracking ownership,
selection and deferred action changes. Production and full isolated compilation
completed without compiler warnings; strict signature and package checks pass.
The full visible suite was not rerun. Build 76 is prepared separately, not installed; actual native
hover acceptance remains open. No live menu action or hardware setting was used
to test these corrections.

## Build 75: dialog ownership and whole-set interaction audit

Installation follow-up: the user authorized installing build 75. It is now
installed at `build/Perch.app` and running after a LaunchServices launch; the
guardian/input helper copy also reports build 75. Saved preferences compared
equal before/after. At installation the lid session was already inactive, both
override readings were off and ownership records were absent. The existing lid
supervisor/watchdog were preserved. This was not an active-session handoff test.
Native dialog acceptance remains open; see the installation checkpoint in
V1.2-REVIEW.md. Earlier preparation-only statements below record the prior pass.

Dialog timers and buttons can finish only their own active confirmation.
Background page refreshes cannot replace its controls or heading. Closing
Settings during a Finder/System Settings handoff releases that ownership so
later Settings actions do not remain queued. Obsolete backing-panel close
handlers no longer stop unrelated modal loops. Layout and main-menu design are
unchanged.

The source audit inventories 58 UI construction/entry sites. New hidden tests
exercise actual NSButton dispatch and hit testing, late/duplicate completion,
Back/X, picker cancellation and handoff close/reopen. A build gate requires
review entries for new UI sites and keeps modal control in the shared host.
The reusable flow skill and a harmless native smoke app capture the distinction
between simulated responses and actual mouse/keyboard input.

The user’s unidentified dead-button dialog remains an open acceptance item.
The UI tool reported the Mac locked; no native clicks occurred. Hidden ownership
tests pass and the full isolated suite compiles, but its visible run is pending.
Build 75 is prepared separately; the installed build 70 and active lid session
are preserved. No public release, permission change or hardware action occurred.

## Build 74: stable sleep state and launch-access recovery

Keep awake ignores transient activity assertions and updates each menu row only
when its final presentation changes. Including with lid closed retains your saved
choice after a session ends; status identifies stopped or unconfirmed protection.
Keep awake offers Resume lid protection, and clearing a checked inactive choice
no longer starts a session. The guarded helper and 60-second policy are unchanged.

If the choice was on when the running app observed closed-lid sleep, Perch retains
that context and explains the recorded sequence on wake, with View lid activity.
It does not warn for ordinary sleep with the choice off, invent a cause from a
sent command, or repeat an acknowledged incident. Recovery across app restarts
requires corroborating sleep/wake evidence. If Perch was absent before sleep,
the exact historical choice is unknown and no notice is fabricated.

Blocked connected external keyboards receive a startup access notice and shared
recovery throughout keyboard setup. An already-enabled permission has a Finder
relaunch route; independent helper permissions remain separate. Exact OS privacy
attribution cannot be inferred from a parent process. Actual Automation denial
also explains its own permission and normal-launch recovery.

All 20 isolated suites are covered by passing runs, with the changed AppKit
suite rerun after fixture corrections. New checks cover stable polling, saved
lid actions, durable conditional notices and scoped access recovery. Light/dark
recovery pages were inspected.

Build 74 is signed and packaged; production and isolated compilation had zero
warnings, and strict signature verification passed. Build 70 remains installed to preserve the
active lid session. Physical sleep/wake, hardware and affected-machine acceptance
remain open. No public release or live permission/hardware change is part of this
preparation.

## Build 73: direct restart, Quit shortcuts and clear Fn recovery

App settings replaces the developer-oriented Updates page with **Restart Perch**.
Restart reopens the installed app without choosing or installing anything. Its
verified worker preserves a compatible active lid session with the existing
bounded ticket and unchanged battery/watchdog deadlines. Inactive closed-lid
restart is allowed only after confirming the override is off and unowned.
Required lid-helper updates remain visible in Keep awake and Setup & status.
A release update checker is deferred.

Quit now has application-menu wiring for Settings and explicit shortcut routing
in the custom status menu. The tuned status-menu layout is unchanged. The user
confirmed CPU colors and password entry. The MX Keys Fn-access failure was
traced to direct terminal launching: macOS attributed access to Codex even though
Perch was already enabled in Input Monitoring. Normal app launch restored access
without changing permissions; in-app Restart preserved it. The Fn page now shows
unknown state and a direct Input Monitoring route when access is unavailable,
with recovery wording for an already-enabled app. Ordinary Keep awake flicker
remains open.

Build 70 live checks confirmed ordinary restart, Command-Q from Settings and
retained Fn access after restart. Isolated tests cover both Quit routes, plain
restart without bundle replacement, cancellation, legacy bootstrap replacement,
unchanged battery/watchdog limits and helper-maintenance recovery. Production and isolated compilation completed with zero warnings. All 20
isolated suites passed after correcting the dialog test setup, its superseded
recovery-route expectation and isolation of the durable lid ownership journal;
the final changed AppKit suite passed a targeted rerun. Light/dark recovery
renders and strict signatures passed. Build 73 is prepared as a local package.
Build 70 remains installed and running because the user activated lid protection
during verification; the active session and helper processes were preserved.
Active lid-session restart and remaining hardware/failure acceptance stay open.
No permissions were reset or changed, no physical Fn toggle was issued and no
public release was made.

## Build 69: usable controls during polling and guarded lid recovery

F1–F12 controls retain their confirmed state and remain usable during ordinary
two-second background reads. A click queues the selected change behind the read;
actual writes, first discovery and invalidated devices still have distinct
availability. Unchanged reads do not refresh the Settings page. CPU colors now
follow the CPU measurement's severity, independently of unavailable optional
process statistics or words in process names. The other periodically refreshed
menu controls were audited for the same read-versus-write distinction. Main menu
section design and order are preserved.

Lid helper revision 2 replaces the unreliable shared clamshell flag with a
guarded system sleep override. It blocks manual Sleep too while enabled; turn
off lid protection to sleep immediately. A durable root-owned journal, bounded
serialized commands and independent launchd recovery handle ended supervision,
crash and reboot recovery. Cleanup retains its recovery record until persistent
and live state confirm restoration. Existing overrides are refused, and helper
updates keep recovery running until cleanup succeeds. The 60-second policy and
short watchdog leases remain. See [behavior and recovery limits](LID-RECOVERY.md).

Build 69 is installed through build 68's actual Updates page; the new process
reported successful completion and preserved saved choices. This was an inactive
lid session with the lid open, not an active-session handoff test. The privileged helper
requires its separate update; installing only the app does not replace the old
lid mechanism. Production and isolated compilation completed with zero warnings;
all 20 isolated suites passed, including a disposable stalled-writer test, durable
ownership and failed-cleanup retention, boot/lease/process identity checks, real
read-only power-state checks, and unplugged/open → close → plug → open policy.
Keep awake renders were inspected in light and dark appearances. Physical power
mutation, crash/reboot recovery and sleep/wake acceptance remain open; simulated
tests do not establish those results. No public release was made.

Subsequent local acceptance with the installed build 69 helper: powered close/
open, short undock/open and unplugged/open → close → plug → open recorded no
system sleep and retained the override. A full battery timeout released the
override and requested sleep at 60 seconds; macOS recorded actual sleep about
five seconds later. After opening, both override readings were off and ownership
was cleared. These four runs passed their observed behavior. Explicit disable,
app/helper failure, reboot recovery and active-session update acceptance remain
open; this is not a guarantee across all hardware or failure conditions.

## Build 68: controlled restart and separate lid-helper updates

**App settings → Updates** prepares a newer local signed Perch app and offers
**Update & restart**. The old app waits for the staged worker to verify readiness
before exiting. The worker checks both bundles, keeps a rollback copy, starts the
exact new executable and waits for its completion receipt. A prepared update and
its result survive Back/Close during the app session; there is no extra Done.

A compatible, active lid session can grant one restart allowance of at most 60
seconds. Only a new connection from the exact staged executable can claim it.
The existing battery countdown and short watchdog deadlines remain in force;
retries, a launch alone or stale replies do not establish successful handoff.
Missing/expired claims do not silently enable a new session. App and helper
component versions are separate, so UI-only builds do not require lid-helper
replacement. See [the update contract and failure paths](UPDATES.md).

Required installed-helper updates appear in Setup & status, Keep awake and
Updates. They wait for an open lid and **Finish helper update…**, including a
second lid check in the authorized installer before stopping the old helper.
Opening the lid does not itself trigger a surprise password prompt. The first
upgrade from the older build 63 helper needs the lid open; that helper cannot
hand a session across an app restart. Saved preferences are retained.

The functional runner now enforces AGENT MODE for native tests, including its
isolated panels. Build-only and run-only phases separate background compilation
from announced desktop use. This corrects a test-ownership failure caught by the
user; the reusable settings-flow skill was updated too.

Validation: zero production or isolated compiler warnings; all 20 isolated suites
passed under AGENT MODE. A real signed disposable worker replaced and relaunched
copied fixture apps and received completion acknowledgment. Tests cover ticket
expiry/replay, preparation failure cancellation, unchanged battery/watchdog
limits, late replies, rollback, invalid paths/signatures, queued/open/busy/error
states and Back/re-entry. Light/dark Updates renders and strict app/tool signatures
passed. The exact-hash requirement accepts signed build 68 and rejects build 67.
Build 68 and its privileged helper are now installed; the helper journal confirms
startup. Live session handoff, first-attempt password entry and physical sleep/wake
acceptance are still pending; the shared macOS clamshell-control defect remains unresolved.
Physical acceptance: undock then open after 12.2 seconds on battery behaved as
intended. The next reconnect test reproduced Clamshell Sleep on AC despite the
user seeing an immediate return. powerd logged clearing prevention before lid
closure while Perch retained its earlier command state. The P1 enforcement defect
remains open; the diagnostic collector now includes bounded powerd evidence.
No public release or privacy reset was performed. The tuned main menu is unchanged.

## Build 67: stable menu geometry during live refresh

Custom menu rows now retain the width allocated by macOS while the menu is open. Unchanged text does not resize a row, and changed status text defers its preferred width until the menu closes. Long updates truncate within the existing row without overlapping shortcut labels; the full text remains accessible. Unchanged external-keyboard headings and visibility assignments no longer trigger redundant menu updates. Section order, colors, overlines, spacing and text alignment are preserved.

The previous renderer reproducibly shrank an AppKit-allocated 620-point row to 430 points on an unchanged text assignment. New regression checks cover allocated-width preservation, changed live text and shortcuts, hover retention and width updates after dismissal. This corrects a source-confirmed cause of periodic menu movement; the user's exact live flashing/glitch symptom still needs checking in the new installed build. Keyboard controls still deliberately withhold actions during pending reads; this change does not conceal that state.

Validation: production and isolated compilation completed with zero compiler warnings; all 20 isolated suites passed. Native light/dark menu renders and strict app/embedded-tool signatures passed inspection. The shortened overview explanation measures 46 points within its 59-point row. Tests and renders used isolated storage with hardware, permission and emergency actions blocked.

Builds 65–66 were intermediate candidates as the live menu report expanded the pass. Build 67 includes the display overview and disconnected-keyboard corrections below. It is prepared separately from the running build 63 and active lid session.

## Build 65: honest first-show display status and disconnected keyboard guidance

Setup & status no longer counts a saved monitor connection as Ready when its current input is unknown. It shows Unverified with a route to read or confirm the input. A failed read or unavailable shortcut/connection still needs attention. Explicit named display groups do not require a current-input observation. Saved connections and input lists are preserved.

Navigation settings now distinguish a disconnected external keyboard, pending discovery, detection failure and a keyboard that actually needs learning. A disconnected keyboard prompts connection and explains automatic recognition, while preserving saved behavior choices.

These changes follow a live, read-only build 63 journey through Setup & status, Displays, Monitor inputs, Switching groups, keyboard/navigation pages, scrolling and completed Accessibility setup, Maintenance, and agent settings. Back navigation and ready access presentation worked. The monitor overview incorrectly changed from Ready to Needs attention only after the monitor page performed its read. No hardware setting, shortcut, panic, permission reset or OS authorization was triggered during this pass.

The main menu design is unchanged. Build 64 was an intermediate layout check; build 65 shortens the new overview explanation to fit its row. This candidate is prepared separately from the active build 63 lid session. Actual password entry, physical lid/monitor/hotkey tests and the existing lid-control defect remain open.

## Developer testing: visible agent sessions

Live UI testing now uses a separate **AGENT MODE** desktop banner. It remains visible across Perch restarts, uses a nonactivating panel, and offers **Request control**. The agent checks its session before every action batch; control requests, missing banner processes and expired sessions block continuation. This is a cooperative handoff, not an input lock or cancellation of already-issued actions. See `Tools/agent-mode/README.md` and the repository's `AGENTS.md`.

This testing tool does not change the Perch application or its tuned menu. The banner itself requires no app/helper reinstall; its addition left the installed app at build 63.

## Build 63: consistent settings journeys and menu readiness

Privacy resets now keep their running state and result when you leave and return during the current app session. Back no longer claims to cancel an issued command. A failed reset can be retried; simultaneous resets and stale completion callbacks cannot overwrite another operation. After success, starting another reset returns to a proposal before any new command runs.

Keyboard changes stay on the page where you made them. Group edits preserve position and unsaved text, reveal new destinations and restore identifiable focus. Monitor setup has one final Save for its connection and input list: model selections fill the draft directly, Back keeps valid child edits, and invalid edits can be corrected or discarded. The ordinary monitor page continues to save preferences immediately.

A saved “this Mac’s input” mapping is shown separately from the monitor’s current input. Unknown readback does not erase completed mapping setup, and a successful read does not imply that this Mac has been identified. Change and automatic Retry are available; Stop and retries use separate cancellation state. Confirming a mapping does not also enable unconfirmed cycling.

Shared alerts use Back/Close for navigation while preserving named actions and their cancellation results. Input permission setup reads the input helper directly. When ready, it shows a compact confirmation and optional review instead of prominent grant instructions; missing access restores the relevant steps. Process-event readiness makes permission controls secondary.

Non-System menu rows distinguish initial Checking from a failed/offline helper, repaint when status arrives, and preserve their availability through native validation. Scrolling depends on the input helper and distinguishes saved choices from running controls; a saved choice can still be turned off after losing access. Keyboard reads refresh external state while the menu is open and withhold stale Fn choices during pending reads. A read-only refresh cannot consume a later device-connection action. The tuned menu section order, overlines, highlights and System area are preserved.

Validation: production and isolated compilation completed with zero compiler warnings; all 20 isolated suites passed. Expanded tests exercise reset navigation/results/retry, shared alert exits and action indices, all four keyboard-details controls, group position/draft retention, monitor identification Stop/Retry/mapping persistence, permission-ready recovery, menu validation and authenticated XPC publication without a feedback loop. Native light/dark renders were inspected. Hardware, resets, OS authorization and other external mutations were injected or blocked. The previous local build 62 was an intermediate verification build; build 63 includes the compact permission-ready presentation.

This is a separately prepared local build, not an automatic installation. The shared macOS lid-control flag defect is still unresolved. Actual 60-second undocking, affected-Mac password entry, hotkeys and multi-monitor behavior, native collector installation/FDA/reboot behavior, and broader release/distribution acceptance remain open.

## Build 61: collector identity without deprecated job lookup

CPU accounting no longer calls `SMJobCopyDictionary`. A small signed native launcher records its PID, process start time and boot UUID in a protected file, then replaces itself with Apple's eslogger using a fixed command. No extra persistent process, shell launcher or new Endpoint Security client is added. The reader rejects unsafe ownership/modes, symlinks, hard links, special files, oversized data, stale boots and reused/exited PIDs. Sampling checks identity again afterward; a collector transition leaves the combined total unavailable for that sample.

Existing direct-eslogger installations keep collecting events. **Process event collection → Update CPU accounting…** explicitly installs the new launch path with administrator authorization and restarts observation. Until an installed collector has a verified identity, Perch reports its combined CPU total as unavailable rather than silently omitting the collector. The installer stages and verifies the signed launcher and configuration before stopping the existing collector. Identity-write failure does not prevent event collection.

The new launch path's Full Disk Access behavior still needs installation acceptance on the affected Mac. No grant is reset; macOS may require access for the native launcher. Event delivery and the existing health probe remain the authority for collection readiness. This build was prepared separately, without installing/restarting live helpers or touching permissions. The separate lid-control defect and password-entry acceptance remain open.

Validation: production and isolated test builds completed with zero compiler warnings. All 20 isolated suites and the native launcher fixture checks passed. App, display-tool and launcher strict signatures passed; the installer’s derived launcher requirement matched, and the production launcher refused unprivileged execution. The isolated harness now replaces blocked power-method bodies instead of retaining unreachable code, preserving the safety blocks without their two synthetic warnings. No warning suppression was added.

## Build 60: complete system-dialog focus sweep

The [focus audit](V1.2-FOCUS-REVIEW.md) covers all administrator command sites, three file-picker entry routes, 16 app-alert sites, nine external-destination routes and explicit activation/window-ordering paths. File pickers and standalone alerts now own shared busy state; parent navigation and delayed notices cannot interrupt their interaction. Overlapping synchronous confirmations return abort. Queued page changes and notices wait until the active interaction finishes.

System Settings and Finder handoffs keep drag instructions visible at normal window level and hold competing Perch UI until the user returns. Permission links no longer request an independent OS grant prompt at the same time. Saving input choices still updates the helper through configuration observation. The main menu design is unchanged.

This extends build 59's candidate password-focus correction. Actual secure password entry on the other Mac and native picker keyboard behavior remain acceptance checks; injected panel tests do not close that report. The shared macOS lid-control flag defect and BW-01 deprecation remain open.

Validation: the final production build and all 20 isolated suites passed, including the new picker-entry and external-link action tests. Strict app/helper signatures and archive integrity were checked before packaging completion. One distinct production warning remains (BW-01). No live OS grant, password entry, installation, panic or hardware operation was performed.

## Build 59: system password-prompt handoff

Administrator authorization temporarily withdraws the floating Settings panel while preserving its page, and no longer requests app activation immediately before opening the macOS prompt. Previously open Settings returns after authorization; menu-only actions do not open it. Delayed error and shortcut-test result dialogs wait until authorization ends. Nested or repeated completion cannot restore the panel prematurely.

This addresses source-observed focus competition after the user reported that the first lid-install password prompt on the other Mac would not accept typing, while cancellation and retry worked. The exact affected build and OS focus state were not captured, so the incident's cause and actual first-attempt password entry remain unverified. No password prompt, installed helper, permission or live power operation was exercised in preparing this candidate.

Validation: production compilation and all 20 isolated suites passed. Native panel checks cover withdrawal, page retention, refresh suppression, deferred notices, nested/duplicate completion, immediate retry and menu-only entry. No real OS authorization dialog was opened. The previously tracked BW-01 compiler warning remains.

## Build 58: reviewed compiler warnings

The six warning lines in build 57 represented three distinct deprecations, each printed twice. Audio volume now uses `AudioObjectHasProperty` and `AudioObjectGetPropertyData` with the same virtual main-volume property. A read-only comparison across all three audio devices on this Mac matched both API paths: one readable volume control returned the same scalar, and two unsupported controls remained unavailable. No volume, mute or output-device setting was changed.

The remaining `SMJobCopyDictionary` warning is retained and tracked as BW-01 in the review. It supplies the event collector's actual launchd PID for Perch CPU accounting. Apple's SDK explicitly supplies no replacement for this dictionary lookup; `SMAppService.status` reports service registration rather than the running PID. Replacing it safely requires another reliable source of collector identity. No warning was suppressed, and no process-name guess was substituted.

Validation: production compilation and strict app/helper signatures passed, with one remaining distinct compiler warning (BW-01). All 20 isolated regression suites passed. The isolated test copy also emits two unreachable-code diagnostics from its deliberately injected power-operation blockers; those are not production warnings. Prepared separately from the installed app, without live permission, helper or hardware changes.

## Build 57: lid-session recovery and accurate protection status

Lid heartbeats now run on a dedicated serial queue, with responsiveness maintained while a user-requested session is active. A busy menu or Settings thread no longer blocks renewal. A delayed, failed or malformed reply makes status unconfirmed and retries the existing token within a bounded recovery window. It does not silently enable another session or extend the helper's five-second lease. Late callbacks cannot undo recovery, disable/new-session choices, or an acknowledged helper stop.

When macOS announces sleep during an active lid session, Perch stops that session, records the remaining battery interval, and retains an explanatory message after wake. Cleanup releases the request without issuing an additional sleep command from this policy path. Earlier watchdog entries remain important because a watchdog failure can also initiate sleep.

Settings, activity history, the menu and Setup & status now label active lid mode as requested with unverified prevention. Setup & status does not count it as ready or repeatedly direct the user through a repair that cannot verify the kernel flag. The checkbox represents the request. The shared macOS clamshell-flag race remains open: this build does not establish reliable protection across undocking. The 60-second normal policy and shorter fail-safe deadlines are unchanged.

Validation: all 20 isolated suites passed, including recovery, late replies, expiry, explicit disable and a real client heartbeat running while the UI thread was blocked. After shortening the overview status text, the lid and overview suites passed again. Native light/dark overview renders, production compilation and strict app/helper signatures passed. All sleep and enforcement mutations were injected; the build was prepared without installing it or changing live helpers, permissions or hardware settings.

## Build 55: highlighted section titles with overlines

The selected menu treatment now highlights only each section title and places a two-point colored line above it. Action rows use the neutral menu background. System remains first and neutral, Agent Kill Switch remains immediately after System, and the existing three-point gaps and row heights are preserved. This implements option B from the title-style comparison. Menu actions and shortcut labels retain their existing behavior.

The user traced the reported missing checkbox, button and list-box outlines on the other Mac to that monitor's contrast. That report is resolved separately from this appearance change. The reported early closed-lid sleep and other open functional findings remain under investigation.

All 20 isolated suites pass. Native menu renders were inspected in light and dark appearances; production compilation, strict signatures and archive integrity passed. Prepared separately from the running app, with no installed helper, permission or hardware change.

## Build 54: agent settings interactions and menu shortcuts

Agent choices, emergency-shortcut controls and the privacy-reset scope now use a regular settings page with Back and automatic saving. Each edit preserves unrelated settings. Invalid or conflicting shortcut edits retain the saved shortcut, and failed saves offer Retry saving. Changing the privacy-reset scope does not perform a reset. This replaces the nested modal editor used in the reported click failure; interaction on the affected test Mac still needs confirmation.

Enabled, configured Panic and monitor-cycle shortcuts appear on the right edge of their menu rows, aligned like Quit. Display groups show the selected group's shortcut. Readiness and failure hints remain separate, so displaying a configured shortcut does not claim its helper is running. The existing hotkey handlers continue to own activation; the labels do not register competing menu actions. Menu position remains System, Agent Kill Switch, then the other sections. Outline and title-background experiments remain preview-only.

All 20 isolated suites pass, including native hit testing and action dispatch, independent saves, invalid/conflicting shortcuts, failed-save retry, Back/reopen, group shortcut labels and unchanged Quit behavior. Light/dark native renders were inspected. Production compilation and strict signatures passed. Prepared separately from the installed app; no live Panic, privacy reset, monitor switch or hotkey activation was performed.

## Build 53: Agent Kill Switch below System

The complete Agent Kill Switch section now appears immediately after System, retaining its red tint, Panic, all-app privacy reset and conditional Resume action. Other sections keep their relative order and compact spacing. Stronger section outlines remain a design preview; this build changes only the section's position.

All 20 isolated suites pass after updating the existing menu-order expectation. Production compilation and strict local signature checks passed. This candidate is prepared separately; no installed app/helper, live permission or hardware setting was changed.

## Build 52: retain monitor readiness on first show

An unchanged monitor is usable from the menu's first frame after background discovery completes. Build 51 unnecessarily discarded that result on every opening. Startup, display changes and wake still refresh metadata; opening the menu now first compares a small macOS display-identity snapshot with the checked configuration. A changed or unknown configuration triggers discovery, including when the screen-change notification has not arrived. An unavailable configured monitor keeps its Settings route. Failed checks can retry on opening, and results overtaken by a display change never enable stale controls. Setup & status now shares the pending state for individual monitors and groups.

All 20 isolated suites pass, including first show after background checking, repeated opens without another discovery, missing displays, notification delay, same-ID replacement, wake, failed checks/recovery, unreadable macOS metadata, menu-tracking completion, queued work, groups and overview agreement. A separate read-only sample of the macOS identity query on this Mac took about 29 ms on its first call, with a fastest subsequent sample of 0.08 ms; this is not a latency guarantee. Menu opening does not read or switch the monitor's input. Physical switching and the other Mac remain acceptance work. The candidate is prepared separately from the running app.

## Build 51: monitor availability before menu display

Opening the menu starts a read-only monitor metadata check before the first draw. Cycle monitor input stays disabled with “Checking monitors…” until the result arrives, including during native menu validation. Screen changes invalidate readiness immediately; overlapping opens share an in-flight check, stale replies cannot restore a disconnected monitor, and checks queued behind another operation do not briefly enable the row. Failed discovery drops old DDC routes and successful recovery clears the discovery error. Missing setup remains reachable in Settings. Switching groups check their selected members, while saved independent USB/LAN routes are retained when video is inactive.

The menu check does not read or switch the current input. Explicit cycling still reads the current input before selecting a destination. This build also includes the automatic keyboard setup saving and known-keyboard recognition from builds 50 and 48.

All 20 isolated suites pass, including startup and repeated menu opening, native and accessible disabled state, completion during menu tracking, disconnect debounce, superseded replies, failed discovery/recovery, queued checks, group membership and inactive-video routes. Production compilation and strict local signature verification passed. One read-only metadata check using the production adapter on this Mac completed in approximately 0.37 seconds; this is not a latency guarantee or acceptance on the other Mac. No physical input switching was exercised. The candidate was prepared without replacing the running app or installing helpers.

## Build 50: automatic keyboard setup saving

Manual navigation setup saves automatically after the final key is released or marked absent. The completed page shows the saved result and Back, with no Done, Use this layout or Cancel setup step. Back, closing, losing focus or timing out during unfinished setup keeps the previous layout. If saving fails, Perch says the previous layout remains in use and offers Retry saving without repeating the lesson. Navigation app-exception checkboxes also save immediately, with an inline error and restored checkbox state if a write fails. The existing automatic recognition of known keyboards remains available.

All 20 isolated suites pass, including final-release/absent-key autosave, one save per completion, incomplete replacement, timeout, focus loss, Back/close, failed save/retry, reopening and immediate app-exception changes. Production compilation and strict local signature verification passed; light/dark completion renders were checked. Build 49 was an intermediate candidate before the updated flow checks and completion wording were finalized. Physical key delivery and the pending live helper upgrade remain separate acceptance work.

## Build 48: keyboard recognition correction

Known external keyboards, including MX Keys, are identified from macOS registry metadata without requiring an HID input client or manual four-key learning. The existing 28-profile catalog still requires exact model/transport and matching navigation usages, and saved custom layouts take precedence. The learning page shows recognized keys as ready; Input Monitoring is needed only for learning a different layout. Home/End and Page Up/Down behavior remain explicit choices. Read-only reproduction confirmed that the previous device path could return no keyboards despite available identity and descriptor data. Clean-Mac and physical key-delivery acceptance remain open.

Build 48 validation: production compilation, strict signature verification and all 20 isolated suites passed. A separate read-only check using the production metadata/registration code and no saved profiles recognized the connected MX Keys and all four navigation usages. This does not claim physical remapping delivery or a completed installation on a second Mac.

## Build 47: remote lid setup

A new lid-protection session can start with the lid closed on confirmed external power. This removes Perch's unnecessary open-lid restriction for remote, docked use. Lid and power state must both be readable; starting while closed on battery is still refused. The startup condition is checked again after the watchdog handshake. Helper/watchdog identity, fresh acknowledgments, leases, legacy-override cleanup and the existing 60-second undocking policy remain enforced. A helper restart still begins disarmed and requires an explicit fresh enable request. Setup and recovery wording now describes the actual requirement.

Build 47 source validation: production compilation, strict signatures and all 20 isolated suites passed, including open/closed/power startup combinations and revalidation after a power change. Physical undocking/sleep acceptance remains open.

## Build 46: activity history and menu experiment

**Settings → Keep awake → Lid activity** shows the last 24 hours, capped at 1,024 entries across the helper and watchdog. It records observed lid/power transitions with elapsed times, countdown starts/cancellation/expiry, session failures, command results, and separate macOS sleep-begin/wake-complete notifications. History persists through app/helper restarts in a local root-owned journal and remains readable if the helper is offline. Logging runs away from the power-control loop; unchanged polling does not fill the history. Live updates can be paused, and Copy log copies the displayed history. Missing observations and unconfirmed sleep are explicit. Notifications indicate an OS transition, not a guarantee of how long hardware remained asleep. [Apple notification semantics](https://developer.apple.com/library/archive/qa/qa1340/_index.html).

At the user's request, **System is first** again with a neutral background. Other main-menu sections have faint color backgrounds, no separator lines and three-point gaps. Main-menu actions, including the all-app privacy reset, remain in place.

**Identify this Mac’s input → Find this Mac automatically** tries the selected monitor's known ports and watches that display's own macOS identity, rather than the total screen count. Reconnection suggests a candidate; unchanged connectivity and input readback alone cannot identify the computer. Stop/Back stops further tests and attempts to return to the original input when known. If switching breaks the control connection, restoration can fail and the monitor's Input button is needed. No mapping is saved until the user confirms the picture. Saving this Mac's port no longer creates the confusing 30-second current-state prompt; manual current-input observations remain short-lived and separate from the saved mapping. This experiment still needs user-operated hardware acceptance.

Build 46 preparation: production compilation and strict signatures passed. All 20 isolated suites passed, including journal retention/restart/concurrent writers, elapsed transitions, log navigation, and monitor probe scope/ambiguity/cancellation/return. Light and dark menu, log and identification-page renders were inspected. Physical monitor scanning and closed-lid sleep behavior were not tested.

## Build 45 correction

Build 44 could reject an accepted lid-control command with “macOS did not confirm lid-sleep prevention.” XNU updates `AppleClamshellCausesSleep` when sending clamshell notifications, but its clamshell-control setter does not refresh that cached property. It is no longer treated as immediate readback or as ongoing session authorization. Command failures, sensor failures, expired leases and watchdog failures still stop the session. Enabled now means the helper is running and macOS accepted the control command; physical sleep behavior is not independently verified. A failed, cleaned-up lid start also no longer disables ordinary Keep awake controls. The shared powerd control bit and actual undocking/sleep behavior remain physical acceptance gates.

Build 45 validation: all 20 isolated suites and the production build pass. The app, input/guardian helpers and privileged lid helper were updated on the affected Mac. With the lid open and external power connected, the normal Settings controls successfully enabled protection, sustained it beyond the client/watchdog lease intervals, disabled it with the session record removed, and enabled it again. Ordinary Keep awake and existing input access remained active. No physical lid closure, undocking, sleep request, privacy reset, panic, or monitor switch was performed.

## Build 44 correction

Build 43 passed a task port to `IOPMFindPowerManagement`, which requires the default IOKit port. That prevented enabling and releasing lid protection and blocked cleanup with “macOS power control is unavailable.” Both lid control and sleep requests now share the corrected connection setup. A read-only check reproduced the failed old call and successful corrected call on the affected Mac. The regression suite now exercises the real connection setup and closes it without sending a power command. When cleanup finds an older installed lid helper, it stages the current verified helper and uses that code for cleanup before restarting disarmed, rather than retrying the old binary. Actual sleep/wake and failure acceptance remain open.

Build 44 validation: all 20 isolated suites, production compilation and strict signatures pass. The affected Mac's app and background helpers were updated to build 44; the normal lid-helper repair upgraded the privileged helper, successfully removed the stale session record, and restarted the service and watchdog disarmed. Existing input access remained granted and active. The UI returned to ordinary Keep awake controls. No sleep countdown, privacy reset, panic, or monitor switch was tested.

## Where to find the changes

- **Settings → Setup & status:** a reusable overview of required setup, missing access, helper response, and the next relevant action. It opens on first use and remains available for checking or repairing setup later.
- **Settings:** one home for Displays, Keyboards, Scrolling, Keep awake, Agent Kill Switch, and App settings. Maintenance and recovery actions sit with the feature they affect. The tuned main-menu layout remains, including the all-app privacy reset.
- **Settings → Displays → Switching groups:** select one monitor, either monitor, or several together; name destination computers and map each monitor's input independently. Check current inputs, see each monitor's result, and retry incomplete switches. The existing cycle action can use an explicitly selected group.
- **Monitor settings:** ordinary choices save immediately. Connection/input-list and group editors use explicit Save/Cancel because they commit related changes together. Ordinary pages use shared Back/Close and the window close control; redundant Done buttons are removed.
- **Settings → Keep awake:** the supervised lid mode stays awake while closed on external power. Closing on battery or undocking while closed starts 60 seconds to open the lid. Remaining closed on battery releases the override and requests sleep. Enabling the mode requires explicit setup with the lid open or confirmed external power; an old global sleep override must be removed explicitly first.

## Functional repairs

Agent recognition is more conservative about Node/Bun entry points. Helper readiness checks the installed/running build. Settings and permission links reach the relevant page, long dialogs scroll, validation retains drafts, monitor state distinguishes fresh observations from previous commands, and disconnected keyboard layouts remain manageable. First authorization focus has a source fix; actual first-prompt typing still needs user-operated confirmation.

## Local build and remaining checks

The app uses the existing local signing identity. It is not notarized or published. Normal launch updates outdated Perch background helpers and can reapply saved input/awake behavior. Preparing the app does not launch it, install the privileged lid helper, remove a legacy override, or enable lid mode.

The lid implementation does not await special Apple approval. Native timed assertions with the identified closed-lid/battery options require Apple-internal entitlements; investigating a supported replacement is an optional TODO and may be unnecessary if the supervised implementation is reliable. The current private clamshell interface, real sleep/wake and crash recovery, two-computer/multi-monitor hardware behavior, clean installation/uninstall, performance, and accessibility still require acceptance. Signing and passing simulations do not establish those results.

All 20 isolated functional suites passed for these sources. Production compilation and strict local signature verification passed; the designated signing requirement matches build 41. The runner exercises logic and AppKit flows while blocking live hardware, installation, permission and panic mutations. Build 42 was reserved by an unsuccessful compilation using a relocated module cache; after moving that generated cache aside, build 43 completed. The running build 41 and its helpers were not replaced or restarted while preparing the preview.

Build 75 preparation: production and full isolated compilation completed with
zero compiler warnings; strict nested/app signature and ZIP integrity/version
checks passed. Hidden dialog ownership fixtures passed. No visible suite or
physical-click pass is claimed while the Mac remains locked.
