# Guarded system sleep override

The previous lid command changed a flag also owned by powerd. A physical test
showed powerd clearing it on a power transition, followed by Clamshell Sleep on
AC while Perch still considered protection active. Repeating that command on a
timer would leave a race with immediate sleep evaluation.

The replacement uses `/usr/bin/pmset -a disablesleep 1`. This blocks **all system
sleep**, including manual Sleep, while the supervised session is active. Turning
off lid protection restores normal sleep. The user authorized this tradeoff.
Display sleep and locking are separate; an immediate return or password screen
does not prove whether system sleep occurred.

## Ownership and cleanup

- Before enabling, refuse an already enabled system override. Write and sync a
  root-owned journal at `/var/db/local.scott.perch.lid-override/owned.json` before
  changing the setting. The journal records a unique session and restoration to
  normal sleep; no unrelated power preferences are rewritten.
- Require the independent recovery launch job to be installed and loaded.
  Enable and disable commands run in bounded worker processes. A POSIX lock
  survives exec into pmset, allowing cleanup to identify and stop a stalled
  writer before issuing a restore. Waiting enables check their session token
  and deadline; cleanup revokes the token.
- Confirm both the persistent system setting and the live root-domain
  `SleepDisabled` property. Continued supervision verifies these values without
  rewriting them. If another writer clears the setting, end the session.
- Keep the journal until restoration is confirmed. Failed cleanup is retried,
  rather than reported as successful. Helper startup starts disarmed and restores
  any owned override before accepting a new session.
- A separate root launch job, `local.scott.perch.lid.recovery`, runs at boot and
  every five seconds while the system is running. It only restores sleep. It
  checks a short supervisor lease, session token, boot identity and process birth
  identity. A missing, expired or invalid lease causes cleanup even if the app,
  supervisor and watchdog are gone. Helper replacement retains this recovery job
  until cleanup succeeds.

The existing five-second app lease, three-second watchdog lease and 60-second
closed-battery policy remain. Closing while already on battery starts the same
grace interval as unplugging while closed. Opening cancels it. Reconnecting power
stops enforcement; five seconds of stable power resets the next undock interval.
Expiry restores normal system sleep before requesting sleep.

This is recovery software, not a kernel-guaranteed expiry. A non-running OS,
removed/disabled launch jobs or unusable recovery storage can prevent cleanup.
Do not promise that a persistent setting can never be stranded. Before removing
Perch's privileged helper or recovery job, disable lid protection and verify
`pmset -g` reports `SleepDisabled 0`; retain recovery if cleanup fails.

## Compatibility and acceptance

The wire protocol remains 2; helper revision 2 requires a separate visible helper
update. UI-only app replacement can still use the existing restart handoff.
Replacing the privileged helper requires an open lid and administrator
authorization. The updater does not itself enable a sleep override.

Isolated tests exercise journal reconstruction, ownership refusal, failed-cleanup
retention, boot/lease/process identity rejection, and stopping a disposable
stalled writer before cleanup obtains the lock. Read-only integration checks
compare actual persistent/live system state. These do not establish real power
mutation, crash/reboot recovery or physical lid behavior.

Physical acceptance must cover powered close, close/unplug/open, close/unplug/
replug/open, **unplugged and open → close → plug → open**, full 60-second expiry,
manual Sleep after disabling, and coordinated app/helper/watchdog/reboot failure
recovery. Correlate Perch's journal with macOS Sleep/Wake evidence. Do not infer
success from immediate resume or plausible countdown logs.

Primary implementation references: Apple's [pmset implementation](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m),
[powerd clamshell policy](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmconfigd/PMAssertions.c),
and [IOPMrootDomain](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp).
