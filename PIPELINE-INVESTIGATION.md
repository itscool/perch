# Event pipeline investigation — 2026-09-04

Live monitor PID 42847 sampled for three seconds at 22:19 PDT. Main thread waited in the run loop in 2593/2617 samples; worker thread waited in 2616/2617. This short sample does not prove the cause of the backlog.

Fifteen non-consuming FIONREAD checks (one second apart) found 8192 bytes waiting in the current FIFO every time. Status event timestamps were about 23 minutes behind wall time. lsof confirmed the monitor's FIFO inode matches the current path (12760346). No events were read by the diagnostic process.

Isolated named FIFO test transferred 8 MiB with writer kept open: current reader 0.018 seconds; staged drain-until-capacity reader 0.011 seconds. A separate anchor descriptor test also completed in 0.015 seconds. These synthetic tests do not reproduce the live stall and do not establish the staged reader change fixes it.

Staged diagnostics now report read count, queued bytes, queue high-water mark, maximum delivery delay, and average parsing/handler time sampled once per 64 events. No per-event disk writes. No deployment performed. Root collector and permissions unchanged.

Validation: 1 MiB backpressure/EOF preservation test passed. Event self-test passed, including 10,000 fixture events in 0.036 seconds. Swift compilation succeeded. Certificate signing failed within the sandbox ('no identity found'); staged bundle must be signed with the existing Perch Local Code Signing identity before deployment. Settings self-test exited 134 without diagnostic output in this environment; do not count it as passed.

Next: run the diagnostic build only after signing and deployment authorization; compare queue delay with parsing and handler cost while checking source timestamps. Do not infer that a first received event proves current coverage. Do not clear accumulated gaps or silently discard backlog.

## Reproduced cause and fix — 2026-09-05

The earlier synthetic test issued 4 KiB writes. Changing only the writer to issue blocking 64 KiB writes after readiness registration reproduced the stall: both the installed DispatchSourceRead implementation and the staged drain-until-capacity tweak delivered **0 bytes in 5 seconds**, with no parser or ancestry handler involved. This distinguishes writer syscall size from total stream size.

Apple's published XNU code explains the result:

- [fifo_write](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/miscfs/fifofs/fifo_vnops.c#L373) calls `sosend`, then `lock_vnode_and_post` after it returns. A blocking write larger than the FIFO buffer can wait for space before the notification is posted.
- [vn_kqfilter](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_vnops.c#L1983) attaches FIFO read knotes to the vnode.
- [fifo_select](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/miscfs/fifofs/fifo_vnops.c#L447) instead uses the underlying socket's `soo_select` readiness.
- A [firsthand 2018 report](https://stackoverflow.com/questions/48786079/poor-performance-on-large-writes-on-o-nonblock-fifo-in-mac-os) independently describes macOS large FIFO writes taking minutes, including a kqueue reader. It has no accepted solution; the reproduction and XNU source above support this fix.

Perch now uses a dedicated reader thread sleeping in `select` with **no timeout**, and a control pipe for cancellation. Reads remain nonblocking and serialized; the 256 KiB queue applies backpressure with a condition variable. Panic/preview still drains available bytes synchronously. There is no event dropping, busy loop, or new periodic polling. Closing the event stream stops its worker, and only that worker closes its descriptors.

The same 8 MiB/64 KiB-write test now completes in ~0.112 seconds, including the intentional 0.100-second writer delay. `Tools/fifo-reader-test.swift` verifies 4 KiB, 64 KiB, and 2 MiB single writes, delivery before writer EOF, a deliberately blocked consumer, final bytes before EOF, and cancellation of an idle reader. All pass. The existing anonymous-pipe 1 MiB backpressure/EOF test also passes.

Full safe self-tests and Settings navigation/render tests passed outside the sandbox. The app was signed with the existing Perch Local Code Signing certificate and deployed with its user helpers. The root eslogger service and macOS permissions were unchanged. Live observation then drained about 137 MB, confirmed the current probe, and reported an empty byte queue; sampled parse/handler averages were 13/5 microseconds with a 22 ms maximum queue delivery delay during catch-up.

## Appearance audit

All explicit status color uses in menu hints, menu-bar critical indicator, Settings buttons/details, process-event setup steps, and input permission setup now use `StatusColors`. Normal labels, links, disabled controls, backgrounds, and selected text retain AppKit semantic colors. Custom menu rows and permission drag tiles resolve colors in their effective drawing appearance and redraw on appearance changes.

Rendered the same attributed controls after switching their window from Aqua to Dark Aqua without recreating color objects. Minimum status text contrast against window/control backgrounds is 5.79:1 light and 7.81:1 dark; high-contrast appearance checks also exceed 4.5:1. Disabled and hovered menu rows were visually checked. Local previews: `/private/tmp/perch-colors-light.png` and `/private/tmp/perch-colors-dark.png`.

## Live burst verification

90/90 once-per-second readiness checks passed through 30 seconds with no added workload, 30 seconds launching 50 disposable true processes/second (1,500 total), and 30 seconds recovery. No reported sequence gaps. Accessibility and panic shortcut remained active after the signed update. FIFO diagnostics at completion: queue 0 bytes, maximum delivery delay 22 ms, sampled parse 21 microseconds and handler 8 microseconds.

CPU measurements use cumulative ps TIME deltas and percentages of **one core**, summed over the menu app, input helper, monitor, and Apple eslogger. No added workload: 1.599% total (monitor 0.433, input 0.100, eslogger 0.666, menu 0.400). Burst: 10.132%. Recovery: 3.067% (monitor 0.900, input 0.100, eslogger 1.667, menu 0.400). Background event counts differed between phases; these are not controlled-idle estimates and do not establish near-zero overhead. The specific FIFO delivery failure is fixed; remaining CPU optimization is separate.
