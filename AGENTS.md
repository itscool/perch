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
on live permissions, hardware, emergency actions and publication. Source reads,
compilation and isolated tests that do not operate the desktop need no banner.
