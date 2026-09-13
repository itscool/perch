# Recovery correctness and device following — 2.0.119

September 13, 2026. Static review, injected-hardware real-TLS tests and offscreen
native rendering only. No live permissions, input capture, hardware operations,
helper maintenance or running-app restart were performed.

## Prioritized findings and corrections

1. **P1: recovered input could retain a failure from an older state.** Healthy
   coordinator replies did not clear a prior issue, and generic local messages
   outlived the readiness prerequisite that produced them. Separate local and
   coordinator errors, derive blocked-target messages from current readiness,
   discard expired observations and clear recovered issues. A cleared warning
   never starts control automatically. Context changes release control once on
   transition; an unavailable coordinator is named and conflicting edits point to
   the existing conflict review action. Retry touches only missing trusted links.
2. **P2: working lid protection was presented as Unverified with no repair.** The
   fresh armed helper snapshot follows successful enforcement/readback; treating
   future macOS uncertainty as failed setup created an impossible task. It now
   reports active/ready, retaining the limitation that macOS may force sleep.
   Stale errors cannot masquerade as current observations. Idle sharing likewise
   reports readiness separately from actually controlling a destination.
3. **P2: monitor failures offered no local recovery and persisted after evidence
   recovered.** Results name affected screens and their inputs. Screen review,
   read-only current-input checks through paired peers and a separate switch retry
   are exposed together. Later matching reads reconcile failed results only for
   the current configuration/request; pre-attempt observations cannot confirm a
   failed command. Read refreshes are rate-limited and never write monitor inputs.
4. **P2: host-button following had an incomplete mouse journey.** Keyboard and
   mouse now share illustrated numbered setup, per-Mac matching, opt-in following
   and visible control destination. Passive HID attachment notifications refresh
   observations without opening devices for input. Ambiguous identity remains
   unmatched. The signed configuration includes device kind and fences changes.
5. **P2: preset warning/status rows changed card height.** Reuse the existing
   count/status line for attention and In use; keep editing selection distinct.

## Pattern sweep

Traced setup summary/sidebar, Keep awake, lid activity/update messaging, permission
and prerequisite pages, launch access repair, reset result/retry handling and agent
save/status handling, plus Desk coordinator, monitor results, input readiness and
recovery actions. Existing permission rechecks and reset failure-only retries keep
explicit scope; they were not exercised against live grants. This pass is a
static cross-feature review, not a claim of full production dialog acceptance.

The settings-flow skill now requires evidence-based readiness, clearing stale
failure states on recovery, concrete local recovery actions, concise device setup
with success evidence, and stable status geometry.

## Evidence and limits

- Production Developer ID build and bundled Sparkle/runtime/nested-signature checks pass.
- Real TLS loopback suites pass: pairing/reconnect/conflicts/revocation, sixteen
  peers/screens, input handoff, named failures, read-only monitor reconciliation,
  stale-read refusal, dynamic readiness recovery and simulated keyboard/mouse
  attachment following. Hardware calls are injected; no native input is posted.
- Offscreen recovery checks pass fresh/stale/failed/stopped/update lid states and
  idle/active/failed sharing states. Functional fixture compiles; broad native
  window tests were not run during the user's manual testing.
- Offscreen production Desk rendering passes socket gesture/cancel/rewire and
  24 preset/subset checks. Rendered cards retain equal height. Device illustrations
  rendered offscreen. Prior unchanged sidebar/inspector geometry checks remain
  recorded in DESK-CLARITY-AND-INSPECTOR-2.0.md.
- Physical mouse/keyboard host-button switching, receiver detach behavior, actual
  LG readback, two-Mac networking and native interactive acceptance remain QA.

Illustrations are schematic. Product examples follow the official
[MX Keys setup guide](https://hub.sync.logitech.com/mx-keys/post/mx-keys-for-business---setup-guide-RfWxVegf2vZCAjM)
and [MX Master 3 guide](https://support.logi.com/hc/en-ch/articles/360035271133-Getting-Started-MX-Master-3).
Some receivers hide host attachment changes; the UI states this limitation.

## Why networking may have improved after upgrading

Commit f5cc9bc, between builds 106 and 110, clears completed temporary pairing
before close, isolates failed duplicate routes from working peers, scopes errors
and clears recovered peer failures. Build 96's e2e87c0 fixed synchronization load
stalls. These are real improvements, but neither proves the root cause of Scott's
recent resets. Build 119 adds targeted retries and recovery-state accuracy; the
real-Mac reset defect stays open until its cause and recovery are verified.

## Delivery

Developer ID 2.0.119 is installed at /Applications/Perch.app for the user's next
restart. Previous bundle: /Applications/.perch-previous-kqezxl6w/Perch.app.
The running process was left untouched. This candidate was not notarized or
published; public release remains 2.0.94. TODO.md records the remaining gates.
