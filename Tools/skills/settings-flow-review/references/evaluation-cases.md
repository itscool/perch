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

## Buttons named but unreachable by keyboard

Scenario: a settings set has accessible labels and passes direct button-dispatch
tests, but Tab leaves focus on the window with macOS keyboard navigation off.
A long result uses a read-only label in a scroll area. A custom key handler also
intercepts Return and Control–Option combinations.

Expected review: distinguish OS policy from missing app navigation, verify real
focus and native input without changing the OS preference, provide readable
long-result navigation, preserve default buttons/text editing/VoiceOver chords,
and retain explicit spoken-VoiceOver acceptance. Do not mark accessibility done
from labels alone or announce unchanged polling on every refresh.


### Persistent category navigation

Scenario: every settings page autosaves and has a working Back, but users must
return through several pages to find another feature. A proposed sidebar clears
the old stack on every click, including invalid drafts and active tests. Clicking
the selected category does nothing when a child is open.

Expected: identify discoverability separately from button consistency. Use
persistent direct destinations for stable pages; retain transient interaction
ownership. Respect validation and explicit discard, preserve saved settings,
clean up page work, and make same-category clicks return to the root. Verify
mouse/arrow/Tab navigation and actual focus after cancelling, not only selected
row metadata. The legitimate exception is a confirmation or operation that must
finish/cancel before navigation, with a clear explanation and no queued surprise.

### Editing, activation and redundant chrome

Scenario: a preset editor has three cards, an Active badge and a large footer
repeating which preset is active plus Choose/Use buttons. Removing Apply causes
clicking a card to execute hardware changes, although users only wanted to edit.
The app recently gained a sidebar, but stable pages retain Back buttons and
ordinary connection edits still open nested dialogs. A None choice could mean
skip the device, turn it off, or merely leave a device mapping unassigned.

Expected: preserve distinct editing and activation, colocate a compact explicit
activation action with its preset where suitable, and retain independent active
state. Remove redundant persistent status/navigation, move ordinary edits inline,
and define meaningful operational choices separately from incomplete setup.
Do not hide useful pending/error information or remove scoped draft/operation
exits. Persistent progress during a long operation is a legitimate exception;
an Active badge repeated in a footer is not additional evidence of completion.

### Expanded editor loses its owner

Scenario: each connection row has a pencil. Clicking it inserts a text field,
computer dropdown and repair actions between that row and the next, with no
shared visual boundary. The common computer mapping requires expanding this
editor even though the complete choice fits in a dropdown.

Expected: expose the simple mapping choice directly, and visually group the
expanded advanced fields with their owning row using restrained contrast and a
readable boundary. Preserve the row identity and an obvious collapse action.
Do not add decorative containers to every unexpanded row or replace native
dropdowns with more dialogs.

### Expansion introduces a scrollbar and reflows controls

Scenario: an inspector fits without scrolling until a connection editor opens.
The new scrollbar narrows all dropdowns, shifts the pencil buttons and wraps
labels. Collapsing the editor while scrolled down can leave the top clipped.

Expected: keep content width stable across overflow, using a fixed gutter or an
overlay inside the margin. Verify expansion, scrolling, collapse and text-field
focus. Preserve native scrolling/accessibility and avoid covering controls.
Responsive reflow caused by deliberately resizing the window is legitimate.

### About opens an unusable settings shell

Scenario: About opens inside the shared settings window, acquires an alert scope,
and disables the visible category list. Only dismissing About works.

Expected: use an independent modeless About dialog, or a normal navigable page
with no exclusive interaction lock. Verify the existing settings page, draft,
and focus survive opening and closing it. Keep real confirmation/test ownership
when a competing action would be unsafe.


### A new feature exceeds the setup overview's row capacity

Scenario: a new sharing page works on its own. Setup & status now emits eight
checks, but its native view still creates seven labels and seven action buttons.
Refresh indexes the parallel arrays using the model's length.

Expected: identify the first-use crash, build rows from the model or otherwise
remove the capacity mismatch, and test that the last feature stays visible by
scrolling and navigates correctly. Preserve control identity and scroll position
on unchanged refresh. A genuinely fixed, exhaustively validated enum is not a
reason to redesign every fixed-size form.


### Add saves but the child list does not refresh

Scenario: Add keyboard commits a new record and syncs it to another computer.
The open child view observes connection status but not the group containing its
list, so the new record appears only after closing and reopening.

Expected: trace the action, persisted record and view observation separately.
Fix the missing model observation and verify one click creates one immediately
visible item, including remote additions. Do not disable the working button,
add a second Save step or mistake a successful backend write for a working flow.

### Embedded editor without an Edit menu

