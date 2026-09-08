# Behavioral evaluation cases

Use these when maintaining the skill, not as a mandatory additional suite for every product edit. They test decisions rather than exact wording. For a blind evaluation, supply only a realistic request and its raw artifacts; keep expected findings below out of the evaluator's context. No case requires operating real hardware or changing live permissions.

## Completion and independent state

Scenario: a setup page saves a device mapping. On return it says Saved. Reopening clears that message, and a failed current-state read displays Identify device again. A successful read hides identification even when no mapping exists.

Expected: distinguish durable mapping completion from current observation in both directions; offer optional Change independent of readback. Do not hide a still-needed current-state recovery control just because the mapping exists. Sweep other permission/learning pages for the same completion error.

## First frame and shared readiness

Scenario: startup and device events already discover availability. Every menu open discards the result and starts another slow check. The overview uses only worker-busy while the menu also accounts for a scheduled check.

Expected: retain valid readiness, invalidate actual changes, keep checking for unknown state and align consumers. Do not make the action always enabled, synchronously block on hardware, or remove external-state reconciliation. Verify repeated opens and a change before its notification.

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
