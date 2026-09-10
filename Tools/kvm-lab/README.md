# Native KVM desk preview

An interactive SwiftUI prototype using Perch's portable KVM configuration and
handoff models. All computers, screen connections, pairing and switch results
are simulated. It never opens network connections, requests input permissions,
captures/forwards input, switches a physical monitor or changes Perch settings.

Build an isolated lab (does not launch):

```sh
python3 Tools/kvm-lab/build.py --output /absolute/work/desk-lab
```

The lab saves only `/absolute/work/desk-lab/demo-desk.json`. For a separately
installable **Perch Desk Preview.app**, add `--installable`. That variant has its
own bundle identity and saves to the current user's Application Support/Perch
Desk Preview/demo-desk.json. It does not replace the live Perch app or its helper.
Sparkle belongs to the main Perch app; this disposable preview has no updater.

Run headless checks:

```sh
python3 Tools/check-kvm.py
python3 Tools/kvm-lab/check.py
```

Before any native UI inspection, follow AGENTS.md and start/check AGENT MODE.
Use the computer-use skill to interact; stop the indicator when finished.

Try selecting a preset card (editing only), its Play button (simulated switch),
the X/rotate controls on a screen and dragging its remaining surface. The right
pane exposes the screen's input-to-computer mappings and all three preset
connection choices. Computer mappings are direct dropdowns; the pencil expands
additional fields inside a lightly tinted, outlined area belonging to that row.
Unassigned physical inputs warn but remain usable for picture-only switching.
There is no None operating mode or bottom status bar. Active state appears on
the preset card. The small Desk Lab menu contains failure, concurrent-edit and
first-use scenarios. Temporary steps close with X/Escape.

This prototype is not an implementation of live discovery, pairing, group
membership authorization, production sync, physical switching or input routing.
Those are the next adapters described in KVM-ARCHITECTURE.md. Its readiness,
pairing and acknowledgement controls must not be connected to production traffic
as if they established trust or verified hardware.
