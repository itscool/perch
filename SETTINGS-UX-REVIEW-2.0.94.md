# Full static Settings UX review

September 10, 2026. Reviewed source: `cb44f87c2cca5e5e19f8901603bbcc54eef16602`.

## Outcome and evidence boundary

The complete current Settings set has now received a source-based UX pass: all
24 sidebar destinations, their task/confirmation/permission children, and the
11 production Desk sheet states. This is broader than the preceding setup-only
review. It follows first use, ordinary changes, repair, add/remove, learning,
completion, leaving/reopening and external changes where applicable.

**The initial review found 11 actionable issues: one P1 and ten P2.** The user
authorized all corrections, including design refinements D1–D3. They are now
implemented in source as described below. No GUI interaction, permission changes,
hardware actions, installation, notarization or publication were performed during
this correction pass. Native clickability, visual contrast and real permission/
hardware acceptance remain separate from source and compile verification.

Current release notes were read first. Installed/public 2.0.94 uses the earlier
466b2ec source snapshot. The preceding setup corrections in cb44f87 have compiled
but are not installed or natively accepted. Findings here apply to cb44f87 unless
stated otherwise; they are not claims that the earlier corrections shipped.

## Correction checkpoint — all findings implemented in source

The original findings and source references below are historical evidence at
cb44f87, not a description of the corrected source. The application currently
installed/public is still 2.0.94; these changes have not shipped.

| Finding | Implemented correction | Verification / remaining acceptance |
| --- | --- | --- |
| U1 | Both shortcut editors use current Desk presets and the emergency shortcut. Desk registration invalidates when the emergency choice changes. Emergency replacement acquires a new registration before releasing the working one, rejects queued events for obsolete registrations, and reports the actually registered keys separately from saved intent. | Registration replacement assertions and injected readiness regressions compile; physical key registration and use remain native QA. |
| U2 | Reset is explicitly local. Labels name learned navigation layouts versus local preferences/keyboard modes/agents; confirmation expressly retains shared Desk membership, computers, screens, connections and preset shortcuts. | Traced defaults, Safety files and separate Desk storage. No live reset performed. |
| U3 | Turning either navigation behavior off skips layout-store reads and preserves the other behavior and current helper payload. Enabling still validates profiles. | Added injected damaged-store disable/enable regression; compiled, not executed. |
| U4 | Agent Kill Switch offers the existing Resume action and explains blocking when lockdown or unrecovered launch jobs remain. | Traced checklist → Agent page → existing confirmation; no agent operation executed. |
| U5 | Add app/executable returns success/failure; only success rebuilds the custom-agent list. Cancellation and validation/storage errors retain the originating page and feedback. Removal already rebuilt only after success. | Static callback/lifetime trace; existing picker ownership fixtures updated and compiled. |
| U6 | Completed, saved layout setup offers Choose another keyboard. It restores selection/relearn controls without automatically starting capture. Failed save retains its retry path and saved prior layout; missing identity offers the next-keyboard route. | Completion/reset source trace; native layout suite compiled. |
| U7 | Input names retain invalid drafts with errors/retry. Input codes retain all typing and save on Return, focus loss or editor exit after complete validation. Intermediate digits are not automatically stored while typing. Leaving after a reported failure discards that draft rather than silently retrying it. | Nonpresenting draft tests passed; native text selection, focus loss and closing need acceptance. |
| U8 | Pristine names follow incoming changes. Dirty drafts survive and expose Use saved / Keep my edit. The same component covers screen, connection, Desk, preset and shared-keyboard names. | Pure pristine/dirty/repeated-remote/own-acknowledgement transitions passed. Two-machine UI propagation remains QA. |
| U9 | Each version lists identities, panel size/position/rotation, every input code/mapping, monitor-control host/display/protocol/endpoint/address/model, every preset assignment/shortcut, and shared keyboard attachments/follow choices. Whole-version resolution still requires an explicit choice. | Pure tests prove operational differences produce different review content; real conflict selection remains QA. |
| U10 | Stable Agent, target preview, event collection and layout pages use route-neutral completion/leave language. Real test-result and destructive confirmation exits remain scoped operations. | Source sweep; contextual setup return and physical navigation remain native QA. |
| U11 | App exceptions has Add app and custom Remove. Custom names remain listed when unchecked and on reopening. Changes merge into fresh preferences; failure keeps the previous row/value and visible error. | Injected toggle/reopen/remove-failure/success regression compiled; OS app picker acceptance remains QA. |
| D1 | Desk settings and Keyboard & mouse sharing are stable sidebar pages. Shared names/presets and per-Mac/session controls have distinct scope wording; membership removal remains visible. Pairing/removal/conflict and per-screen control editing retain temporary dialogs. | Now 26 sidebar destinations and 10 reachable production Desk sheet journeys. Sidebar/recovery regression compiled. |
| D2 | Border and highlight-dependent controls disable when their area is absent; border copy names the prerequisites. Saved choices, independent System styling and the shared preview remain. | Static condition/render trace; native clipping, contrast and keyboard access remain QA. |
| D3 | Keyboard access leads with Ready and optional Review permission setup when granted. Lost access automatically exposes repair, current app drag/copy, Finder and System Settings actions. | Ready/review/hide/revoked fixture compiled; live permission handoff remains QA. |

