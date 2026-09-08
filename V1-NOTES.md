# Historical performance and implementation notes

These dated checkpoints preserve the investigation, including superseded failures and earlier version plans. They are not a current todo list. Current releases: [1.0](RELEASE-1.0.md), [1.1](RELEASE-1.1.md). The full review and distribution work belong to [1.2](V1.2-REVIEW.md).

## September 5: Perch 1.0 release

The local 1.0 release is recorded in RELEASE-1.0.md. Final safe regression and app-owned UI/workflow suites pass. Input readiness now requires an active handler when controls are enabled; stale/missing/denied access remains explicit. Shortcut preparation cancel, success, ten-second timeout, cleanup and parent restoration are covered through isolated helper requests. Live menu updates pass in AppKit event-tracking mode. Settings/input/collector/Advanced view renderings were inspected in light and dark themes; native desktop click-through automation remained unavailable.

The installed update passed ten consecutive fresh/healthy checks. Saved configuration is byte-for-byte preserved, the input helper remains trusted and active, the helper binary matches the app, and the existing root eslogger PID is unchanged. No real panic/privacy reset, global key injection, root-service modification or new grant was performed. The package now declares macOS 26.0, matching its actual binary deployment target; it is an Apple Silicon local release. Stable signing requirements are unchanged.

Performance is frozen for 1.0 with the measured costs documented. The broader 1.1 review remains separate.

## September 5: guardian housekeeping and immediate initial CPU result

The guardian now uses configuration/catalog/request change notifications to mark work pending. One-second file-revision checks remain as the recovery path; a missed notification, in-place edit, deletion or recreation still triggers processing. Unchanged files skip configuration decoding/merging and request-directory enumeration. Failed configuration reads and request scans remain pending for retry.

Tracking membership and metadata changes advance an explicit revision. One-second checkpoint maintenance sorts only after that revision changes; actual durable state write timing, panic’s immediate save, live event handling and fresh panic sweeps are preserved. Diagnostic formatting is deferred through an immutable snapshot: no cross-thread reads of mutable guardian/stream state. Authenticated XPC still reports the helper loop’s original timestamp.

The menu takes an immediate baseline and a second CPU sample about one second later. The sampler notifies the visible CPU row as soon as its result arrives; the measured first callback was 1.063 seconds. The ten-second recurring cadence and closed-menu cancellation remain. Reopening starts a new CPU interval rather than averaging across the closed interval.

Safe regression, settings/navigation/theme and live CPU checks passed. New coverage checks unchanged reads/scans/sorts, changed exec metadata and exits reaching checkpoints, immediate request notifications, in-place file edits, deletion/recreation recovery, and deferred/cached status construction. The installed helper consumed an actual read-only preview request in 19 ms. No real panic, privacy reset, root-job change or new permission grant was performed.

A synthetic test reused private CGEvents without posting them or installing a tap: median batch means were 0.022 microseconds per scroll transformation and 0.018 microseconds per modifier transformation (200,000 events each). These warm, transform-only timings exclude OS delivery, scheduling and full callback latency. They do not establish zero input latency.

The installed build passed 360/360 one-second freshness/coverage observations across six minutes: 120 seconds without a synthetic burst, 120 seconds at 50 disposable execs/sec (6,000 total), and 120 seconds recovery. Input trust and tap activity stayed true. All three final queue readings were empty. Reader-to-consumer delivery had a 30 ms observed maximum; this is not end-to-end kernel delivery latency.

| 120-second phase | Menu | Input | Monitor | eslogger | Four-process total | Events between endpoint samples |
|---|---:|---:|---:|---:|---:|---:|
| No synthetic burst | 0.067% | 0.050% | 0.750% | 2.441% | 3.308% | 17,500 |
| 50 disposable execs/sec | 0.067% | 0.050% | 1.041% | 3.699% | 4.857% | 21,280 |
| Recovery | 0.075% | 0.067% | 0.350% | 0.667% | 1.159% | 3,834 |

