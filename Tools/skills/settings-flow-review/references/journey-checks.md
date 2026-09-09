# Settings journey checks

Use these checks to find concrete failures in the actual product, not as a mandatory list of features to add. Inspect applicable states for every in-scope page; keep the task's evidence ledger separate from these reusable principles.

## First use and returning to check setup

- Start from the real menu, first-run entry or settings home. Can a new user choose the intended feature without knowing its internal architecture? Are ordinary controls available without unrelated optional setup?
- Prefer trustworthy built-in device/profile recognition and sensible defaults before manual learning. Do not guess an identity or treat a vaguely matching model as proof. Known layouts still need clear, separate behavior choices where appropriate.
- When prerequisites span categories, can the user see what works, what is optional and what needs fixing in one reusable overview? Follow its next-action links to the exact repair and back. A numbered wizard alone is not a later health check.
- Open a ready feature directly, complete it from missing prerequisites, then reopen it. In all three cases, does it say ready/saved and stop asking for the completed steps? Optional change/review should remain discoverable.
- Remove or expire a prerequisite in a fixture. Does readiness change from current evidence, with a scoped repair that retains preferences? Restoring access must not require relearning a still-valid layout or redoing every category.
- A progress screen should be safe to leave where feasible. Successful work should persist and remain visible; do not force a final acknowledgement solely to mark setup complete.

## Ordinary changes and valid replacements

- Trace each control through persistence and application, not only its handler name. Does a checkbox take effect immediately? Can validation elsewhere in the form unexpectedly block it? Does a write failure restore the prior value or retain the appropriate draft with an error?
- Count decisions, not button names: Select model → Use preset → Use input list → Save is still multiple acceptance layers even without Done. One actual final transaction can be justified; nested acceptance for ordinary selections usually cannot.
- When removing a child Apply button, define how Back carries valid edits into the parent draft. An unchanged empty child must still allow Back; invalid edits need an in-page correction or explicit discard route, without silently losing the working setup. Closing the whole draft must not accidentally commit child edits.
- Inspect parent and child drafts. Going Back from a child should preserve the parent proposal; cancelling the whole replacement should retain the working setup. Editing after a successful check must invalidate any validation that no longer applies.
- Distinguish a test/preview from saved configuration. The test must not secretly overwrite preferences or let a temporary success message replace the operating feature's status.
- Complete learning and release the final captured key. Save a complete valid result automatically when this is the agreed interaction. Interrupted learning retains the old layout; a failed final save offers retry without another lesson.
- OS file pickers may legitimately require Choose/Cancel, and high-impact related changes may require explicit confirmation. Consistency concerns meaning and outcome, not making every button identical.

## Back, close, focus and asynchronous operations

- Give dialog completion an explicit owner. A timer, delayed result or obsolete panel-close handler must not stop whichever modal loop happens to be active. Confirm that closing Settings during an external-app handoff clears ownership so later actions can open normally. Protect the active dialog’s view and title against all background refresh paths.

- Verify controls through their real interaction path: hit testing, enabled state, action dispatch and resulting persistence. Assigning a checkbox's state directly can test validation but cannot prove that a person can click it. A modal test driver that returns a response bypasses native input routing; even performClick is not proof that the real modal loop receives mouse/keyboard events. Keep hidden dispatch tests and real-click acceptance distinct, and require the latter for a reported dead-button regression. Inventory new UI entry sites and gate unreviewed additions where practical. When embedding an editor or alert in a shared window, inspect modal-session ownership and control routing; scrolling alone does not establish interactivity. Distinguish isolated control dispatch from physical input on the affected machine.

