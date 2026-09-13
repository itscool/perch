# Automated QA and candidate — September 12, 2026

The other Mac's build/launch correction is **user-confirmed fixed**. Developer ID
**2.0.96** is prepared locally with strict nested signing and Sparkle packaging
checks and no compiler warnings. Installed/public **2.0.94 remains unchanged**.
No notarization, publication, live permission reset, hardware writes, power
changes, Panic or production helper/app replacement occurred.

## Finding fixed before handoff

**P1: sustained Desk edits could interrupt input sharing.** In an optimized
16-peer TLS fixture, leases expired after approximately 61 seconds / 42,562
captured events while cosmetic Desk edits arrived. Redundant verification of
already-admitted history and unchanged presentation publication consumed the
serialized executor used for input coordination.

`KVMSyncGraph` now caches decoded current heads and sorts stored revision IDs
instead of repeatedly hashing payloads and verifying trusted history on reads.
`KVMDeskNode` only publishes changed group/conflict/acknowledgement values.
Incoming revisions and imported archives still pass signature, membership,
ancestry and group validation. Duplicate messages with invalid signatures are
still rejected. One-second fail-closed control expiry remains unchanged.

## Results

| Check | Result and boundary |
| --- | --- |
| Full isolated regression fixture | **23/23 passed** on corrected sources, under AGENT MODE. Includes native settings hosts, update identities, lid timing/recovery and helper IPC; hardware changes injected. |
| KVM integrity/behavior | **101 checks passed**, including concurrent conflict resolution, authenticated catchup, tampered replay rejection, rejected revisions preserving current state and exported values unable to mutate graph state. |
| Optimized two-minute network workload | **89,664 / 89,664 events**, all 16 peers retained authority; queues drained. |
| Optimized five-minute network workload | **211,328 / 211,328 events**, all 16 peers retained authority with edits every ten seconds. Full-batch p95 **33.33 ms**, sampled peak queue **19,536 bytes/link**. |
| Memory during growing history | Entire 16-node fixture RSS **61.81 → 81.31 MiB** over 300 seconds. Signed history intentionally accumulates; this alone does not establish or rule out a leak. Follow-up below. |
| Real interrupted Sparkle download | Loopback server closed a ZIP response after 128 KiB while advertising its full size. Native error appeared; cancelling returned control and preserved old build 1. |
| Real slow-download cancellation | Native Cancel pressed during progress. Build 1 remained on disk; Settings restore callback ran; no update handoff began. |
| Real Sparkle retry in Applications | Disposable app replaced build 1 with 2, relaunched through Sparkle and claimed the exact saved identity. Completion receipt PASS. Lid client was simulated; no live lid session was involved. |
| Documents installer diagnosis | TCC at 20:53:35 recorded a pending `SystemPolicyDocumentsFolder` request for the blocked fixture's Autoupdate process. This explains its `renamex_np` wait; no permission bypass/reset was used. It does not prove the cause of a separate concurrent dependency rename delay. |
| Desk connection validation | Native invalid input-code draft showed Not saved with the previous code preserved. Corrected code 27 saved and remained 27 after collapse/reopen. |
| Desk child returns | Protocol menu Escape, monitor-control sheet Escape, physical-screen correction X and remove-screen confirmation Escape all returned to the parent; sidebar then opened Scrolling. No physical settings or deletion performed. |
| Build | Developer ID 2.0.96 passes production bundle checks; source snapshot and local candidate receipt retained. No compiler warnings. |

All 16 network peers run on one Mac with real TLS and temporary identities/storage.
Display reads/writes and native input sinks are injected. Batch latency is the
whole 32-event fixture batch, not measured cross-Mac input latency. This is bounded
stress evidence, not production network or lifetime memory acceptance.

The native Desk child pass used the previously compiled setup-fix fixture; the
final 23-suite regression and signed candidate contain the synchronization fix.
No claim that every child/failure route or spoken VoiceOver is accepted is made.
An initial run-only command issued before fixture compilation completed failed
with missing executable; after compilation, the full 23-suite run passed.

## Memory follow-up

A disposable copy of the same optimized test stopped cosmetic edits after
60 seconds but continued input traffic for 180 seconds. **125,760 / 125,760**
events arrived and authority stayed active. From 90 to 180 seconds, RSS stayed
between **67.328 and 67.359 MiB** (32 KiB range across all 16 peers). This supports
history accumulation as the earlier workload's growth mechanism and shows a
stable bounded interval once edits settle. It does not certify lifetime memory
usage. The only harness change was adding `elapsed < 60` to the edit condition;
production sources were unchanged. Scratch harness and results remain in task
`work/desk-memory-settle.*`.

Desktop testing is finished; both AGENT MODE sessions are stopped and their
banner processes exited. The isolated Settings process, loopback download server
and disposable Applications test bundles were stopped/removed. The production
app and its helper state were not changed.

## Reproduction and artifacts

- `python3 Tools/check-kvm.py`
- `python3 Tools/check-desk-network.py --endurance-seconds 300`
- Build native fixture first using `Tools/check-functional-review.py --build-only`;
  run `--run-only` only under the documented checked AGENT MODE session.
- `Tools/sparkle-test-server.py --root FIXTURE/feed --port PORT --control MODE_FILE`
  binds only 127.0.0.1. Mode file supports normal, disconnect and slow. Use the
  existing disposable Sparkle fixture; never point at a public feed or live app.
- Candidate: task `work/release-2.0.96/Perch.app`, with `source-snapshot.json`
  and `candidate-receipt.json`. Native update event/completion receipts, build
  logs and endurance JSON remain in task `work/`.
- No public DMG, Sparkle ZIP or appcast is claimed for this version. Those stages
  require the candidate's accepted notarization and explicit release authorization.
  `Release/notes-2.0.96.md` is the correction-specific draft for the next release.

## Where Scott is needed

1. Install the corrected candidate in a coordinated session; verify actual
   production launch/access, recovery and update/restart permission continuity.
2. Test helper maintenance and protected-lid restart, power/lid edges and wake
   explanations with the Mac physically available. Watchdog/reboot failures
   require a coordinated safe test window.
3. Pair the two physical Macs, identify real displays and accept presets first,
   then pointer/keyboard sharing, lock/unlock and network/disconnect recovery.
4. Accept spoken VoiceOver and the remaining production keyboard/OS handoffs;
   a clean account/device is needed for first-grant/install/uninstall lifecycle.
5. Authorize notarization/publication after required acceptance. Destructive
   emergency/privacy acceptance requires a separately authorized disposable setup.

Optional Homebrew distribution, mixed-platform members and VM adapters remain
outside this correction batch. See TODO.md for the complete categorized list.