These are percentages of one core. The four-process totals exclude the observer and completed utilities; including completed utilities from readable user-process counters gives about 1.27% in recovery. macOS denied native eslogger counters, so its CPU uses ps and its memory uses RSS. Ambient activity was uncontrolled, including during the first phase; the event rates differ substantially. These data do not establish a controlled before/after speedup or near-zero total overhead.

Across all six minutes, guardian configuration processing ran zero additional times. Request-directory scans ran three times around the read-only preview test and zero times for the following four minutes. Checkpoint sorting ran 51/45/41 times in the three phases, driven by changed tracking state; checkpoint writes were 50/42/41. The one-second recovery timer remains: native interrupt-wakeup counters were approximately one per second for each helper, with package-idle wakeups near zero in this run. These counters are not complete energy measurements.

Monitor physical footprint started at 9.719 MiB, peaked at a sampled 9.907 MiB, and ended at 9.797 MiB. Input footprint ended at 7.688 MiB; menu footprint at 18.501 MiB. eslogger RSS stayed at 63.438 MiB. No sustained memory growth was observed in this bounded run; it is not a leak-free guarantee. Input and menu recorded zero disk bytes written during the measurement. The guardian wrote about 2.9 MiB of durable changed-state checkpoints, whose write semantics are intentionally preserved.

A three-second native sample of the installed monitor found the main thread waiting in 2,612 of 2,615 samples, two samples in durable checkpoint writing and one in event parsing; the pipe reader waited in select throughout. This short profile found no busy loop, but is not precise CPU attribution. A separate AppKit run-loop probe confirmed that the initial CPU callback can run in menu-tracking mode; actual desktop menu rendering remains unverified.

The desktop automation tool still times out even for SystemUIServer; visual inspection remains unconfirmed.

## September 5: in-memory helper status and optional CPU attribution

Current build: the C parser and select-based event transport remain in place, with stable certificate signing. Two read-only, authenticated XPC services replace `status.json` and `input-status.json`; helpers remove the old files on startup. The original four-second freshness threshold still uses the helper main-loop timestamp. Encoding happens only on demand, getters never wait, connection identity is checked on both ends, and restart failures cannot refresh stale snapshots. No new timer or polling thread is added for XPC. Durable safety/configuration/request files and the explicit shortcut-test lease are unchanged.

Live verification: both user helpers were individually restarted and the persistent observer reconnected automatically. Accessibility remained trusted/active, event coverage returned healthy, and both old heartbeat files were absent. The root collector stayed at PID 28500 throughout; no root-service change or new privacy grant was made.

A bounded 90-second XPC test passed 90/90 health observations, including 1,500 disposable execs. CPU percentages below are relative to **one core**, include the four long-running processes, and exclude the diagnostic observer and transient utilities. Background workload, including local LLM work, is uncontrolled; these are not a controlled idle comparison or a zero-overhead claim.

| 30-second phase | Menu | Input | Monitor | eslogger | Total | Observed events | Degraded |
|---|---:|---:|---:|---:|---:|---:|---:|
| No added workload | 0.067% | 0.033% | 0.333% | 0.467% | 0.900% | 548 | 0/30 |
| 50 disposable execs/sec | 0.067% | 0.067% | 1.167% | 4.333% | 5.634% | 5,726 | 0/30 |
| Recovery | 0.100% | 0.033% | 0.367% | 0.900% | 1.400% | 1,318 | 0/30 |

CPU attribution is configurable directly in Settings and defaults on. It samples only while the menu is open, every ten seconds after its initial two-sample interval. Percentages in the **menu** use total logical CPU capacity. Perch combines its GUI, input helper, monitor, completed child utilities and its own eslogger job; it is never counted twice as both top and us. Unreadable/stale/missing counters are explicit, and birth identities prevent PID reuse from transferring CPU time.

