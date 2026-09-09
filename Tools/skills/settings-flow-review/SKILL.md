---
name: settings-flow-review
description: "Review and improve settings, preferences, setup, permissions, and recovery dialogs as complete user journeys. Use for confusing flows, inconsistent saving/navigation, completion states, first-use or repair experiences, and audits across a dialog set. Captures new confirmed lessons in the skill. Not a substitute for a general code or security review."
---

# Settings Flow Review

Review what a person understands and accomplishes across the settings set. A page can look tidy, have no Done button, and pass its tests while the journey still fails. The agent owns finding and following through on these problems; do not make the user supply the missing pages or repeatedly request the next pass.

Default to a focused settings/setup review. Apply the same principles to related menus and system handoffs when they participate in the journey. Preserve the product's established design and the user's accepted decisions. This skill does not turn every task into a whole-app redesign or authorize operations outside the user's scope.

## Establish scope and evidence

- For an existing product, read its current release notes and relevant review/decision records when available before judging the implementation. Identify the source revision, prepared build, installed/running build, and relevant helper/service versions when they differ. A source fix does not mean the user has it. A supplied prototype or fixture may be the entire evidence boundary; do not invent missing release history or search beyond the stated scope to fill it.
- Carry forward previous authorization, rejected alternatives, and protected design choices. Record product-specific preferences with the project; do not convert them into universal rules in this skill.
- Distinguish review-only from an authorized review-and-fix task. Report prioritized findings before fixes when requested. Reporting those findings is a checkpoint within an already authorized task, not a reason to ask again before every page or repair.
- Inspect source, product copy, persistence and asynchronous callbacks as well as the rendered interface. Use the relevant UI/browser skill when interacting with an app. Where live operations are restricted, use isolated fixtures or render states with external mutations stubbed. Label source traces, simulated interactions and live observations accurately.
- When the user and agent share a live desktop, make interaction ownership visible before testing. Use the project's session indicator when available, announce the scope, and check for user handoff requests between short action batches. The indicator must survive app switches/restarts without stealing focus, distinguish active/paused/requested-control states, and end when handing back. Do not imply it locks input or cancels an issued command unless that is actually implemented. Source-only work and truly nonpresenting tests need no takeover notice. Do not infer invisibility from isolated storage, injected hardware, a prohibited activation policy, or a test-runner label: native tests can still order windows front and restore floating panels. Audit window/panel presentation in the test harness and enforce the same session check before running it and before visible action batches. Compile separately before starting a short desktop session.

## Map the complete journey before declaring coverage

For a full dialog-set review, read [journey-checks.md](references/journey-checks.md). For a narrow task, apply its relevant checks to the affected journey and shared components without expanding into unrelated work.

Inventory every in-scope page, nested dialog, shared alert, popup, result, permission handoff and entry route. Enumerate actual call sites and runtime pages; searching for Done, Save or Cancel is only a way to locate controls. Include hidden/error/empty states, advanced and maintenance pages, and dialogs reached from both a menu and Settings.

Keep one coverage ledger in the task's existing review record or a suitable artifact. Use a compact structure such as:

| Page / entry routes | User task and applicable states | Save and exit behavior | Evidence / finding | Status |
| --- | --- | --- | --- | --- |

For each relevant feature, follow first use, ordinary use, adjustment, repair, add/remove, and learn/relearn. Cover missing prerequisites, loading, ready, editing, running, success, failure, retry, leaving, reopening and external changes where applicable. Do not manufacture irrelevant combinations. Record a short reason for an omitted material state; do not silently call an unexamined page consistent.

At each transition answer in the user's terms:

1. Where am I, and which device, app or scope does this affect?
2. What is saved, what is currently working, and what is still unknown?
3. What will this action do, and when will it take effect?
4. Is another step actually necessary, or am I already finished?
5. What happens if I go Back, close, switch pages, or return later?
6. If it fails or circumstances change, can I recover here without repeating successful work?

If those answers require knowing implementation details or reading the whole page twice, treat that as evidence to investigate.

## Apply a consistent interaction contract

- Independent, reversible preferences normally save immediately. Explain an exception by the actual validation/transaction need, not by the existence of an Apply button. Preserve the user's chosen product convention when one has been agreed.
- Related fields may need one coherent draft and one explicit commit. Child selections update that draft without a chain of Use/Apply/Save steps. Incomplete or invalid replacement work must not damage the working configuration; save failures preserve the draft and offer a clear retry.
- Completed setup becomes a durable ready/saved state on return and reopening. Make Change, Relearn or Recheck optional. Detect known working defaults before requesting manual setup. A permission or layout that is already working should not keep presenting instructions to grant or teach it.
- Keep saved intent, current availability, last observation, last command, and verified outcome distinct. External changes can invalidate an observation without erasing completed setup. Installed is not responding; sent is not confirmed; connected is not proof of the visible picture or successful hardware behavior.
- A page with shared Back/Close normally needs no extra Done, OK or footer Back for an informational result. Preserve meaningful operational confirmation and OS-owned picker conventions. Escape, window close, the header and footer must not disagree about saving or cancellation.
- Back navigates predictably. Refresh the current page without pushing another copy, changing category, losing scroll/focus or hiding newly added fields. Completion and return wording must fit every entry route.
- Leaving a page is not necessarily cancelling its operation. Before an irreversible action, leaving can abandon the proposal. After it starts, show the true running state and preserve the result if the user leaves. If cancellation is supported, show its actual cleanup outcome before claiming it stopped.
- Check availability before presenting an action as usable, while retaining confirmed readiness when unchanged. Prefer background refresh and event invalidation to forcing a disabled first frame on every opening. Unknown can require a brief checking state; unavailable needs an explanation and a useful repair/setup route. Never fake readiness to avoid a delay.
- Provide a reusable Setup & status overview when first use or recovery spans several categories. It should show what needs attention and the relevant next action, be skippable for optional features, and remain useful after permissions or devices change. It must agree with the feature pages and menus.

