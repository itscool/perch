# Coordinated Perch KVM — replacement feature todo

Status: implementation started September 9, 2026. The portable configuration,
signed synchronization graph, geometry and handoff state machine have headless
tests; a separate native Desk Lab exercises simulated user journeys. Live
pairing/network/input/monitor adapters and production integration remain open.
See KVM-ARCHITECTURE.md and KVM-REVIEW.md. The installed app does not yet support KVM.

## Current milestone and replacement boundary

September 9 priority: first make real computers join a group, synchronize the
shared desk and switch physical monitor inputs through the three presets.
Keyboard/mouse capture, forwarding, pointer-edge handoff and same-keyboard
following come afterward. Monitor-only operation must not depend on input-sharing
permissions or pretend that changing a picture changes keyboard ownership.

Desk replaces the existing monitor-input cycling pages, switching-group model,
shortcuts and setup/recovery workflow. Keep the proven low-level DDC/USB/other
monitor transports where useful. Migrate compatible saved names and input maps;
ambiguous physical identity or control mappings require confirmation. Retire old
entry points and hotkeys during the production migration so two independent
monitor systems cannot compete. Keep the current controls working until the
replacement is actually ready; the separate simulation is not that replacement.

## Intended experience

A named group contains 2–16 computers running Perch. Pairing authorizes
each computer to join; it does not restrict the group to one pair. Members communicate and agree on a handoff **before**
switching monitor inputs. The user changes the computer they are working on;
Perch coordinates display routing, pointer control and keyboard focus together.
The user should not need to know which computer physically receives the mouse
or keyboard events.

- **Pointer-driven handoff:** moving the mouse to another computer's workspace
  transfers control/focus there, even when a different computer receives the
  physical mouse input. Define the spatial/edge behavior and input forwarding
  needed to make this predictable; moving a pointer and merely changing a video
  input are not equivalent.
- **Keyboard focus:** route typing to the intended computer after handoff, with
  a clear indication of the destination. Avoid duplicate delivery, feedback
  loops, or stuck keys/buttons/modifiers across a transition.
- **Hotkey handoff:** a keypress selects or changes the destination and its
  configured display/input arrangement as one coordinated action.
- **Follow the same keyboard:** optionally hand off when another paired Perch
  computer detects that the same physical keyboard has switched to it. The
  reference experience is the 1/2/3 host buttons on an MX Keys-style keyboard.
  Match a registered physical device across hosts, not just a shared model name.
  Research what Bluetooth/receiver/device events actually reveal; do not assume
  the host-button number or arrival identity is directly readable. Do not use
  the absence of typing alone as evidence that the keyboard changed hosts.
- **Single and multiple displays:** support one shared monitor, either of two,
  both, and saved combinations assigning different displays to different
  computers. Explicitly define which display owns pointer/keyboard focus in a
  mixed arrangement. A new display must not silently join an existing action.

## Interface quality is a feature requirement

The primary experience is arranging a desk and choosing where to work. Use one
beautiful, readable visual desk layout, three named preset choices and contextual
details for the selected computer/monitor. Keep Identify, Add, Remove and Change
obvious. Technical identifiers, transport/protocol details and diagnostics stay
in contextual details/recovery rather than dominating first setup. Information
hierarchy must remain clear at both a two-computer desk and the 16-member limit.

September 9 refinements: each screen tile has an X for scoped removal and a
clockwise rotation button; drag the rest to move it. Keep exact position/size
entry available contextually for keyboard access. The selected screen's details
have two compact lists: connections with their mapped computers, and all three
preset connection choices together. Each choice is **Connection — Computer** or
**Connection — Unassigned**. An unassigned physical input remains selectable
with a small picture-only warning; it does not grant remote input ownership.
There is no operational None option. Choose connection is an incomplete-setup
placeholder, and each preset must choose a real connection for every screen
before activation. Removing a computer unmaps its inputs without removing those
physical inputs or their preset selections. New screens require explicit choices
before a preset can switch them; they do not silently join existing actions.
Selecting a preset card changes what is being edited. Its own small Play button,
beside the shortcut, switches to it. An Active badge indicates the running preset;
editing remains distinct from activation. There is no bottom status bar; exceptional problems appear contextually.
Ordinary connection editing expands inline. Stable Settings pages rely on the
left navigation list rather than also offering a Back/Close header button.

Before building the KVM UI, prototype complete first-use, daily-switching, edit,
add/remove, monitor-identification correction, offline-member and failure/retry
journeys. Apply the settings-flow-review skill iteratively across the whole set.
Review real transitions, saving/synchronization, completion and recovery, not just
static screens. Preserve consistent Back/Close and immediate saving for ordinary
choices, with explicit confirmation only for meaningful disruptive actions.

