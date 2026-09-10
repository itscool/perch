# Persistent Settings navigation — build 82

September 9, 2026. Review and implementation of the user's requested left-hand
settings list. Build 82 is prepared separately; build 77 remains installed.
This change does not redesign the status-bar menu or implement Sparkle.

## Findings and decisions

- The existing one-window host concealed the category list when entering a
  feature, forcing repeated Back navigation. A persistent native sidebar now
  exposes 22 stable destinations, grouped by feature. Settings opens Setup &
  status directly; there is no extra category-launcher page.
- A sidebar adds an exit path that must respect drafts and ongoing operations.
  Direct navigation validates before removing pages, confirms discard for
  explicit Save/Cancel drafts, and invokes page cleanup. Cancel retains the draft
  and returns keyboard focus to the category list. Busy clicks do not queue a
  later surprise navigation. Ordinary independent preferences remain immediate.
- Current selection follows child pages and direct menu entry. Clicking the
  already-selected category returns from its child to the category root.
  Selection changes reveal the row, while unchanged refreshes retain list
  position. Arrow keys choose categories; Tab enters the page's controls.
- The window retains its size across pages, with scrolling for long content.
  Tests, confirmations and OS handoffs keep exclusive interaction ownership.
  There are no new hardware, permission, sleep or agent commands.

## Route coverage

These are direct bindings to the existing production page entry points, not
claims of physically executing each feature. Existing page tests and the full
isolated suite remain applicable. Dynamic child editors/results keep their
feature's context; meaningful Save/Cancel and operational confirmation remain.

| Sidebar destination | Production entry | Evidence boundary |
| --- | --- | --- |
| Setup & status | setupOverview | First-use/repair/Back tests; light/dark render |
| Keyboards | keyboardSettings | Scope/access/layout tests; light/dark render |
| Navigation keys | navigationSettings | Behavior and parent/child tests; render |
| Keyboard layouts | testNavigationKeys | Known/learned/unknown/save-failure fixtures |
| App exceptions | navigationExceptions | Immediate-save and Back fixtures |
| Keyboard details | keyboardDetails | Scoped device/status/scroll fixtures |
| Scrolling | scrollingSettings | Saved choices versus current access fixtures; render |
| Displays | displaySettings | Existing task page and render; no physical commands |
| Monitor inputs | monitorInputSettings | Existing mapping/draft/result fixtures |
| Switching groups | monitorGroupSettings | Group/member/draft/result fixtures |
| Keep awake | keepAwakeSettings | Saved intent/unknown/active/recovery fixtures; render |
| Lid activity | lidActivity | Log limits, leaving and late-response fixtures |
| Agent Kill Switch | configurePanic | Parent/child and shared alert ownership tests |
| Agents & shortcut | editSafetyConfiguration | Autosave, shortcut result/Back and focus tests |
| Add or remove agents | manageAgents | Existing custom-entry and executable safeguards |
| Recognition | agentRecognition | Catalog validation/choice-preservation fixtures |
| Process event collection | processEventSetup | Readiness and Back/timer tests; render |
| Target preview | safetyReport | Existing read-only route and poll cleanup trace |
| App settings | appSettings | Preference/restart/busy fixtures; render |
| Maintenance | advancedSafetySettings | Repair/authorization handoff fixtures; render |
| Input access | inputPermissionsFromSettings | Ready/denied/unknown/handoff/Back fixtures |
| Reset Perch settings | resetSettingsPage | Scope/confirmation fixtures; no live resets |

The legacy monitor editor's dense guidance remains the recorded P3 issue for
KVM replacement. A persistent sidebar does not by itself resolve that content.

## Verification

- Production build 82 and final isolated compilation: no compiler warnings.
  Strict app/PerchDisplay/PerchEventLauncher signatures and ZIP integrity/build
  metadata checks pass. The package is prepared, not installed.
- Final full isolated run: **22/22 suites pass**. The affected AppKit suite
  includes new sidebar direct/child/same-category navigation, stable geometry,
  actual responder ownership, draft refusal/cancel/discard, busy exclusion and
  cleanup assertions. The shared dialog construction gate covers 59 sites.
- The first full run was 21/22 because an old test expected the removed launcher
  button. The fixture now checks the persistent keyboard destination; the
  affected suite and final full suite passed. Other overview tests were updated
  for Setup & status being the actual root, without weakening save/repair checks.
- Real input in the isolated native lab under AGENT MODE: mouse category
  selection, Down/Up category navigation, draft-discard presentation, Escape
  retaining the draft, retry, Tab/Return discard and Tab into the destination's
  editable field. The subsequent focus correction is covered by hidden actual
  responder assertions; that specific post-cancel focus fix was not replayed
  with native keys after rebuilding.
- Light/dark production-view renders inspected. They use simulated feature
  state, not the installed app's live state. This does not close spoken VoiceOver,
  every production-route native click or small-screen acceptance.
- AGENT MODE sessions ended. No installed app/helper replacement, live permission
  change, Panic, monitor command, sleep/reboot or public publication occurred.

The settings-flow skill now checks persistent category discoverability, sidebar
exit semantics, same-category return, actual keyboard focus and stable geometry.
Public signing and Sparkle's installation/handoff design are tracked separately
in DISTRIBUTION.md and the categorized TODO.md.