## Review grouping, language and visual hierarchy

Organize around what people want to do and what the setting affects. Keep a feature's ordinary choices, status and relevant repair discoverable together; reveal protocol/implementation details only when useful. Explain app-owned versus system-wide effects. Do not relocate a carefully tuned menu or redesign established controls merely to satisfy a preferred layout.

Guide through clear defaults, status and the next useful action rather than a mandatory tutorial. Use concrete action labels and consistent terms for the same concept. Distinguish changing a preference, testing something, installing a component and performing a destructive action. Do not leave developer/tool names in product copy when they do not help the user.

Check density, grouping and emphasis in actual rendered states. A nominal border can be invisible; a shorter label can still be clipped; color alone does not communicate status. Use cheap prototypes or fixture renders for visual experiments, then verify implemented flows in the actual UI framework. Test relevant themes, small windows, scrolling, focus, keyboard access and accessible names/state. Keep navigation stable across refreshes and asynchronous results.

## Iterate within the same task

1. Report concrete findings with priority, affected journey, trigger, expected/actual behavior, evidence and recommended correction. Functional harm, misleading state, lost work and broken recovery take priority over styling. Separate an observed defect from a design preference or untested hypothesis.
2. For authorized fixes, complete the correction and replay the journey from its real entry point through success, leaving and reopening. Exercise failure/retry or interruption when affected. A screenshot of the replacement page is not a replay.
3. Sweep sibling pages and shared components for the same pattern. A duplicate exit in one alert, incorrect ready state in one setup page, or draft loss in one editor is a reason to inspect the rest of the set immediately.
4. Check for the opposite regression: removing redundant acceptance must not erase meaningful confirmation; caching readiness must not hide disconnection; hiding setup instructions must not conceal a later missing permission; autosave must not commit an incomplete destructive edit.
5. Update findings and evidence, then continue until the authorized scope is handled. Do not leave known implementable work as a new suggestion merely because one batch of tests passed. Keep genuinely blocked hardware/OS acceptance explicit and continue independent safe work.

Use meaningful state-transition and behavior tests for material fixes, not tests that just match a button label or mirror the implementation. Run applicable checks once; broaden or repeat when a new change, failure or unresolved risk warrants it. Do not perform a live reset, hardware change, emergency action, installation or publication solely to obtain review evidence without the necessary authorization.

Completion requires accounted-for pages/routes, replayed affected journeys, prioritized findings resolved or explicitly deferred/blocked with reasons, and a final report distinguishing source fixes, simulated verification, installed behavior and remaining acceptance. Report build/install and commit/push status when part of the task. Passing a suite or removing every Done label cannot close the overall review by itself.

## Improve this skill as new lessons emerge

The user explicitly wants this skill maintained during use. When a correction or a demonstrated missed pattern changes the review method, update the skill in that same task; do not merely promise to remember it or wait for another skill-edit request. Do not rewrite it after every routine bug fix.

- Capture the failure mechanism and the missing review question. Generalize only as far as the evidence supports. Keep app-specific ownership, layout choices, permissions and release decisions in the project's record.
- Amend the existing rule or relevant section of `journey-checks.md`; replace superseded guidance instead of appending conflicting rules. Add a discriminating case to [evaluation-cases.md](references/evaluation-cases.md) when it would catch a future recurrence. Include the legitimate exception so the lesson does not become an absolute ban on Save, Cancel, wizards or confirmation.
- Sweep the current app for the newly recognized pattern and rerun the affected journey. A skill edit does not fix the product. Keep both statuses clear.
- Edit the actual installed skill source, resolving a symlink if present, and preserve unrelated instructions. Validate structure/references and assess the changed guidance against realistic cases. Use `skill-creator`'s validator if available; its structural pass is not behavioral proof. Report the concise lesson added and any remaining product work.
- Updates are ordinary scoped skill-file edits, not authorization to expand live operations, change other skills, publish, or copy secrets/private incident data into a reusable resource. If the owning skill source cannot be edited, prepare a patch and report the specific limitation.

When substantially changing this skill, use `evaluation-cases.md` to check its decisions. A blind independent evaluation, when authorized, should receive the skill and raw scenario only—not the expected findings or prior conclusions. Small refinements can be checked locally; do not claim an independent test when none occurred.
