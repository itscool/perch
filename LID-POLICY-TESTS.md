# Fast lid-policy verification

September 13, 2026.

Run `python3 Tools/check-lid-policy.py`. The initial invocation compiles; subsequent
unchanged invocations reuse a source/compiler-fingerprinted binary. `--output`
selects another cache directory. Test execution measured 1.131 seconds on the
development Mac, excluding compilation. No clock sleeps or desktop control.

## Production code exercised

Policy, watchdog leases and enforcement have been separated from their macOS
adapters without changing their implementations. The headless executable compiles
these production files and the restart handoff directly. Its only harness type
is the app's plain error container. Fake hardware records commands and injects
failures; IOKit, AppKit, privileged helpers and live power access are not linked.
The same tests also run in the existing full functional suite.

## Coverage

- Every lid (open/closed/unknown), power (external/battery/unknown), authorization
  and time-step (0/1/60/3600 seconds) sequence through three transitions:
  378,504 transitions including prefixes. Invariants prohibit simultaneous sleep
  and prevention, revival of stopped sessions, protection with lost authority or
  unknown sensors, sleep requests while open/powered, and battery deadline renewal.
- Startup eligibility, countdown rounding and just-before/exactly-at/after expiry;
  opening/replugging at expiry; five-second power stabilization boundaries;
  sixty alternating power observations; invalid/backward clocks; sleep/wake.
- Watchdog lease expiry, transport loss, malformed leases, late renewals of stopped
  tokens and sixty healthy renewals that must not extend the battery deadline.
- Restart ticket expiry, inactivity, replay and retries that retain the deadline.
- Injected enable, verification, release and sleep failures. Cleanup/retry ordering,
  release before sleep, and the five-second retry throttle.

This is bounded exhaustive sequence coverage plus explicit boundary/failure
cases, not a proof over infinitely many possible histories. Existing broader
suites still cover persistence, independent recovery, session RPC ordering,
sleep-notice classification and native presentation. Physical QA is reserved for
adapter/event delivery and recovery integration, not rechecking each policy path.

The proposed configurable grace/meeting shortcut is not implemented and is not
covered by these current-policy results. Its virtual-clock acceptance matrix is
recorded with the feature in TODO.md. The complete isolated app compiled successfully after the source separation.
All relocated production declarations were checked against the previous commit
and are unchanged. No app was installed or published.
