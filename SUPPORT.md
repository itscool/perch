# Perch setup and recovery

For the first Developer ID release candidate: Apple silicon, macOS 26 or later.
Use the published release's notes to confirm its version and acceptance status.
A development build is not evidence that Apple notarization is complete.

## Install and find your way around

Download the DMG from https://github.com/itscool/perch/releases. Drag Perch into
Applications, then open that copy from Finder. Use Settings → Setup & status to
see what is ready and what needs attention. The left-hand list moves directly
between pages. Most settings save immediately; a named draft action explicitly
saves a draft. About opens its own informational window.

There is no Apple-device registration step for Desk. Set up this desk creates
this Mac's local Desk identity in your login Keychain. Add computer invites or
joins another Perch; compare and approve the same code on both Macs. Merely being
on the same network does not grant membership.

## A setting or permission seems unavailable

Start at Setup & status, then open the affected feature. Follow the specific
permission it names; Perch and its background helper can have separate access.

If Perch is already enabled in Input Monitoring but external Fn controls or key
learning are unavailable, quit and reopen the Applications copy from Finder.
Launching its binary from a terminal or another app can change the access seen
by that launch. Scrolling/remapping may instead need Perch Helper's access.
For an Automation error, review System Settings → Privacy & Security → Automation;
that permission is separate from Input Monitoring. Do not reset every permission
as a first repair step.

The first Developer ID build has a different signing identity from development
copies. Install it normally and review Setup & status. A queued lid-helper update
needs the explicit completion action in Keep awake with the lid open. A successful
app update does not prove every feature's permission or helper is ready.

## Desk shortcuts or screen switching fail

A warning about enabling a preset shortcut concerns that key combination, not
registration of the Mac. The early 1.2.87 build had a default F1–F3 mapping bug;
the 1.2.89 candidate fixes it. Use Desk's Play button to request a preset, or
choose another combination in Desk settings if macOS reports a conflict.

Editing presets saves configuration; it does not switch physical inputs. Each
screen's selected connection needs to match its real monitor port. A connection
without a mapped computer may still switch the picture; Perch cannot infer where
keyboard/mouse input should go. Input sharing is not implemented in this milestone.

Check that both Perches are running and online. For discovery problems, use
Add computer's Connect by address option when the Macs have a reachable route.
Different routers or client isolation can prevent a connection. Approve membership
on both ends; do not weaken trust or replace identity files to force a connection.
If Keychain access fails, unlock your login Keychain and try opening Desk again.

Identify and explicitly match a shared physical screen. Identical model names are
not sufficient to merge monitors. Check the video cable and any separate USB
control connection. A monitor may need DDC/CI enabled through its own controls.
Use the monitor's physical input selector to recover a picture if necessary.

Read each screen's result: confirmed means the configured readback confirmed the
input; unverified means the picture still needs checking; failed needs attention.
Do not repeatedly switch all screens to diagnose one failure. Reconnect an offline
control computer or correct the affected connection before retrying.

For conflicting offline edits, use Review conflicting changes. Inspect both
arrangements before choosing the one to keep; resolution chooses an arrangement,
not a field-by-field merge. Switching remains blocked until the conflict is
resolved. If this Mac was removed, its old setup is preserved; Start a new desk,
then ask the other desk's owner to invite it again. Do not delete Desk files or
Keychain identities as routine troubleshooting.

## Lid protection stopped, or the Mac slept

Open Settings → Keep awake. A checked Including with the lid closed choice is
saved intent; the status tells you whether protection is currently active.
After a stopped session, use Resume lid protection if offered and appropriate.
Perch does not silently rearm solely because the saved box remained checked.

The guarded mode blocks all system sleep, including Apple menu → Sleep, while
active. Turn it off to sleep manually. Closing on battery or unplugging while
closed starts the 60-second interval for opening the lid. Opening cancels it;
power reconnection changes enforcement. Consult the recorded sequence when timing
is unclear. A lock/password screen by itself does not prove system sleep.

Open Lid activity to inspect observed power/lid changes, deadlines, command results
and macOS sleep/wake notifications. Copy log includes up to 1,024 entries from
the last 24 hours. Review it before sharing. Observational gaps and accepted
commands are not proof that sleep prevention succeeded.

If a helper update is queued, open the lid and use Finish lid helper update.
For a connection failure, use Repair lid protection or Review background helpers
as directed by the status. If cleanup fails, keep the recovery helper installed;
do not remove it to silence the warning. Review sleep reset opens an explicit
system-affecting action: read its explanation before confirming.

## Update or restart fails

An update check, download and installation are different stages. Confirm the
installed version afterward. Use the Updates page's retry action after a network
failure; if signature verification fails, download a fresh official copy and
report the failure. Do not disable signature checks or bypass Gatekeeper warnings.
If the production feed has not yet been published, an update check cannot supply
a release; development builds may instead say checking is not configured.

Restart Perch when it reports a newer copy at its own path, after finishing any
active test/operation. Active lid protection needs a confirmed handoff; if Perch
cannot confirm it, open the lid and review Keep awake. App replacement and a
privileged lid-helper update are separate operations. Follow the queued helper
notice rather than assuming Restart installed the helper too.

## Agent Kill Switch and event collection

Use Test shortcut for a harmless shortcut check. Do not use Panic as a diagnostic:
it can terminate selected work and reset the configured privacy permissions.
Preview targets before relying on your configuration. Resume agent activity
removes Perch's relaunch blocking; it does not reopen apps or restore privacy grants.

Process event collection has its own status and permission guidance. The current
collector uses Apple's eslogger through a signed launcher; it is not the future
Endpoint Security implementation. Missing event coverage reduces tracking coverage.
Follow the feature's instructions instead of granting a development terminal broad
access or assuming a green menu proves complete descendant tracking.

## Before removing Perch

Open the lid and disable Keep awake/lid protection. Confirm that normal system
sleep was restored before removing the privileged helper or its recovery job.
If Perch reports failed or unknown cleanup, retain those helpers and seek support.
Removing the app alone is not a complete uninstall of its optional background jobs.

A diagnostic Terminal command, which only reads system state, is `pmset -g`.
SleepDisabled 0 is the expected restored value, but review Perch's cleanup status
too. Do not run a blanket power reset or delete recovery records to force that
value. Detailed helper/collector removal needs coordinated administrator actions;
there is no tested one-click full uninstaller in this release candidate.

## Report a problem

Use https://github.com/itscool/perch/issues. Include the Perch/macOS versions,
what you tried, the exact message, and expected versus observed behavior. For
monitor problems include model, cable/control path and which preset failed. For
lid problems include the power/lid order and a relevant Lid activity excerpt.
Review screenshots/logs for private computer names or unrelated information.
Never include passwords, pairing approvals, Keychain exports or private keys.