Validation: `Tools/check-settings-models.py` passed without creating windows,
launching app/helpers, reading devices or writing live settings. The UI ownership
gate inventories 61 native construction sites. The full regression fixture and standalone Desk Lab compile without warnings.
The Desk Lab build treats warnings as errors. No native test
binary was run under the static-only instruction. The reusable review skill now
includes current-resource conflicts, complete conflict comparison, reset-store
scope and synchronized field drafts; structural validation passed and its added
scenario was reviewed locally, not by an independent agent.

## Findings in recommended correction order

### U1 — P1: Emergency shortcut validation still checks retired monitor settings

**Journey:** In Desk settings, give a preset Ctrl–Opt–Cmd–F6. Then set the Agent
Kill Switch to the same combination. The agent page accepts and saves it because
its conflict closure checks `monitorInputs.plan` and the old switching group,
not the live Desk presets. The background guardian unregisters its prior shortcut
before attempting the new registration. A collision can therefore remove the
working emergency shortcut. The edit page reports a saved shortcut, without
showing the registration failure there.

**Evidence:** `Sources/PanicUI.swift:185–192`,
`Sources/AgentSettingsPage.swift:97–131`, `Sources/PanicShortcut.swift:39–45`,
`Sources/AgentGuardian.swift:244–259`, `Sources/DeskRuntime.swift:339–364`.
Desk checks for Panic when registering, but the reverse editing path is missing;
its registration cache also keys only on the Desk shortcuts.

**Correction:** Validate against the current Desk shortcuts in both directions,
preserve the prior working registration on failure, and show saved versus actually
registered status next to the shortcut editor. Reevaluate conflicts when either
configuration changes. No main-menu redesign is needed.

### U2 — P2: Reset's advertised scope excludes the new Desk configuration

**Journey:** Choose Device setup, or Reset all settings, expecting shared-screen
mappings and related setup to be forgotten. The reset handles old monitor defaults,
keyboard profiles and selected files in the safety directory. It never handles
`Perch/Desk/desk.json`. On reopening, Desk automatically resumes from that file,
including its screens, mappings and shared preset shortcuts.

**Evidence:** `Sources/ResetSettings.swift:4–73,101–141`;
`Sources/DeskRuntime.swift:368–385`. The source still uses the retired monitor
keys when classifying device setup.

**Correction:** Define the actual reset scopes before implementation. Separate
local device/access preferences from shared desk membership and shared arrangement.
Either explicitly exclude Desk in the labels/confirmation or offer a separately
reviewable leave/forget operation. Do not silently erase a synchronized group on
other computers as a consequence of a local reset.

### U3 — P2: Turning navigation off depends on successfully reading damaged layouts

**Journey:** A saved navigation profile becomes unreadable. Home/End or Page
Up/Down is enabled, so the page correctly leaves its checkbox available to turn
off. The handler nevertheless reloads all profiles before saving *any* change.
That read throws, and the off choice is never saved. Recovery now requires resetting
layouts merely to stop the behavior.

