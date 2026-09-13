# Desktop participation after monitor handoff

September 13, 2026. Scott reports that after a monitor switches to another
computer's input, this Mac still leaves windows on that monitor.

Source review: DeskRuntime refreshes reported displays and KVMMonitorSwitch
tracks fresh input observations. No Perch code changes macOS display enablement,
mirroring or window positions in response. A successful input command does not
promise that the losing Mac removes the screen from its desktop.

The likely mechanism is that the monitor continues advertising the connection
while displaying another input. This particular monitor's electrical/OS state
was not tested, so it remains a diagnosis to verify, not an observed hardware fact.

## Feasibility evidence

- Apple's Quartz Display Services overview distinguishes online/active displays
  and desktop configuration. The current SDK's CGDisplayIsOnline reports the
  connection; it is not a query for the monitor's selected input.
  https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/Overview.html
- BetterDisplay documents software disconnect/reconnect without unplugging,
  showing this class of behavior is achievable on supported Macs.
  https://github.com/waydabber/BetterDisplay
- displayplacer documents enabled:false and warns that re-enabling can require
  unplug/replug. Its command is not a proven recovery mechanism for Perch.
  https://github.com/jakehilborn/displayplacer

## Proposed implementation boundary

Treat shared input, physical monitor input and participation in each Mac's desktop
as separate states. On a confirmed handoff, reconcile which screens each Mac can
actually use, and restore its saved configuration when screens return. Investigate
the OS-specific disconnect backend before wiring it into normal switching.

Required cases: last visible screen, closed lid, an offline peer, partial monitor
switch, unknown input, app crash/restart, manual monitor changes and reconnection.
Ensure disconnecting video does not remove the only DDC/control route needed to
return. Preserve mirroring, rotation, scale and layout; do not promise exact
per-app window restoration without testing it. A user-invoked window-gather action
could be a fallback, but would not stop future windows opening on an extended
screen that remains active.

No display settings, windows, power state or permissions were changed during this
investigation. This is a recorded known gap, not part of the installed 2.0.116 fix.


## September 13 follow-up: BetterDisplay and the unshipped experiment

BetterDisplay's author addresses this exact use case: read VCP 0x60 and use
software connect/disconnect according to the selected input. The answer explicitly
leaves practical reliability to experimentation; the later CLI example exposes
`connected`, rather than treating a physical power-off command as disconnection.
https://github.com/waydabber/BetterDisplay/discussions/4364
https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI

The author also documents reconnect-all and its default on normal app quit;
this is not evidence that force-quit/crash restores every screen.
https://github.com/waydabber/BetterDisplay/discussions/2604
On Intel, removing a screen from the layout does not fully power it down.
https://github.com/waydabber/BetterDisplay/issues/1806

Perch briefly prototyped public application-lifetime mirroring as a way to remove
separate desktop space while retaining the DDC path. Its 16 two-monitor ownership
combinations passed policy tests; the native backend was only compiled, never
invoked. That draft is outside production source and is NOT in the next candidate.
Do not call this defect fixed. BetterDisplay's internal implementation has not
been verified, and its existence does not prove private display-disable APIs are
safe for Perch's independent switching/recovery needs.

Next: develop a recoverable software-disconnect backend with injected topology,
last-visible-display checks, saved configuration, expiry/crash restoration and
control-path recovery; then perform explicitly coordinated physical acceptance.
New reads must invalidate pre-switch observations before driving desktop changes.
Do not use a previous command, desired preset, lost peer, or unknown input as
permission to disconnect a display.
