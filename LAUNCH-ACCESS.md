# Access in the current app launch

The September 8 MX Keys failure reproduced with Perch already enabled in Input
Monitoring. Scoped TCC logs attributed direct agent-shell menu-app launches to
Codex. LaunchServices (`open -a /absolute/Perch.app`) restored current HID access
without privacy changes. That is evidence for those observed processes, not a
rule that every app-launched process has incorrect permissions.

The menu app uses the public IOHID access preflight. A denial does not identify
TCC's responsible application or prove a missing saved grant. Build 74 therefore
reports actual current denial, checks connected external keyboards at startup,
and offers the already-enabled/Finder relaunch route. It does not guess the
responsible app from parent PID, use private responsibility APIs, read the TCC
database, require log-reading privileges or reset permissions. Exact automatic
attribution remains unimplemented; unavailable or redacted logs cannot be proof.

| Capability | Process / evidence | Recovery scope |
| --- | --- | --- |
| Supported external Fn controls | Menu app; IOHID listen-event preflight and actual device result | Startup notice for a blocked connected device; menu hint, Keyboard settings/details, shared Keyboard access page and Setup & status |
| Learning navigation keys | Menu app; same HID preflight | Shared recovery beside learning controls. Saved known layouts do not require learning access just to remain configured. |
| Scrolling and navigation remapping | Independently launched Perch Helper; reported Accessibility status | Existing helper-specific recovery. Menu HID denial never marks this helper denied. |
| Built-in Fn preference / modifier properties | Native preference/property operations and their actual results | Preserve specific failures; no blanket HID-denial gate on unrelated controls. |
| AppleScript Automation | Menu app; actual error -1743 | Name Automation and offer normal-launch recovery for an already-allowed app. Cancellation and unrelated failures are unchanged. |
| Monitor transport | Display subprocess / transport-specific results | No evidence that menu Input Monitoring denial blocks display transport; no new gate or misleading keyboard-permission instruction. |
| Event collection / Full Disk Access | Collector and its existing setup probes | Keep collector-specific status; do not infer FDA from menu-app launch or keyboard denial. |
| Lid / ordinary keep awake | Privileged supervisor and background helper | Keep their authorization, freshness and supervision diagnoses separate. |

Normal restart can preserve the current responsibility identity. Recovery shows
the exact current bundle in Finder and explains Quit followed by double-click;
it does not terminate an active lid session merely to diagnose access. Native
app launch, helper access and physical keyboard writes still require acceptance
on the affected machine. No permission setting is modified by diagnosis.