**Evidence:** `Sources/NavigationSettingsUI.swift:23–24,59–85`;
`Sources/KeyboardRegistration.swift:39–47`.

**Correction:** Save disabling choices without requiring a fresh layout read;
preserve the last usable profile payload for any remaining enabled behavior.
Show the independent layout-repair issue and verify the failure/off path.

### U4 — P2: Setup's “resume agents” route has no Resume action

**Journey:** Agents remain blocked after Panic. Setup & status identifies that
condition and tells the user to review protection to resume. Its destination is
Agent Kill Switch, whose Settings options contain configuration, tests, repair
and another destructive stop, but no Resume action or current blocked-state
explanation. The usable Resume command exists only on the main menu.

**Evidence:** `Sources/SetupOverview.swift:113–116,303–314`;
`Sources/PanicUI.swift:103–111,127–140`.

**Correction:** Give the blocked Settings state the existing, confirmed Resume
flow and show what it does. Keep the main menu intact. Replay checklist → blocked
status → Resume → updated checklist.

### U5 — P2: Adding an invalid agent erases its own error

**Journey:** From Add or remove agents, choose a general-purpose executable,
invalid app, or encounter a save failure. `addTarget` displays the error inline,
but the caller unconditionally rebuilds `manageAgents` immediately afterward.
`SettingsWindow.show` clears feedback on that rebuild. The picker disappears,
no agent appears, and the reason disappears in the same action.

**Evidence:** `Sources/PanicUI.swift:155–159,197–217`;
`Sources/main.swift:417–430`; `Sources/SettingsWindow.swift:310–323`.

**Correction:** Return a structured cancelled/saved/failed result. Refresh the
list on success; preserve failure feedback and an obvious retry on the current
page. Audit sibling picker-return handlers for the same pattern.

### U6 — P2: Completed keyboard learning has no next-device/change action

**Journey:** Open Keyboard layouts directly from the sidebar and finish learning.
The completion state hides the keyboard picker, Recheck, Start and Reset. There
is no action to choose another keyboard or relearn this one. Clicking the same
sidebar category does nothing because the shared navigator returns early for an
already-open root page. The user must visit an unrelated page and return.

**Evidence:** `Sources/NavigationProbeUI.swift:180–207`;
`Sources/SettingsWindow.swift:111–118`;
`Sources/SettingsNavigationRoutes.swift:12`.

**Correction:** Keep the durable “layout saved” result, and offer an optional
Choose another keyboard / Learn a different layout action. Do not restart capture
or ask for more keypresses automatically. Include a direct-sidebar completion test.

### U7 — P2: Desk connection fields still reject normal replacement editing

**Journey:** Clear an existing input name or code to type its replacement. The
name field is bound directly to validated shared state; an empty name is rejected
and the field has no independent draft. The code field silently drops invalid,
empty or zero strings. Intermediate valid digits can be saved as the actual code
before the intended replacement is complete. This repeats the old desk-name
editing problem that already received a local-draft fix elsewhere.

**Evidence:** `Sources/DeskView.swift:137–143`;
`Sources/DeskModel.swift:125–138,205–207`;
`Sources/KVMGroup.swift:155–159`. Compare the name-draft handling in
`Sources/DeskLiveSettings.swift:181–190`.

**Correction:** Retain editable text independently, make incomplete/error states
explicit, and preserve the working value until the replacement meets a defined
editing/validation boundary. Keep ordinary saving automatic and avoid adding an
unexplained Done button.

### U8 — P2: A synchronized screen rename leaves the visible editor stale

**Journey:** Two Perches display the same selected screen. One renames it. The
other receives the updated group and canvas name, but its Screen name field uses
`@State rename`, synchronized only on appearance or selected-screen-ID changes.
The selected ID does not change, so the editor continues showing the old name.
A later local edit starts from that stale text despite successful synchronization.

**Evidence:** `Sources/DeskView.swift:14,103–115`;
`Sources/DeskRuntime.swift:125–138`.