A menu-bar application hosts native text fields inside SwiftUI sheets. Typing and
clicking work, but Command-A does not select text; the app only installs a Quit
command. Its isolated fixture also omits the application menu. Review should
trace shared native command dispatch, supply standard responder-chain editing
actions, align the fixture with production, and replay real selection/replacement
and child exit. It should not rewrite each field or declare keyboard acceptance
from manually assigning an NSTextView selected range.

### Retained library with no path from the replacement setup

A device wizard is replaced by a shared settings page. The protocol library and
model-identification table still ship and pass tests, but the new page only reads
generic device names. Two models with the same generic name need different port
codes. Expected: trace detection through suggestion, override and saved setup in
the new page, including remote devices and late results. Do not call retention
complete from library tests, silently replace a manual choice, infer unique
physical identity from a model family, or restore intentionally retired features.

### Native inventory misses a family of declarative settings sheets

Scenario: a source gate inventories every native alert and settings constructor.
One hosted declarative root uses a string-selected sheet for pairing, ordinary
preferences, conflict resolution, removal and device control. The native gate
counts the root once, while old fixture-only pages contribute many extra sites.

Expected: enumerate the production sheet cases and their distinct save/exit/error
journeys; separate fixture-only pages from current user routes. Do not infer full
coverage or interaction ownership from a passing native constructor gate. Ordinary
settings may benefit from direct navigation, but real pairing and destructive
confirmation may legitimately remain dialogs. Static-only permission does not
authorize launching those sheets to obtain missing native evidence.


### Saved shortcut replacement and competing shared edits

An emergency shortcut editor checks only a retired device model. A new shared
preset editor checks the emergency preference. Registration releases the old
shortcut before discovering the replacement is occupied. Separately, two shared
versions differ only in input codes and keyboard attachments, but their comparison
shows identical screen names.

Expected: validate both editors against current resources, preserve working
registration on failure and show saved versus registered state. Include the values
that a whole-version decision replaces. Do not claim the new shortcut works just
because saving succeeded, or solve the comparison by silently choosing a version.
For an unrelated pristine name field, accept remote text automatically; an unfinished
local draft must survive and offer a clear reconciliation path.

## One setup owner, contextual feature links

Scenario: an app has Setup plus Keyboard and Sharing settings. Both feature pages
embed their own copy of Input Monitoring instructions and each can install the
same helper. A sharing failure can also mean that the other computer is locked.

Expected: place each prerequisite/repair stage once in Setup, with direct links
from affected features and consistent checklist selection/return. Re-entering
from another feature must not duplicate the stage or reset working setup. Preserve
ordinary keyboard/layout choices and sharing-session recovery under their topics;
a locked remote computer is not evidence of missing permission. Check every
entry route, including permission loss during learning and helper update failures.
Do not mandate a separate Setup section for a product with one trivial permission
or move routine customization merely because it was first chosen during setup.

## Destination names and reset discoverability

A settings checklist says “Review repair,” a ready permission page says “Review
setup,” and a sidebar Reset page only forgets preferences. Sleep, privacy,
appearance and saved-device resets are hidden in unrelated feature pages.

Expected: identify unclear destination/disclosure wording and incomplete reset
ownership as one journey defect. Name destinations and Show/Hide instructions
accurately; inventory all reset entry points and make their scopes discoverable
from the reset center. Contextual repair links must open the exact option under
that owner and return to the same setup step/checklist after Cancel, failure,
success and retry. A generic index link is insufficient. Choosing another sidebar
page or closing the window must not retain a stale return. Preserve
real review of proposed changes, ordinary editing, destructive confirmation,
Cancel, disconnected devices, and failed-write retry. Do not perform live resets
to prove navigation. Verify navigation separately from injected scoped writes.


## Scope selection without a tour of child pages

A reset center has six buttons. Each opens a short explanation, then a checkbox
or target picker. People must visit all six to learn what can be reset. A repair
link lands in the center, and the fixed window clips the longer explanations.

Expected: bring comparable scopes and concise consequences onto the center page,
with inline detail for device targets. Keep broader all-app effects distinct from
app-local selections and preserve explicit confirmation. Highlight repair targets
without selecting them. Verify multi-selection, overlaps, partial failure, retry
without repeating successes, and quit ordering. An initially unchecked checklist is the default for independently resettable areas,
with inline scope/targets and joint confirmation. Separate pages remain legitimate
for substantial distinct work; an indivisible reset must not acquire fake independent
checkboxes. This depends on reset semantics, not whether the app is a tool or game.
Verify resizing uses extra space, preserves selection/confirmation, remembers size
across pages and reopening, and remains usable when restored on a smaller screen.

## Propose the complete structure early

A utility has 25 individually tidy settings dialogs. A requested flow review finds
consistent Back buttons and autosave, but first setup, repair and reset are spread
across several topics. The user asks for the nicest complete settings experience.

