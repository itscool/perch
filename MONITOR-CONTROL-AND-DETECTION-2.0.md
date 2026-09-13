# Monitor control and detection — September 13, 2026

Developer ID 2.0.115 was built, verified and installed at /Applications/Perch.app.
The existing app was not restarted. The previous bundle is retained at
/Applications/.perch-previous-ap6xavla/Perch.app. No helper, permission, hardware,
notarization or publication actions were performed.

## Changes

- Control through only offers paths associated with this physical monitor,
  labeled by computer and port. A path bound to another monitor is excluded.
  USB/network/serial overrides select their actual host and explicit endpoint.
- Protocol override preserves and labels its original default separately;
  changing protocol does not erase the input profile. Serial stays in details.
- Detect input profile requests fresh local or correlated remote inspection.
  Verified catalog profiles or monitor-reported ports can be applied. Unknown
  results, errors and concurrent monitor/port edits retain the existing setup.
  Remote requests expire after 15 seconds; both Macs need the supporting build.
- The LG catalog has 162 firmware families but only eight nonempty input maps.
  Family recognition alone is insufficient evidence for a complete port profile.
- Preset execution already read the monitor before writing and skipped an input
  that was confirmed current. That production policy is now extracted and tested;
  cancellation is checked again after reads. An already-selected input sends no
  switch command and incurs no settling delay.

## Evidence and limits

- 13 production monitor-command policy checks pass, covering confirmed current
  input, unknown/read failure, mismatched input, failed write and lease expiry.
- Offscreen profile tests pass for scoped paths, offline labels, wrong-monitor
  exclusion, verified/reported/unknown detection, persisted protocol default and
  correlated reply serialization. They assert no windows are created.
- 105 pure KVM checks pass; functional fixtures compile; the release build passes
  the 61-site dialog contract and bundle/Sparkle/architecture/signature validation.
- Settings skill validation and git diff whitespace checks pass.
- Native setup acceptance and actual remote detection callbacks remain QA.
- Real-Mac connection churn and Scott's failed pointer crossing remain open.
  Sharing is session-scoped and must be enabled on both Macs; crossing also needs
  confirmed mapped inputs and adjoining screen geometry. The user's sharing-state
  clarification is pending. No claim that these reports are fixed in this build.
