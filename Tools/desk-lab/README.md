# Desk lab: two macOS guests

Runs Perch's Desk on two disposable macOS virtual machines and exercises the
parts that used to fail only on the real desk: discovery, connection,
reconnection, version skew, and keyboard and mouse sharing. Every run writes
its evidence to `work/desk-lab/<timestamp>/`, including a merged timeline, so a
failure names the step that broke.

## What it needs

- `tart` (Apple silicon virtualization). Installed at `~/.local/bin/tart`;
  set `TART` to point elsewhere.
- The base guest image `ghcr.io/cirruslabs/macos-tahoe-base:latest` (macOS 26).
- A Perch build to test: `./build.sh --no-bump` produces `build/Perch.app`.

Apple allows two macOS guests per host, so the lab uses exactly two:
`perch-a` and `perch-b`, cloned from the base image and disposable.

## Running it

```
python3 Tools/desk-lab/provision.py            # clone and boot both guests
python3 Tools/desk-lab/run.py                  # prepare, then run the matrix
python3 Tools/desk-lab/run.py --only sharing-crossings --rounds 200
python3 Tools/desk-lab/provision.py --stop     # stop both guests
```

`run.py --recreate` rebuilds the guests from the base image first. The base
image is never modified.

## What each part does

- `provision.py` clones, boots headless and reports each guest's address.
- `prepare.py` copies the build in, installs the guest input tool, seeds a
  desk both guests already belong to, turns sharing on, and grants
  Accessibility and Input Monitoring. Granting is only unattended when the
  guest has System Integrity Protection off; otherwise it reports the one-time
  clicks a person must do in that image.
- `seed.py` builds a paired desk with Perch's own identity and membership
  types, so the lab spends its time on connection and sharing rather than on
  the pairing handshake, which the loopback suite already covers.
- `sharing.py` drives synthetic input inside whichever guest has control and
  judges each crossing by what the *other* guest recorded: hundreds of
  crossings, slow drags, fast flicks, diagonals, crossing with a button held,
  typing bursts, modifier chords, key repeat and switches mid-sequence. It
  reports switch latency, missed crossings, echoes back to the sender, and any
  key or modifier left stuck.
- `run.py` runs the permutation matrix and collects both guests' desk
  connection logs and Perch log slices.

All synthetic input happens inside the guests over SSH. The lab never drives
the host's desktop and never touches the host's Perch or `/Applications`.

## Relayed links

tart's shared networking isolates the guests from each other, so
`run.py --relay` forwards each guest's desk port to the other through this Mac
and seeds each guest with that dial address. It exists so the sharing work can
run today; it is not the real path. A relayed run bypasses discovery,
link-local addressing and interface selection, so pairing through discovery,
reconnect storms and version-skew refusal over the network still need real
guest-to-guest networking (bridged to a wired interface, or softnet). Every
relayed run prints that list at the end.


A relayed link poisons the saved dial address, and that is the lab's doing, not
Perch's. When a peer reports its listening port, Perch saves the remote host of
the current path as that peer's address. Through the relay the connection
arrives from inside the guest, so each side saves `127.0.0.1` or the host
gateway, and one guest ends up recorded as reaching its peer at its own
listener. After a restart it dials itself and the handshake is refused as a bad
certificate.

On a real network this recovers: when a discovered and a saved address both
exist, Perch alternates between them, so a stale saved address cannot block a
reachable peer. Here discovery is unavailable, so only the poisoned address is
ever dialled. Read a failed peer restart in a relayed run as this artefact
unless the same failure appears with real guest-to-guest networking. The one
thing worth checking on hardware is that the saved address is accepted without
a loopback or self check.

## Reading the results

`results.json` carries one summary for all crossings. To see whether slow drags,
fast flicks, diagonals and button-held crossings behave differently, and whether
a switch works in one direction but not the other, run the reporter over a
finished run:

    build/release-tools/bin/python3 Tools/desk-lab/report.py work/desk-lab/<timestamp>

It recomputes the same per-crossing judgement from the saved plan and traces, so
it can be run again later without touching the guests.

The reporter's columns are count, missed, echo, wrong, then median, 95th
percentile and worst latency. "Echo" counts input that came back to the machine
that drove it, which would mean both Macs think they own the pointer. "Wrong"
counts crossings that arrived but landed away from the shared edge, measured
against the edge the pointer entered from. Both should be zero.

Typing passes only on evidence. Counting unbalanced key events is satisfied by
no events at all, so a run that captured nothing would report no stuck keys and
mean nothing by it. The check now requires keystrokes to have been captured
first, then requires them balanced and the modifiers released, and a capture of
zero fails outright. The same rule of thumb applies throughout: a check that
passes on missing data is worse than no check.

Event counts from the tap are approximate, and the checks are written to suit
that. During fast bursts the tap loses a fraction of events: one run posted
1500 drag events and recorded 1160, while the fixed-interval pointer sampler
lost none at all, 10,600 ticks for 530 seconds. So unequal press and release
totals mean sampling loss, not a stuck input, and the stuck check asks instead
whether a machine finished with a key or button still pressed. Treat every tap
count as a lower bound, and never conclude anything from a small imbalance.

