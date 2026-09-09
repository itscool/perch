# Dialog interaction audit — September 9, build 75 candidate

User report: another dialog had nonfunctional buttons and required the window X.
The exact page/preceding action is not yet identified. Installed build 70 remains
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
