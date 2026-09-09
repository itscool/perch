# Installed-app replacement notice

September 9, 2026. Build 80 candidate; build 77 remains installed.

When another tool installs a newer Perch at the running app's own location,
Perch offers a restart independent of how the replacement was delivered. This
component neither discovers downloads nor installs files.

- Capture the running version/build once during process initialization. Read the
  on-disk Info.plist directly instead of reusing Bundle's cached metadata.
- Compare numeric release versions, then numeric builds. Equal/older versions,
  malformed metadata and different bundle identifiers do not offer a new build.
- Check at startup, periodically (10 seconds), and on menu opening, with coalesced
  background work. Unchanged file revisions reuse the last validated result.
- A newer bundle must pass the existing same-publisher, strict nested-code
  signature check. Incomplete installations are retried; a file change during
  verification rejects that sample. Restart independently verifies again, so a
  previously displayed offer cannot authorize different unverified code.
- Under Perch in the main menu, conditionally show Running / On disk information
  and a Restart Perch command next to the existing app commands. Background
  completion does not insert/remove rows during menu tracking. Cached information
  is ready on the next opening; no unrelated control is disabled while checking.
- Show the first verified detection once per process run, with both versions,
  Restart now and Later. Defer while a menu, Settings window, modal interaction
  or restart/helper handoff is active. Later, Back or Close does not nag again
  in that run; the menu offer remains. No dismissal is saved across runs.
- Both menu and dialog restart use the existing verified restart worker and
  bounded lid-session handoff. Open App settings for visible progress/errors if
  restart cannot complete. The existing Settings restart remains available.

Validation covers release/build ordering, equivalent dotted versions, equal and
older copies, invalid/oversized/missing metadata, wrong app identity, failed then
successful verification, replacement during validation, unchanged-file caching,
once-per-process/deferred notice, dismissal and conditional menu stability.
The file fixtures inject signature outcomes, not the production identity check;
existing signed restart-worker tests cover that mechanism separately. No live
bundle replacement, app restart, helper maintenance, permission reset or hardware
change is part of this task. Active-session restart acceptance remains on TODO.

The dialog route is recorded in Tools/dialog-routes.json. This adds one conditional
menu action; the previous build-78 count of 21 actions is a historical count.

Final verification: all 22 isolated suites passed. Production build 80 compiled
without warnings; strict executable/app signatures and ZIP integrity/version
checks passed. Build 80 was packaged, not installed.
