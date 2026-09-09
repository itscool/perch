# Current Perch backlog

Reconciled September 9, 2026 after installing build 77. This is the planned
execution order, not the dates issues were first reported. It supersedes stale
open-item wording in dated review checkpoints. Functional bugs come first;
acceptance gaps below are not automatically established defects.

1. **Confirm the build 77 Back fix with native input.** Replay shortcut success
   and timeout → Back → cleanup → responsive parent, plus repeat entry and X.
   Exercise sibling alert/result/error routes, external handoff return, and
   standalone notices. The 58-site static sweep and hidden tests pass; native
   acceptance is still open. Add app/executable and shortcut detection already
   have user confirmation.
2. **Confirm native menu interaction corrections.** Hover across rows to check
   Panic help no longer leaks; mix pointer and keyboard selection and activate
   harmless actions with Return/Space. Check conditional/disabled rows and
   reopening. Build 77 includes source fixes and passing hidden boundary tests.
3. **Run the current full isolated functional suite and native dialog lab.**
   Compilation and targeted hidden tests pass. The full visible run remains
   outstanding after the callback migration; use AGENT MODE for visible work.
   Fix any regressions before proceeding to discretionary feature work.
4. **Accept first-use and access-repair journeys.** Verify the new blocked-access
   startup notice and already-enabled recovery route on the affected launch,
   including scoped Automation errors and correct helper-specific explanations.
   Normal launch and Restart already restored keyboard access. Do not reset
   live permissions to manufacture a failure. Check Setup & status as a useful
   first-run/repair summary, not only individual pages.
5. **Accept saved lid intent and wake explanations.** A stopped session must not
   uncheck the saved choice or silently rearm. Verify Resume, an explanation only
   when lid protection was requested, sequence-specific evidence, acknowledgement,
   and View lid activity. Confirm the 24-hour/1024-entry log contract. Source and
   deterministic tests exist; actual sleep/wake notification order remains open.
6. **Validate active-session Restart and separate helper maintenance.** Check
   successful transfer, expired/unclaimed transfer cleanup, preserved grace
   deadlines, and the visible queued-helper update/open-lid completion flow.
   Inactive restart passed; build 77 installation also had no active session.
7. **Finish lid safety edge/failure acceptance.** Cover just-before/after expiry
   opening/replugging, repeated power changes, unknown power, and uncovered
   battery-open → close → plug → open ordering. Exercise supervisor and watchdog
   failures, both absent with independent recovery, and reboot recovery in a
   coordinated safe session. Confirm actual OS sleep/restoration, not just logs.
   Ordinary powered close/open, short grace/replug, full 60-second expiry,
   menu-process-loss cleanup and explicit disable already have recorded passes.
8. **Finish native event-collector migration acceptance.** Install the implemented
   identity launcher through the collector maintenance route when coordinated;
   check Full Disk Access attribution, event delivery, exact CPU accounting,
   collector restart/PID reuse and reboot. Direct-eslogger delivery is supported;
   new native launcher installation/FDA/reboot acceptance is still outstanding.
9. **Complete the broader whole-app review.** Close remaining first-use, repair,
   add/remove/relearn and failure journeys; keyboard-only/VoiceOver, contrast and
   light/dark readability; security/least privilege, helper identity, recovery and
   feature-bloat review. Review every relevant route, record prioritized findings,
   fix them and retain evidence. Destructive panic/privacy-reset end-to-end work
   belongs in a separately authorized disposable environment, not this session.
10. **Measure current performance and memory.** Idle, open menu, input activity,
    process bursts and recovery; wakeups, event backlog and sustained memory
    growth; honest combined collector CPU attribution. Prior bounded measurements
    exist, but do not establish release-wide performance or near-zero overhead.
11. **Design and build coordinated Perch KVM.** First settle pairing and input
    capture/forwarding feasibility, then authenticated handoffs, computer/port
    mappings and saved arrangements. Support pointer/focus transfer, hotkeys and
    optional same-keyboard host-button detection; one monitor, either/both of two,
    and mixed arrangements. Track observed versus requested monitor input and
    handle concurrency, sleeping peers and partial failure. Replace old cycling
    UI/settings once ready; migrate useful mappings. Detailed order: KVM-PLAN.md.
12. **Validate KVM and hardware support.** Two real Perch computers, multiple
    display arrangements, split keyboard/mouse hosts, identical keyboard models,
    reconnect and partial failures. Validate reused DDC/USB MCCS/MSI USB/NEC
    LAN/serial transports and proprietary LG identification where hardware is
    available. Research catalog entries are not certified support. Retired
    standalone cycling acceptance is not a separate prerequisite.
13. **Prepare distribution.** Choose the initial Homebrew tap/cask or appropriate
    source formula; remove machine-specific identity/path/certificate assumptions;
    decide signing/notarization and supported Mac/macOS scope. Audit dependency
    and catalog provenance/licenses; define catalog/profile maintenance. Prepare
    packaging, checksums, support/recovery documentation and release/cask drafts.
14. **Verify clean installation and release lifecycle.** Clean Mac/account setup,
    Perch's own permission grants, helpers/collector, login behavior, upgrade,
    rollback and uninstall. Confirm compatibility without this development Mac's
    grants/jobs. Review the concrete release before any separately authorized
    publication; public publishing is not authorized by this backlog.
15. **Later: real release update checker.** The development file-picker Updates
    flow was intentionally replaced by Restart. Design user-facing release
    discovery/delivery when preparing an actual public release.
16. **Optional/deferred research and metrics.** A supported native expiring lid
    assertion may simplify recovery, but is not required if the guarded override
    meets acceptance. Retain older optional thermal-alert/swap-rate ideas; numeric
    temperature requires a reliable sensor. These are not current bug blockers.

Ongoing: update the settings-flow skill when new confirmed lessons emerge;
review the agent catalog monthly against official sources, preserving explicit
user choices and reviewing changed matches. Commit/push completed work; build
and installation are separate from public publication.

Already confirmed: flicker resolved; CPU colors correct; password entry works;
physical keyboard behaviors accepted by the user; external Fn access recovered
without changing grants; Quit/Command-Q has recorded installed dispatch evidence;
shortcut detection and Add app/executable work. Do not reopen these generically
without a new failure. The saved shortcut is preserved; new installations default
to Control–Option–Command–Escape, displayed with Esc.
