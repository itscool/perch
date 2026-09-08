# Perch 1.2 — local preview

September 8, 2026, build 57. This is a local build for trying the implemented 1.2 changes; the whole-app review and physical acceptance checks remain open in [V1.2-REVIEW.md](V1.2-REVIEW.md). The previous release is [1.1](RELEASE-1.1.md).

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
