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


## Live verification and automatic flow, September 13

The first 2.0.129 attempt stopped during launchd unloading. The old helper could
wait for the ownership lock while the installer waited for its exit; an immediate
job check falsely treated asynchronous unloading as failure. Cleanup completed,
the maintenance/ownership records were absent, and SleepDisabled remained No.
The corrected path launches bootout asynchronously, reaps only root-owned exact
old-helper processes with PID-birth checks, then verifies both job removal and
process exit within ten seconds. Virtual tests cover delayed completion, timeout
and invalid clocks. Helper version is now 5, protocol remains 3.

2.0.131 was installed and started through Perch's restart worker. Startup
maintenance automatically replaced the 2.0.94 lid helper while the lid stayed
closed on AC power. The activity journal confirms temporary sleep protection,
replacement helper/watchdog startup and ending the temporary allowance. The
guard job then reported not running, with no maintenance record. Perch resumed
the saved enabled lid choice automatically; the helper confirmed an active
owned session and SleepDisabled became Yes. No Resume or Finish action was
needed; the current-helper update action was disabled and Setup showed Ready.
A passive 200 ms observer recorded closed-lid state throughout; its sampling did
not resolve the very short maintenance-on interval, which is established by the
helper's verified-write activity events instead. This checks startup and the
originally-off override path, not transfer of an already-active countdown.

Automatic resume has virtual tests across 576 initial combinations, repeated
polls, failed attempts, active countdowns, retained cleanup, and opening/power
transitions. It does not restart an expired timer while closed on battery.
Background/input helpers already updated on launch; runtime recovery now waits
through brief outages and attempts once until a healthy session or next launch.
Installed collector configuration updates join serialized startup maintenance.
Optional uninstalled components remain optional; failed/cancelled authorization
leaves a specific failure instead of repeated prompting.

Settings follow-up: Background helpers becomes a status-only Setup page. There is
no standalone Security page or optional administrator-protection choice. If
administrator ownership ever becomes a product prerequisite, it belongs in the
relevant Setup stage. Reset Settings remains its own scope-wide destination.
Login approval opens from the failed Start at login action or its attention-only
overview entry. Generic repair, manual lid resume, and the duplicate
privacy-reset link are removed. UI evidence for these later changes is recorded
with their final candidate below.


## Active app restart verification, 2.0.135

The 131→134 active restart exposed a separate client race: an outstanding status
request could invalidate the connection carrying the restart claim. The helper
accepted the claim but the app reported no reply, then missed its five-second
heartbeat lease. The helper cleared the override as designed. This was a real
failed acceptance, not a successful handoff.

The client now fences pre-claim callbacks, suspends ordinary polling during the
claim, uses a separate claim connection, and immediately resumes normal-endpoint
heartbeats after adopting the reply. Injected tests cover an old status failure,
late timeout/off reply, successful adoption and failed-claim recovery.

Native verification on September 13: 134→135 with protection initially off
restored the saved enabled choice. A second restart, 135→135 while active,
reclaimed the owned session successfully. PID 48371 reported the preserved lid
session; the root journal recorded claim and resumed normal heartbeats with no
subsequent expiry. A 200 ms observer collected 801 samples across 180 seconds:
the lid remained closed, SleepDisabled became Yes after initial auto-resume,
and stayed Yes through the active restart and observation window. No maintenance
record was left behind. The compatible lid helper remained 131/helper version 5.
This is powered closed-lid app restart acceptance, not a battery/countdown helper
replacement, physical sleep/reboot, or Sparkle download/update acceptance.

Keyboard registration, lid/enforcement and AppKit settings suites passed against
135; two-/16-peer TLS fixtures also passed. Live settings navigation checked
Background helpers, Reset Settings, Keyboards and Keyboard access.
Permission instructions retain the current app drag/copy target and omit Finder
reveal. No reset or file-protection action was performed. The only later source
change for 136 corrects a stale sidebar destination in permission-ready copy.
