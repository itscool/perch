# Unexpected sleep notice

September 13, 2026. The user clarified that a completed 60-second closed-lid
battery grace period is expected and belongs only in Lid activity.

## Correction

Previously every closed-lid sleep with the saved include-lid option enabled could
produce a Settings-hosted notice, including the normal timeout. Notice delivery
now suppresses helper/watchdog grace expiry and explicit disabling, and clears
that pending notice without deleting the activity journal. Saved intent with
inactive/unknown protection alone is insufficient to claim unexpected sleep.
Active protection or recorded interruption/lost supervision can warrant a notice.
The same sleep interval still requires wake evidence. Temporal boundaries keep
old expiry/cancel/wake/session records from being applied to a later incident;
the helper sleep timestamp handles callback ordering around the timeout.

Unexpected incidents use their own native app-modal NSAlert with OK and View lid
activity. Presentation waits for existing Settings interactions. The current
Settings page/draft and visibility are retained; only View lid activity navigates
to history. This modal owns its loop and does not use an unrelated stopModal.
No helper protocol, sleep policy, enforcement or log-writing changes were made.

## Evidence boundary

Full isolated suite passed 23/23. Regression cases cover helper/watchdog expiry,
stale cached active state, callback ordering, previous wake/cancellation/new-session
boundaries, inactive/unknown saved intent, supervision loss, durable suppression,
standalone modal ownership and acknowledgement. The final focused AppKit suite
passed 1/1 including the activity route. Native fixture clicks verified that OK
returns to the unchanged Desk page and View lid activity selects Lid activity.
The fixture defers its alert until NSApp finishes launching so it exercises the
normal modal event loop. Tests use journal fixtures, disposable preferences and
an isolated UI app. AGENT MODE ended after acceptance. No live sleep, lid movement, power changes or permission resets.
macOS sleep/wake notifications do not establish every possible cause of sleep;
the explanation reports observed protection and supervision evidence.

Signed 2.0.103 passed build, bundled Sparkle and nested-signature checks. It is
prepared only: not installed, notarized or published. The configurable grace and
meeting shortcut remain a separate proposal.
