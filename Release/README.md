# Perch releases

The supported release is Apple silicon, macOS 26 or later. Local developer builds
remain available through build.sh. Developer ID releases require a separate output
folder and use the public settings in config.json; signing keys are never committed.
The app/helper bundle ID remains local.scott.perch, with the Developer ID team in
its designated requirement. The production Sparkle key is in Keychain account
perch-production. Back up that Keychain key securely; do not put exports in Git.

## One-time notarization setup

Create an app-specific password at account.apple.com, then run this in Terminal
with your Apple Account email substituted. Enter the app-specific password only
at the secure prompt, never in chat, source, or command-line arguments:

    xcrun notarytool store-credentials Perch --apple-id YOUR_EMAIL --team-id S42F8BV6J2

Use the resulting Perch Keychain profile for the commands below. A Developer ID
certificate does not itself authenticate notarytool.

## Pipeline

Create a Python 3.10+ virtual environment and install Release/requirements.txt.
Use its python for packaging (the other stages also work with system Python).

    python Tools/release.py build --output /absolute/release-folder
    python Tools/release.py submit-app --output /absolute/release-folder --profile Perch
    python Tools/release.py package --output /absolute/release-folder --profile Perch
    python Tools/release.py submit-dmg --output /absolute/release-folder --profile Perch
    python Tools/release.py finish --output /absolute/release-folder --profile Perch

Submissions return an ID immediately. If Apple is still processing, package or
finish reports the status; retry that stage later without resubmitting. For
rejected submissions, inspect the saved ID using notarytool log and fix the cause
in a fresh version. Never label a signed-but-unnotarized package as ready.

If a submission fails without returning a saved ID, the attempt marker prevents
blind resubmission. Use `xcrun notarytool history --keychain-profile Perch` to
find the submission, then recover its ID and artifactSHA256 from the attempt
record into the corresponding submission JSON. Only clear an attempt marker
when Apple history confirms that no submission was created.

The app is stapled before generating its update ZIP. The branded DMG contains
that stapled app and an Applications shortcut, is independently signed/notarized
and stapled, and has explicit Finder layout metadata. Sparkle verifies the archive,
appcast and exact app identity; the appcast restricts updates to arm64/macOS 26+.

After relevant acceptance and authorization for publication:

    python Tools/release.py publish --output /absolute/release-folder

The tool uploads to a draft GitHub release, then makes the complete release live.
The stable feed is the latest GitHub release's appcast.xml asset. Releasing the
assets together avoids a feed that points to an incomplete upload. Verify the
public feed/downloads and native update check after publishing. Published release
assets are immutable; use a new version for corrections. If a draft upload fails,
inspect the draft and its assets before resuming publication.

## First Developer ID installation

The development certificate and Developer ID are different publishers. Install
the first official build normally; do not loosen helper/Sparkle trust or reset
permissions to conceal that distinction. Install to Applications, then launch
through LaunchServices and review Setup & status. An existing lid helper from another publisher queues an explicit helper update;
finish it with the lid open before enabling a new session. A signed/notarized download does
not replace physical monitor, permission, sleep/restart or accessibility QA.

References: Apple notarization workflow and Sparkle publishing documentation,
linked from DISTRIBUTION.md.