Native `proc_pid_rusage` reads work for current-user processes but are denied for protected processes including root eslogger. Apple’s `ps` handles that smaller subset; no extra entitlement, root helper or privacy permission is introduced. The native counters use Mach timebase conversion on Apple Silicon. `KERN_PROC_PID` supplies protected-process birth identity where `PROC_PIDTBSDINFO` is denied. The read-only, deprecated `SMJobCopyDictionary` obtains the specific collector PID without spawning launchctl. See [Apple’s XNU counter overview](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md) and [job dictionary documentation](https://developer.apple.com/documentation/servicemanagement/smjobcopydictionary(_:_:)).

A 20-sample production benchmark covered 423 native and 277 protected processes: mean 13.34 ms wall time, 5.10 ms Perch CPU plus 8.08 ms ps CPU, equivalent to about **0.132% of one core** at a ten-second cadence. This is the sampler’s own/child cost, not an attribution of induced collector or system-service work. It is not zero or a universal bound. Kernel_task and processes that exit between samples are not included in top-process ranking.

The final repeat benchmark included the actual root collector and all enumerated live processes: 422 native plus 268 protected; 12.94 ms wall, 4.82 ms Perch CPU and 7.97 ms ps CPU per sample (0.128% of one core at ten seconds). The real asynchronous sampler passed startup, throttle and closed-menu checks. Final safe regression, signing-requirement comparison and Settings/theme tests passed. An additional installed-build 30-second no-added-workload check had 0/30 degraded readings; four-process total was 1.234% of one core (668 events, uncontrolled ambient work). This total is separate from the menu-only CPU sampler cost.

Desktop visual inspection could not attach to this menu-bar app (computer-use timeout). The in-process Settings rendering was incomplete; geometry/navigation and checkbox state tests passed, but this is not a completed desktop visual sign-off.

Safe tests cover default/on/off behavior, total-capacity math, grouped-winner formatting, missing collector counters, PID reuse/new processes, invalid/stale intervals, ps time parsing, and no closed-menu requests. The broad 1.1 review is still deferred. Total collector overhead under arbitrary process activity is still not near-zero; eslogger remains the dominant burst cost.

## September 5: allocation-free parser and measured follow-up

Parser checkpoint architecture: single-pass C event parser; independent input helper; select-based memory FIFO reader; full fork/exec/exit coverage with snapshot reconciliation; stable local certificate signing. The entries below this section are historical checkpoints, not simultaneous descriptions of the current build. Broad 1.1 review remains pending.

- Parsing and borrowed text comparisons use no heap allocation or padded input. The output struct is 192 bytes; nesting is capped at 64 and records at 2 MB. This claim covers the parser, not transport Data buffers, retained ancestry or AppKit. The monitor's sampled physical footprint was about 9.2 MiB (9.5 MiB peak); RSS includes shared mappings and is larger.
- The production parser benchmark processes 100,000 synthetic 2,844-byte records in 0.29–0.31 seconds (about 3 microseconds each). Real-stream sampled parsing was about 10–11 microseconds, reflecting different records, CPU scheduling, and cache state. Synthetic timing is not total app overhead.
- The C object imports only memcpy, memcmp and strlen; it has no allocator imports. AddressSanitizer and UndefinedBehaviorSanitizer passed guard-page, every-truncation, 100,000 deterministic-mutation and 2 MB boundary tests. Swift tests cover Unicode/surrogates, escaped keys, numeric overflow, duplicate fields, exec arguments, framing, identity reuse and surviving descendants.
- Guardian comparisons borrow paths/signing IDs/arguments instead of materializing Strings. Exit records only clean up their own identity. Only snapshot-tracked PIDs require live lookup to bridge unknown actors into ancestry. Snapshot refresh invalidates earlier unmatched-actor results. Full audit-token checks still bracket live birth/ownership inspection; panic retains its fresh sweep and final signal identity check.
- Live identity inspection uses temporary stack storage and avoids the redundant PID-only path lookup and intermediate path String. Input maintenance reuses its verified tap state instead of querying WindowServer twice. Small timer tolerances permit maintenance wakeups to coalesce; input callbacks, event delivery and the immediate hotkey are unchanged.
- Full safe regression and settings/navigation suites passed for this parser pass; the final cache correction has its own targeted regression. Stable certificate requirements match, input Accessibility remained trusted/active, and the root collector stayed unchanged. No real panic, privacy reset, reboot or security grant was performed.

The user reports that a local large LLM runs during some measurements and not others. None of these intervals proves a controlled idle baseline. CPU is percent of **one core**, from cumulative counters for the menu app, input helper, monitor and eslogger; transient child/system-service work is excluded.

| Final 30-second phase | Menu | Input | Monitor | eslogger | Total | Events between first/last sample | Degraded |
|---|---:|---:|---:|---:|---:|---:|---:|
| No added workload | 0.033% | 0.067% | 0.233% | 0.267% | 0.600% | 297 | 0/30 |
| 50 disposable execs/sec | 0.067% | 0.067% | 0.833% | 2.800% | 3.767% | 4,243 | 0/30 |
| Recovery | 0.033% | 0.233% | 0.200% | 0.200% | 0.666% | 391 | 0/30 |

The burst launched 1,500 `/usr/bin/true` processes. All 90 one-second health observations were active; no sequence gap was reported. The reader queue was empty at each phase's final sample; maximum observed reader delivery delay was 2 ms during this test. This is not total kernel-to-consumer latency and does not establish universal losslessness.

An earlier 45-second run of the C parser under much higher ambient activity observed 22,633 events (roughly 500/sec): menu 0.067%, input 0.067%, monitor 2.154%, eslogger 8.261%, total 10.549%, with 0/45 degraded samples. Raw percentages from these different loads cannot establish a before/after speedup. The remaining dominant burst cost is Apple's eslogger; near-zero total overhead under arbitrary process load is not achieved.

Collector filtering/transport options were checked against the installed executable and manual. `--select` is an executable-path prefix filter, not descendant-tree selection; restricting it to known agent paths risks losing arbitrary child executables. JSON is the only exposed format, without field selection. The FIFO already avoids raw-event disk writes; unified logging can truncate records. A native minimal Endpoint Security collector would avoid general JSON serialization but requires Apple's entitlement. The subsequent XPC pass above replaces the two helper heartbeat files, independently of eslogger’s cost. See EVENT-COLLECTOR.md.

## Current verification — event collection working

Direct eslogger launch is installed and Full Disk Access works. The live probe was observed at its exact PID as /usr/bin/true; status reports Process events active with no error. A disposable double-fork fixture verified that the live pipeline retained a detached sleep child after its intermediate parent exited. The child exited automatically; no real panic or privacy reset was run.

A 20-second measurement during development work showed eslogger 0.70%, monitor 1.15%, input 0.30% CPU (2.15% combined). This is a bounded sample, not a worst-case guarantee. Safe regression and same-window navigation checks pass. Required setup rows now show green checks for confirmed readiness, amber for missing prerequisites, and red for critical failures. Optional disabled features are not warnings. Saves have explicit confirmation.

The UI restart now identifies its exact executable even when setup arguments are present. Previous anchored command-line matching could leave an older UI running.

## Unified settings workflow

Settings, Agent safety, Advanced, input setup, collector setup, and panic preview share one persistent window with Back navigation. Agent configuration and shortcut-test preparation/results/cleanup render in that same window. File pickers attach as sheets; macOS administrator/permission UI remains system-owned. The collector page has installation, access confirmation, and health verification stages with one next action. Settings exposes the unresolved collector setup at the top rather than a generic warning.

Internal AppKit navigation tests verify the same window identity, parent restoration, and timer cleanup. The safe regression suite passes. Desktop UI inspection timed out, so no end-to-end visual verification is claimed. The user installed the root collector through Perch; current collection remains unavailable with zero received events and recent Apple logs reporting denied Full Disk Access. Live collector performance verification remains pending that grant.

## Process-event backend update — awaiting in-app setup

The signed app now contains the eslogger stream consumer, bounded JSON parser, audit-token ancestry tracking, and an installer exposed only through Perch's setup UI. Safe tests pass and the installed input helper retained Accessibility. The privileged collector has NOT been installed by the assistant: automatic approval review rejected that deployment, and the user specified authorization through Perch rather than Codex.

Perch's collector setup is open for administrator installation and Full Disk Access for `/usr/bin/eslogger`. Until then, collection is visibly degraded and a five-second snapshot fallback runs. A ten-second sample measured 0.90% monitor CPU and 0.30% input CPU in this fallback state. These numbers exclude eslogger, which is not running; live combined performance and real event-schema verification remain pending. See EVENT-COLLECTOR.md for implementation and limits.

# Perch 1.0

Perch prepares a Mac for AI work: sleep and sound controls, input preferences, live resource readings and local agent panic protection.

## Final performance and signing pass

Input handling now runs in its own KeepAlive launchd job (`local.scott.perch.input`), separate from process monitoring (`local.scott.perch.guardian`). Only required event types are intercepted. Scroll-only settings do not intercept keyboard events. Input callbacks perform field transformations without process scans or logging. Disabled controls leave no active tap.

The monitor caches application metadata by PID and birth identity, precomputes application matches, and avoids filesystem URL construction in process-name comparisons. It continues scanning every 250 ms to retain observed descendants. A five-second local sample measured 6.79% of one CPU for monitoring and 0.20% for the active input helper. The original combined helper showed roughly 53% in ps. These are observations under different sampling methods, not a benchmark or zero-latency guarantee. macOS event-tap latency telemetry produced implausible values and is not presented as verified latency.

A persistent self-signed `Perch Local Code Signing` identity is installed in the login Keychain. The build fails rather than falling back to ad-hoc signing if that identity is unavailable. The private key is not stored in this repository. Certificate-based designated requirements matched across successive builds; Accessibility remained granted and input remained active after signed updates. This is local signing, not Apple notarization or Developer ID distribution.

Reviewed Apple event-tap documentation and Scroll Reverser's MouseTap implementation. Both use Quartz event taps. Scroll Reverser additionally uses gesture tracking for device discrimination; Perch's phase-based distinction is simpler and may not distinguish every third-party input device.

## Verification

Safe suite passed: synthetic scrolling/key transforms, PID reuse and ancestry checks, disposable process freeze/kill isolation, mocked privacy reset commands, shortcut registration conflicts, sleep assertions and memory-unit conversion. Earlier helper crash recovery and settings preservation were verified. No production panic, privacy reset or macOS reboot was performed. Full end-to-end input latency and all UI paths are not covered by automated tests.

## Limits

Panic targets the current user's selected local agents and observed descendants; it cannot stop root/remote work or guarantee blocking before a relaunched process executes. Broad privacy reset is best effort and does not remove every protected or managed permission. GPU allocation is not exclusive physical usage. System memory uses GiB. Numerical temperature and CPU/GPU overlap are unavailable. Optional thermal alerts and swap-rate details are deferred.

## September 4 menu and performance pass

- Toggle rows dispatch their existing actions without dismissing mouse menu tracking. Command rows retain normal dismissal. Toggle rows expose checkbox accessibility semantics.
- System readings use teal; elevated pressure/thermal readings use amber and critical readings red. Lid sleep allowed is explicitly green; lid wake is amber with Keep ventilated. The extra Perch lid confirmation is removed; macOS authorization remains.
- Invisible System readings are no longer sampled. Open-menu updates remain every two seconds; protection checks remain every two seconds, and closed-menu general state refreshes every ten seconds.
- Configuration decoding is cached by inode, size, modification and change timestamps. Atomic replacements, corruption, deletion and recovery were tested. Catalog validation is cached until the installed file changes.
- Input processing reuses its trust query and uses direct modifier mapping. Input events retain immediate callback handling; no event batching or input delay was added.
- Process JSON uses bounded temporary field offsets to avoid repeated object scans, optimized newline search, and a plain UTF-8 string path with full escape decoding fallback. The 10,000-event fixture improved from 0.089s to 0.039s. The full safe suite passed, including fragmented streams, ancestry, PID reuse, exclusions and mocked privacy resets.
- Signed app and user helpers were restarted using the existing local certificate. Accessibility remained granted. No root collector mutation or real panic/privacy reset was performed.
- Performance is NOT signed off as near-zero. Menu CPU measured roughly 0.3% versus 1.8% previously; input roughly 0.2%. Combined collector/monitor cost varied substantially with live process activity, including delayed probes and temporary degraded coverage during a burst. Event coverage subsequently recovered, but this does not establish a bounded cost or lossless collection under all loads. Do not present synthetic parser throughput as end-to-end CPU or latency evidence.

## Follow-up: theme, wakeups and sustained-load validation

- Main attributed menu text now explicitly uses dynamic labelColor, and custom toggle views redraw when appearance changes. Hint colors remain semantic.
- Thermal fair wording is now Warm · OK · Keep ventilated.
- Monitor idle maintenance runs once per second, with vnode signals for configuration replacements and queued requests. Lockdown, shortcut testing and termination verification retain 250 ms checks; global hotkeys remain event driven.
- Input maintenance runs once per second, with immediate configuration notifications. Event-tap callbacks are unchanged. Status heartbeats remain within their existing freshness bounds.
- Tracking checkpoints are written only when their content changes. Critical lockdown/resume writes remain immediate. Full event batches enqueue bounded follow-up reads to avoid relying on the fallback timer for continued progress.
- Safe full suite and file-notification tests passed (atomic replacement, delete/recreate, request-directory signals). Signing identity and input grant were preserved.
- Live 90-second healthy-start test: zero degraded samples out of 90, including 1,500 harmless execs at 50/sec for 30 seconds. Combined CPU: 0.968% before added workload, 5.267% during workload, 1.934% recovery. These are CPU percentages relative to one logical core, from cumulative process counters; all four processes are included. Background machine activity is uncontrolled.
- A preceding run begun before collector readiness had 90 degraded samples and recovered later. Startup/backlog health is still an unresolved limitation. The healthy-start run establishes steady-state behavior for this workload, not universal losslessness or near-zero overhead.

## Follow-up: restart failure investigation and pending collector update

- Repeated user-monitor restart checks reproduced probe timeouts, including under a 50-exec/sec workload. Earlier successful steady-state tests do not resolve startup readiness.
- Added a bounded 256 KiB dedicated pipe reader; the main thread retains parsing, ancestry changes and synchronous queued-byte consumption before Panic snapshots. A 1 MiB transport test with delayed consumption verifies byte ordering and preservation through EOF. Safe behavior and settings suites pass.
- The protection helper now declares user-initiated activity that permits idle system sleep, and pipe descriptors use close-on-exec. This does not change the user's keep-awake setting.
- Installed collector plist lacks ProcessType. The host's launchd.plist(5) documentation states that omission throttles CPU and I/O bandwidth. The bundled installer now specifies Interactive because timely delivery supports emergency controls. This is a plausible contributor to the delays; it has NOT yet been applied or verified on the root collector.
- Collector setup identifies the outdated scheduling configuration and offers Update collector. The privileged installer must run only from Perch after the user's in-app approval, per their explicit boundary. Codex has not changed the root service.
- After an approved collector update, the helper starts a new observation session with a new ID and cleared readiness; the UI waits for that acknowledgement and a fresh proof. Earlier gaps remain unrecoverable and are recorded. This is an explicit session restart, not silently clearing a sequence-loss warning.
- Remaining: user approves Update collector inside Perch, then repeat restart/burst and total-CPU measurements. Do not sign off reliability or near-zero CPU before that verification.

## Post-approval verification under local LLM workload

- User applied the in-app collector update. The installed root plist now has ProcessType=Interactive and initially reported active coverage.
- User reports heavy local LLM work during verification. These checks are not idle benchmarks.
- Three monitor restarts yielded: no readiness within 35 seconds; readiness after 25.11 seconds under 50 execs/sec; readiness after 2.01 seconds without added workload. The scheduling change alone therefore did not resolve reliability.
- Added a passive read-only FIFO anchor to the separate input helper. It consumes no events and keeps the writer connected during monitor restarts. A local FIFO regression test confirms data preservation across consumer close/reopen. Full safe suite passed; signed app/helpers updated, root service unchanged by Codex.
- Live delivery remained delayed after installation, with timeout warnings. Do not mark monitoring as ready for release or claim near-zero overhead under this workload. Snapshot fallback remains enabled. Further synthetic stress was stopped to avoid adding load to the user's active work.


2026-09-05: Reproduced and fixed Darwin named-FIFO large blocking write / kqueue readiness stall using a reader that sleeps in select without a timeout and wakes explicitly for cancellation. Live collector caught up after signed user-helper update. Full details and regression evidence: PIPELINE-INVESTIGATION.md. Audited status colors across all UI surfaces; dynamic light/dark palette with contrast checks and rendered previews passed. No root service or privacy permission changes.

## September 5: measured status and menu overhead

- The unchecked lid hint is now exactly **Currently sleeps on lid close**, with no decorative check mark. The checked state retains **⚠ Keep ventilated**; the actual checkbox indicates whether the option is enabled.
- Repeated audio-state reads now query CoreAudio's current default output device and mute property. Outputs without that property retain the AppleScript fallback. Audio changes still use the existing verified action. On this Mac the native read succeeds. The previous profile showed AppleScript compilation invoking Apple's script security checks on refresh; the updated profile contains no such path.
- Only the two temporary helper status files use `VolatileStatusFile`: private, complete files published by atomic rename, without an fsync per heartbeat. Persistent configuration, tracking checkpoints and panic state retain the existing durable writer. Heartbeat cadence and the four-second stale-status threshold are unchanged. This is local IPC, not network publication. Replacing status files with local messaging is a possible 1.1 design review item.
- JSON cache keys use metatype identity instead of repeated type-name reflection. Unchanged menu labels, status icons and status-item geometry avoid repeated layout; checkbox/permission state still redraws. Each refresh reads login-service status once.
- The concurrent status writer/reader test passes 200 replacements and checks complete documents, private permissions and temporary-file cleanup. The JSON cache regression test, full safe self-tests, appearance checks and Settings tests passed. No real panic, permission reset or reboot was performed. Existing certificate signing and input Accessibility access are preserved.

CPU figures below are cumulative process-time deltas over 45 seconds, in percent of **one core**, including all four long-running processes. No synthetic workload was added; other machine activity is uncontrolled. The four-process sum does not include short-lived pmset/probe children or work charged to system services.

| Measurement | Menu | Input | Monitor | eslogger | Total | Events observed | Degraded samples |
|---|---:|---:|---:|---:|---:|---:|---:|
| Before this pass | 0.200% | 0.089% | 0.422% | 0.666% | 1.377% | 1,047 | 0/45 |
| Immediately after update | 0.200% | 0.200% | 0.555% | 0.977% | 1.932% | 2,213 | 1/45 |
| Subsequent steady-state check | 0.044% | 0.089% | 0.689% | 1.244% | 2.066% | 3,439 | 0/45 |

The first post-update run did not retain individual degraded-state details, so its single degraded sample must not be presented as a proven startup-only condition. The subsequent run records each degraded state's details and had none. It finished with an empty reader queue and no reported sequence gap; maximum reader-to-handler queue delay since helper start was 31 ms (not total event-source latency).

These different event rates prevent a controlled before/after speedup claim. The selected expensive code paths are removed, but near-zero total overhead is **not signed off**. The remaining measured cost is dominated by process monitoring and Apple's eslogger. Broader design/usability/security/bloat review remains deferred to 1.1 as requested; this performance limitation remains explicit for the 1.0 decision.