Acceptance requires users to understand what each screen represents, which
computer will receive input, whether the desired arrangement is actually active,
what has synchronized and what to do next when something is unavailable. Use
clear text plus visual state, keyboard access and accessibility labels; avoid
color-only meaning, subtle-only outlines, dead buttons, unexplained disabled
actions, flickering availability and surprise focus changes. Underlying protocol
complexity is not a reason to make the user manage it manually.

## Presets, physical layout and pointer handoff

- Up to three named presets choose computer-to-monitor assignments across the
  group. Default shortcuts are Ctrl–Opt–Cmd–F1, Ctrl–Opt–Cmd–F2 and
  Ctrl–Opt–Cmd–F3, customizable and synchronized. Unconfigured slots must not
  perform an action; show shortcut conflicts/readiness per member computer.
- One visual layout editor represents the actual positions and relative physical
  sizes of up to 16 monitors, including rotation. Support irregular arrangements,
  edge alignment, mixed sizes/resolutions/scaling and portrait screens. Identify
  screens on demand; label computer assignments directly on monitor tiles.
- Crossing a configured screen boundary moves the pointer and keyboard focus to
  the computer owning the destination screen under the active preset. The logical
  destination is independent of the computer physically receiving the mouse or
  keyboard. Forward captured events from their source to the agreed owner, avoid
  duplicate local delivery and loops, and retain a local recovery action.
- Within one computer, preserve normal native pointer behavior. Across computers,
  transform edge/entry coordinates for rotation, scaling and physical alignment.
  Define visible boundary behavior for gaps, overlapping/ambiguous edges, corners
  and disconnected layout islands; do not silently choose a surprising target.
- Preset activation may reroute a shared physical monitor. Negotiate availability
  and monitor switching before committing control/focus to the destination. Keep
  verified-visible routes distinct from requested routes; do not blindly send
  typing to an unseen computer when an input switch fails or is unconfirmed.
- Synchronize layout, presets and shortcuts; arbitrate the current active preset
  and control owner separately as live group state. Concurrent hotkeys/edge
  crossings must converge on one transaction. Preserve/release held modifiers,
  keys and mouse buttons safely on handoff, loss of connection and cancellation.

Acceptance includes all three presets/shortcuts, portrait/rotated screens, mixed
DPI and scaling, irregular edges/gaps, one versus multiple computers in a preset,
mouse/keyboard attached to different source computers, three-member traversal,
16-screen layout simulation, conflicting requests, unavailable destinations and
partial physical monitor switching. OS limits on input capture/injection remain
feasibility work; do not claim secure-input or login-screen forwarding without
platform-specific evidence.

## One shared group setup

The user configures the group from any member computer. Every member displays
the same group-owned setup and stays synchronized after joining: computer and
monitor names/identities, membership, per-computer input/port maps, arrangements,
switching behavior and shared shortcuts. No repeated manual setup on each PC.
An offline member catches up when it reconnects; its absence does not erase its
configuration or block ordinary edits to other members.

Present one understandable group/layout view with named computers and monitors,
Identify, Add/Remove and direct editing. Ordinary valid changes save immediately
and synchronize; show pending/offline/conflict status only when useful, without
claiming a change is saved remotely before acknowledgement. Explain any explicit
confirmation needed for membership removal or a disruptive routing change.

Define authenticated revisions, durable local storage, peer acknowledgements,
conflict resolution, schema migration and propagation of removals. Concurrent
incompatible edits require clear resolution; do not silently apply last-writer
wins to monitor identity, input mappings or ownership. Revoked peers must not
rejoin or restore removed configuration through stale sync. Keep the group
protocol portable for eventual Windows/Linux members.

Synchronize configuration separately from live observed state and active handoff
ownership. Per-machine OS permissions remain locally granted, but the group view
shows which computer needs attention and what action must happen there. A shared
shortcut must also expose per-host conflicts/availability. Never propagate local
Input Monitoring grants, lid policy, privacy resets or unobserved monitor state
as if they were shared group settings.

Acceptance includes editing from different members, reopening elsewhere, offline
edits/rejoin, interrupted synchronization, simultaneous conflicting edits,
removal/revocation, schema compatibility and 16-member convergence.

## Physical monitor identity and sharing

A group supports up to 16 distinct physical monitors, counting a shared screen
once across all member computers. This is a group limit, not a promise that one
Mac/GPU can drive 16 displays. Keep the physical monitor record separate from
each computer’s local display identifier and cable/input connection.

- Compare manufacturer/model plus meaningful numeric and textual serials from
  EDID/DisplayID when available. Exchange observations only among trusted group
  members. Treat a strong match as a proposed shared monitor; detect collisions.
- Physical input ports exist independently of their computer mapping. Keep an
  unmapped input available for consoles, devices outside the group, or a computer
  not yet mapped. Switching its picture requires a trusted member with a verified
  control/readback path. Pointer crossing into it is blocked; selecting it as the
  focus screen by preset keeps input local. Never invent a remote computer owner.
