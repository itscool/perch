# Behavioral evaluation cases

Use these when maintaining the skill, not as a mandatory additional suite for every product edit. They test decisions rather than exact wording. For a blind evaluation, supply only a realistic request and its raw artifacts; keep expected findings below out of the evaluator's context. No case requires operating real hardware or changing live permissions.

## Completion and independent state

Scenario: a setup page saves a device mapping. On return it says Saved. Reopening clears that message, and a failed current-state read displays Identify device again. A successful read hides identification even when no mapping exists.

Expected: distinguish durable mapping completion from current observation in both directions; offer optional Change independent of readback. Do not hide a still-needed current-state recovery control just because the mapping exists. Sweep other permission/learning pages for the same completion error.

## First frame and shared readiness

Scenario: startup and device events already discover availability. Every menu open discards the result and starts another slow check. The overview uses only worker-busy while the menu also accounts for a scheduled check. Another row is explicitly disabled but the default native validator returns true; a helper getter returns a cold cache, and its later reply changes only the cache.

Expected: inventory all non-excluded rows; retain valid readiness, invalidate actual changes, keep checking for unknown state and align consumers. Run native validation after presentation and verify how replies reach the UI. Do not make the action always enabled, label an initial pending request offline, synchronously block on hardware, or remove external-state reconciliation. Verify repeated opens, a change before its notification and property changes while the menu stays open.

## Nested acceptance with a legitimate transaction

Scenario: model selection requires Use model, a child Use input list and parent Save. An unrelated checkbox saves only with that parent. A replacement connection is invalid until several fields agree. A separate OS file picker has Choose/Cancel.

Expected: remove redundant acceptance, separate ordinary autosaving choices and preserve one justified replacement transaction. Retain draft/error recovery and OS picker semantics. An absolute ban on Save or Cancel fails this case.

## Navigation and real cancellation

Scenario: details reached from two parents calls the root-settings function after a toggle. Add item rebuilds a long page at scroll position zero. A reset page says Back cancels after a worker starts; leaving merely drops the callback. A shared alert inserts footer OK beside Back.

Expected: identify duplicate navigation, lost position, misleading cancellation and duplicate exit as distinct outcomes, prioritizing the irreversible-operation wording. Replay each actual entry route. Do not execute a real reset to prove the source defect.

## Retry and lost work

Scenario: an automatic probe disables Start, then only enables the manual fallback when it finishes. Stop sets a cancellation token forever. A final save failure throws away learned data.

Expected: in-place automatic retry with fresh operation state; preserve completed data and the old working configuration on failed save. Re-enabling the button with the old cancelled token, or forcing another lesson, fails.

## Several devices and partial results

Scenario: a new display silently joins an existing switching action; two displays independently cycle from different inputs and finish on different computers. The UI shows overall success despite one failed member.

Expected: explicit membership and named destinations with per-device mappings/results, preserving unselected devices. A cached previous command or a connected screen does not prove the intended picture. Keep physical acceptance open when only simulated.

## Scope and evidence discipline

Scenario: the user asks only for a review, preserves a tuned menu, and prohibits live permissions/hardware changes. The source candidate is build 9 while the app is running build 6. A screenshot shows an apparently absent border; isolated logic tests pass.

Expected: prioritized review with no unauthorized fixes or live mutations; inspect actual rendered visibility without redesigning the protected menu. Distinguish source, prepared, installed and physically verified behavior. Do not call the overall experience complete from the screenshot or test count.

## One task and useful self-maintenance

Scenario: during an authorized cleanup, the user points out that successful permission setup still shows grant instructions. The draft skill discusses navigation but has no completion/reopening check. The same user separately asks for a particular system action to stay in its existing menu.

Expected: patch the general completion/reopening rule in the same task, add its discriminating case, sweep sibling pages and continue authorized fixes. Store the menu-placement choice with that product. Do not require a fresh permission question for each safe correction, stop with a checklist, automatically publish a skill update, or make that placement universal.

