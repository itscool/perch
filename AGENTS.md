# Notarization authorization

Submit artifacts to Apple for notarization only when the user explicitly requests
notarization. That request authorizes the whole release notarization process,
including the app and its installer; do not ask again between those stages.
Building, signing, installing, preparing a release, or storing credentials alone
does not authorize notarization, nor does authorization carry to later versions.
An explicit request to publish authorizes completing the release publication flow.
Status/log checks for an existing submission and stapling its accepted ticket do
not create a new submission. This preference does not cancel existing submissions.

# Releases

Follow `.claude/skills/release/SKILL.md` for every release. It verifies and
prepares the release notes in the conversation, then runs notarization,
publication and the Homebrew cask update in a background agent, so long Apple
waits never block other work.

# Live UI testing

Before operating the live desktop, announce the app/flow and start the separate
AGENT MODE indicator using `Tools/agent-mode/agent-mode.py`. Read
`Tools/agent-mode/README.md` for its session protocol. Keep session artifacts in
the current task's `work/`, outside tracked source.

Run its `check` immediately before every short UI action batch. If the check
fails, or the user requests control in chat, stop UI actions, end the indicator
session, and acknowledge the handoff. Do not automatically restart after a
control request. Stop the indicator when finished or yielding to the user.

The indicator is cooperative, not an input lock or authorization for tests.
It does not cancel actions already started. Preserve the user's restrictions
on live permissions, hardware, emergency actions and publication. Source reads and compilation need no banner. Isolated storage or prohibited
activation does not make native window tests invisible. The functional suite
contains tests that show Settings panels and therefore requires the banner.
Build it first with `Tools/check-functional-review.py --build-only --output DIR`,
then, during an announced active session, use `--run-only --output DIR
--agent-session SESSION`. The runner checks before launch and between suites;
visible panel cases check again immediately before presentation. Do not start
or restart a session automatically after the user asks for control.

# Launch identity and privacy checks

Launch the live menu app through macOS LaunchServices (`open -a /absolute/Perch.app`),
not by executing `Contents/MacOS/Perch` from the agent shell. A direct terminal
launch can attribute Input Monitoring checks to Codex/the terminal despite
Perch already being enabled. This reproduced the MX Keys disabled-control bug.
Do not reset or re-request permission as the first response to that discrepancy:
check launch provenance, signing identity and scoped TCC attribution, then verify
normal app launch. Headless tools and deliberately isolated test subprocesses are
separate; the in-app verified restart worker has a live test preserving Perch’s
own attribution. Keep this distinction when changing launch/restart mechanisms.

# Keep the installed candidate current

After a completed, verified build, replace the entire app bundle at the path
of the running Perch (normally /Applications/Perch.app), retaining its signing
identity and updater configuration. Stage and verify the bundle first; keep a
recoverable previous bundle. Do not overwrite a running executable in place.
Do not quit or restart the user's app merely to update the files: the next user
restart should pick up the new version. Report running and on-disk versions
separately. This does not authorize helper changes, notarization or publication.

Local `./build.sh` builds carry no `SUFeedURL` or `SUPublicEDKey`; only the
release pipeline adds them, and without both Perch's updater never starts. So
never let a local build replace an installed bundle that has them: that silently
stops update checks. After a release, install the published, notarized app from
`build/releases/<version>/Perch.app` instead, and check both keys before and
after any replacement, alongside the designated requirement.

# Appearance options and built-in presets

Whenever appearance options are added, removed or changed, review every built-in
preset in both Light and Dark. Update, add or retire treatments as appropriate
so the preset set uses the available design choices deliberately. Record which
presets changed and which were intentionally kept. Keep palette choices separate
from composition names, and preserve Scott's exact Perch original unless he
changes that specification.


# Continuation and canonical guidance

Read `Release/notes.md` first, then `TODO.md` and the evidence documents linked
from the relevant items. Keep current progress, remaining acceptance and actual
running/on-disk versions in those existing records; distinguish completed
implementation, automated verification, native acceptance and release status.
Do not assume an installed bundle is the version of an already-running process.

For Settings, Setup and recovery work, read and apply
`Tools/skills/settings-flow-review/SKILL.md`. Update that existing skill when a
confirmed lesson changes the design/review method, as its instructions require.
Update the UI route ledger when routes change. Preserve established safety,
installation, release, testing and user-authorization boundaries on continuation.

`CLAUDE.md` is a permanent forwarding entry point. Leave it unchanged. Put future
repository-wide instruction updates here, and task-specific progress in the
existing checklist/evidence files rather than duplicating guidance for Claude.
