# Closed-lid helper replacement

September 13, 2026. Replaces the requirement to open the lid merely to finish a
queued helper update. This changes helper version 3 to 4; XPC protocol stays 3.

## User behavior

Finish lid helper update remains available with the lid closed. Administrator
authorization is still required. An owned active session is captured after that
authorization, including the remaining battery deadline or manual countdown.
The installer temporarily holds the existing system sleep override. A previously
off override returns to off; a previously active session transfers to the new
helper. Unrelated system overrides are refused, not adopted or cleared.
Without an active session, a closed laptop must have external power. Unknown
observations, stale/unavailable session evidence and expired timers stop the update.
Saved menu choices are not changed. Ordinary app restarts still use their existing
separate handoff.

## Replacement and recovery

- Serialize the whole installer with a kernel-released lock; concurrent apps
  cannot replace an in-progress installer’s guard. Stage and verify the complete
  signed bundle before system changes.
- Install a separate signed update-recovery bundle/job outside the replaced helper
  path. Its durable maintenance record has one nonrenewable 60-second deadline.
- Capture the current session through authenticated XPC from a child that drops
  root privilege to the configured user. Taking this snapshot after authorization
  avoids resetting a timer based on state from before the password prompt.
- Serialize against pmset writers, save old/new ownership tokens before stopping
  jobs, explicitly launch recovery and require its live PID/birth/heartbeat proof.
  Do not depend solely on a PathState filesystem notification.
- Unload old helper/recovery jobs, then verify/reap only root-owned processes at the
  exact helper executable path, with PID-birth checks. Transfer tokens while the
  writer lock is held. Old queued workers cannot write using their old token.
- Preserve the override through replacement. The independent guard observes the
  existing lid policy during the gap and records deadline/countdown changes.
- The replacement starts its watchdog before accepting the captured session.
  It adopts the same token and latest timer state and resumes ordinary heartbeats.
- Failure, expiry, explicit disable or reboot invalidates the update allowance and
  restores normal sleep. Retain recovery records while a write/readback fails.
  Independent recovery uses its own immutable bundle, so moving/replacing the main
  helper cannot remove the recovery executable.
- Once the maintenance record is gone the update guard exits; its PathState job
  does not repeatedly launch in steady state. RunAtLoad also checks recovery after
  reboot. Activity records distinguish temporary protection, handoff and recovery.

## Verification boundary

New deterministic checks cover deadline/reboot/clock boundaries, owned versus
unowned overrides, stale capture, lid/power combinations, original countdown and
battery deadlines, and shell syntax without executing installation commands.
Existing virtual-time enforcement/ownership/restart tests remain applicable.
The actual privileged launchd replacement, process quiescence, XPC capture after
UID drop, failed-install recovery and physical continuity require a coordinated
administrator-authorized integration test. A passing isolated suite is not a
claim that this privileged integration has been exercised on the live Mac.

## Removal

The update guard is a separate installed component:
`/Library/PrivilegedHelperTools/Perch Lid Update Guard.app` and
`/Library/LaunchDaemons/local.scott.perch.lid.update-recovery.plist`.
Uninstall must first complete Perch-owned sleep cleanup and verify it, then unload
this job and remove its bundle/plist. Never remove the guard while maintenance or
failed-cleanup ownership remains. This is also part of clean-account lifecycle QA.

## Delivered candidate

2.0.129 is Developer ID signed and installed on disk; PID 12800 remains 2.0.120.
The final lid/enforcement regression suite passed, including 378,504 generated
policy transitions, 47,988 countdown transitions, the new maintenance boundary
and frozen-countdown checks, ownership/restart recovery and helper-update UI.
A real disposable-process lock test confirmed exclusion and crash release.
The build was warning-free and passed bundled Sparkle/signature checks. No live
helper replacement, sleep-setting write, notarization or publication occurred.
The recoverable prior app is /Applications/.perch-previous-7_6cfko1/Perch.app.
