# Dialog interaction audit — September 9

## Build 81 keyboard follow-up

ACCESSIBILITY-REVIEW-81.md records completed shared keyboard/accessibility
implementation and actual native-lab typing, Tab/Shift-Tab, Space/Return, popup,
multiline, result Back, picker return, explanation scrolling and default-button
checks. Those observations supersede the earlier unresolved lab Tab note.
Spoken VoiceOver and broader production-route acceptance remain release tests.

## September 9 whole-app follow-up

Build 79 adds shared focus/selection restoration and explicit accessible names;
see WHOLE-APP-REVIEW-79.md. The final full isolated run passed 21/21 suites.
The harmless native lab was operated with AGENT MODE: confirmation/Escape,
informational Back, native picker cancellation and the parent action worked.
These observations supersede the dated lab-not-operated/full-suite-pending notes
below. They do not establish native input on all 58 routes, full Tab navigation
or spoken VoiceOver. The reported original Back defect remains user-accepted.

## Build 77: result-page Back, whole-set static sweep

The user identified the affected flow on installed build 75: Test shortcut works,
but Back on both success and timeout results does not respond. X initiates
Ending shortcut test and returns to the working Agent Kill Switch parent.
The preparation screen has header Back, not a separate Cancel. Add app and
Add executable pickers work. These observations supersede the unidentified-route
status below; no agent-operated physical reproduction is claimed.

**P1, source correction and native acceptance open:** replace repeated native
modal loops in the shared Settings window with asynchronous alert presentation.
Back, X, action buttons and timers finish the exact owned alert; completion runs
after the button action unwinds and may present the next step. The shortcut
test keeps its harmless heartbeat through result/cleanup, its normal timeout,
and its bounded cleanup wait. Ordinary menu actions remain disabled while an
alert owns Settings. File pickers retain their existing native path.

Back and X previously reached the same completion method; hidden target/action
and full-root hit tests did not reproduce the reported physical-click failure.
This replaces the fragile nested-loop mechanism rather than claiming a proved
AppKit event-dispatch cause. The old synchronous `run` is now a testing-only
adapter, and the source gate rejects its use by product features.

**P2, separately found and fixed:** Setup & status repeatedly called Back until
reaching an earlier page. An invalid monitor draft can legitimately refuse Back,
leaving the page count unchanged and hanging the main thread. The shared return
helper now stops after refusal and preserves the draft's correction/discard UI.
Hidden refusal/recovery tests pass.

Static sweep covers the existing 58-site inventory:

- All app-owned alerts (shortcut stages; stop/resume/lockdown confirmations;
  helper protection/install results; catalog import/update results; navigation
  reset; group removal; wake/access notices; About and errors) use callbacks.
  Consequential branches still require their explicit acceptance response.
- Ordinary pages retain the shared header, parent stack, controller lifetimes,
  leave/refresh hooks and autosave/draft conventions. Both `beforeBack` validators
  were examined: invalid monitor-input text offers correction/discard; changed
  checked connection details ask for another check. Refusal is not swallowed in
  an unbounded parent-navigation loop.
- Only native picker ownership, administrator handoff, and the bounded shortcut
  cleanup deliberately withhold Back. No other code assigns the shared Back
  target/action or disables it. Picker return restores its prior availability.

Verification: `check-shortcut-back.py` compiles the exact production shortcut
method and shared window, injecting only status/clock/commands. It uses no modal
response driver: shared Back is dispatched after success and timeout, preparation
Back cancels, result X follows cleanup, repeated entry works and the parent
remains usable. No window or native modal session is shown. The general hidden
ownership tests also hit-test Back against the full window content and cover
stale/duplicate completion, action responses, picker return and refused Back.
The harmless dialog lab now uses callbacks too; it was built, not launched.

Fresh configuration already selects Control–Option–Command–Escape; new checks
preserve that default. Menu spelling is now `⌃⌥⌘Esc`, without changing saved
combinations or enabling the emergency shortcut automatically.

Build 77 preparation: production and final full isolated compilation completed
without compiler warnings; hidden ownership, shortcut flow and menu boundary
checks pass. Strict signature and ZIP integrity/version checks pass. A disposable
source-gate fixture confirmed that synchronous product alert calls are rejected.
The installed app remains build 75. No live-click or full visible-suite pass is
claimed for this static review.