- A monitor network-interface MAC is not a universal display identity. Some hub
  monitors provide Ethernet, but HDMI/DisplayPort endpoints need not expose it.
  Host-specific display IDs, registry paths and USB location IDs also cannot
  establish cross-computer physical identity by themselves.
- Missing/duplicate serials, identical model names, changed inputs/adapters,
  emulated EDID and ambiguous observations require a visual Identify/confirm
  flow. Never silently merge monitors based on model, resolution or a hash of
  non-unique EDID. Confirm one visible physical screen at a time.
- Give a confirmed screen a group-owned Perch UUID/name and retain its per-host
  connections (computer, local display, monitor input). Provide merge/split and
  remap recovery without discarding other confirmed screens.
- Track shared identity, connectivity, requested input and verified currently
  visible input separately. Read input state where supported; keep unknown state
  explicit. Being detected by macOS is not proof that its picture is visible.
- Test duplicate/missing serials, two identical monitors, changed docking routes,
  different ports on one monitor, disconnected members, split/merge correction,
  16 unique monitors and rejection of an additional unique monitor.

References: [Apple display serials](https://developer.apple.com/documentation/coregraphics/cgdisplayserialnumber(_:)),
[Windows EDID identity](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorid).

## Design and implementation work

1. Design group creation, joining, naming, adding/removing computers, layout
   setup, reconnect and repair as one understandable flow. Pairing establishes
   trust for membership; a group can have 2–16 computers. Enforce the limit consistently in
   join requests and Settings, explain when the group is full, and keep named
   destinations/layout navigation usable at 16 members. Define group
   membership changes, revocation, offline members and who currently owns each
   input/display arrangement. Start with Macs; Windows/Linux members are backlog
   work. Keep the group/authentication/handoff protocol independent of Apple
   discovery and transport APIs so mixed-platform groups remain possible.
2. Establish authenticated, explicitly paired peer communication. Define
   capabilities, destination readiness, current display routes, active input
   focus and an agreed handoff transaction. Network protocol/discovery choices
   will be validated with two Macs: Bonjour on the local network plus Apple
   peer-to-peer Wi-Fi through Network.framework (includePeerToPeer), allowing
   nearby Macs on different routers to discover/connect directly. Present one
   Add computer list, confirm pairing on both Macs, and retain authenticated
   identities across reconnects. For routed networks beyond radio range, support
   an explicit reachable address first; automatic cross-subnet discovery needs
   DNS-SD infrastructure or a rendezvous mechanism. Do not assume discovery
   implies reachability or authorization. Prototype latency, VPN coexistence,
   sleep and reconnect before promising seamless input forwarding.
   Reference: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
3. Define monitor-to-computer port mappings and saved arrangements. Evaluate
   which existing monitor transports/catalogs can be reused underneath this
   experience; do not carry the standalone cycling setup forward by default.
4. Resolve physical input reception versus the logical destination. Evaluate
   supported input capture/forwarding, required user permissions, suppression of
   duplicate local delivery, cursor placement and modifier/button continuity.
   Peer communication alone does not move hardware input or verify monitor input.
5. Negotiate the destination and arrangement before issuing monitor commands.
   Track requested versus observed results per display, including unsupported
   readback. Two peers must not assume success merely because a command was sent.
6. Handle concurrent triggers, delayed messages, reconnect, sleeping/unavailable
   peers and partial monitor failures. Prevent oscillating handoffs; keep a clear
   local way to regain control. Do not promise atomic switching or rollback until
   the selected monitor/control paths can support it.
7. Replace the old cycling menu action, shortcut and setup journey with the new
   handoff experience. Plan migration of useful saved mappings and retirement of
   obsolete settings. Leave the current implementation intact until its
   replacement is ready and reviewed.

## Acceptance

Exercise two and at least three real Perch computers in a group, plus simulated
16-member discovery/membership/routing and rejected 17th-member joins, with one display, either/both of two displays,
and mixed arrangements. Cover pointer and hotkey handoffs, physical keyboard host
buttons, mouse and keyboard initially connected to different computers, devices
with identical model names, simultaneous requests, peer sleep/disconnect,
reconnection and a display failing partway through a handoff. Verify both the
visible desktop and the actual recipient of keyboard/mouse input.

**Existing keyboard acceptance:** after the physical keyboard checklist was
explained, the user confirmed those behaviors work on build 75. This is user
acceptance, not an agent-observed replay of every combination or certification
of all catalog hardware. Shortcut detection and Add app/executable also have
user confirmation; build 77's result Back fix still needs native acceptance.
KVM-specific cross-host identity, focus and physical handoff tests above remain
open. See [the current ordered backlog](TODO.md).
