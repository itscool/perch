# Desk sharing and lid rows — September 13, 2026

Developer ID 2.0.116 built and passed bundle/Sparkle/architecture/signature checks.
Installed at /Applications/Perch.app without restarting the user process; previous
bundle retained at /Applications/.perch-previous-zrkvzi3s/Perch.app.

## Findings and disposition

| Priority / journey | Finding | Change / evidence |
| --- | --- | --- |
| P1: Keep awake → Resume → activity/setup | Seven rows were added to a fixed-height document; the last two painted outside the native hit-test bounds. Direct performClick tests bypassed the failure. | Shared task page grows as rows are added. 210 native row hit targets and explanation bounds pass without a window; existing Keep awake fixture also checks hit geometry before dispatch. |
| P1: switch cancelled by a configuration edit | Delayed writes did not recheck the configuration revision, and a failed stale command could attempt invalid fallback and retain a lease. | Recheck revision before hardware work; never delegate stale requests. TLS fixture edits a port during held work, observes zero writes, then verifies later preset/delegation works. |
| P2: Desk → pointer crossing | Session enable and a second preset selector were on a separate page. Scott confirmed sharing was off. | Desk inspector owns one Share on this Mac switch, peer readiness and start action for its selected screen/editing preset. Session restart semantics are visible. Setup routes here. |
| P2: optional shared-keyboard setup | Technical attachment wording and a name-only Add step obscured the physical task and implied this was needed for ordinary sharing. | Input options keeps pointer tuning and optional computer-button following. Choose a connected keyboard to add and match this Mac together; other Macs show matched/needs matching. Instructions explain reusing the same entry after switching the physical keyboard. |
| Feature: monitor port → direct picture change | A port menu could edit cables but not switch the picture without a preset. | Switch to this input uses a distinct one-port request, canonical validation against the shared group and the existing paired lease/verification protocol. Presets remain untouched; shared input returns locally. |

## Verification

- Full isolated functional fixture compiled. The new early offscreen task-layout
  mode ran without windows, action dispatch, permissions or hardware access.
- 105 pure KVM checks passed.
- Real TLS loopback tests with temporary identities and injected monitor/input
  adapters passed: one-off remote switching to an unassigned port, exactly one
  monitor, unchanged shared configuration, request validation/serialization,
  stale edit cancellation, subsequent presets, competing leases, fallback,
  pointer handoff and 16-peer convergence. This does not close the separate
  real-network connection-churn report.
- Settings skill updated for ancestor hit bounds and visible session controls,
  with discriminating evaluation cases; structural validation passed. No claim
  of independent agent evaluation.
- Native acceptance of the revised Desk UI and repaired buttons on the other
  Mac remains QA. No live UI takeover, hardware/helper changes, permission reset,
  notarization or publication was performed.

## Compatibility and use

Both Macs need 2.0.116 for the new one-off port request. Ordinary preset requests
retain their wire form. In Desk, turn on Share on this Mac on each participant,
use a confirmed preset and select a screen to start control. Crossing needs
adjoining screen geometry. Input options is optional tuning and host-follow
configuration, not a prerequisite for ordinary mouse crossing.

The verified installed version and retained bundle path are recorded at the top
of TODO.md. The running user process is left unchanged until the user restarts.
