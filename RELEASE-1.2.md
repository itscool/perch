# Perch 1.2 — local preview

September 8, 2026, build 44. This is a local build for trying the implemented 1.2 changes; the whole-app review and physical acceptance checks remain open in [V1.2-REVIEW.md](V1.2-REVIEW.md). The previous release is [1.1](RELEASE-1.1.md).

## Build 44 correction

Build 43 passed a task port to `IOPMFindPowerManagement`, which requires the default IOKit port. That prevented enabling and releasing lid protection and blocked cleanup with “macOS power control is unavailable.” Both lid control and sleep requests now share the corrected connection setup. A read-only check reproduced the failed old call and successful corrected call on the affected Mac. The regression suite now exercises the real connection setup and closes it without sending a power command. When cleanup finds an older installed lid helper, it stages the current verified helper and uses that code for cleanup before restarting disarmed, rather than retrying the old binary. Actual sleep/wake and failure acceptance remain open.

Build 44 validation: all 20 isolated suites, production compilation and strict signatures pass. The affected Mac's app and background helpers were updated to build 44; the normal lid-helper repair upgraded the privileged helper, successfully removed the stale session record, and restarted the service and watchdog disarmed. Existing input access remained granted and active. The UI returned to ordinary Keep awake controls. No sleep countdown, privacy reset, panic, or monitor switch was tested.

## Where to find the changes

- **Settings → Setup & status:** a reusable overview of required setup, missing access, helper response, and the next relevant action. It opens on first use and remains available for checking or repairing setup later.
- **Settings:** one home for Displays, Keyboards, Scrolling, Keep awake, Agent Kill Switch, and App settings. Maintenance and recovery actions sit with the feature they affect. The tuned main-menu layout remains, including the all-app privacy reset.
- **Settings → Displays → Switching groups:** select one monitor, either monitor, or several together; name destination computers and map each monitor's input independently. Check current inputs, see each monitor's result, and retry incomplete switches. The existing cycle action can use an explicitly selected group.
- **Monitor settings:** ordinary choices save immediately. Connection/input-list and group editors use explicit Save/Cancel because they commit related changes together. Ordinary pages use shared Back/Close and the window close control; redundant Done buttons are removed.
- **Settings → Keep awake:** the supervised lid mode stays awake while closed on external power. Closing on battery or undocking while closed starts 60 seconds to open the lid. Remaining closed on battery releases the override and requests sleep. Enabling the new mode requires explicit setup with the lid open; an old global sleep override must be removed explicitly first.

## Functional repairs

Agent recognition is more conservative about Node/Bun entry points. Helper readiness checks the installed/running build. Settings and permission links reach the relevant page, long dialogs scroll, validation retains drafts, monitor state distinguishes fresh observations from previous commands, and disconnected keyboard layouts remain manageable. First authorization focus has a source fix; actual first-prompt typing still needs user-operated confirmation.

## Local build and remaining checks

The app uses the existing local signing identity. It is not notarized or published. Normal launch updates outdated Perch background helpers and can reapply saved input/awake behavior. Preparing the app does not launch it, install the privileged lid helper, remove a legacy override, or enable lid mode.

The lid implementation does not await special Apple approval. Native timed assertions with the identified closed-lid/battery options require Apple-internal entitlements; investigating a supported replacement is an optional TODO and may be unnecessary if the supervised implementation is reliable. The current private clamshell interface, real sleep/wake and crash recovery, two-computer/multi-monitor hardware behavior, clean installation/uninstall, performance, and accessibility still require acceptance. Signing and passing simulations do not establish those results.

All 20 isolated functional suites passed for these sources. Production compilation and strict local signature verification passed; the designated signing requirement matches build 41. The runner exercises logic and AppKit flows while blocking live hardware, installation, permission and panic mutations. Build 42 was reserved by an unsuccessful compilation using a relocated module cache; after moving that generated cache aside, build 43 completed. The running build 41 and its helpers were not replaced or restarted while preparing the preview.
