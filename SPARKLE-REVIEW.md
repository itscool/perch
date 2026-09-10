# Sparkle integration — Perch 1.2.84

September 9, 2026. Implementation and isolated evidence; no installed Perch or
live helper replacement, privacy reset, hardware change or public release.

## Implementation

- Pinned Sparkle 2.9.6 archive with SHA-256 verification, framework embedding,
  explicit inside-out signing and bundled license. Production uses HTTPS feeds.
- Updates sidebar page: immediate-save automatic-check preference, manual check,
  native available/download/verify/install/relaunch flow and error recovery.
  Development builds without a feed/public key explain why checking is unavailable.
  Automatic downloading/installation is disabled; the user chooses installation.
- Standard Sparkle windows temporarily own the Settings interaction. Closing or
  finishing them restores Settings. Background reads do not disable Restart or
  helper maintenance; actual update interactions do. Scheduled offers defer if
  another Settings/helper/restart operation owns the interaction.
- Require signed feeds and verification before extraction. A separate Ed25519
  signature binds the exact replacement code hash, bundle, build, publisher
  requirement and lid protocol. This identity is verified independently even if
  Sparkle falls back while handling a feed-signature failure. The archive remains
  subject to Sparkle verification; no private cache or installer APIs are used.
- The final app-termination gate covers install/relaunch and install-on-quit.
  Active lid sessions request the existing 60-second exact-identity helper ticket
  only when installation is ready to terminate. A private bounded record binds
  the ticket to boot, app path, build and new code identity. The new app claims it
  after Sparkle's LaunchServices relaunch. Battery deadlines and helper watchdog
  behavior remain independent. Failed handoff keeps the old app running and
  returns to Updates with explanation and Retry installation. Quit also retries
  the waiting installation, explicitly explained on that page.
- Compatible updates leave lid-helper maintenance separate. A publisher/protocol
  mismatch is refused by ordinary updates; there is no legacy migration path. No automatic rearming after an expired/failed claim.
- User-facing versions use major.minor.build, e.g. 1.2.84, from bundle metadata; signed bundles and appcasts expose that same full version to
  Sparkle. CFBundleVersion remains the monotonic update comparison counter.

## Findings resolved during implementation

P1: A relaunch-only callback would miss some install-on-quit paths. The final
NSApplication termination gate owns the handoff for every pending installation.

P1: Unauthenticated candidate hashes could authorize the wrong replacement app.
The signed identity manifest pins publisher, protocol, build and exact code hash.

P2: In the first real failed-handoff fixture, Sparkle's install window had closed
and the old app stayed running without a visible next step. Recovery now restores
Settings and exposes Retry installation. The real retry fixture subsequently
completed replacement and claimed the exact new identity.

P2: Formatting only Perch's About text would leave Sparkle displaying “1.2 (83)”.
The build now writes 1.2.84 into the signed bundle and feed display version too.

## Evidence

- Real locally signed old/new disposable apps, real Sparkle 2.9.6 standard UI,
  loopback HTTP server (fixture-only exception), signed feed, signed archive and
  independently signed identity. Clicked Install Update and Install and Relaunch
  under AGENT MODE. Verified replacement from fixture build 1 to 2, LaunchServices
  startup, and exact-code-identity mock lid claim. No physical helper was used.
- Injected mock prepare failure: original build stayed installed/running; no
  completion record or accepted termination. After the recovery fix, native
  Retry installation succeeded, the new app claimed the same pinned identity,
  and a completion marker plus ordered event log confirmed the result.
- Native Sparkle text observed: “1.2.2 is now available—you have 1.2.1”, without
  duplicate parenthesized build numbers.
- The fixture's recovery window is a test scaffold; production recovery uses
  the shared Settings host. Whole-app isolated tests cover that host and the
  unconfigured Updates page, including its explanation, disabled unavailable
  choices, no orphaned retry controls and Back.
- Crypto/state regressions cover valid identity, tampering, wrong key/build/
  publisher/protocol, oversized payload, reboot/path/code/build mismatch,
  expired/future/nonfinite tickets, bounded file reads and symlink refusal.

The final 23/23 isolated suites passed. Sparkle’s signature tool accepted the
original archive and rejected a modified copy. The updated packaging tool was
replayed successfully on a signed fixture. Final build results are recorded in
RELEASE-1.2.md. Reproduce with
Tools/check-sparkle.py (builds fixtures only) and Tools/check-functional-review.py.
Native execution requires the repo's AGENT MODE protocol.

## Remaining QA and release dependencies

This is not certification of live sleep continuity. Real active-lid updates,
power transitions, restart interruption, permission attribution, installer
cancellation, invalid/truncated network delivery and helper maintenance remain
release acceptance. The user now reports Developer ID certificate creation is available; the
actual identity and notarized release acceptance have not yet been verified. Production feed hosting, a securely backed-up release EdDSA
key, public signing, notarization and publication approval are still
required. Local fixture keys are disposable, private, and outside the repository.

The current manifest deliberately supports Perch's arm64 app only. Extend it to
per-architecture hashes before shipping universal/other-architecture updates.
