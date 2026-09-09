# App updates and lid-helper updates

Perch's **App settings → Updates** page accepts a newer local, signed `Perch.app`.
There is no release feed, download, public upload or automatic installation.
The app must be in a user-owned writable location. A copy running from a mounted
volume must first be moved to a writable Applications folder.

## App update transaction

1. Choose an update. Verify its complete signature against the running app's
   designated requirement, bundle identity, newer build and compatible lid
   protocol. Copy it into private Application Support staging and verify again.
   Choosing does not restart Perch or change a setting. Back/Close keeps the
   prepared candidate during this app session; verification errors keep the
   previously prepared candidate.
2. **Update & restart** rechecks both app identities and the destination. An
   active session must be owned by this app and confirmed by a compatible helper.
   Otherwise the lid must be open. A saved preference is not session authority.
3. The helper issues one UUID ticket pinned to the staged executable's code hash,
   with a continuous-clock deadline 60 seconds away. Retrying the preparation
   returns the same ticket and deadline. It does not reset the existing battery
   countdown, watchdog state, ownership token or sleep-interruption state.
4. Start the signed staged worker. The old app waits for the worker to acknowledge
   verification before quitting. A failed spawn/readiness check requests
   cancellation of the allowance and keeps the old app running. A missing
   preparation reply also requests cancellation. Connection failure is reported
   as uncertain; it is never displayed as successful preservation.
5. The worker waits for that specific old PID and birth identity to exit, checks
   both bundles again, moves the old app to a sibling backup, installs the staged
   app and launches it with the ticket. A failed file move restores the old app;
   later failure retains a backup and attempts to reopen an intact verified app.
6. The new app claims through a separate authenticated XPC endpoint restricted
   to the ticket's exact code hash and the helper's configured user. Its existing
   helper session then resumes ordinary five-second app renewals. Old connections,
   wrong tickets, expiry, disable and stopped policy cannot claim. The normal
   status/cancellation endpoint stays accessible during preparation failures.
7. The worker requires the new app's completion receipt before removing its
   backup. A launch alone is not completion. A failed claim does not enable a
   replacement lid session. Updates retains the result and reopens after restart.

The independent watchdog still receives short leases, normally three seconds,
and its acknowledgments must remain fresh. Closed-battery expiry still requests
sleep even if the update allowance has time left. At app-allowance expiry, normal
fail-safe policy ends protection and requests sleep when closed without external
power. No system-wide persistent sleep setting is written by the updater.

These rules preserve the supervised session, **not proof that macOS honors the
private clamshell request**. The separate powerd/shared-bit defect remains open.
A lost cancellation/claim reply may end protection; it must not be hidden by
silently creating a fresh session.

## Separate helper revision and visible deferral

`PerchLidProtocolVersion` describes the wire contract and
`PerchLidHelperVersion` describes the helper component. UI-only build increments
do not make a compatible lid helper obsolete. Increment the helper revision
when its implementation needs replacing; incompatible protocol changes require
an explicit migration and cannot use this app-only handoff.

A required installed-helper update appears in Setup & status, Keep awake and
Updates. The existing helper remains installed while the lid is closed. Opening
the lid makes **Finish helper update…** available; it does not spring an automatic
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
Known legacy builds 44–67 can still perform their corrected explicit cleanup
without replacement merely because the app build changed.

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
