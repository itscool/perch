# Distribution and Sparkle

September 9, 2026: direct download/Homebrew plus Sparkle. Local integration is
implemented while Apple Developer enrollment processes. Public release still
requires Developer ID signing, notarization and explicit publication approval.
Nothing in the local preparation tools uploads or publishes an app.

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
nested code, hardened runtime, notarization and clean-install acceptance are the
next release step after enrollment. The embed tool supports an explicit identity
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

1. Finish Apple enrollment and obtain Developer ID Application. The September 9
   identity check found only Perch Local Code Signing on this Mac.
2. Finalize public app/helper identities and test clean installation.
   Helper IPC trusts the publisher; changing certificates is not an ordinary
   compatible UI-only update. The signed update manifest deliberately refuses
   incompatible publishers/protocols. No development-build migration is required.
3. Complete and test the Developer ID/hardened-runtime/notarization pipeline,
   including nested executables, framework and helper; staple artifacts and
   verify clean-machine Gatekeeper and permissions. Preserve the local build path.
4. Secure the production EdDSA key and finalize HTTPS appcast/archive hosting.
   Build configured releases; exercise real update, interruption and lid/session
   scenarios listed in TODO.md. No public feed has been activated yet.
5. Prepare a polished branded DMG with a clear drag-to-Applications layout and
   Setup & status on first launch. Keep feature permission requests contextual.
   Developer ID Application signs app/DMG; a PKG wizard would also need Developer
   ID Installer. Prepare an initial Homebrew cask/tap pointing to the
   same app, with auto_updates. Test externally replaced app detection as well
   as in-app installation; two installers must not race.
6. Publish only after relevant QA, zero known defects and explicit approval.

Optional later distribution: PKG/managed deployment. The current root-helper
architecture does not fit the Mac App Store's sandbox/privilege model.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle installation delegates](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html),
[Sparkle gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/),
[Apple Developer ID](https://developer.apple.com/developer-id/).