**Correction:** Update pristine fields when shared state changes, retain genuinely
unfinished local drafts, and explicitly handle a concurrent change to the edited
field. Verify rename propagation without changing selection or reopening Settings.

### U9 — P2: Conflict resolution cannot show what the user is choosing

**Journey:** Two computers change different input mappings, input codes, monitor
control routes, screen sizes, preset shortcuts or shared-keyboard bindings. The
conflict sheet asks which whole arrangement to keep, but displays only screen
name/X/Y/rotation and preset names followed by input names. Different arrangements
can therefore render identically—particularly when multiple screens use “USB-C.”
Keeping a version resolves the whole group, including differences not shown.

**Evidence:** `Sources/DeskLiveSettings.swift:207–225`;
`Sources/KVMDeskNode.swift:314–321`.

**Correction:** Present meaningful differences with screen and computer identity,
not just port names. Include every editable field that the decision will replace,
and identify the competing version/source where available. Preserve both versions
until the decision is made; do not add blind merge behavior to hide the UX gap.

### U10 — P2: Several stable pages still instruct users to press nonexistent Back

**Journey:** Open a stable page directly through the sidebar. The shared host
correctly hides Back, but page copy still refers to it:

- Agents & shortcut: “Back discards unsaved shortcut edits.”
- Target preview: “Use Back to return to Agent Kill Switch.”
- Process event collection, ready state: “Use Back to return…”
- Keyboard learning, listening/save-failure states: “Back stops setup…” /
  “use Back to leave.”

The prior fix changed the shared button policy and some success copy, but did
not finish the route-specific wording sweep.

**Evidence:** `Sources/AgentSettingsPage.swift:84`, `Sources/PanicUI.swift:331`,
`Sources/EventSetup.swift:117`, `Sources/NavigationProbeUI.swift:174–175,224`,
`Sources/SettingsWindow.swift:251–255`.

**Correction:** Use route-neutral wording about leaving/changing category, or
derive the actual contextual return label from the host. Preserve Back to setup
for checklist-origin journeys and scoped cancellation for real operations.

### U11 — P2: App exceptions cannot add an app outside the preloaded list

**Journey:** A user wants one particular editor or other app to retain its native
navigation behavior. The exceptions page offers only the union of built-in names
and IDs already stored in the preferences, with checkboxes. There is no add-app
picker or editable entry path, so a new custom app cannot be excluded through UI.
The behavior model supports those IDs, but Settings cannot create them.

**Evidence:** `Sources/NavigationSettingsUI.swift:88–137`.

**Correction:** Provide Add app with immediate persistence, a named custom entry,
and an explicit scoped removal action. Keep existing browser defaults and their
explanation. This is a missing adjustment journey, not a request for a larger
exception system.

## Design refinements, separate from confirmed functional defects

- **D1 — Persistent Desk settings deserve a direct Settings destination.** Desk
  names, preset shortcuts, pointer speed, access and shared keyboards currently
  occupy a 440-point sheet reached through Desk → Desk settings. Keep pairing,
  removals and conflict decisions as temporary dialogs. Consider sidebar children
  for the ordinary shared-desk preferences and local input-sharing settings, with
  clear “shared with the desk” versus “this Mac/session” grouping. This is a
  grouping recommendation, not evidence that every SwiftUI sheet button is broken.
- **D2 — Appearance should explain inactive controls.** Thickness/intensity remain
  editable with Border=None; background sliders remain editable with Highlight=None.
  Those edits have no visible effect. Either disable dependent controls with clear
  context or explicitly explain that they are retained for when the area is enabled.
  Preserve the requested breadth, independent System styling and shared-renderer preview.
- **D3 — Ready permission pages should lead with readiness.** Keyboard access now
  correctly reports granted access, but retains the full add/replace grant recipe
  and recovery actions as the main content. Put optional repair behind Review access
  when healthy. Keep repair discoverable; don't hide a later lost grant.

## Coverage ledger: every current sidebar destination

“Traced” means source-reviewed, not native-tested. A cell without a finding is
not a blanket guarantee: it means no additional supported issue was found in the
listed paths. Shared findings and previous source corrections still apply.

