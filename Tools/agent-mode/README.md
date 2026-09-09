# Agent mode for desktop testing

Show an explicit **AGENT MODE** banner before an agent operates the live UI.
This tool is separate from Perch: it works through app restarts and OS handoffs,
does not change the main menu, and does not activate or take keyboard focus.
It puts a high-contrast notice on each connected screen and across Spaces.
It is an indicator and a cooperative handoff protocol, not an input lock or
a mechanism for cancelling commands that have already started.

Use an absolute directory in the current task's `work/` for the session:

```sh
python3 Tools/agent-mode/agent-mode.py start --session /absolute/task/work/agent-mode
python3 Tools/agent-mode/agent-mode.py check --session /absolute/task/work/agent-mode
# Perform one short UI action batch, then check again before the next batch.
python3 Tools/agent-mode/agent-mode.py stop --session /absolute/task/work/agent-mode
```

Before starting, tell the user which app/flow you will operate. Start must
succeed and the banner must be visible before any UI actions. Use the required
computer-use tool for those actions. Run `check` immediately before **every**
batch; its nonzero exit means stop, including if the banner disappeared. Never
renew in a background loop. Keep action batches short. Check again after a
long-running action and before doing anything else.

**Request control** writes a separate marker that a concurrent heartbeat cannot
erase. The banner then says **CONTROL REQUESTED**, explaining that the current
action may finish. At the next check, the agent must stop operating, run `stop`,
and tell the user control has returned. A user request in chat has the same
effect. This button does not invoke Perch Panic, kill other processes, or reset
any settings or permissions.

Each successful check renews the session for 90 seconds. An expired session
shows **AGENT MODE PAUSED** and refuses further checks; it must be explicitly
stopped and a new session announced before restarting. The agent must not
restart automatically after a control request. On completion, errors or chat
handoff, run `stop` and verify the banner has closed. A normal completion should
not leave a stale testing notice. Only the banner process watches this session;
there is no login item or persistent service.

Do not use the indicator to imply permission for the underlying tests. Continue
to honor restrictions on live hardware changes, credentials, destructive
actions and external publication. It does not enforce tool access and cannot
stop another agent that ignores this protocol. Native system/security UI may
appear above the floating banner; it deliberately avoids elevated levels that
could obstruct a password prompt.

## Native test suites also need the banner

An isolated preferences domain and `NSApplication.ActivationPolicy.prohibited`
do not prevent a test from showing windows. The functional regression suite has
native panel handoff tests, so compile it before taking the desktop:

```sh
python3 Tools/check-functional-review.py --build-only --output /absolute/task/work/tests
# Announce the test scope, then start/check AGENT MODE as described above.
python3 Tools/check-functional-review.py --run-only --output /absolute/task/work/tests --agent-session /absolute/task/work/agent-mode
# Stop the banner on completion or error and hand the desktop back.
```

Execution without a session is rejected. The test process checks before each
suite and the visible-panel cases check immediately before ordering a window
front. A stopped, expired or control-requested session prevents those actions.
These are foreground action-boundary checks, not a background renewal loop.
