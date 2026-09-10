# Distribution and Sparkle plan

Decision, September 9, 2026: finish persistent Settings navigation, establish
public signing, then integrate Sparkle. Direct downloads and a Homebrew cask
will use the same app. This is a plan, not an implemented network updater or
authorization to publish.

## Ordered prerequisites

1. Establish the owner's Apple Developer Program membership and Developer ID
   Application certificate on the release machine. The September 9 read-only
   identity check found only `Perch Local Code Signing` on this Mac. Do not
   replace it or change live grants while preparing distribution.
2. Choose the stable public app/helper identities and review migration from the
   local certificate. Existing helper IPC trusts code identity; a certificate
   change is not an ordinary compatible UI-only update. Test the explicit
   maintenance path, retained preferences and permission attribution.
3. Add a release build/sign/notarize pipeline, preserving the local build path.
   Sign nested executables/frameworks, use hardened runtime, notarize and staple
   the distribution artifact, then test clean-machine Gatekeeper behavior.
4. Generate and securely back up the separate Sparkle EdDSA signing key. Only
   its public key belongs in the app/repository. Configure an HTTPS appcast and
   versioned downloads, initially hosted through GitHub Releases/static hosting.
5. Integrate a pinned Sparkle version, its license and update-signing tools.
   Provide Check for updates, available version/release notes, download,
   verification, install/restart, cancellation, failure and retry. Automatic
   checking is a saved preference; automatic installation is a separate choice.
6. Add the Homebrew cask pointing to that same packaged release, declaring its
   own updater with `auto_updates`. Test externally replaced app detection as
   well as in-app installation; two installers must not race.

## Perch-specific installation contract

- Reuse the running-versus-installed version model and avoid duplicate notices
  between Sparkle and the existing local-replacement detector.
- Integrate all actual installation/termination paths, including install-on-quit
  and cancelled termination. Sparkle's relaunch-postponement callback is not
  guaranteed to run for every installation path; it alone is insufficient.
- Before permitting active-session replacement, establish the verified candidate
  identity required by Perch's existing exact-code-hash restart ticket, and a
  bounded claim/completion mechanism after Sparkle relaunches the app. Do not
  weaken that identity check or infer it from unsigned appcast metadata. Do not
  depend on undocumented Sparkle cache paths or internal installer classes.
- If a safe handoff cannot be established, retain the running app and explain
  why installation is waiting. Never silently clear the user's saved lid choice
  or extend the original battery deadline.
- Keep lid-helper maintenance separate: compatible app updates retain it;
  required replacement stays visible and waits for the existing open-lid,
  explicitly authorized maintenance flow. Ordinary app updates must not trigger
  unnecessary administrator prompts.
- New public signing, Sparkle integration and the real replacement/handoff
  protocol are implementation work. Invalid downloads/signatures, interruption,
  rollback/recovery, permission continuity, helper compatibility and lid-session
  scenarios are QA. Neither is complete just because the app builds.

## Distribution choices

- Direct download: signed, notarized app in a DMG for initial installation;
  Sparkle-compatible signed archives for updates.
- Homebrew: our own cask tap initially; a second installation route to the same
  app, not a second updater implementation.
- PKG/managed deployment: optional later distribution work if organizations
  need it.
- Mac App Store: unsuitable for the present root-helper/system-control
  architecture under its sandbox and privilege rules.

Primary references checked September 9:
[Apple Developer ID](https://developer.apple.com/developer-id/),
[Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle installation delegates](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html),
[Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook),
[App Store requirements](https://developer.apple.com/app-store/review/guidelines/#software-requirements).