Expected: begin with a compact proposed navigation and representative first-use,
change, repair and reset journeys. Establish one home per task and justify extra
steps before polishing each existing dialog. Then audit and implement within the
authorized scope. Do not treat the proposal as mandatory user approval or expand
a narrow button fix into a whole-app redesign.

## First implementation, without an existing defect

Request: “Build settings for a new file-transfer utility. It has folder access,
saved destinations, transfer preferences, appearance, and independently resettable
preferences and destination lists.” No settings screens exist yet.

Expected: apply this skill before writing the screens. Define task homes,
contextual prerequisite recovery, ordinary autosave versus a validated destination
draft, and an unchecked reset checklist with explicit consequences/confirmation.
Show the overall navigation and representative journeys, including completed setup,
failed destination validation, lost folder access and return after repair. Encode
the contract in appropriately shared components and complete one flow through
success/failure/return before repeating it. Proceed with authorized implementation;
do not wait for a defect report, demand a review of nonexistent pages, invent
release history, or claim a prototype proves runtime behavior.

Boundary: “Add a launch-at-login preference to this established settings page”
should inherit its save/navigation conventions and handle an unavailable or failed
write. It must not trigger a new sidebar, setup wizard, reset center or framework.

## Expected automation versus an incident

A utility intentionally stops protection after a configured grace interval and
records the result. Its wake observer sees a saved enable flag plus a briefly stale
active status, then replaces the user's Settings page with an error about sleep.

Expected: planned expiry remains in history without an incident dialog. Correlate
current-interval evidence, including reordered callbacks; old expiry records must
not suppress a later actual interruption. Distinguish saved intent from active
protection. Where acknowledgement of an unexpected incident is warranted, use a
separate notice, defer during existing interactions and preserve Settings drafts.
Open history only when requested; missing evidence cannot establish a cause.

## Navigation that earns its place

A menu utility has a Scrolling page repeating two menu switches and an access link,
a Displays page containing only Open Desk and Turn display off, and Desk settings
for three names and shortcuts. Setup already owns access. Other pages contain
keyboard exceptions and live event diagnostics.

Expected: consolidate the wrapper pages, edit names beside their objects, group
shortcut editing in one home and preserve meaningful exceptions/diagnostics. Do not
ban every contextual link or erase feature-specific configuration. Ready/attention
markers beside Setup entries must use observed state, preserve optional/unknown
meaning, and update without selection or focus churn.

## Stable permission disclosure

A ready permission page replaces its status with a large repair layout when Show
instructions is clicked; the status moves below the instructions. Another page
shows both a settings link and a settings button with staggered helper drag cards.

Expected: status stays anchored above disclosure; required recovery is expanded
and cannot be collapsed, ready recovery defaults collapsed and can be reviewed.
Exercise readiness loss/regain, partial grants and manual expansion without losing
focus. Align correctly identified file targets and provide one action per OS
destination. A missing helper needing installation must not instruct the user to
grant a nonexistent or unverified file.

## Visible controls outside their hit area

A task page gained two rows without changing its fixed document height. Every
button paints and is enabled; direct performClick tests pass. The last two rows
ignore mouse clicks while earlier rows work.

Expected: inspect parent bounds and native hit testing, derive document size from
the rows, and sweep sibling pages using that helper. Add geometry/hit tests rather
than another action-only test. Keep physical event routing acceptance explicit;
do not infer a permission or modal problem solely from the dead buttons.

## Session start hidden behind advanced input options

A paired-device canvas has screens and presets but no sharing control. A separate
page contains session enable, its own preset selector, and an optional physical
keyboard host-switch matcher. A user expects pointer crossing to work after pairing
and thinks the matcher is mandatory.

Expected: put session enable/readiness/start in the primary canvas journey, using
its existing selected objects. Explain what each device must enable and what a
restart ends. Keep optional host-follow automation and tuning separate, with
concrete physical-device matching steps. Do not silently enable capture on peers
or equate permission readiness with an active sharing session.

## Spatial editing without hidden primary choices

Scenario: monitor cards have clickable sockets, but a full-height scrolling overlay intercepts body dragging. Clicking a socket secretly chooses its preset input. All cables look identical. The inspector repeats preset dropdowns; an empty-preset warning appears over the canvas. Dragging an occupied input creates another cable or disconnects the original before a valid drop. An Unchanged option appears even though execution requires every monitor.

Expected: visible direct preset choices, distinguishable cable gestures, route/endpoint highlighting tied to the editing preset, actual control-only exclusions, hover/focus feedback, and per-preset attention. Rewire atomically with cancel/concurrency checks; test omitted monitors through execution and input routing. Keep secondary connection actions in a menu when useful; this is not a blanket prohibition on context menus.
