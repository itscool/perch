# Restart Perch and separate lid-helper maintenance

**App settings → Restart Perch** closes and reopens the installed app. There is
no Updates page, file picker, download or installation in this action. Saved
choices are kept. A real update checker and release distribution are deferred
until release work.

## Restart contract

1. Verify the app at its current path against this publisher’s signing identity.
   A plain restart does not require a writable installation and never copies,
   moves or replaces the app bundle.
2. An active lid session requires a confirmed owned session and a compatible
   helper. With an inactive session and a closed lid, require fresh native
   evidence that both sleep-override states are off and no ownership is recorded.
   Otherwise explain that the lid must be opened or Keep awake reviewed.
3. The helper grants one ticket, pinned to the exact app code hash, for at most
   60 seconds. Existing battery countdowns, watchdog deadlines and ownership do
   not reset. Missing, expired or failed claims never create a new session.
4. Start a worker from the verified app. Keep the original process running until
   the worker acknowledges readiness. Failed readiness cancels the attempt and
   the handoff ticket, leaving a visible retry action in App settings.
5. The worker waits for the specific original PID and birth identity to exit,
   verifies the app again, and starts its exact executable. It waits for the new
   app’s completion receipt. App settings reopens with the result; a failed lid
   claim directs the user to Keep awake. A launch alone is not successful handoff.
6. The independent watchdog still has its short lease. Closed-battery expiry
   requests sleep even during restart. A missing replacement eventually ends the
   allowance; no restart path grants extra battery time.

The internal worker retains legacy file-replacement compatibility for builds
68–69, so those installed apps can bootstrap to this version. That branch checks
both bundles, retains a rollback copy and requires completion acknowledgment.
It is no longer an exposed user workflow. The plain restart branch cannot enter
file replacement. These mechanisms preserve the supervised session, not proof
of physical sleep prevention; see [lid recovery](LID-RECOVERY.md).

## Separate helper revision and visible deferral

`PerchLidProtocolVersion` describes the wire contract and
`PerchLidHelperVersion` describes the helper component. UI-only build increments
do not make a compatible lid helper obsolete. Increment the helper revision
when its implementation needs replacing; incompatible protocol changes require
an explicit migration and cannot use this app-only handoff.

A required installed-helper update appears in Setup & status and Keep awake. The existing helper remains installed while the lid is closed. Opening
the lid makes **Finish lid helper update…** available; it does not spring an automatic
administrator prompt. Back/Close does not clear the version-based pending notice.
A missing optional helper is not presented as a mandatory update.

The root installer stages and verifies the new complete bundle, then checks the
lid again immediately before stopping the old helper. Closing the lid during
password entry therefore leaves the queued replacement pending. Installation
starts disarmed. A previously confirmed active choice may be restored only after
the new helper responds and the app still observes an open lid. Otherwise the
result tells the user to review Keep awake. Saved choices are not rewritten.

Builds before this protocol cannot preserve a session through an app restart.
The first upgrade from build 63 needs the lid open, followed by the queued helper
update and explicit re-enabling if the old session could not be confirmed.
Known legacy builds 44–68 can still perform their corrected explicit cleanup
without replacement merely because the app build changed.

## Development launch and access

Launch the live app through LaunchServices (`open -a /absolute/Perch.app`).
Executing its binary from an agent terminal can attribute privacy checks to that
agent, despite Perch already being enabled. This reproduced unavailable MX Keys
Fn controls. Normal launch restored access without permission changes; the
in-app worker then preserved the correct attribution across a plain restart.
The explicit permission state is not itself proof that a particular process has
access. Check provenance before requesting a reset or another grant.

## Verification boundaries

Isolated tests cover ticket timing and replay, exact-hash requirement parsing,
wrong/late claims, lost preparation reply cancellation, queue adoption and late
callbacks, unchanged battery/watchdog deadlines, invalid signatures/paths,
transaction rollback, and queued/open/busy/error/return UI states. A disposable
signed worker test replaces copied test bundles, launches a fixture completion
process and checks its receipt; it never involves a live helper or lid session.

The test runner requires AGENT MODE because some native panel cases show windows.
Compile with `--build-only` before taking the desktop. See
[the session protocol](Tools/agent-mode/README.md).

Live acceptance remains required for the bootstrap, first password prompt,
compatible app restart with an active session, an expired/unclaimed restart,
queued helper replacement, and physical undock/sleep/wake transitions. Do not
inject failures into a working closed-lid session without coordinating with its
user. Public release/distribution is a separate gate.
