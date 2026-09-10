# Notarization authorization

Submit artifacts to Apple for notarization only when the user explicitly requests
notarization for those artifacts. Building, signing, installing, preparing a
release, or storing credentials does not authorize a notarization submission.
Do not automatically notarize subsequent builds or the DMG after an app submission.
An explicit request covering both app and installer authorizes both stages.
Status/log checks for an existing submission and stapling its accepted ticket do
not create a new submission. This preference does not cancel existing submissions.

# Live UI testing

Before operating the live desktop, announce the app/flow and start the separate
AGENT MODE indicator using `Tools/agent-mode/agent-mode.py`. Read
`Tools/agent-mode/README.md` for its session protocol. Keep session artifacts in
the current task's `work/`, outside tracked source.

Run its `check` immediately before every short UI action batch. If the check
fails, or the user requests control in chat, stop UI actions, end the indicator
session, and acknowledge the handoff. Do not automatically restart after a
control request. Stop the indicator when finished or yielding to the user.

The indicator is cooperative, not an input lock or authorization for tests.
It does not cancel actions already started. Preserve the user's restrictions
on live permissions, hardware, emergency actions and publication. Source reads and compilation need no banner. Isolated storage or prohibited
activation does not make native window tests invisible. The functional suite
contains tests that show Settings panels and therefore requires the banner.
Build it first with `Tools/check-functional-review.py --build-only --output DIR`,
then, during an announced active session, use `--run-only --output DIR
--agent-session SESSION`. The runner checks before launch and between suites;
visible panel cases check again immediately before presentation. Do not start
or restart a session automatically after the user asks for control.

# Launch identity and privacy checks

Launch the live menu app through macOS LaunchServices (`open -a /absolute/Perch.app`),
not by executing `Contents/MacOS/Perch` from the agent shell. A direct terminal
launch can attribute Input Monitoring checks to Codex/the terminal despite
Perch already being enabled. This reproduced the MX Keys disabled-control bug.
Do not reset or re-request permission as the first response to that discrepancy:
check launch provenance, signing identity and scoped TCC attribution, then verify
normal app launch. Headless tools and deliberately isolated test subprocesses are
separate; the in-app verified restart worker has a live test preserving Perch’s
own attribution. Keep this distinction when changing launch/restart mechanisms.
