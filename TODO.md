# Perch work checklist

Reconciled September 9, 2026 for build 82. Build 77 remains installed; newer
candidates are prepared separately. Categories are distinct: known defects,
features, QA, release and backlog. Order within each category is planned work
order. Dependencies take precedence: public signing precedes Sparkle integration.
This supersedes stale open-item wording in dated review checkpoints.

## Known defects — fix before shipping; target zero

- [ ] **P3: legacy monitor guidance is dense and its next action is unclear.**
  The persistent sidebar improves access but does not replace the old monitor
  editor's nested guidance. Resolve through the coordinated KVM replacement;
  retain this as a known usability defect until the replacement resolves it.
  See WHOLE-APP-REVIEW-79.md. No other confirmed unresolved functional defect
  is currently recorded for the candidate. QA gaps are not established defects.

## Features

1. [x] **Persistent Settings navigation (build 82).** One window with a left
   category list, direct access to stable pages, Setup & status as home, stable
   geometry, keyboard navigation and explicit draft discard. Tests and operational
   confirmations retain their own interaction scope. See SETTINGS-SIDEBAR-82.md.
2. [ ] **Sparkle updater, after public signing.** Direct-download and Homebrew
   installations use the same app. Integrate authenticated downloads, install and
   restart, existing lid handoff, separate helper maintenance, quiet availability
   notices and recovery. This is now planned feature work, not optional backlog.
   Signing identity and integration prerequisites are in DISTRIBUTION.md.
3. [ ] **Coordinated Perch KVM, replacing monitor cycling.** Settle pairing and
   input capture/forwarding feasibility, then authenticated handoffs, computer/port
   mappings and arrangements. Support pointer/keyboard focus transfer, hotkeys,
   optional same-keyboard host-button detection, one monitor, either/both of two,
   and mixed arrangements. Track observed versus requested input; handle competing
   requests, sleeping peers and partial failures. Migrate useful mappings and
   replace dense legacy monitor guidance. Detailed order: KVM-PLAN.md.

## QA — implementation acceptance, with defects returned to the first section

1. [ ] **Install and accept build 82.** Check persistent navigation, direct menu
   entry, same-category return from children, validation/discard, Back/Close,
   small-screen scrolling, keyboard focus and sidebar behavior during operations.
   Check the new tooltip content (78+) and shared Esc labels. The original Back,
   tooltip-ownership and flicker fixes remain accepted; do not reopen without a
   new failure. Installation is separate from preparing a signed candidate.
2. [ ] **First use and access repair.** Blocked-access startup notice,
   already-enabled recovery, scoped Automation errors and helper-specific guidance;
   Setup & status must agree with feature pages. Normal launch and Restart already
   restored keyboard access. Do not reset live grants to manufacture a failure.
3. [ ] **Local replacement detection and restart notice.** Test actual newer-copy
   replacement, one notice per run, deferral while interacting, dismissal, manual
   restart and failed/partial replacement. Build 80 implementation and isolated
   tests are complete; see APP-REPLACEMENT-REVIEW.md.
4. [ ] **Saved lid intent and wake explanations.** Stopped protection retains the
   choice without silently rearming. Verify Resume, sequence-specific explanation
   only when requested, acknowledgement and View lid activity. Confirm actual
   sleep/wake notification order and the 24-hour/1024-entry log contract.
5. [ ] **Active-session restart and separate helper maintenance.** Successful
   transfer, expired/unclaimed cleanup, unchanged grace deadlines and visible
   queued update/open-lid completion. Inactive restart passed; installation of
   build 77 did not exercise active-session handoff.
6. [ ] **Lid safety edges and failures.** Just-before/after expiry opening/replugging,
   repeated power changes, unknown power and uncovered battery-open → close →
   plug → open ordering. Coordinate supervisor/watchdog failures, both absent
   with independent recovery, and reboot recovery. Confirm actual OS sleep and
   restoration. Powered close/open, short grace/replug, full 60-second expiry,
   menu-process-loss cleanup and explicit disable already have recorded passes.
7. [ ] **Native event-collector identity migration.** Install the implemented
   launcher through coordinated maintenance; test Full Disk Access attribution,
   event delivery, combined CPU accounting, restart/PID reuse and reboot.
   Direct-eslogger delivery remains supported. This launcher is separate from
   the optional direct Endpoint Security collector in Backlog.
8. [ ] **Keyboard and spoken VoiceOver acceptance.** Implementation is complete
   for the reviewed settings set, including the new sidebar. Finish spoken
   VoiceOver, broader production-route/dynamic-list journeys and coordinated OS
   permission/authorization handoffs. See ACCESSIBILITY-REVIEW-81.md and
   SETTINGS-SIDEBAR-82.md. Metadata and harmless-lab input are not full acceptance.
