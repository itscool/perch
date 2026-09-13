# Unattended QA and corrections for candidate 2.0.120

September 13, 2026. No live UI control, input capture/injection, permission reset,
monitor input writes, sleep, helper maintenance, notarization or publication.

## Isolated update continuity

Tools/check-sparkle.py --headless plus Tools/run-sparkle-headless.py builds and
runs disposable signed build-1/build-2 apps with ephemeral fixture keys and a
loopback feed. The production updater remains in the fixture; a scripted public
Sparkle user driver substitutes for windows, and the lid client is injected.
The fixture now derives its lid protocol from production rather than hardcoding 2.

Five final scenarios passed: dismiss; cancel a slow download; interrupted download;
tampered ZIP rejection; failed simulated handoff followed by successful retry,
replacement and relaunch. The first four preserved build 1 and never prepared a
lid handoff. Retry prepared the same exact signed identity twice, claimed that
identity from build 2 and consumed its network-restart record. The corrected
record path was also checked after completion. An earlier fixture retry timed out
because DispatchQueue delivery was starved inside termination; that run is excluded.
A run-loop Timer in the test scaffold resolved this without a production change.

No public feed or real protected lid session was used. Real grants/helper transfer,
clean account lifecycle and public update acceptance remain separate.

## Performance

A 60-second passive sample of the user's stable running app and user helpers
measured 1.863% app CPU, 0.296% and 0.047% user-helper CPU (2.206% measured total).
App footprint was 34.689 to 34.829 MiB, sampled peak 34.860 MiB. App interrupt
wakeups averaged 13.017/second and recorded disk writes were zero. Root lid-helper
counters were inaccessible and excluded, not counted as zero. This is the user's
current workload, not controlled idle/menu/input measurements or lifetime proof.
An initial 120-second sample straddled a user restart and is excluded.

The 16-peer loopback endurance fixture delivered 129,152/129,152 events over
181.56 seconds. Batch p95 was 31.46 ms (not physical pointer latency); maximum
queued bytes per link were 19,531 and queues drained. Sampled RSS was 62.16 MiB
initially, peaked at 71.86 and finished at 64.19. This run preceded connection-log
edits; updated functional TLS tests passed afterwards. No native input was used.

## Packaging and isolated first-build checks

check-app-bundle, check-build-dependencies, check-release-all,
check-release-pipeline, check-release-assets, check-release-launcher and
check-settings-models passed. Coverage includes real relocated Mach-O/Sparkle,
missing or broken links/rpaths, tamper rejection, atomic replacement rollback,
fresh/corrupt/offline cache and certificate failure, missing signing identity,
resumable release stages and publication opt-in. Dependency network responses and
external release commands are stubbed; these are not a fresh macOS account test.

## Sidebar correction

The screenshot's right-hand badges were clipped by the scroll viewport even
though their own cell bounds passed. A 204-point viewport contained an icon
extending to x=211. AppKit now sizes the last column after source-list insets.
64 offscreen state/theme/resize/scrollbar combinations pass, with enough rows to
force scrolling. Badges remain on the right and labels truncate first. The skill
and evaluation case now require containment through clipping ancestors.

## Connection activity

Desk > select a computer > Connection activity shows authenticated connections,
closures, known local causes, bounded network error codes and elapsed duration.
Expected duplicate/shutdown/pairing closures are distinct from unexpected active
link losses. The retained window is 24 hours, at most 1,024 entries, private local
JSON; disk work is serialized off the network/UI executor. It records no keys,
input events or shared payloads. The previously reported real-Mac reset issue is
removed from current known defects at Scott's request; no root cause is invented.
The updated TLS suite verifies retention/classification, authenticated ready
records, injected heartbeat-loss cause and duration, private persisted records,
reopening, and ordinary reconnect/recovery. Real recurrence can now be diagnosed.

## LG detection

Read-only installed-adapter inspection of the newer LG returned a bare UP850K
model token and VCP 60 values 11,12,0F,00. The parser missed the bare model and
rejected the whole list because 00 is reserved. Both are corrected. Detected model
is shown in setup and the display picker and retained through local/peer refresh.
Standard capability codes retain the standard protocol even when LG inspection
was selected; they must not be sent as LG F4 codes.

This monitor returned firmware EF=c024, A1=0074; the retained firmware table maps
that family to 27G850A. Explicit conflicting model evidence now prevents applying
that automatic family profile. No K-W USB-C code is invented. Exact reported
27UP850-W names are now fed into the existing verified profile matcher. The older
connected LG returned no capabilities, current input or firmware identity, so its
actual automatic identification remains unresolved on that path.

## Still open

Software desktop disconnection/reconnection remains implementation and hardware
work; no temporary-mirroring prototype is shipped. LG K-W input control needs
verified USB-C/protocol evidence, and the older W monitor needs a readable identity
path. Matching helper maintenance, real two-Mac control, secure input boundaries,
VoiceOver, active-lid update continuity and clean-account lifecycle remain distinct
acceptance tasks. Do not collapse these limits into a claim of zero known defects.


## Delivery

Developer ID build 2.0.120 completed without compiler warnings. Bundle structure,
Sparkle load paths, nested signatures, architecture and 22 release resources passed.
The full bundle was atomically exchanged into /Applications/Perch.app with its
publisher identity and updater configuration intact. Previous bundle:
/Applications/.perch-previous-uupq81g3/Perch.app. Running PID 66808 was unchanged
(2.0.119). No notarization, publication, helper install or app restart occurred.

The network test exposed a fixture ordering race: it replaced the input session
before waiting for that session's queued first key. Waiting for delivery before
starting the next scenario fixed the test sequencing. The final full TLS suite,
including durable incident/reopen checks, passed; production input logic was unchanged.
