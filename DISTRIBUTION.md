# Distribution and Sparkle

September 9, 2026: Developer ID Application is available; production signing and
Sparkle configuration are implemented. The 1.2.89 candidate is separate from the
running local build. Apple notarization credentials/acceptance, final publication
and public update acceptance remain pending. Release/README.md documents explicit
build, submit, package, verify and publish stages; only submit/publish stages
upload externally. Tools/prepare-update.py alone remains local-only.

## Implemented locally

Sparkle 2.9.6 is pinned by version and SHA-256 in Tools/sparkle-dependency.py.
build.sh links and embeds it; Tools/embed-sparkle.py signs nested executables and
bundles explicitly and includes its license. Updates lives in the Settings
sidebar, uses native Sparkle dialogs, saves checking preferences immediately and
requires the user to choose installation. See SPARKLE-REVIEW.md for handoff design,
actual signed-fixture installation/retry evidence and remaining acceptance.

Builds without update configuration remain usable and explain that release
checking is not configured. They do not contact a placeholder server. To prepare
a configured build, set both public values before running build.sh --output APP:

- PERCH_UPDATE_FEED_URL: the intended HTTPS appcast URL.
- PERCH_UPDATE_PUBLIC_KEY: the base64 32-byte public Ed25519 key.

The build applies these before signing. Only the public key goes into the app;
never put a private key in source or command arguments. The local build still
uses Perch Local Code Signing. Developer ID release signing of the app and all
nested code and hardened runtime are implemented in Tools/release.py; Apple
notarization and clean-install acceptance remain release gates. The embed tool supports an explicit identity
and --release signing options for that pipeline.

## Prepare an update without publishing

Start with the final signed app, including its feed/public key and version.
Tools/prepare-update.py APP --output DIRECTORY --download-url HTTPS_ARCHIVE_URL
requires either --account KEYCHAIN_ACCOUNT or --key-file PRIVATE_KEY_PATH.
Prefer a dedicated Keychain account for production. Use --notes TEXT_FILE for
release notes and --appcast EXISTING_FEED to retain previous releases.

The tool verifies the app, creates the ZIP, generates an exact signed-app identity
manifest, signs it, checks that its signature matches the public key embedded in
the app, signs the archive, and emits a signed appcast. It refuses duplicate
builds/archives and unsupported multi-architecture apps. It never uploads files.
The URL must point to the resulting Perch-VERSION.zip. Signing output is captured
on failure because upstream tools can echo malformed private-key input.

Sparkle's archive/feed key is independent of Apple's code-signing identity.
Generate and securely back up the production key before the first public build.
Keep the same public key in subsequent versions unless following Sparkle's
explicit key-rotation process. Disposable fixture keys are not production keys.

## Remaining release order

1. Store notarization credentials in the Perch Keychain profile, submit the signed
   app, and obtain Apple's acceptance. Developer ID Application and the production
   Ed25519 key (Keychain account perch-production) are already available.
2. Staple the app, create and verify the branded DMG and signed update ZIP/feed,
   notarize/staple the DMG, and verify Gatekeeper. Packaging/layout and isolated
   failure gates are tested; final notarization acceptance is not yet complete.
3. Verify clean installation and contextual permissions. Helper IPC trusts the
   publisher; incompatible helper signatures queue explicit repair. No migration
   from development signing or weaker trust is required.
4. Publish the verified assets together through the draft GitHub release stage.
   The feed is https://github.com/itscool/perch/releases/latest/download/appcast.xml.
   It is not live yet. Exercise public download and native update acceptance,
   plus interruption/lid scenarios tracked in TODO.md.
5. Prepare the Homebrew cask/tap against verified public checksums. Test external
   replacement detection and in-app updating; two installers must not race.
6. Publication needs relevant QA, zero known defects in the candidate and explicit
   user authorization. A request to commit/push alone is not publication approval.

Optional later distribution: PKG/managed deployment. The current root-helper
architecture does not fit the Mac App Store's sandbox/privilege model.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle installation delegates](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html),
[Sparkle gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/),
[Apple Developer ID](https://developer.apple.com/developer-id/).
