# Tooltip coverage and consistency — build 78

The user accepted build 77's native menu interaction fix (todo 2). This pass
addresses the newly visible content gaps, not a recurrence of tooltip leakage.
Evidence is source inspection, warning-free isolated compilation and existing
hidden menu boundary regressions; actual new tooltip timing/layout is untested.

## Findings before correction

- P2: Panic help implied immediate execution although the menu action confirms.
  The separate global shortcut is immediate; its Settings explanation retains
  that distinction.
- P2: healthy refresh could erase Settings help; other refreshes replaced action
  purpose with device/helper status, leaving the effect or next step unclear.
- P3: five action rows lacked help. Keyboard/sleep explanations varied across
  menu and Settings, and some menu help exposed backend details or device dumps.

## Contract

Every action row has explicit help from construction. Explain effect/scope first,
then current availability or the route opened instead of changing a setting.
Refreshes clear obsolete context while preserving purpose. Use ControlHelp for
matching menu/Settings controls. No duplicate native tooltip registration is
added; custom rows retain their own help and accessible shortcut text.

## Menu inventory

| Rows | Coverage and state handling |
| --- | --- |
| Panic | Confirmation, affected agents, loss/relaunch effects; checking/offline/error/test context retained. |
| Reset all apps' privacy permissions | Confirmation, all-app scope including Perch, future permission requests; no agent termination. |
| Resume agent activity | Confirmation; allows relaunch without reopening apps or restoring permissions; checking context clears when ready. |
| Turn display off | Connected displays, wake action and Keep awake relationship. |
| Cycle monitor input | Selected display/group, visible-screen consequence and local recovery; checking, busy and Settings routes. Existing cycling is still scheduled for KVM replacement. |
| Mute audio | Current output, retained volume, reversal; unavailable read adds Sound-settings recovery and clears after a good read. |
| Reverse trackpad / mouse wheel (2) | Distinct device scope, vertical-only behavior; pending, access setup, saved-off route and inactive controls. |
| Built-in / external Control–Command swap (2) | Scope and external reconnect behavior; disconnected and mixed/custom mappings. |
| Built-in / external F1–F12 (2) | On/off/Fn behavior and device scope; missing devices, blocked reads, external access/setup and mixed modes. |
| Home/End / Page Up/Down (2) | Actual cursor behavior, built-in/app exclusions; checking, setup route and saved-but-unavailable status. |
| Set up keyboard | Access/layout journey and completed-save behavior plus current attention. |
| Keep awake / Including with lid closed (2) | Idle versus closed-lid/manual sleep, disable effects, 60 seconds, saved intent versus protection, explicit Resume. |
| Start at login | Menu-app scope; approval route appears only when macOS requires it. |
| Settings | Feature changes plus Setup & status; healthy/attention refresh preserves the explanation. |
| About | Version/build information. |
| Quit | Background controls that continue and menu/lid controls that stop. |

All 21 action rows are covered, including conditional Resume and keyboard setup.
The five System information rows already explain metrics and their limitations;
this pass retains those definitions. Section titles are grouping, not actions,
and do not get redundant hover text. The status icon retains its existing
normal/critical-attention help.

## Settings coverage and deliberate omissions

- Shared category/action lists and SettingsTaskPage controls expose their visible
  descriptions as both tooltip and accessibility help, covering Setup/category,
  feature, maintenance and recovery routes using those builders.
- Custom keyboard Fn/modifier controls reuse the menu explanations with page
  recovery context. Keep awake controls share the longer hover explanations while
  retaining concise visible text and existing layout.
- Agent selection, immediate shortcut enable, modifier/key selection and privacy
  scope explain effect and immediate saving versus executing an operation.
- Existing permission-drag, collector-identity, monitor-test/reordering and device
  identity help remains useful to those specialized controls. Necessary warnings,
  result/status text and setup instructions remain visible on their pages.
- Back, Close, ordinary named picker entries, text-field labels and confirmation
  buttons are not given generic copies of their own labels. Their visible page or
  confirmation explains the task. This is not a claim that every NSView should
  have a tooltip, nor a full new native click-through acceptance of all dialogs.

## Verification

Required help at the menu construction API makes omitted arguments a compile
error. The complete isolated app compiles; existing hidden tests pass for help
ownership, replacement, clearing, accessibility/tracking, pointer/keyboard
selection and deferred action identity. These verify mechanics, not prose quality;
source review above accounts for purpose and state routes. The settings-flow skill
and its evaluation cases now distinguish hover correctness from content coverage
and require shared terminology across menu, dialog and accessibility consumers.
