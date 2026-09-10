# Perch work checklist

2.0 development, September 10, 2026. Developer ID 2.0.94 is notarized and installed
in /Applications. 2.0.94 is published; setup defects and live acceptance remain open. Categories are distinct: known defects,
features, QA, release and backlog. Order within each category is planned work
order. Dependencies take precedence: public signing precedes public Sparkle releases.
This supersedes stale open-item wording in dated review checkpoints.

## Known defects — fix before shipping; target zero

- [ ] **2.0.94 setup review: seven open findings.** Fix keyboard recovery loops
  and external-handoff navigation lockout first (P1), then missing permission
  drag/copy controls, wrong-helper target selection, missing collector-launcher
  recovery, publisher-aware helper readiness, and stale Desk onboarding (P2).
  Source-only review; no native reproduction or app fix yet. Evidence and route
  coverage: SETUP-REVIEW-2.0.94.md.

- [x] Fresh-Mac builds failed fetching Sparkle when Python lacked issuer
  certificates. Downloads now use system curl with HTTPS and checksum verification;
  missing/corrupt caches repair automatically. Toolchain and local signing checks
  run before version allocation or app writes. `./build.sh --check-dependencies`
  prepares pinned dependencies without signing/notarization credentials. Fresh
  Sparkle download, clean Swift package resolution and failure/repair tests passed.

- [x] Desk omitted the retained LG firmware-ID-to-profile lookup. Explicit setup
  inspection now carries identity to local/remote profile suggestions, preserves
  manual choices and offers the owner-evidenced USB-C 209 profile. Isolated
  transaction tests and native fixture clicks passed; new live hardware
  acceptance remains part of the protocol QA below. Duplicate refresh errors in
  the Add screen dialog are also removed. Installed in 2.0.94; physical monitor acceptance remains open.

These fixes are included in the installed 2.0.94 app:

1. [x] About opened a Settings shell with unavailable navigation. It now uses
   the independent native modeless About panel.
2. [x] Desk default F1–F3 shortcuts could not register because the runtime used
   the emergency shortcut's smaller key list. All offered F1–F20 keys now map
   explicitly; failed registration leaves no partially active preset set.
3. [x] Lid helper installation rejected Sparkle's legitimate framework links.
   The installer now permits only the pinned relative links, verifies nested
   signatures, and rejects redirected/extra links. Publisher mismatch queues
   a helper update rather than claiming the old helper is current.

2.0 additionally fixes setup-summary overflow, stale shared-keyboard rows,
standard text-editing shortcuts and input handoff/ordering failures described in
RELEASE-2.0.md. They are included in the installed app; hardware acceptance remains open.

23/23 isolated regression suites pass. Actual hardware and broader native QA
remain open; this is not a claim that untested behavior is defect-free.

## Features

1. [x] **Persistent Settings navigation (build 82).** One window with a left
   category list, direct access to stable pages, Setup & status as home, stable
   geometry, keyboard navigation and explicit draft discard. Tests and operational
   confirmations retain their own interaction scope. See SETTINGS-SIDEBAR-82.md.
2. [x] **Sparkle updater integration.** Pinned 2.9.6, signed feed/archive/identity,
   Updates sidebar, saved checking preference, native installation, exact-identity
   lid handoff and visible failure/retry. Real signed disposable installation and
   mock handoff/retry passed. Public signing/hosting and live acceptance remain
   below. SPARKLE-REVIEW.md; DISTRIBUTION.md.