## Historical build 75 audit

User report: another dialog had nonfunctional buttons and required the window X.
The user later recalled Agent Kill Switch setup while assigning the shortcut,
possibly a child dialog. The exact screen is still unconfirmed. Installed build 70 remains
running; prepared build 74 was not installed. This audit covers current source
at 5a92c60 and the corrections below, not a claim that the user has the fixes.

## Prioritized findings

1. **P1 acceptance open: reported dead-button route.** A native lab using the
   actual shared window code was built, but the computer-use tool reported the
   Mac locked with automatic unlock paused. No clicks were performed. The lab
   and AGENT MODE were stopped. The original symptom is not reproduced and must
   remain open until the actual route or native event replay is available.
2. **P2 source correction: completion was application-global.** Shortcut-test
   timers and obsolete backing-panel close handlers could stop the active modal
   loop without establishing that they owned it. Timers now complete their exact
   alert; obsolete handlers no longer control modal sessions. Stale controls and
   duplicate completion requests are ignored. A shortcut test cannot arm while
   another interaction is busy. Picker completion also checks its current owner.
3. **P2 source correction: external handoff could outlive the parent.** Closing
   Settings while it was handed off to Finder/System Settings removed its pages
   without clearing externalHandoff. Later page actions could remain queued with
   no visible parent to return to. Closing now releases that ownership.
4. **P2 shared hardening: refresh could bypass presentation ownership.** `show`
   checked interaction ownership but public `display` did not. Direct refreshes
   are now deferred until the current interaction ends. Ordinary task refresh,
   navigation resize and privacy-reset heading updates respect the same guard.
5. **P2 verification gap:** many dialog tests injected a modal response rather
   than dispatching the rendered button or entering a real native event loop.
   New hidden fixtures perform hit tests and actual NSButton target/action
   dispatch, including Back/X and stale timer/control checks. A separate native
   smoke app is retained for mouse/keyboard tests when the Mac is unlocked.

These findings establish source risks and corrected contracts. They do not
establish which risk caused the user's unidentified dialog failure. The native
modal APIs remain centralized in SettingsWindow; this change does not replace
all OS modal loops or use worksWhenModal to bypass their protections.

## Focused replay from the user's shortcut clue

Start with Agent Kill Switch → Agents, shortcut & panic actions. Exercise the
enable checkbox, each modifier and the key popup, including incomplete edits,
valid autosave, Back and reopening. Assignment itself opens no child alert in
the current source; do not assume the user was testing rather than assigning.
Keep configuration writes and shortcut registration injected in an isolated app.

Separately follow Agent Kill Switch → Test shortcut → preparation/countdown →
result → Back → Ending shortcut test → parent. Inject success, timeout, cancel,
helper loss and delayed cleanup. Verify actual mouse input, keyboard navigation,
parent controls after return and repeated entry. The cleanup screen deliberately
disables Waiting and Back/X while it waits, but must complete within its five-
second bound and report unconfirmed restoration. A screen that remained stuck
until X is not explained merely by that deliberate temporary disabled state.

Also cancel the neighboring Add app / Add executable native pickers and verify
parent controls afterward if the shortcut path does not reproduce the report.
Record the exact title, preceding action and first failed control. The generic
smoke lab and injected response tests cannot close this product-route report.

## Whole-set source ledger

The checked-in route inventory covers 58 UI construction/entry sites. The build
and isolated-build runner reject new unreviewed sites or feature code that starts
or stops application-global modal sessions. This is a review gate, not exhaustive
static analysis or proof that every button receives physical input.

