# Perch 1.0

Local release for Apple Silicon, macOS 26+, validated on an M5 Max running macOS 26.2. This package uses the existing Perch Local Code Signing identity. Public notarized distribution and older-system qualification are outside this local release.

## Included

- Persistent sleep controls, display-off action, sound and input preferences, and start at login.
- Live CPU/GPU/memory/thermal readings, with optional CPU attribution. Initial CPU measurement completes after about one second; recurring attribution runs only while the menu is open.
- Agent panic through a confirmed menu action or enabled immediate shortcut, observed descendant tracking, relaunch blocking, and best-effort privacy resets.
- Separate input and tracking helpers, allocation-free C event parsing, bounded in-memory event transport, and authenticated XPC status.
- One Settings window with Back navigation, permission status and draggable helper identities, and theme-aware status colors.

## Release verification

The signed build passes the safe regression and AppKit workflow suites. `bash Tools/check-release.sh` repeats them.

- Process identity/ancestry, detached children, parser bounds and framing, helper IPC, stale status, input transformations, hotkey registration/conflicts, mocked reset sequencing, and disposable-process termination isolation pass.
- The production menu updates during AppKit event tracking, uses the current lid-sleep wording, keeps Settings under Start at login, and stops CPU sampling when closed.
- The actual shortcut dialog logic passes preparation cancellation, success, the ten-second timeout, cleanup confirmation and return to Safety settings. Its test transport is isolated from the real helper.
- Input setup distinguishes ready, denied, missing, stale, and granted-but-inactive states. Granted permission alone no longer produces a green ready state when enabled controls are inactive.
- The app-owned Settings, input setup, collector setup and Advanced views were rendered and inspected in light/dark appearances. Production toggle drawing and attributed menu rows were inspected through a view fixture. Minimum semantic-text contrast tests pass at 5.79:1 in light mode and 7.81:1 in dark mode, including high-contrast appearances.
- Post-installation checks passed ten consecutive healthy observations. Settings were byte-for-byte preserved, Accessibility stayed trusted with input active, app/helper binaries matched, and the existing root collector was unchanged.
- The unchanged event backend passed an earlier six-minute installed-build run: 360/360 freshness checks, including 6,000 disposable processes at 50/sec. Input stayed trusted and active; no sustained memory growth was observed during that bounded run.

The desktop automation service could not attach. These are app-owned view and workflow checks, not a claim of successful desktop click-through automation. Physical keyboard delivery, full input latency, and a real system-wide destructive panic/privacy reset remain outside this validation. The harmless shortcut test remains available for testing from the user's actual apps.

## Performance and operating limits

Performance work is closed for 1.0. No further measured, substantial Perch-side optimization is identified that preserves current behavior. This is not proof of an absolute engineering limit or a zero-overhead claim.

In the final six-minute backend run's recovery phase, Perch's menu/input/monitor together used approximately **0.49% of one core** and eslogger **0.67%**. The four-process total was **1.16%**; including measured completed user-process utilities gives about **1.27%**. Background activity was uncontrolled. With 50 disposable execs/sec, the four-process total was **4.86%**, mostly eslogger. These figures vary with process activity and exclude work charged to other system services.

Monitor physical footprint remained about **9.7–9.9 MiB**. Input ended at **7.7 MiB**, menu at **18.5 MiB**; eslogger RSS was **63.4 MiB**. RSS and physical footprint are different measures. CPU percentages in the menu use total CPU capacity; the diagnostic numbers above use one core.

Panic is a same-user emergency stop, not tamper-resistant containment. It cannot undo prior actions or stop root/remote jobs. Event gaps cannot be reconstructed; snapshot fallback and fresh panic sweeps remain. `tccutil` acceptance does not prove every ongoing permission has stopped. Keep ventilation available with lid wake enabled. Full limits are in README.md.

## Next release

The requested 1.1 review covers design, performance, memory, usability, intuitiveness, clarity, feature set and bloat, plus accessibility, failure recovery and security boundaries. It does not hold this local 1.0 release open.