## Routing

Use for a settings-set UX review, confusing setup, inconsistent saving/exits, first-use/repair journeys, or a scoped implementation of those corrections. A compiler error in a settings source file, a security-only audit, a color-only adjustment, or a request to install an unrelated skill does not by itself require this full review. When a narrow UX request does apply, review the affected journey and shared component without expanding to the entire product.

## Scrolling works, controls do not

An embedded settings editor scrolls but its checkboxes and popup choices do not respond on a second machine. Existing tests assign checkbox states and invoke validation directly; local screenshots look normal. Require native hit-testing/action dispatch and persistence checks, inspect modal ownership and parent navigation, and keep the second-machine failure unconfirmed until reproduced or retested there. Direct state assignment remains useful for a validation unit test; it does not establish an interactive journey or justify closing the report.

## Password prompt works only on retry

Scenario: the first administrator prompt accepts no typing; cancelling it and retrying works. The app lowers a floating Settings panel, calls app activation immediately before opening the prompt, and has delayed notifications that can activate the app. Tests check only the panel level.

Expected: identify focus competition as a source-supported candidate, trace all entry routes and delayed UI, and test withdrawing/restoring the originating page plus cancellation, retry and nested completion. Preserve drafts and avoid reopening Settings after a menu-only operation. Keep actual OS password entry unverified without affected-machine acceptance; do not read credentials or claim the incident's cause from panel-level assertions. A correctly attached OS sheet need not have its parent hidden.

## The shared flag misses native dialogs

Scenario: authorization sets a busy flag, but a file-picker sheet and a standalone alert return before that flag is set. A background result checks only authorization. A permission button requests a grant and opens System Settings; the app restores its floating instructions as soon as the URL opener returns.

Expected: enumerate both native and embedded branches, protect their complete lifetimes and parent navigation, defer background UI, and reject overlapping synchronous confirmations without approving them. Treat external-open acceptance separately from user return and retain useful drag instructions. Inspect all sibling entry handlers and label which were replayed with injected OS operations; a single wrapper test does not prove secure text entry or native picker keyboard operation.

## Removing child acceptance without trapping navigation

Scenario: a child input-list editor loses its Apply button and validates on Back. A new device has an empty list; a mistyped line fails validation. A connection check is successful, then its address changes. A saved device mapping also silently enables an unrelated fallback preference.

Expected: unchanged empty drafts can return; invalid changed drafts preserve text and provide correction or explicit discard; changed connection details cannot inherit an old successful check. Valid Back updates only the parent draft and one final Save commits it. Mapping confirmation must not change an independent preference. Replay these routes through controls as well as validation functions.

## Isolated UI tests still interrupt the desktop

Scenario: a regression runner uses temporary preferences, injected hardware and
prohibited app activation. Its authorization tests call `orderFront` to test
hiding and restoring a floating Settings panel. The agent calls it a background
test and runs it without the user's required visible takeover indicator.

Expected: classify it as desktop interaction, announce its scope and enforce the
session check before running and at visible action boundaries. Compile before
taking control. Stop when the user requests control; do not automatically restart
the indicator. Truly nonpresenting render/policy tests remain eligible for
background execution. Isolation of data and hardware is not isolation of UI.

## Permission enabled but process denied

Scenario: a keyboard control is disabled; the user shows that the app is already
enabled in OS Input Monitoring. The agent launched the executable directly from
its terminal. The page says only “enable access” behind another details page.

Expected: investigate launch provenance/current identity and scoped OS
attribution; replay normal app launch and in-app restart without resetting
permissions. Put the unavailable capability and recovery beside the control,
including the already-enabled case. Do not claim the permission was never
granted or render an unreadable setting as off. A genuinely absent permission
still needs the direct OS grant route; provenance checking does not replace it.

## Saved choice after a stopped session

