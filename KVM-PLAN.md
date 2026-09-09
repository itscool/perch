# Coordinated Perch KVM — replacement feature todo

Status: requested September 8, 2026; design and implementation pending. This
replaces standalone monitor input cycling as the product direction. It is a
planning change, not a claim that the installed app already supports it.

## Intended experience

Two or more computers running Perch communicate and agree on a handoff **before**
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

## Design and implementation work

1. Design first-use pairing, recognizable computer/device names, layout setup,
   reconnect and repair as one understandable flow. Define whether the first
   supported scope is Mac-to-Mac and record other-platform scope separately.
2. Establish authenticated, explicitly paired peer communication. Define
   capabilities, destination readiness, current display routes, active input
   focus and an agreed handoff transaction. Network protocol/discovery choices
   are not decided by this todo.
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

Exercise two real Perch computers with one display, either/both of two displays,
and mixed arrangements. Cover pointer and hotkey handoffs, physical keyboard host
buttons, mouse and keyboard initially connected to different computers, devices
with identical model names, simultaneous requests, peer sleep/disconnect,
reconnection and a display failing partway through a handoff. Verify both the
visible desktop and the actual recipient of keyboard/mouse input.

**Keyboard testing remains independently open:** built-in/external F1–F12,
Control/Command mappings, navigation keys, learning/default recognition, physical
device transitions and safe shortcut tests. Account for physical versus synthetic
input and active modifier mappings when interpreting automation results. The
monitor-direction change does not cancel these tests or existing keyboard fixes.
