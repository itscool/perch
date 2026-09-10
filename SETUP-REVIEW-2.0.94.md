# Perch 2.0.94 static setup review

September 10, 2026. Reviewed running release 2.0.94 source (candidate snapshot
matches 466b2ec), plus current release tooling at a8dea49. No application source
was changed during this review. No UI control, test app, permissions change,
helper repair, hardware action or restart was performed after the static-only
instruction. Earlier read-only signature inspection established that the installed
app and user helper use Developer ID, while the preceding development app used a
different certificate. Reading the privacy database was denied; its actual grant
records are unknown. Signing mismatch is therefore a hypothesis for the live
access failure, not an established TCC diagnosis.

## Prioritized findings

### S1 — P1: keyboard recovery sends an already-enabled user into a relaunch loop

Sources/LaunchAccessRecovery.swift:6–7, 41–52; Sources/NavigationProbeHID.swift:43;
Sources/KeyboardSettingsUI.swift:219.

All denied capability checks receive launch-context advice. The recovery page
specifically says to leave an enabled Input Monitoring entry enabled and relaunch
from Finder. Rechecking can only repeat the same advice. The page neither
identifies a changed signed app nor offers a next step when a Finder relaunch
fails. It also lacks the current app's drag/copy-path control. The transition
from the old development certificate to Developer ID makes this omission
particularly relevant, without proving the OS denial's cause.

Correction: show observed access separately from possible causes. Present the
current app/path, a direct add/reselect route and explicit recovery for an old
entry or denied grant. Keep Finder relaunch as one conditional remedy, not the
only remedy. Do not automatically reset permissions or claim that a checkmark
proves access to the current process.

### S2 — P1: returning through the menu can leave Settings blocked after a handoff

Sources/SettingsWindow.swift:50–53, 111–113, 202–217, 303–306;
Sources/SettingsSidebar.swift:49–53; Sources/PanicUI.swift:119–125.

Opening Finder/System Settings sets externalHandoff, which makes all settings
interaction busy and disables the sidebar. Release depends on app activation,
the settings window becoming key, a failed open, or closing the window. The
Settings menu route calls navigate, which simply returns while busy. It does
not first bring the existing settings window forward or release the external
handoff. Thus a return through a menu that does not activate the accessory app
cannot escape this state. Ordinary pages such as Scrolling can appear inaccessible.

Correction: explicit user return through Settings/menu/sidebar must restore the
handoff before navigation, while password prompts, actual pickers and in-progress
confirmations retain their proper ownership. Preserve page/draft and avoid
background refresh stealing focus. The code has this dead-end path; the user's
specific incident has not been reproduced.

The existing PresentationHandoffTests.swift:60–76 injects the expected activation
notification. That validates handling the notification, not recovery when it
never arrives. Add the missing menu-return/click-return cases before claiming
this regression is covered.

### S3 — P2: permission setup controls differ across entry points

Sources/KeyboardSettingsUI.swift:213–221; Sources/LaunchAccessRecovery.swift:41–55;
Sources/NavigationProbeUI.swift:57–67; Sources/DeskInputSettings.swift:28–35.

Navigation learning provides the current Perch app as a drag/copy item, but
Keyboard details and Keyboard access do not. Desk input sharing has direct
Accessibility/Input Monitoring links with no drag/copy target or explanation
of which executable to add. Those links also bypass the shared handoff, so a
floating settings panel can remain above the destination app.

Correction: reuse one permission setup component with an explicit target
(Perch, the active Perch Helper, or the collector), drag and keyboard-copy options,
observed readiness, and consistent return handling at every entry point. General
macOS settings such as login items or keyboard behavior have no file drop target;
they should retain a clear return route without presenting a meaningless drag item.

### S4 — P2: Accessibility setup may supply the wrong helper copy

Sources/PermissionSetup.swift:35–36, 95–97;
Sources/GuardianInstall.swift:54–59, 62–76.

The draggable/revealed helper is chosen by whether a protected helper binary
exists on disk. Installation chooses the active location using the launch job's
ProgramArguments instead. With an old protected copy and a job running the user
copy, the page sends the user to the wrong executable. Existence is not evidence
that this is the helper macOS is currently checking.

Correction: derive the permission target from the validated active job/helper,
show its path, and distinguish stale files from the running component. No claim
that this stale-protected-copy condition exists on this Mac.

