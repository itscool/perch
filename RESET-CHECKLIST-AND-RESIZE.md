# Reset checklist and Settings sizing

September 13, 2026. Supersedes the reset subpage design in RESET-DISCOVERABILITY-2.0.md.

## Design correction

Consistency includes the work needed to understand and choose. A tidy index still fails when users must open each child to learn its scope. Comparable reset scopes now appear together, with target choices inline. Ordinary settings retain immediate saving; destructive selections remain proposals requiring one confirmation. Broad all-app privacy stays distinct.

The settings-flow-review skill now asks whether each extra page advances the task, requires decision information to be visible where choices are made, checks partial batch failure/retry and quit ordering, and evaluates resizing across navigation, reopening and active confirmation. Added a discriminating evaluation case; no new independent-agent evaluation is claimed.

## Implementation and coverage

| Route/state | Result |
| --- | --- |
| Sidebar Resets | Six unchecked scopes with consequences; Reset selected disabled until a valid selection |
| Learned layouts | Inline one/all saved keyboard selector, including disconnected profiles; bundled defaults retained |
| Setup/feature repair | Relevant row highlighted without selecting it; labeled Back preserves origin; sidebar navigation ends context |
| Confirmation/cancel | Exact selected scopes shown; Cancel/Back abandons only the proposal |
| Running/leaving | App-owned batch continues; result available on return |
| Partial failure/retry | Successful areas recorded; retry only failed/skipped areas |
| Preferences combined with other scopes | Includes ending protection; executes last and quits only after all scopes succeed |
| All-app privacy | Separate existing broad confirmation; never part of the checklist batch |
| Window sizing | Resizable shared window; stored size stable across pages/reopening; screen clamp and usable minimum |
| Setup/checklist layout | Uses additional width; Setup uses additional height; overflow remains scrollable |
| Active confirmation | Resize retains modal ownership, live text and default action |

## Validation

- Full isolated functional suite: 23/23 passed after fixing an existing hit-test coordinate assumption exposed by the new content positioning. The assertion still checks that the actual button receives the hit; it now converts into the superview coordinates required by AppKit.
- New injected batch checks: unchecked entry/highlight, disconnected keyboard target, Cancel retaining proposal, asynchronous partial results after navigation, failure-only retry, duplicate callbacks, quit ordering and preserving unchecked appearance/layout data.
- New isolated geometry checks: resizable style, useful minimum, expanded content width, stable page transitions, active confirmation ownership and persisted size across a fresh window instance.
- Native fixture: sidebar Resets; checked layouts and chose All saved layouts inline; resized smaller with readable wrapped scope/scrolling; opened confirmation; resized it larger; Back returned to retained proposal. No reset accepted.
- Native fixture: Lid protection → Sleep reset options highlighted the unchecked sleep row under Resets; Back to Lid protection returned to the original stage, then Back to setup. Setup retained the enlarged window. The final label-width refinement passed a focused AppKit suite rerun and native inspection: Keyboard & mouse sharing is fully readable.
- 61 construction sites pass the shared-dialog contract inventory; the skill validator passes. Native screenshots are in the task outputs.

These checks use an isolated fixture and injected/disposable reset writes. OS privacy resets, sleep/audio mutations, production helper changes, app installation, notarization and publication were not performed.

## Candidate

Developer ID signed 2.0.102 passed staged runtime/framework, nested signature and source-snapshot verification. It supersedes prepared 2.0.101. Installed/public 2.0.94 remains unchanged; no notarization or publication.