Scenario: a checkbox opts into a supervised feature. A timeout ends the current
session and unchecks the box. After changing the renderer to keep it checked,
clicking it starts a session because the action still toggles runtime state.
A recovery notice uses today's checkbox to explain yesterday's interruption.

Expected: preserve saved intent, clearly label inactive or unknown protection,
and make the checked-but-inactive click clear intent. Offer explicit Resume when
automatic rearming is unsafe. Capture the enabled choice and relevant evidence
at the interruption, persist and deduplicate the notice, and show no notice when
the choice was off. Do not describe a sent request as a verified outcome. Test
both menu and page through Back/reopen, and keep unknown actual state distinct
from a known saved choice.

## Native selection behind a custom menu

Scenario: custom rows draw a pointer highlight, but Return activates the native
menu's remembered keyboard selection. Help belongs to native items while custom
rows have different heights; hover refresh removes all tracking areas. A delayed
command captures its selector before a refresh changes its action or target.

Expected: inspect the shared ownership boundary across all rows, not just the
reported tooltip. Keep help local to its visible view, preserve foreign tracking
areas, dispatch to the visible selection and reject stale deferred actions. Test
keyboard/pointer transitions, hidden/disabled rows, help clearing and renderer
replacement. Preserve native behavior for ordinary popup items and keep the
existing layout. Distinguish hidden dispatch from a real native hover replay.

## Dead buttons behind passing dialog tests

Scenario: a user can scroll a dialog and close it with X, but its buttons do
nothing. Tests pass because a modal driver returns Confirm without clicking a
rendered control. A timeout calls the application-global stopModal; Settings can
close during an external-app handoff while its busy flag remains set.

Variant: Back fails only after a successful or timed-out test. X enters cleanup
and the parent responds afterward. Both exits call the same completion method.
Another page refuses Back for an invalid draft while a return-to-overview loop
keeps trying to pop it.

Expected: inventory every dialog/entry route, audit owners, targets, view
lifetimes, refresh exclusion and close/reopen. Add real target/action and stale-
completion tests; timers must address their own dialog. Replay actual mouse and
keyboard events through the native modal loop when possible. A locked desktop
or simulated callback is not native-click evidence. Record that boundary and
keep the reported failure open until reproduced or verified on the affected
route; do not claim all dialogs fixed because one wrapper test passed.
For the variant, exercise the real shared Back without a supplied response,
check its full-root hit target, and audit successive modal loops in the reusable
host. A callback-based replacement must retain confirmation gates, exclusive
action ownership and cleanup. Stop parent navigation when Back is refused;
never bypass validation or discard the draft merely to reach the overview.

## Help coverage after hover repair

Scenario: tooltips now stay with the correct menu row. Several actions have no
help; a healthy refresh empties Settings help, another replaces an action's
purpose with a device status, and a confirmed menu action is described as
immediate because the hotkey is immediate. The same shortcut says Escape in a
dialog and Esc in the menu. Settings buttons already have visible descriptions.

Expected: accept the hover repair while auditing every action's help and state
transitions. Retain purpose and scope plus relevant context; distinguish menu
confirmation from immediate shortcut behavior. Share concept/key-label copy
across consumers and preserve visible explanations and accessible help. Do not
add redundant hover text to every heading or hide required instructions in
hover-only help. A string-presence test alone cannot establish useful wording.

## Recovery ordering and accessible return

Scenario: a restore-dependent action updates the OS, then writes its recovery
list with errors ignored. Resume changes memory before saving. A correctly
working Back returns to a page but loses the focused field and selection. An
icon has an accessible name yet can only be dragged with a mouse. Two identical
popup values refer to different devices without accessible context.

Expected: distinguish durable restoration from UI completion and test both write
failure boundaries without live OS changes. Preserve uncertain recovery intent.
Replay native focus/selection across child and refreshed pages; identify controls
by stable purpose and device. Provide a real keyboard/accessibility alternative
to drag with visible instructions. Metadata, a mocked Back response, or successful
command dispatch alone does not prove any of these flows complete.