### S5 — P2: Full Disk Access fallback has no executable selection route

Sources/EventSetup.swift:62–64, 111, 136, 177–178.

The collector page says macOS may require Full Disk Access for the Perch collector
launcher when granting eslogger does not work. However, its sole drag target and
Finder action remain /usr/bin/eslogger. The user is told to authorize another
component without a name/path control to find it. This is an incomplete recovery
branch even if many machines only need the primary route.

Correction: provide the installed collector launcher's verified path and matching
drag/copy action when that recovery applies; report confirmed event receipt
separately from access that is still unknown.

### S6 — P2: helper startup freshness ignores signing identity

Sources/GuardianInstall.swift:24–44; Sources/main.swift:150–152;
Sources/HelperStatusIPC.swift:20–29.

The initial installed/current check compares only build number, bundle ID,
MachServices and launch-job presence. A same-version helper signed by another
publisher passes that check, while authenticated IPC can subsequently reject it.
Startup can therefore skip installation and leave setup saying the helper is
unavailable. This is distinct from S4's wrong drag target; it is not the observed
state of this Mac's currently matching Developer ID app/helper.

Correction: validate publisher compatibility as well as build/protocol and
surface a specific helper replacement requirement. Never weaken IPC trust to
make the mismatch disappear.

### S7 — P2: Desk first-use text contradicts the shipped setup

Sources/DeskLiveSettings.swift:293–296, 307;
Sources/DeskInputSettings.swift:19–24.

The welcome screen still says this version only switches monitor pictures and
that keyboard/mouse stay on their connected computer. The surrounding page and
shipping controls now offer keyboard/mouse sharing. A new user receives mutually
inconsistent instructions before setting up Desk.

Correction: describe monitor presets first and optional per-session input sharing
accurately, including the local-keyboard requirement for secure entry.

## Journey coverage ledger

All evidence below is source tracing, including handlers, readiness/persistence
and shared-window ownership; it is not a native click or hardware pass.

| Journey | States/routes examined | Result |
| --- | --- | --- |
| First launch and Setup & status | Startup notice, first-visit flag, optional/ready/attention/unknown, row routes, recheck | S1/S2 inherited; overview distinguishes saved intent from observed readiness |
| Keyboard details and access recovery | Missing access, already enabled, Finder, macOS settings, recheck | S1/S3 |
| Navigation learning | Recognized/saved, missing grant, drag/copy, learn/skip, completion/retry, leave | Has a drag target; shares S1/S2 recovery weaknesses |
| Scrolling and navigation access | Enabled preference, denied/unknown helper access, repair, permission review, leave/return | S2/S4; preference remains saved when helper access is absent |
| Background helper setup | Startup install/current check, repair, protected copy, process status | S4/S6 |
| Process event collection | Install/update, eslogger access, launcher fallback, stream readiness, return | S2/S5; received events and health remain separate checks |
| Keep awake/lid setup | Saved choice, active/unknown/stopped, resume, queued helper update, repair and logs | No additional static defect established; physical sleep/restart acceptance still open |
| Agent setup and shortcut test | Selection persistence, registration, scoped test, timed cleanup, parent return | Shared ownership traced; no additional isolated static defect established |
| Desk grouping and monitor setup | Invite/join/approve, address fallback, add screen, input mapping, preset editing/activation, conflict choice | S7; no new monitor/network acceptance claimed |
| Desk input sharing | Session enable, missing permissions, recheck, local recovery, keyboard follow setup | S3; physical access/routing remains untested here |
| App/login settings and updates | External login-items route, update ownership/retry, restart | S2 applies to external handoff; completed publication is not update-lifecycle acceptance |
| Maintenance/reset recovery | Repair, permission reset scope, confirmation, async result, leave | Scope/operation persistence traced; no reset executed |
| Shared sidebar, alerts, pickers and external windows | Busy flags, activation, explicit menu return, Back/Close, queued pages | S2; existing injected-return tests miss the relevant alternate path |

## Limits and disposition

All seven findings are open; no application fixes were made. The strongest
code-supported explanations for today's experience are S1–S3. The exact OS grant
failure and native dialog event sequence remain unknown. Static review cannot
establish that the signed release works on a fresh account or prove that every
native control is clickable. This report replaces any claim of zero known setup
defects and keeps live QA separate.
