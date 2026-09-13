# Setup ownership — September 12, 2026

Decision: Setup owns prerequisites and repeating those stages for repair. Feature
pages own behavior, customization and ordinary runtime recovery. A feature
explains what is unavailable and links directly to the one authoritative stage;
it does not embed another copy of permission or installation instructions.

## Coverage and implementation

| Journey | Change | Acceptance |
| --- | --- | --- |
| Setup sidebar | Background helpers, Keyboard access, Scrolling & navigation, Shared input access, Lid protection and Agent tracking are contiguous children of Setup. | Injected destination tests passed; native clicks confirmed all six selected Setup stages. |
| Feature → Setup; stage → stage → overview | The selected stage belongs to Setup and preserves the existing overview, including its selection/scroll. Repeated entry reuses the stage; Back returns to that checklist. Draft validation and owned dialogs still gate navigation. | Injected reuse/checklist tests and native Back/child-switching passed. |
| Keyboard root/details and layout learning | Replace duplicate OS permission buttons and draggable app items with one direct Keyboard access link. Saved layouts and ordinary keyboard choices stay under Keyboards. | Native handoff regression updated to prove feature → Setup → external app → return. |
| Scrolling/navigation | Access/helper links open the matching Setup child. Disabling an existing choice remains available after lost access. | Source and existing input readiness/regression tests. |
| Desk sharing | Remove duplicated permission instructions. Missing grants link to Shared input access; locked/inactive sessions and native tap failures retain feature-specific retry guidance. | Injected access state tests; physical sharing remains separate QA. |
| Shared input access | Accessibility for Perch is checked independently of the helper grant. Input Monitoring links to the existing Keyboard access stage. Ready instructions collapse; optional review and revoked-access transitions stay available. No access check starts sharing. | Injected missing/ready/revoked and row reflow tests passed. Native shared-input → Keyboard access → Setup passed. |
| Keep awake/lid menu | The saved choice, Resume and activity remain with Keep awake. Installation, queued update and recovery live in Lid protection setup; entry or a missing prerequisite never installs/enables on its own. | Update availability/readiness tests moved to the Setup stage; feature navigation tested. Physical sleep/helper operations not performed. |
| Agent Kill Switch/tracking | Feature helper failure and collector prerequisite failure lead to Background helpers. Agent tracking setup owns collector/FDA stages. Recognition, agent choice and shortcut tests remain features. | Public route tests; no live Panic or installation. |
| App settings/login startup | Setup link replaces Maintenance; a missing login approval opens Background helpers. The startup preference stays in App settings. | Source route review; no login item changes. |
| CLI setup entry | --show-event-setup selects the same Setup child as ordinary navigation. | Source trace. |

The settings-flow-review skill now checks for one prerequisite owner and direct
feature links, with the exception that ordinary customization and session
recovery stay with the feature. Its structure validator passes. This is a
confirmed product rule, not a mandate that every simple app needs a Setup area.

## Verification

- **23/23 isolated suites passed** after updating two obsolete tests that required
  the duplicated keyboard permission button and Maintenance nested under Agent
  Kill Switch. Tests now exercise direct Setup links and its external handoff,
  retained overview, repeated entry, permission recovery and draft refusal.
- **63 native construction sites** pass the ownership/coverage gate. The source
  ledger includes the two new Setup pages and the renamed helper-stage owner.
- Real native clicks under **AGENT MODE** confirmed all six Setup destinations,
  Keep awake → Lid protection setup → Back to setup, shared input access → the
  same Keyboard access stage → Setup, and Agent Kill Switch → Background helpers
  → Setup. The sidebar selected the correct Setup child each time.
- The sidebar and lid stage were inspected in an actual rendered window. Setup
  labels fit, repair controls remain in the stage, and the ordinary Keep awake
  page contains its choices, Resume, activity and direct setup link.
- Native tests used an isolated fixture with separate storage, identities and
  injected hardware. Setup read current availability; no helper installation,
  live permission reset, monitor write, sleep command or Panic occurred.
- The 2.0.97 signed build passed bundle/signature checks without warnings. The
  final signed 2.0.98 build passes the same checks without warnings. Its
  additional helper-success color regression passed in the targeted lid suite
  (**1/1**): a result message alone is not a reason to show warning color.
  The final candidate matches all 262 source/resource/tool snapshot files.
- The settings review skill's structure validator passed. Its new evaluation
  case distinguishes prerequisite repair from normal customization and runtime
  recovery. No independent agent evaluation is claimed.

Installed/public **2.0.94 remains unchanged**. This is a source/build and bounded
native UI result, not acceptance of real permission changes or physical lid,
monitor and shared-input behavior. The native preview is from the isolated
2.0.97 fixture; the final color-only refinement does not change its layout.

Task artifacts: `outputs/perch-setup.png`, native/compiled logs in `work/`,
and the final candidate in `work/release-2.0.98/Perch.app`. Release/notes.md is
current for the normal resumable release workflow. No new notarization,
installation or publication was performed.

All AGENT MODE sessions and isolated UI processes are stopped. The live app was
not restarted/replaced and its settings were not changed. Physical feature and
permission acceptance remains in TODO.md; this change reorganizes its setup UI.
