# Perch implementation review

Historical notes from the initial implementation. Several details below (polling, signing and menu workflow) have since changed; current behavior and validation are in README.md, EVENT-COLLECTOR.md and V1-NOTES.md. The broad design/performance/memory/usability/clarity/bloat review assigned to 1.2 has not yet been performed.

Reviewed the process-selection and termination paths, watcher lifecycle, hotkey state machine, reset ordering, persistent controls and native menu behavior.

## Corrected during review

- Identify Codex by its verified bundle ID; its display name on this Mac is ChatGPT.
- Keep observed detached descendants, but drop records when the PID birth time changes or the target is unselected.
- Exclude Perch/UI/helper descendants and other users; recheck identity immediately before each signal.
- Freeze before disabling relaunch jobs; never leave a process intentionally frozen when SIGKILL fails.
- Record exit verification separately from a successfully sent signal.
- Continue reset attempts after individual failures; broad reset requests are queued rather than lost behind targeted reset workers.
- Preserve originally disabled launch jobs and retain failed restore entries for retry.
- Process queued requests in time order; reject expired requests so old resume requests cannot unexpectedly release a later lockdown.
- Keep harmless-test interception active until explicitly ended; late test keypresses cannot fall through to panic.
- Do not silently restore default targets from a damaged configuration.
- Bound event history; never write full argv or environment variables to reports.
- Keep lid mode on exit, and move awake/input behavior into the independent helper so menu exit does not undo choices.
- Replace ambiguous input dashes with selection checkmarks and contextual failure explanations.

## Tests

Automated checks passed for synthetic ancestry, observed detach/reparent, PID reuse, exclusions, removed targets, Codex identification, live disposable shell + child freeze/termination, unrelated-process preservation, caffeinate isolation, native hotkey registration/conflicts/release, mocked privacy-reset ordering/failure continuation, scroll-axis preservation and modifier transitions.

Live read-only detection found Codex and Claude Code process groups. No production panic, live agent termination, reboot or privacy reset was performed.

## Material limitations

- The watcher is a same-user launchd process, not a privileged tamper-resistant service. Optional administrator-owned files protect the executable from ordinary edits but do not prevent stopping/disabling the service.
- Polling can miss short-lived detached ancestry and allows some execution before a relaunch is stopped. This is not equivalent to a VM, separate account or mandatory process containment.
- No remote-job cancellation or administrator/root-process control is implemented.
- tccutil results are reported as accepted/failed commands, not proof of immediate revocation of every capability. CLI authorization can be attributed to a host app.
- Ad-hoc signing still requires reauthorization after rebuilds when macOS invalidates the previous code identity.
- Physical input/hotkey testing is available through harmless test mode. Full destructive end-to-end panic should be exercised only in a disposable session or VM.

## Completion pass

System menu now reports interval CPU utilization, optional GPU driver utilization/allocation, estimated physical memory, macOS memory pressure, and macOS thermal state. Unsupported metrics remain unavailable; no inferred CPU-exclusive or overlap memory, temperature, or imminent-damage claim. GPU allocation must not be added to total RAM usage.

Safety settings has explicit None / Selected apps / All apps privacy-reset scope. Existing settings retain their selected-app scope. Global scope includes Perch. No actual reset is used in testing.

Lid enable requires a heat/ventilation warning, with Cancel first. Turning it off needs no warning. The warning states persistence after exit. Menu uses a coffee cup for detected awake state, Agent Safety before Perch, Safety settings and Tools labels, and a visible resume action during lockdown.

Installed verification: the safe suite passes. Closing the menu process left the helper alive and config byte-for-byte unchanged. Killing only the verified Perch helper caused launchd to start a new helper within 10 seconds; configuration remained unchanged. Shortcut registration is active. Input event tap reports inactive and requires Accessibility reauthorization after ad-hoc rebuild. Live panic/privacy resets and physical shortcut delivery have not been tested. Visual menu interaction has not been verified through UI automation.
