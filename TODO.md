# Current Perch backlog

Reconciled September 9, 2026 after the build 81 keyboard/accessibility work; build 77 remains installed. This is the planned
execution order, not the dates issues were first reported. It supersedes stale
open-item wording in dated review checkpoints. Functional bugs come first;
acceptance gaps below are not automatically established defects.

1. **Back fix accepted by the user on build 77.** The user confirmed item 1 works.
   Esc spelling differed between Settings and menu; the follow-up now uses one
   shared shortcut title and key label. Broader sibling/native-lab coverage stays
   under item 3, not an unresolved claim about the reported Back defect.
2. **Menu interaction fix accepted by the user on build 77.** The user confirmed
   item 2 is perfect, then reported incomplete and inconsistent tooltip content.
   Build 78 adds required help for all 21 action rows, shared explanations and
   state-specific context. Its content changes still need native hover acceptance;
   the original tooltip ownership/selection defect is not being reopened.
3. **Full isolated suite and limited native dialog lab completed for build 79.**
   All 21 suites pass. Real harmless-lab confirmation/Escape, result Back, picker
   cancellation and parent action passed with AGENT MODE. This closes the pending
   full-suite run, not native acceptance on every production route. See item 9.
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
9. **Keyboard/accessibility implementation complete for the reviewed settings set; release acceptance remains.**
   Build 81 supplies local Tab/Shift-Tab navigation even with the system's
   button-navigation preference off; native default Return, text editing,
   VoiceOver chords and OS sheets are preserved. Long explanations scroll by
   keyboard. Page identity, change notifications and remaining scoped labels
   are implemented. Actual harmless-lab keyboard journeys passed. See
   ACCESSIBILITY-REVIEW-81.md for coverage and the remaining test checklist:
   spoken VoiceOver, broader per-route keyboard/dynamic-list acceptance and
   coordinated external permission/authorization handoffs. No known code work
   from this pass is deferred; test-discovered defects still require fixes.
   WHOLE-APP-REVIEW-79.md retains the earlier review findings. Physical lid,
   collector and clean-install acceptance remain items 4–8 and 14. Destructive
   panic/privacy testing requires a separately authorized disposable environment.
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
    UI/settings once ready; migrate useful mappings. Replace the legacy dense, nested-scrolling monitor
    guidance with clear arrangement/status/next-action pages. Detailed order:
    KVM-PLAN.md.
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
15. **Later: real release update checker.** Build 80 adds the reusable local
    replacement step now: detect a newer signed app at the running copy's path,
    show running/on-disk versions and Restart in the menu, and notify once per
    process run. See APP-REPLACEMENT-REVIEW.md. No download/install method is
    assumed. Release discovery and delivery remain future work; the development
    file-picker Updates flow stays retired. Native replacement/notice acceptance
    remains separate from the isolated tests and active-session restart checks.
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