- Enter the same child from every real parent. Change a value and press Back. Does it return once to the expected parent, preserve selections/scroll/focus, and show fresh status? Titles alone cannot reveal a duplicated navigation stack.
- Inspect header navigation, footer actions, Escape, Return and window close together. Does a shared alert wrapper insert OK or a second Back/Cancel after the local page already removed Done?
- In informational results, keep one page navigation exit. Preserve an action such as Retry or Check setup when it is useful. Do not remove a meaningful confirmation just to remove a button.
- Add at the bottom of a long editor: reveal and focus the new item. Remove an item: retain a sensible nearby position and focus. Live refresh must not jump to the top, move the target under the pointer or interrupt reading/copying.
- Exercise permission/authorization handoffs on the first attempt, cancellation and immediate retry using allowed evidence. Trace key-window ownership, floating panels, menu/modal tracking, queued activation requests and delayed result/error notices; lowering a window is not proof it relinquishes keyboard focus. Preserve the page/draft, defer competing app UI until the OS handoff ends, and restore only the previously open UI. Retain normal OS sheet behavior where ownership is already coordinated; do not hide every parent indiscriminately. Do not infer a working password prompt from a mock or a successful retry. Never read, inject or log credentials during inspection.
- Inventory every owner of interaction, including native file pickers and standalone alert fallbacks, not just custom dialogs. Busy state must cover the entire native call and every return path; parent Back/Close must not stop the wrong modal loop. Queue asynchronous notices, but never turn an overlapping synchronous confirmation into an automatic approval. Check all external-app links too: opening Settings/Finder is not completion, and permission buttons should not launch two competing system interfaces. Preserve visible drag instructions when lowering a panel is appropriate.
- For a running operation, distinguish Stop request, stopping/cleanup, stopped, failed and complete. Back/Close must not promise to cancel a command already issued. Preserve the result beyond the view's lifetime or provide a clear way to retrieve it.
- After a failure or Stop, can the user retry in place? Re-enable the relevant action with fresh cancellation/session state; merely reusing a cancelled token can make the retry inert.
- Late responses must not update another device, resurrect a dismissed draft, overwrite a newer request or announce success after a save failed. Test these transitions when the implementation is asynchronous.

## Honest state and first presentation

| State | What it establishes | What it does not establish |
| --- | --- | --- |
| Preference or mapping saved | Intended configuration is retained | Device currently has that state |
| Device connected / route found | A particular connection is observable | Input command will work or picture is visible |
| Current value reported | The device reported a value at a time | It remains current after another actor changes it |
| Command accepted or sent | A request reached the stated stage | The requested effect happened |
| Helper installed | Files/service registration exist | Correct version is responding with working access |
| Ready / verified | The named capability has supporting evidence | All features, hardware scenarios or future states work |

- Keep these facts separately addressable in the UI. A saved “This computer uses USB-C” mapping can coexist with unknown current input. The latter should not relaunch identification of the saved mapping.
- Follow external changes made by another computer, monitor buttons, System Settings or a service restart. Reconcile before deciding a state-dependent action. When reliable readback is unavailable, offer named destinations or an explicitly limited observation instead of treating the last command as current.
- Inspect the first frame, the checking interval and the settled state. An enabled-then-disabled unavailable action is misleading; a ready action disabled on every open is also a defect. Maintain appropriate background evidence, invalidate on relevant changes, and use a cheap current check when feasible.
- Do not block the UI waiting for slow hardware merely to avoid any loading state. Unknown and stale states can legitimately need a short check. A stable missing setup should have a stable explanation and working setup link.
- Menu, overview, details and native/accessibility validation must agree about readiness, ongoing work and failure. Debounce time is still pending time; an old snapshot cannot become ready just because no worker is currently busy.
- Degraded permission/health states should offer the next needed repair. Avoid continuing a prominent grant-access recipe after readiness is actually confirmed.

## Menu first display and updates

- For custom menu rows, distinguish intrinsic/preferred size from the width allocated by the native menu. Replay periodic updates after the host has stretched rows to a common width; unchanged content must not reset that allocation. Keep an open menu's geometry stable through status updates, preserve hover/focus and shortcut space, and apply deferred width changes on reopening. Native light/dark renders must also retain baseline alignment; a static full-width mockup alone cannot expose live layout churn.
- Audit the native/custom ownership boundary too: tooltips must belong to the visible row, tracking refresh must remove only its own areas, and Return/Space must activate the visible highlight rather than a stale native selection. Test keyboard → pointer → keyboard, disabled/hidden selection, rows with no help, renderer replacement, and background action changes between dismissal and deferred dispatch. Keep accessibility help and shortcut text intact. Use native tooltip handling for ordinary native popup items; custom rendering is not a reason to replace all framework behavior. Hidden dispatch tests do not establish actual native hover timing.