| Destination | Journeys and states traced | Disposition |
| --- | --- | --- |
| Setup & status | First/unseen, seen-but-required, checking, optional, ready, blocked, next-action routing and return | U4; preceding setup fixes retained |
| Keyboards | Built-in/external/no device, checking, permission denial, mixed modes, change/recheck/details | Traced; correct group scope; shared feedback/return acceptance pending |
| Navigation keys | Enable/disable, missing helper/grant/layout, unidentified source, app exceptions | U3 |
| Keyboard layouts | Recognized/unknown/disconnected, learn/skip/release, timeout, failed save/retry, reset one/all, finish/reopen | U6, U10 |
| App exceptions | Defaults/custom persisted IDs, toggle, save failure, reopening | U11 |
| Keyboard access | Denied/already granted, stale-copy recovery, drag/copy, Finder/System Settings return, recheck/ready | D3; earlier permission fixes source-only |
| Keyboard details | Per-device results, empty/checking/errors, native settings, recovery and sibling navigation | Traced; no separate new finding |
| Scrolling | Independent trackpad/wheel autosave, missing helper/access, saved-on disable, waiting application, recovery | Traced; no new finding beyond previous setup corrections |
| Displays | Desk entry, current summary, separate turn-display-off action | Traced; no change to protected main menu proposed |
| Desk | New desk, add/remove/match screens, mappings, presets/edit versus Play, rotation/position, grouped synchronization | U7, U8, U9, D1; child ledger below |
| Desk settings (added correction) | Shared names/shortcuts, invalid draft, peer edit, pending acknowledgement, registration error | D1, U1, U8 corrected in source |
| Keyboard & mouse sharing (added correction) | This-Mac/session scope, permission recovery, pointer speed, shared keyboards, membership loss | D1, U8 corrected in source |
| Keep awake | Off/on/saved lid choice, helper absent/pending/fresh/error, explicit install/repair/resume, log and reset links | Previous S8 corrections traced; no live sleep claim |
| Lid activity | Loading/history/error, live/pause, selecting/copying, retained scroll, leave and late reply | Traced; no additional finding |
| Agent Kill Switch | Helper absent/ready, shortcut off/unavailable/test, blocked activity, repair and broad action entry | U4 |
| Agents & shortcut | Agent selection, modifier/key edits, invalid/incomplete/save-failure/retry, privacy scope, leaving | U1, U10 |
| Add or remove agents | Empty/custom list, app/executable picker, cancellation, invalid selection, save failure, add/remove/reopen | U5 |
| Recognition | Import validation, unchanged/new candidates, changed rules, scoped approval, failure/return | Traced; confirmation of matching-rule changes is justified |
| Process event collection | Absent/installing/update, new session, grants/received events/health, degraded/retry, ready/return | U10; collector drag target correction retained |
| Target preview | Pending/fresh/no response, read/copy, leaving and direct/sidebar entry | U10 |
| App settings | Login off/approval/on, CPU preference, restart busy/failure, maintenance/reset/About | Traced; no new finding |
| Menu Appearance | Rainbow versus System, all scopes/sides, intensity/grey/radius/titles, presets/reset, corrupt saved state | D2; native contrast/overflow is outside this static pass |
| Updates | Unconfigured/checking/update offered, download/installation ownership, failure/recovery/retry | Traced; recovery callback rebuilds Updates, so snapshot creation of Retry is not reported as a defect |
| Maintenance | Repair, helper-file protection, OS authorization, success/failure/return, scoped privacy reset | Traced; dialogs for consequential authorization/confirmation are justified |
| Input access | Missing/unknown helper target, denied/granted/inactive, review instructions, refresh/reopen/external return | Earlier S2/S4/S6 corrections traced |
| Reset Perch settings | Selection, review, cancel, partial/all reset, stopped helpers, failure/quit/reopen | U2 |

## Desk child-state ledger

All production cases from `DeskView.sheetContents` and `DeskLiveSheet.contents`
were included; a single `.sheet` factory is not one user journey.

