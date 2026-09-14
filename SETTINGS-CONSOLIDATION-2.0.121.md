# Settings consolidation — September 13, 2026

Scott requested removal of repeated menu operations and redundant detail pages.

| Journey | Final owner | Evidence |
| --- | --- | --- |
| Toggle Fn / Control–Command / navigation / Num Lock | Existing main menu | Removed switches from Settings; menu action/state code retained |
| Recognize and learn keyboard layout | Keyboards | Old Keyboard details and Navigation page selectors route here |
| Change per-app navigation behavior | Keyboards → App exceptions | Existing autosaving editor retained |
| Read lid events | Lid activity, top level | Old Keep awake route opens history; no duplicated feature switches |
| Repair/resume stopped lid protection | Setup → Lid protection | Resume retains the existing readiness/ownership guards; stale links updated |
| Countdown shortcuts | App settings → Hotkeys | Existing owner retained |

The permissions regression initially failed because its expected hidden heading
predated the stable disclosure design. Updated the assertion to require visible,
disabled disclosure while missing access keeps instructions open.

General UI/UX refinement is permanently outside the release QA checklist at Scott's
request. Concrete functional defects and hardware/permission acceptance remain.

## Monitor probe finding

An experimental Get VCP sweep sent to LG's alternate 0x50 channel coincided with
both displays' brightness falling to zero. It was incorrect to assume a Get-shaped
vendor request was read-only. Original brightness was not recorded and has not
been guessed/restored. Production now refuses alternate-channel reads entirely;
a standard-channel query allowlist rejects all other query shapes before I/O.
Explicit alternate input writes remain a separate authorized operation.

The newer display reports UP850K, EF c024 / A1 0074; the older reports UL850,
EF 5124. The latter agrees with the previous firmware-family record for Scott's
owner-identified 27UN850-W. Neither monitor provides a usable current input through
standard VCP 60 (both report 0). Standard F4 values 7/6 have no verified input
semantics. No retail K-W input profile or physical cable code was guessed.

## Verification

23/23 isolated suites passed, including updated consolidation routes, original
menu behavior, permission disclosure, reset return paths and Lid activity.
Desktop/profile and settings offscreen checks passed. The guarded query test
covers all 65,536 address/feature pairs without hardware access.

Input helper 120 reported trusted access and Num Lock support. The installed
collector uses the current fixed launcher and Interactive launchd configuration;
its unsigned executable matches the current app byte-for-byte, and guardian IPC
reports Process events active/eventConnected. Reinstallation is unnecessary.
Lid helper remains protocol 2 and needs its queued protocol-3 update with the lid
open and administrator authorization. Live UI inspection timed out twice; no
collector/helper install was falsely reported.

The final sibling sweep also removed duplicated Start at login, About, Setup and
Reset controls from App settings. Restart remains intentionally available there
even when no replacement app exists; the main-menu restart is conditional.
Desktop recovery support is explicitly advertised by the guardian, so matching
version strings alone never authorize disconnecting without recovery capability.
Final delivered candidate is 2.0.122; 2.0.121 was an intermediate installed build.

Final 2.0.122 verification repeated all 23 isolated suites, desktop/profile and
settings windowless tests, the 58-site dialog contract, and real TLS two-/16-peer
fixtures. The Developer ID build emitted no compiler warnings and passed bundled
Sparkle layout/load-path/nested-signature checks. Atomic installation retained
2.0.121 at /Applications/.perch-previous-isu34yrc/Perch.app; live PID 12800 stays
on 2.0.120. No notarization or publication was performed.