## Readiness before judgement

Every permutation refuses to run until Perch is actually up: the process is
present and the desk port is listening in each guest, and for anything that
depends on the link, both sides hold an authenticated connection. A run that
cannot reach that state fails loudly and saves the guest's own log next to the
results, because a permutation that silently measured a dead app once reported
200 missed crossings that meant nothing.

Seeding is checked too. Both guests are seeded together from one membership,
and preparation then reads back each guest's own keychain identity and compares
it against what both desks pin. A guest that reverted to base-image state, or
was seeded while Perch was still running, presents a certificate the other side
has never seen; the transport calls that "misc. bad certificate" on one side and
a plain timeout on the other, which is slow to recognise and wastes a whole run.
Preparation now fails loudly instead. The headless self-check covers the same
condition in seconds, without guests.

## Host toolchain

The lab builds its guest tool and its seeder with `xcrun`. If a freshly
installed Xcode has an unaccepted licence, every such call fails; the lab then
falls back to the Command Line Tools rather than accepting a licence on your
behalf. This affects the lab only. It does not make a release build.

## Faking the monitor edge

Pointer and keyboard sharing needs a faked monitor edge here, and that fake is
labelled everywhere it appears.

Perch will not start input sharing without an active preset. Building a switch
request throws unless every screen in the preset has a control connection and
an input code. The active preset is set only by a switch that settles with all
routes accepted, or by matching monitor inputs read back over DDC. Automatic
start then needs that active preset and an assignment owned by another
computer. A virtual display answers no DDC, so none of it can happen.

So the lab installs a stub monitor adapter at `Contents/MacOS/PerchDisplay`
inside each guest's copy of the app. Perch resolves that helper beside its own
executable and checks only that it is executable, so the stub can answer the
DDC read and write that gate sharing. It keeps its state in a file, so a read
returns whatever the last switch set, which is what Perch's reconciliation
compares.

What this proves and what it does not. The desk link, the input session, the
handoff and the event taps are Perch's own code, running across two operating
systems with real TLS between them, so crossing and typing results are real.
Monitor switching itself is faked outright, so no run here says anything about
DDC, monitor profiles or picture switching. The runner prints that on every
run and records it in the results file.

The seeded screens are the size the guests really are. Preparation asks each
guest, in its own window session, what CoreGraphics reports, and seeds a screen
of exactly that physical size, with the second placed at the first one's right
edge so the shared edge aligns. This matters because Perch scales pointer
motion by a screen's physical size divided by its size in points, so invented
dimensions distort the mapping and can stop the pointer reaching the edge.

Measured here: both guests report one display, id 1, 1024 by 768 points and
369 by 281 millimetres, identical in-session and over SSH. Those bounds are not
empty, so Perch's fixed-scale fallback for an unreadable display was never
reached. If you see no crossings, that fallback is not the explanation.

Crossings are driven by pushing against the edge, not by moving to it. Perch
builds its canvas position from event deltas scaled by the screen, not from the
cursor's absolute position, and a cursor clamped on the last pixel reports no
further movement. Warping the pointer to the screen's edge therefore produces
no crossing however far the drag intended to travel: the proposed point stays
inside the screen, and the crossing rule needs it strictly outside. So after
reaching the edge the lab posts a short burst of motion events at the clamped
position carrying one plausible mouse delta each, which is what a real device
reports while it is pushed against the side of a screen.

Direction matters too. The first guest's screen sits left of the second on the
canvas, so it crosses off its right edge with a positive delta and the second
crosses off its left edge with a negative one. Driving both to the right would
push one of them off the far side of the canvas, where no screen exists, and
only one direction could ever succeed.

Two instruments separate the questions that look alike from outside.

The adapter stub starts on a different monitor input from the one the preset
selects, so a genuine activation has to issue a switch rather than being
answered "already on that input". It appends every call it receives, with verb,
arguments and a timestamp, and the run collects that log and the adapter's
final state for each guest. No switch in the log means no preset was activated,
which is a seeding fault and belongs to the lab, not to Perch.

The cursor probe asks whether the driving guest's own cursor still follows
input posted on it. When focus moves to the other Mac, Perch captures local
input instead of letting it through, so the cursor stops tracking. A cursor
that stops following means focus went remote and capture began; one that keeps
following means focus never transferred. That is the difference between motion
never being computed and motion being computed but never delivered, and it
needs nothing from the product. The reporter prints both alongside the
crossing table.

## What it cannot cover

This is a smaller gap than it sounds. The headless suite already drives
`KVMInputSession` end to end between two nodes over real TLS
(`Tools/check-desk-network.swift`), covering input routing in both directions,
pointer handoff, release-before-focus and lost visibility recovery, with no
native capture or posting. What two VMs would add is only the real event tap
capture and injection across two operating system instances.


- Monitor input switching over DDC: guests have no real displays.
- Clamshell, lid and battery behavior.
- Real keyboards and their firmware modes.
- Pairing through the interface: the lab seeds an already-paired desk.
- Conflicting simultaneous edits: needs interface automation.

The runner prints this list at the end of every run so a green matrix is never
mistaken for full desk coverage.
