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

## What it cannot cover

Pointer and keyboard sharing cannot be exercised on these guests, and the gate
is worth stating exactly so nobody retries it.

Building a switch request refuses a screen twice over. `KVMMonitorRequest.make`
throws unless every screen in the preset has a `control` connection, and throws
again unless that screen's assigned connection carries an `inputCode`. A preset
with no real monitor routes therefore cannot be built at all, so the commit path
is never reached.

`activePreset` is set in exactly two places. A switch settles with every
requested route accepted, or `deriveActive()` matches a preset whose assignments
equal the monitor inputs read back from the screens. Both need a monitor that
answers DDC.

Input sharing then starts only through `startInputForActivePresetIfNeeded`,
which requires `switching.activePreset` and at least one assignment owned by
another computer.

A virtual display answers no DDC, so none of those conditions can be met, the
pointer never leaves the driving guest, and every crossing is blocked before
Perch consults the screen edges. This is the hardware these guests have, not a
desk fault.

Seeding an arrangement would not lift this. The signed membership carries only
the peers, authority and generation; the screens, cables and presets are rebuilt
from signed revisions in the desk history, so a seeded arrangement means
producing that history, and it would still stop at the DDC gate above.

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