9. [ ] **Performance and memory.** Idle, open menu, input activity, process bursts
   and recovery; wakeups, event backlog, sustained memory growth and combined
   collector CPU. Prior bounded measurements do not establish release-wide cost.
10. [ ] **Sparkle acceptance after implementation.** Signed feed/archive delivery,
    bad signatures, interruption, cancellation, retry, replacement, permission
    continuity, active lid handoff, helper compatibility and external Homebrew
    replacement. See DISTRIBUTION.md for install-on-quit and identity requirements.
11. [ ] **KVM/hardware acceptance after implementation.** Two real Perch computers,
    multiple display arrangements, split keyboard/mouse hosts, identical keyboard
    models, reconnects and partial failures. Validate reused DDC/USB MCCS/MSI USB/
    NEC LAN/serial and LG identification on available hardware. Catalog research
    is not certified support. Retired standalone cycling has no separate QA gate.
12. [ ] **Destructive action acceptance in a separately authorized disposable
    environment.** Actual Panic/privacy reset must not target the live workspace.

## Release — signing, packaging and distribution

1. [ ] **Public signing identity and migration, before Sparkle.** Establish Apple
   Developer Program membership/Developer ID signing. Only the local Perch
   certificate was available on September 9. Review stable identities, helper
   trust and migration from the local certificate without silently resetting
   permissions. See DISTRIBUTION.md; membership confirmation is pending.
2. [ ] **Distribution build pipeline.** Direct-download package plus our own
   Homebrew cask tap; remove machine-specific identity/path/certificate assumptions.
   Decide supported Mac/macOS scope; sign nested code, notarize and staple.
3. [ ] **Dependency and catalog release review.** Audit provenance/licenses;
   define catalog/profile maintenance; include required notices and package checks.
4. [ ] **Release QA: clean install and lifecycle.** Clean Mac/account grants,
   helpers/collector, login startup, upgrade, rollback and uninstall; no reliance
   on this development Mac's grants/jobs. Verify Gatekeeper and supported systems.
5. [ ] **Release artifacts and documentation.** Checksums, appcast/release assets,
   support/recovery documentation, release notes and cask drafts.
6. [ ] **Publish only after explicit approval** of the concrete release, relevant
   QA passing and zero known defects. Commit/push is not public release approval.

## Backlog — optional future work, outside current release gates

1. [ ] **Direct process events.** Investigate a minimal native Endpoint Security
   collector replacing eslogger. Requires Apple's restricted Endpoint Security
   entitlement, separate from user-granted Full Disk Access. EVENT-COLLECTOR.md.
2. [ ] **Native lid research.** Find a supported third-party assertion that
   prevents closed-lid sleep on battery and automatically expires. Identified
   private options require Apple-internal power entitlements; Endpoint Security
   approval does not grant them. Optional simplification of helper/watchdog
   recovery; current guarded implementation still requires QA above.
3. [ ] **Thermal alerts.** Notify on high macOS thermal pressure using the public
   API already read by Perch. Define useful thresholds and quiet notification
   behavior. No special Apple feature entitlement is needed.
4. [ ] **Temperature readings.** Find a reliable CPU/GPU temperature sensor source
   and hardware coverage before displaying degrees. Separate from thermal alerts;
   do not infer numerical temperatures from qualitative pressure.
5. [ ] **Swap-rate metrics.** Show how quickly macOS swaps memory, with clear units
   and sampling semantics, distinct from current swap usage.

## Completed evidence and ongoing maintenance

Build 81's 22/22 isolated suites passed; its production build was warning-free.
Build 82 evidence is recorded in SETTINGS-SIDEBAR-82.md. Whole-app review fixes,
local replacement detection/restart and keyboard/accessibility implementation
are complete at their stated boundaries; pending QA above remains explicit.

User-confirmed: flicker resolved; CPU colors correct; password entry works;
physical external keyboard behavior works; original Back/menu interaction fixes
accepted on 77. External Fn access recovered without grant changes. Quit/Command-Q
has recorded installed dispatch evidence; shortcut detection and Add app/executable
work. Existing shortcuts are preserved; new installs default to Ctrl–Opt–Cmd–Esc.

Continue updating the settings-flow skill for confirmed lessons; review the agent
catalog monthly against official sources while preserving user choices and
reviewing changed matches. Commit and push completed work. No uncoordinated live
permission reset, Panic, hardware change, sleep/reboot/failure injection or public
publication is authorized by this checklist.