| Dialog/page family and routes | Source audit / applicable interaction contract | Evidence boundary |
| --- | --- | --- |
| Settings home, Setup & status, category lists, Maintenance, Agent Kill Switch | Shared list buttons retain callbacks; AppDelegate lives for the app lifetime; child refresh/Back stays in the shared host | Source plus existing journey fixtures; new shared hidden dispatch test; native pending |
| Keep awake, App settings, scrolling, display category, keyboard access | SettingsTaskPage retains its owner through the page; real updates preserve controls and now pause for interaction ownership | Source and prior fixture journeys; current compilation; native pending |
| Keyboard settings/details, navigation settings/exceptions | Controls target live AppDelegate or retained closures; unavailable state differs from dead action; autosave failure restores choice | Source and existing injected action tests; native pending |
| Navigation learning/reset | Page retains owner; reset choices use shared alert; timer/focus transitions cannot resize over another interaction | Source and learning fixture cases; current shared alert dispatch; native pending |
| Monitor ordinary settings, connection/input drafts, identification, compatibility, USB connection | Parent pages retain controller; child active/cancellation tokens reject late callbacks; connection changes are draft transactions; Save/Back contracts retained | Source and prior mock transport/draft tests; no monitor command issued |
| Switching groups, group editor, remove confirmation, display labels | Group/editor lifetime retained; drafts read ordinary checkbox state on Save; removal uses shared confirmation; display labels deliberately ignore input | Source plus previous group fixtures; native/hardware pending; KVM replacement direction unchanged |
| Agent selection/shortcut/action editor, manage agents, catalog review | Editor retained by page refresh closure; selector/closure routing audited; validation failures retain working values | Source and existing autosave/draft tests; native pending |
| Add agent app, add executable, import catalog | Three routes use the same native picker owner; Back/X cannot finish another modal interaction; cancellation restores prior Back availability | Source and hidden cancellation/ownership test; actual native picker input pending |
| Terminate agents, resume, broad lockdown | Explicit shared confirmation response gates the consequential action; abort remains refusal | Source only for consequential branches; nothing executed |
| Shortcut preparation, result, cleanup, delayed success | Timers address exact active alert; duplicate/stale completions rejected; cleanup retains bounded wait and noncancellable interval | Source, compiled injected scenarios, hidden owner tests; no live shortcut/test lease |
| Protect/repair helpers, installation/protection result | Operational confirmation remains distinct; administrator work follows approval; result cannot replace OS-owned interaction | Source and prior authorization fixtures; no installation or password dialog |
| Error, About, catalog result, lid wake notice, startup keyboard notice | Shared alert dispatch/Back/X and standalone fallback; asynchronous notices wait for current owner | Source; hidden shared dispatch; standalone native input pending |
| Selective preference reset, system reset, privacy scopes/result/retry | Meaningful confirmation retained; late status updates cannot change another dialog's heading; leave/result policy stays explicit | Source and existing mock reset journeys; no reset executed |
| Input controls, event collector and their Settings/Finder routes | Controllers retained; unused backing-panel closes no longer stop global modal loops; parent close releases external handoff | Source and hidden close/reopen case; actual OS access unchanged |

The full site list is in `Tools/dialog-routes.json`. Its evidence fields explicitly
mark physical input pending; the list is not a blanket pass for all routes.

## Verification / recurrence prevention

- `Tools/check-dialog-ownership.py`: passes with all windows hidden. Covers hit
  testing and target/action dispatch, confirmation/Back/X responses, foreign and
  duplicate timers, obsolete buttons, refresh exclusion, noncancellable cleanup,
  picker cancellation, and closing/reopening after external handoff. No native
  picker/modal loop or Perch helper is invoked.
- `Tools/check-dialog-contract.py`: 58 inventoried sites; a disposable-copy test
  confirmed it rejects a new unreviewed dialog and global modal control in feature
  code. Both production and isolated builds run the gate.
- The settings-flow skill now explicitly distinguishes mocked responses, hidden
  dispatch and real modal-loop input. A dead-button report cannot be closed by
  passing only the first two. It also covers late completions and parent close
  during an external handoff.
- `Tools/dialog-lab` compiles the production window into a harmless standalone
  app. Its README defines actual mouse/keyboard, repeated entry, Back/Escape/X,
  picker return and parent-button checks. It was compiled, not operated, after
  the UI tool reported the lock.

The current full isolated suite is compiled but its visible/native run is pending
unlock. Previous build-74 suite passes are not asserted for build 75. Keep the
installed app and active lid session unchanged until native acceptance is possible.

Build 75 preparation: production and full isolated compilation completed with
zero compiler warnings; strict nested/app signature and ZIP integrity/version
checks passed. Hidden dialog ownership fixtures passed. No visible suite or
physical-click pass is claimed while the Mac remains locked.
