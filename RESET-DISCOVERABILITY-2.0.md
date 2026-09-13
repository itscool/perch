# Reset discovery and destination wording

Source follow-up to 59115a8 / prepared 2.0.98. Installed/public 2.0.94 is unchanged.

## Findings and correction

- P2: Reset settings exposed preferences only. Privacy, sleep, appearance and
  saved-keyboard resets were hidden in setup or feature pages. Resets is now an
  independent sidebar destination with six scopes. Setup/features point there;
  navigation selects Resets instead of stacking a reset under the originating
  feature. No scope is selected or executed on entry.
- P2: “Review” was used for ordinary navigation and revealing instructions.
  Feature, checklist and prerequisite links now name destinations. Completed
  permission stages say Show/Hide permission instructions. Actual catalog-change
  review and pre-reset consequence review retain the word.

## Route inventory

| Entry | New destination / scope | Mutation boundary |
| --- | --- | --- |
| App settings, sidebar | Resets | None on entry |
| Background helpers | Resets → Perch privacy permissions | Explicit existing scoped action |
| Lid protection setup | Resets → Sleep & audio | Explicit unchecked choices and action |
| System privacy-reset command | Resets → All apps’ privacy permissions | Explicit broad-scope action; no Panic |
| Keyboard layouts | Resets → Keyboard layouts | Choose saved/disconnected keyboard or all, then Cancel/Reset confirmation |
| Menu Appearance | Resets → Menu appearance | Restore original appearance; both System and rainbow sections |
| Saved Perch settings | Existing selective settings page and consequence review | Explicit reset and quit; shared Desk setup kept |

Ordinary style presets, per-item removal/editing, emergency Panic and conflict
resolution retain their separate purposes. This change does not execute any
live reset, modify helper policy, install a helper, or change the main menu style.

## Verification

All 23 isolated suites passed in `work/reset-navigation-verified`. Added tests
cover route/Back, no-default-selection, disconnected and unreadable layouts,
Cancel, write failure/retry, exact targeted reset, and appearance scope. Writes
use injected callbacks or disposable preferences; live resets are excluded.
The initial suite hit a 20-millisecond authorization-notice wait; this now waits
for the queued completion with a one-second bound and reports individual state
on failure. The rebuilt full suite passed without a product authorization change.

Native clicks in the isolated Desk fixture opened all six scopes and returned
with Back. Lid protection, Background helpers and Menu Appearance links selected
Resets in the sidebar. Layout scope started unselected; sleep/audio checkboxes
were off and the action disabled. The two privacy scopes explicitly reported
nothing reset. No destructive buttons were pressed. The screenshot was inspected
for readable scope descriptions and unclipped controls. Production OS reset
execution and spoken VoiceOver remain outside this task's evidence.

The source contract inventories all 66 construction sites; skill validation and
whitespace checks passed. Developer ID signed 2.0.99 built without compiler warnings and passed bundled
Sparkle load-path, architecture and nested-signature checks;
installed/public 2.0.94 remains unchanged. No notarization/publication is included.

## Contextual repair follow-up

The 2.0.99 implementation stopped at the reset index. That was incomplete:
people still had to find the named option, and the original setup context was
lost. This follow-up opens the exact scope and retains the original page stack,
scroll/focus state and Setup checklist while selecting Resets in the sidebar.

| Entry | Direct scope | Labeled return |
| --- | --- | --- |
| Lid protection setup | Sleep overrides only; audio excluded | Back to Lid protection |
| Background helpers | Perch-only privacy permissions | Back to Background helpers |
| Keyboard layouts | Saved navigation layouts | Back to Keyboard layouts |
| Menu Appearance | Both appearance sections | Back to Menu Appearance |
| System privacy command | All-app privacy, beneath Resets | Back to Resets (ordinary Back) |
| App settings / Resets sidebar | Full reset index | No temporary repair return |

The shared scope presenters and mutation boundaries are unchanged. Privacy
operations continue independently when leaving, and reopening shows their result.
Contextual privacy pages use the labeled Back instead of a competing generic
Setup button. Choosing a sidebar destination or closing the window discards the
temporary return path. Draft validation and cancellation still guard navigation;
a confirmed draft discard does not retain the discarded page as a return target.

The initial contextual suite exposed Background helpers rebuilding itself on
return. Its refresh now updates the existing page description, retaining the
original view and checklist. The subsequent full 23-suite run passed. The sibling
flow sweep also found that Keyboard layouts needed to reload saved profiles on
return; a new injected reset-return test covers erased disconnected keyboards.
Final compilation, regression execution and native click acceptance are recorded
below when complete. No live permissions, helpers or sleep state are reset.

### Final acceptance — 2.0.101

- `work/contextual-reset-complete`: all 23 isolated suites passed, including
  retained view/checklist identity, exact reset scope, repeated entry, privacy
  failure/retry/success, sidebar/close cleanup, and a simulated layout deletion
  followed by return to the updated original keyboard page.
- Native fixture clicks passed Lid protection → sleep-only reset → Lid protection
  → Setup checklist; Background helpers → Perch-only privacy → Background helpers
  → Setup checklist; and Menu Appearance → appearance reset → Menu Appearance.
  Resets was selected during each reset scope, and labeled Back controls were
  readable and functional. Screenshots were inspected for clipping.
- Sleep scope began unchecked with its action disabled. Privacy scope reported
  nothing reset. Native clicks did not execute resets; operation results were
  tested only with injected callbacks/disposable data. AGENT MODE and the isolated
  fixture ended after acceptance.
- Developer ID signed 2.0.101 passed bundled Sparkle load-path, architecture and
  nested-signature checks, with no compiler warnings. Skill validation and all
  66 source UI construction contracts passed. No installation, notarization or
  publication was performed. Prepared 2.0.100 is superseded.