3. [x] **Coordinated Perch KVM implementation, replacing monitor cycling.** Support named groups
   of 2–16 computers; pairing authorizes individual membership. One intuitive
   group setup is editable from any member and stays synchronized, including
   monitor identities, mappings, arrangements and shared shortcuts. Up to three
   presets (default Ctrl–Opt–Cmd–F1/F2/F3), physical layout including rotation,
   and pointer-boundary handoff independent of input-device attachment. Handle
   offline catch-up, concurrent edits, revocation and per-host prerequisites. Monitor-only grouping, authenticated synchronization and real preset switching
   preceded the 2.0 input implementation. Support hotkeys,
   optional same-keyboard host-button detection, one monitor, either/both of two,
   and mixed arrangements, with up to 16 distinct physical monitors per group.
   Establish shared physical identity across computers using serial/model
   evidence and visual confirmation when ambiguous; retain per-host input maps.
   Track observed versus requested input; handle competing
   requests, sleeping peers and partial failures. No legacy migration is required.
   Preserve the monitor profile/API/protocol library and use it to replace the old monitor pages, switching groups, cycling shortcuts and guidance
   with one Desk workflow, reusing low-level monitor transports. Detailed order: KVM-PLAN.md.
   **Monitor-only milestone implemented in 1.2.87:** mutual TLS discovery/joining,
   two-sided approval, pinned membership, durable signed synchronization, offline
   conflict recovery and revocation; real monitor adapters, two-phase reservations,
   mapped-peer fallback and readback; production Desk/sidebar/menu integration.
   Matching remains explicit: displays with identical specs are never auto-merged.
   Strong-serial suggestions now supplement manual shared-screen confirmation;
   weak or conflicting identity still requires explicit matching. See KVM-LIVE-REVIEW.md for evidence limits.
   **2.0 implementation:** opt-in session input routing, shared keyboard host
   following with explicit per-host attachment confirmation, three-computer
   pointer traversal, fresh input readback, native event construction, local
   recovery, and strong-serial monitor suggestions. Sixteen real TLS fixture
   members exercise synchronization and routing. See RELEASE-2.0.md for limits.
   Secure-entry/locked-session input is not supported by this event-tap adapter;
   a local keyboard is required. Physical latency, lock/unlock, real mouse/button
   behavior and host-button observations remain QA gates, not passed tests.
4. [x] **Menu Appearance (1.2.87).** Immediate-save rainbow and separate System
   controls for border sides/scope/thickness/intensity, colored or grey backgrounds,
   title/full/none highlights, corner radius, title tint/icons and spacing.
   Includes shared-renderer preview, style presets and Restore defaults. Native
   checkbox changes, independent System values, scrolling and Restore passed.
5. [ ] **Finish the Sparkle release feed.** Configure the production public key,
   stable HTTPS feed and signed release artifacts; complete signing/notarization
   and verification before requesting final publication approval. Integration
   already exists, but the feed is not live.

## QA — implementation acceptance, with defects returned to the first section

1. [ ] **Accept the latest release candidate on both Macs.** Check persistent navigation, direct menu
   entry, same-category return from children, validation/discard, Back/Close,
   small-screen scrolling, keyboard focus and sidebar behavior during operations.
   Check the new tooltip content (78+) and shared Esc labels. The original Back,
   tooltip-ownership and flicker fixes remain accepted; do not reopen without a
   new failure. The local replacement is recorded separately in RELEASE-1.2.md. Desk child Close/Escape, immediate name saving, preset Play with injected monitor commands and Appearance controls were exercised; broader journeys remain.
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
7. [ ] **Native event-collector acceptance.** Install the current
   launcher through coordinated maintenance; test Full Disk Access attribution,
   event delivery, combined CPU accounting, restart/PID reuse and reboot.
   Only the current fixed launcher is supported. This launcher is separate from
   the optional direct Endpoint Security collector in Backlog.
8. [ ] **Keyboard and spoken VoiceOver acceptance.** Implementation is complete
   for the reviewed settings set, including the new sidebar. Finish spoken
   VoiceOver, standard text-editing shortcuts in the new SwiftUI fields, broader
   production-route/dynamic-list journeys and coordinated OS
   permission/authorization handoffs. See ACCESSIBILITY-REVIEW-81.md and
   SETTINGS-SIDEBAR-82.md. Metadata and harmless-lab input are not full acceptance.
9. [ ] **Performance and memory.** A read-only 30-second installed 1.2.87 baseline
   passed (30/30 healthy, combined app/helpers excluding observer about 1.23% CPU);
   this does not measure the new input adapter. Idle, open menu, input activity, process bursts
   and recovery; wakeups, event backlog, sustained memory growth and combined
   collector CPU. Prior bounded measurements do not establish release-wide cost.
10. [ ] **Sparkle acceptance after implementation.** Signed feed/archive delivery,
    bad signatures, interruption, cancellation, retry, replacement, permission
    continuity, active lid handoff, helper compatibility and external Homebrew
    replacement. See DISTRIBUTION.md for install-on-quit and identity requirements.