- Inventory every non-excluded row, including conditional actions and category-dependent visibility. A successful check of one monitor row or one shared renderer does not cover all menu options. Record each row's value source, age/pending state, checkmark, label/hint/tooltip, enabled/hidden state, validation and action destination.
- A status-reply callback must repaint from its snapshot without starting another request through the same getters. Test that replies reach the visible UI and that rendering cannot create a self-sustaining polling loop.
- Trace getter → pending request → reply → UI update. A getter may start a request but return old data; receiving new data does not necessarily repaint the menu. A cold cache is not a confirmed offline device or missing permission. Check first show, unchanged reopening, relevant external changes and updates while tracking remains open.
- Run the framework's native menu validation after assigning presentation state. A default validator can re-enable a control that the application just disabled. Check the rendered, mouse/keyboard and accessibility decisions against the same readiness rule without activating destructive controls as a test.
- Verify that each external property has an actual refresh trigger. Repainting cached modifier or firmware state every two seconds does not reread it; a device connection notification may not cover a mode change on that same device. Preserve valid readiness without forcing a disabled frame on every opening, and show honest uncertainty when a required check is pending.
- Inspect the refresh chain for side effects: a queued discovery worker may also reapply remembered hardware settings. Use an isolated worker when live changes are outside review scope. Include secondary copy and recovery destinations; an updated primary label can coexist with a contradictory old tooltip.

## Several devices, apps or destinations

- Make the affected scope explicit. Newly discovered devices must not join an action just because they exist. “Both displays to Work computer” is different from independently advancing each display's cycle.
- Keep identity, configuration, observations and errors per device. Distinguish duplicate models and retain useful labels/configuration for a disconnected device. Selecting another item must not discard the first item's settings.
- Exercise one selected device, either of two, both, mixed starting states and a failed/unavailable member where applicable. Report per-member outcomes and retry only the incomplete work when possible.
- Removing one custom item should not erase all learned layouts, mappings or app exceptions. Relearning/replacing should preserve the old working configuration until the replacement is valid.
- Explain app-local versus system-wide ownership and effects. Placement follows the user's accepted grouping and actual scope; a system reset is not merely another app preference.

## Grouping, wording and presentation

- Ask a first-time user to find a task: adjust behavior, check readiness, change a device, add/remove an exception, or fix a failure. Is its category based on that goal or on an internal component name? Do advanced users still have direct access without repeating a tutorial?
- Put the status and the immediate useful action together. Keep detailed diagnostics, protocols and implementation names available through relevant details rather than dominating ordinary use.
- Use concrete labels naming the object and consequence: Change this computer's input, Retry saving, Reset these permissions. State saving and activation timing when it could be uncertain.
- Avoid instructions that assume the wrong entry page, confusing command/result tense, repeated warnings, unexplained countdowns or temporary confirmations that appear to expire a permanent saved setting.
- Verify actual tint/border visibility, density, readable contrast and group boundaries. Preserve the purpose of a compact layout when removing separators; replacing them with equally large blank gaps misses that purpose.
- Inspect relevant light/dark and increased-contrast states, small windows, overflow, long labels/errors and disabled controls. Ensure focus order, keyboard activation and accessible roles/names agree with the visible state. Status cannot rely on color alone.
- A HTML/mockup comparison can accelerate styling decisions; it does not prove the native app adopted that style or preserved its interactions. Compare the implemented result before claiming delivery.

## Evidence and stopping

Record a finding as trigger → user expectation → actual result → impact, plus the source/runtime evidence and the intended correction. Separate bug, preference, hypothesis and remaining physical acceptance.

Use isolated state changes to test destructive or hardware-dependent branches within scope. Do not claim a live grant, actual sleep, visible input switch or safe failure recovery from a fixture alone. Bounded activity logs can help users distinguish observed transitions, elapsed times, requests and confirmed outcomes without recording unrelated sensitive content.

After a shared-component change, replay representative normal, confirmation, result, error and nested-entry routes and inspect all affected call sites. Do not mark every page passed solely because its shared wrapper passed one test. Finish the authorized batch, retain honest unresolved statuses, and communicate whether the user is running the new build.
