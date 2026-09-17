---
name: release
description: Release Perch publicly. Notarize, publish the GitHub release and Sparkle feed, and update the Homebrew cask. Use whenever the user asks to release, publish or ship Perch, or to get the latest through brew. Always runs the release in a background agent so notarization never blocks the conversation.
---

# Release Perch

## What a request authorizes

- Run this only on an explicit request to release or publish, such as "release it",
  "publish" or "so I can get it from brew".
- That request authorizes the whole flow for one version: notarizing the app and
  the DMG, the GitHub release, the Sparkle feed and the Homebrew cask. It does not
  carry over to later versions (AGENTS.md).
- A release never installs into /Applications and never restarts the user's Perch.

## In the conversation: verify, prepare, hand off

Keep this part short. The slow work belongs to the agent.

1. Let any in-flight code work finish. It must be verified, committed and pushed:
   the pipeline refuses a dirty checkout.
2. Confirm `git status` is clean on `main` and matches `origin/main`.
3. Run the fast gates and stop on any failure; never release around one:
   - `./build.sh --no-bump`
   - `build/Perch.app/Contents/MacOS/Perch --self-test`
   - `python3 Tools/check-kvm.py`, `Tools/check-desk-network.py`, `Tools/check-lid-policy.py`,
     `Tools/check-dialog-contract.py`, `Tools/check-dialog-ownership.py --output DIR`,
     `Tools/check-release-all.py`, `Tools/check-release-pipeline.py`,
     `Tools/check-release-assets.py`, `Tools/check-release-launcher.py`,
     `Tools/check-build-number.py`, `Tools/check-install-candidate.py`
   - `xcrun notarytool history --keychain-profile Perch` succeeds, so credentials exist.
4. Work out the version: `python3 Tools/build_number.py next` prints the build
   number the release will reserve, the next above the last release, the last
   local build and the installed app. The release is `2.0.<that number>`.
5. Write the notes people will read, in plain feature terms, with no internals:
   - `Release/notes.md`: `# Perch 2.0.N — What’s new`, three to six short bullets
     about what changed for the person. Keep the requirements line.
   - `Release/history.md`: add `## 2.0.N — Current` above the previous entry and
     remove `— Current` from that entry.
   Commit as "Prepare Perch 2.0.N release notes" and push.
6. Launch one background agent (Agent tool, general-purpose) with the prompt in
   "Release agent" below, filled in with the version. Do not run the pipeline in
   the conversation, do not wait on the agent and do not poll it. Tell the user it
   is running and what they can do once it finishes.
7. When the agent's completion notice arrives, relay the outcome: the published
   version, whether `brew upgrade --cask perch` now installs it, and anything that
   needs the user. On this Mac, Perch's own updater offers the release; never copy
   a release into /Applications by hand.

## Release agent

Give the agent these instructions:

- Read AGENTS.md, Release/README.md and DISTRIBUTION.md first. The user explicitly
  authorized notarization and publication of Perch 2.0.N, including the Homebrew cask.
- Preflight: the checkout is clean and matches origin/main;
  `xcrun notarytool history --keychain-profile Perch` succeeds; the Keychain holds
  the Sparkle key account `perch-production`.
- Run `./release.sh --output build/releases/2.0.N --publish` in a background shell
  and wait for it. It builds and signs, commits its version bump, notarizes and
  staples the app and the DMG, verifies them, pushes source, and publishes the
  GitHub release and appcast. If an Apple wait times out, rerun the identical
  command to resume. Never use a second output folder for the same version and
  never resubmit blindly; follow Release/README.md for ambiguous submissions,
  rejections (they need a fresh version) and existing drafts (inspect first).
- Verify publication: `gh release view v2.0.N` lists the DMG, ZIP, appcast and
  checksums; `https://github.com/itscool/perch/releases/latest/download/appcast.xml`
  names 2.0.N; the downloaded DMG's SHA-256 matches the published checksum.
- Update `Casks/perch.rb` in `itscool/homebrew-tap`: set `version "2.0.N"` and
  `sha256` to the published DMG's SHA-256, and change nothing else. Validate with
  `brew style` on the cask and `brew fetch --cask` from the public URL. Commit as
  "Update Perch cask to 2.0.N" and push. Then run `brew update` and confirm
  `brew info --cask itscool/tap/perch` reports 2.0.N.
- Add one short paragraph to the Release section of TODO.md: the version, Apple
  acceptance, GitHub, feed and cask verified, and native acceptance still open.
  Commit and push.
- Never install or restart the user's Perch. Report the version, notarization
  submission IDs and results, the release URL, the feed check, the cask commit and
  anything left for the user.

## When something fails

- A gate fails before hand-off: fix and re-verify, or report. Never publish around it.
- Apple rejects a submission: read `xcrun notarytool log ID --keychain-profile Perch`,
  fix the cause and release a fresh version.
- The pipeline or network is interrupted: rerun the same command and output folder.
- Cask validation fails: leave the previous cask in place and report.