| Child | Coverage and disposition |
| --- | --- |
| Add computer | Invite/join, no discovery, manual address, expiry, codes/approve/reject, owner/16-member limits, leave cleanup; no extra confirmed finding |
| Add/identify screen | Local/remote/offline choice, refresh, ambiguous identity, existing/new, profile/manual input, mapping conflict and save; no automatic shared-identity guess |
| Desk settings (original sheet, now stable sidebar pages) | Shared names/preset shortcuts and local/session input moved to two destinations; D1 and U1 |
| Computer details | Online/offline, owner/non-owner, removal confirmation; no new finding |
| Conflict | Concurrent versions and recovered membership draft; U9 |
| Add connection | Physical port, numeric input, unassigned allowed, validation failure and commit; creation legitimately needs one Add |
| Remove connection | Explicit destructive scope across all presets, failure retained |
| Correct physical screen | Choose existing screen, clear affected assignments, commit/return; no automatic rematch |
| Monitor control | Computer/display, standard/LG/USB/network/serial, endpoint/address drafts, validation/save, no input switch from edit; per-screen control remains a bounded editor |
| Remove screen | Explicit screen/connections/preset deletion, confirmation and save failure |
| Position & size | Exact dimensions versus drag/rotation, overlap/invalid geometry refusal, automatic valid save; native numeric editing remains acceptance |

Input-sharing children inside Desk settings were also traced: access off/denied/
enabled, per-session scope, pointer-speed autosave, preset/target readiness,
Control here/local return, shared-keyboard add/name/binding/follow/remove and
ambiguous/disconnected attachments. They remain opt-in; this review did not run
input capture, pairing or monitor commands.

## Shared and external flows

- Shared Settings host: sidebar/direct/current-category, setup stack, temporary
  pages, error feedback, beforeBack validation, cancellation, close/reopen,
  background page refresh, authorization/picker ownership and external return.
- Privacy reset: local versus all-app scope, initial confirmation, running operation
  survives leaving, status on return, failed retry and fresh second reset.
- System sleep/audio reset: explicit selection, ownership wording, partial failures,
  retry, no implicit hardware action during the review.
- Agent test: preparation → harmless test → result/timeout → bounded cleanup →
  parent. No test was executed. Native Back remains pending acceptance.
- About is still a separate modeless panel. Replacement/update notices remain
  distinct from saved settings. Native OS pickers and Sparkle dialogs retain their
  own operational confirmation.

## Coverage exclusions and remaining verification

- The retired MonitorInputPage/MonitorGroupsPage family remains in source and in
  the 59-site gate, but its production menu entry is disabled by
  `legacyMonitorFixture == false` (`Sources/main.swift:75–78,191–197`). Its internal
  legacy wizard is not represented as current Settings UX. U1/U2 specifically
  identify where live functionality still depends on that old model.
- Desk Lab demo-only cases are excluded from product judgments. Production cases
  that reuse shared code (screen removal/dimensions) were included.
- The construction gate covers native factories and the Desk root, but does not
  enumerate SwiftUI `.sheet` state variants. Its PASS cannot establish complete
  settings coverage. This review explicitly adds those states to the ledger.
- Native AppKit/SwiftUI focus and sheet ownership, keyboard Tab traversal of hosted
  controls, spoken VoiceOver, text clipping, contrast, physical clicks and actual
  System Settings returns require later GUI acceptance. In particular, the custom
  Tab walker uses native view types; source alone cannot prove its enumeration
  reaches every SwiftUI control. This is a targeted acceptance risk, not a claim
  that all such controls are broken.
- Source review does not establish the exact TCC cause on the user's Mac or prove
  real sleep/input-switch behavior. The previous static-only constraint was kept.

## Disposition

U1–U11 and D1–D3 are resolved in source in this correction commit. The initial
review remains above for traceability. Meaningful operation confirmations,
immediate preference saving, independent About and main menu design are retained.
No further confirmed implementation finding from this review is left open.

Remaining acceptance is explicit: full native fixture execution, actual clicks
and keyboard focus through the affected pages, two-Mac concurrent edits, OS grant
recovery and physical shortcut behavior. Installed/public 2.0.94 still predates
these corrections. Compilation is not evidence that those live journeys passed.