11. [ ] **Desk monitor-only acceptance — next.** Join the two real Macs; verify
    cross-Mac edits, restart/reconnect and conflict recovery, identify/match screens,
    map actual ports, and use all presets in both directions. Test one/two screens,
    mixed arrangements, offline control hosts, partial failure and competing
    commands. Test Bonjour/nearby Wi-Fi and explicit routed addresses. Then accept 2.0 keyboard/mouse sharing: Control here, pointer boundary handoff,
    rotation/Retina scaling, separate input hosts, modifiers, buttons/drag/scroll,
    host-selection first key, access loss, lock/unlock and Ctrl–Opt–Esc recovery.
    Local keyboards are required for secure entry. Validate reused DDC/USB MCCS/MSI USB/
    NEC LAN/serial and LG identification on available hardware. Catalog research
    is not certified support. Retired standalone cycling has no separate QA gate.
12. [ ] **Destructive action acceptance in a separately authorized disposable
    environment.** Actual Panic/privacy reset must not target the live workspace.

## Release — signing, packaging and distribution

1. [x] **Public signing identity.** Developer ID Application for team S42F8BV6J2
   is available and a hardened, timestamped release build succeeds. New publisher
   helper compatibility is explicit; no development-certificate migration.
2. [ ] **Distribution build pipeline.** Developer ID build, production Sparkle
   Keychain key/config, branded DMG, signing, notarization submission/stapling,
   archive/feed verification and draft-to-public GitHub publishing are implemented.
   Apple notarization credentials (Keychain profile Perch) were validated on
   September 10; the 2.0.94 app was accepted, stapled and passed Gatekeeper
   assessment (Notarized Developer ID), and is installed in /Applications. The
   DMG is accepted/stapled, and the signed Sparkle ZIP/appcast are published.
   Anonymous public downloads/checksums and the stable feed passed verification.
   The resumable Tools/release-all.py handles the full flow. Real update/restart
   acceptance remains QA.
   Direct distribution currently targets Apple silicon/macOS 26+; Homebrew cask
   draft follows verified public artifacts. See Release/README.md.
3. [x] **Dependency and catalog release review.** Audit completed September 10;
   missing BoringSSL/MSI notices fixed, NEC attribution added, catalog provenance
   and maintenance documented, and 22 bundled resources checked automatically.
   Scott approved retaining and distributing the LG firmware-family table on
   September 10. Publication checks bind that decision to the exact resource
   hash; this does not claim legal clearance. See Release/DEPENDENCY-REVIEW.md.
4. [ ] **Release QA: clean install and lifecycle.** Clean Mac/account grants,
   helpers/collector, login startup, upgrade, rollback and uninstall; no reliance
   on this development Mac's grants/jobs. Verify Gatekeeper and supported systems.
5. [ ] **Release artifacts and documentation.** Support/recovery guide, release
   notes, attribution and dependency inventory are prepared and bundled. Final
   checksum generation/verification is implemented and tested; actual checksum
   values follow final notarization/stapling. Public assets and cask draft remain.
6. [ ] **Publish only after explicit approval** of the concrete release, relevant
   QA passing and zero known defects. Commit/push is not public release approval.

Installation experience: prepare a branded DMG with an obvious app-to-Applications
layout, then the existing Setup & status first-launch journey. Ask for feature
permissions in context. Developer ID Application covers app/DMG signing; a future
PKG wizard additionally needs Developer ID Installer. Verify fresh install, first
launch, existing-install replacement and uninstall/recovery as one journey.

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

6. [ ] **Windows and Linux KVM members.** Extend Perch groups to mixed operating
   systems. Keep group membership, authentication and handoff messages portable;
   Apple peer-to-peer discovery is an optional Mac transport. Implement native
   input capture/injection and monitor control per platform, with suitable
   permissions, discovery/connectivity alternatives and mixed-platform QA.

7. [ ] **VM adapters.** Treat virtual machines as workspace destinations alongside
   physical computers. Choose the initial hypervisor (Parallels, Fusion or UTM)
   with the user before implementing discovery, console selection and input
   routing. Preserve native guest input ownership and handle stopped/locked guests
   explicitly. Deferred by the user; not part of this release.

## Completed evidence and ongoing maintenance

Build 81's 22/22 isolated suites passed; its production build was warning-free.
Build 82 evidence is recorded in SETTINGS-SIDEBAR-82.md. Version 1.2.84 passed
23/23 isolated suites; Desk integration also passed 23/23 suites, 66 portable
KVM checks, 26 model journeys and real TLS/monitor-coordinator fixtures; Sparkle fixture evidence is in SPARKLE-REVIEW.md. Whole-app review fixes,
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
