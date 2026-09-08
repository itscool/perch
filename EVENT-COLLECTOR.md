# Process-event collection

Perch can consume Apple's built-in `/usr/bin/eslogger fork exec exit` through a private named pipe. Input handling stays in its own user process. Perch owns process attribution and panic termination; eslogger only observes.

## Setup in Perch

Settings → Agent safety → Process event collection → Install or repair collector.
The macOS administrator prompt is initiated by Perch. This installs `local.scott.perch.events` in `/Library/LaunchDaemons`, a root job whose fixed command execs Apple's eslogger. It starts at boot, waits for Perch's reader, and restarts after failure with a 30-second throttle. Its process group is separate from the agents it observes. The signed `PerchEventLauncher` briefly runs as root to record identity, then is replaced by eslogger in the same process; it is not a persistent supervisor.

Grant **/usr/bin/eslogger** Full Disk Access in System Settings. With the native launcher, macOS may also attribute the request to `/Library/Application Support/Perch Events/PerchEventLauncher`; if the existing grant does not restore event delivery, review access for that launcher. This launch path’s permission behavior has not yet been verified on the affected Mac. Do not grant Codex or a development terminal this permission for Perch. The grant applies to the Apple executable and macOS cannot limit it to Perch's invocation. Allow up to 45 seconds for the next health probe. The current install supports one local user, selected at installation.

The root-owned directory is `/Library/Application Support/Perch Events`; `events.pipe` is mode 0600 for the installing user. The signed launcher and root-owned mode-0644 `collector.json` also live here. That bounded record contains only protocol version, PID, process birth and boot UUID; it is replaced once per collector launch. Raw JSON and arguments are not logged. eslogger diagnostics are discarded. The user-visible status identifies failed collection, but cannot always distinguish revoked access from another collector failure.

To uninstall the collector (administrator action): unload `system/local.scott.perch.events`, remove `/Library/LaunchDaemons/local.scott.perch.events.plist` and the `Perch Events` directory, then remove eslogger's Full Disk Access grant. These actions do not uninstall Perch.

## Coverage and supervision

A single-pass C parser validates JSON, UTF-8, escapes, numeric identities and nesting while borrowing the input bytes. Its result is 192 bytes; parsing and text comparisons call no heap allocator and need no padded input. Nesting is limited to 64 levels and records to 2 MB. Transport buffers and retained ancestry are separate: they still use bounded/dynamic storage, so the entire monitor is not allocation-free. The ancestry table is capped at 100,000 entries.

Ancestry uses full audit tokens (including PID version), transfers through fork and exec, and is removed on exit. Attribution does not depend on a short-lived parent still being present when its child's event is processed. Before a live process joins the panic table, `proc_pidpath_audittoken` validates its execution identity around the existing birth-time inspection. Panic retains its final live identity checks. The watcher and its input/UI helpers and descendants remain excluded.

A dedicated reader sleeps in select with no timeout and wakes the consumer when bytes arrive. It has a 256 KiB queue with backpressure; it never discards bytes to reduce work. This avoids Darwin named-FIFO stalls with large blocking writes (see PIPELINE-INVESTIGATION.md). Event callbacks replace periodic process scans for normal ancestry updates. EOF marks collection unavailable; launchd supervises the producer. Once every 30 seconds a harmless `/usr/bin/true` child verifies that events actually flow. Silence alone is not considered proof of failure. Healthy reconciliation runs every 30 seconds; degraded fallback every 5 seconds. Panic still drains available events and performs fresh sweeps; active lockdown continues frequent enforcement.

Sequence discontinuity, malformed output, overflow or an established stream disconnect marks an ancestry gap. A later health probe does not erase that gap. Restarting the watcher begins a new observation session; snapshots cannot recover lost historical ancestry. Event collection is not guaranteed lossless, cannot reconstruct events before it starts, and is not pre-execution blocking or a tamper-resistant security boundary. Root and remote workloads remain outside panic scope.

## Validation

Safe tests cover fork/exec/exit identity transfer, detached descendants, reused PID versions, helper exclusions, malformed/nested JSON, escaped Unicode strings, 64-bit sequence numbers, single-byte framing, sequence gaps, disconnect state, bounded buffering, and live audit-token identity validation without signaling real apps. The complete existing safe suite passes.

The production borrowed parser processes 100,000 synthetic 2,844-byte records in roughly 0.29–0.31 seconds on this Mac. AddressSanitizer/UndefinedBehaviorSanitizer checks include every truncation, 100,000 deterministic mutations, a guard page immediately after input, and a record exactly at the 2 MB limit. These tests and synthetic throughput do not establish total CPU or losslessness under every workload. Live measurements and their load caveats are recorded in V1-NOTES.md.

Apple ships eslogger as a diagnostic tool with no schema/API compatibility guarantee. Sources reviewed: Apple's eslogger man page; WWDC22 "What's new in Endpoint Security"; the open-source tracce project's eslogger architecture. Implementation is independent; no third-party code was copied.

## Why filtering and transport do not remove all collector cost

This Mac's `/usr/bin/eslogger --help` exposes `--select` for executable-path prefixes. It does not advertise descendant-tree, UID, per-field or binary-output selection. Restricting output to agent app paths would not cover descendants executing arbitrary shells, runtimes or newly built programs; Perch therefore retains all fork/exec/exit events. No file/network event categories are subscribed.

The named FIFO carries bytes in kernel memory, without writing raw event data to disk. `--oslog` would route through unified logging and the installed manual documents truncation above 32 KiB. It is unsuitable for complete ancestry records. The two user helpers now publish status in memory through read-only local XPC services. Both peers must match Perch’s designated signing requirement; the server also checks the same user ID. Replies preserve the helper main-loop timestamp, so a hung loop cannot look healthy just because XPC answered. Getters are asynchronous and reconnect after helper restarts. This removes the two periodic status-file writes; it does not remove JSON generation inside eslogger. Persistent safety checkpoints and requests retain their existing file storage.

Apple's native Endpoint Security API offers direct structured events and filtering. A dedicated minimal collector would avoid eslogger's general JSON encoding, but requires Apple's restricted entitlement. No entitlement, SIP or privilege workaround is used. These conclusions use the installed help/man page and [Apple's WWDC22 presentation](https://developer.apple.com/videos/play/wwdc2022/110345/). The installed binary imports Foundation JSONEncoder; that is evidence of its implementation, not a CPU attribution profile.

## Collector CPU identity migration (build 61)

An existing direct-eslogger installation remains supported for event delivery. The optional **Update CPU accounting…** action installs the fixed native launch path with the usual administrator prompt, restarts the collector and requests a new observation session. It does not reset Full Disk Access. Until identity is verified, an expected collector makes Perch's combined CPU total unavailable; unrelated eslogger processes are never matched by name. Metadata failures do not stop the collector, and stale records are rejected using boot and live process birth checks.

The launcher has no runtime command/path overrides, shell evaluation, Endpoint Security code or persistent loop. Tests use compile-time fixture paths and a harmless child executable; production defaults are fixed. Run `python3 Tools/check-collector-identity.py` for that isolated native test and `python3 Tools/check-functional-review.py` for the app suites. Full installation/FDA/reboot acceptance remains separate.
