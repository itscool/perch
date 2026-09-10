# Signed release preparation — September 9, 2026

About uses the native standalone modeless panel without acquiring Settings' modal
interaction scope. Other shared alerts were reviewed as operative confirmations,
tests, errors or recovery notices. Native About open and close passed; isolated
Settings-state checks passed. Mouse selection through the UI inspection tool
reported offscreen elements, so that complete mouse journey remains QA.
The settings-flow skill captures the passive-information lesson; structural
validation passed. VM adapters were moved to backlog at the user's request.

A user-reported registration message exposed a Desk defect: Carbon registration
looked up default F1–F3 in the emergency shortcut picker, which omits them. The
Desk picker/runtime now share an explicit F1–F20 map. Tests check all 20 against
Mac virtual key codes and reject unsupported values. Registration failure cleans
up the whole set instead of leaving earlier presets active.

Release review found that the lid installer rejected all symlinks, including
Sparkle's expected framework structure. The allowed set now contains only the
pinned framework's exact relative links; extra links or redirected targets are
rejected before ownership changes or execution. Strict nested signing verification
follows. Tests execute that validation against disposable valid, redirected and
unexpected-link bundles; no installer or power action is executed. A helper
publisher mismatch also queues an update and prevents reusing it for cleanup.

All 23 isolated functional suites passed with the fixes, including About state,
key mapping and the lid/helper cases. No live grants, power setting, lid session,
monitor input, input helper or safety helper was changed. AGENT MODE was ended.
The running app remains the previous 1.2.87 local build.

Developer ID Application is available for team S42F8BV6J2. Production Sparkle
key generation used the dedicated perch-production Keychain account; only the
public key is committed. No private key was exported. The release tool signs
nested code with hardened runtime/timestamps, gates each notarization stage,
verifies signed archive/feed and creates a branded DMG. Publishing requires
unchanged build inputs and verified artifact hashes, uses a draft until uploads
finish, and refuses overwriting a public release. Failure tests cover pending,
rejected and accepted notarization, changed archives, safe retry and uncertain
submission outcomes. Developer ID signing succeeds; final candidate is 1.2.89. The disposable DMG
mounted read-only, preserved the signed app and Applications link, and contained
the specified Finder icon layout. This is packaging evidence, not notarization.

The production Sparkle signing smoke test is waiting for macOS Keychain
authorization for sign_update. SecurityAgent inspection is blocked by the UI
tool, so that prompt requires the user. No signing success is claimed yet.

Notarization profile Perch was not found in Keychain. Apple submission/acceptance,
stapling, final Gatekeeper verification, the public GitHub feed and public native
update/download acceptance remain pending. Signing and packaging fixtures do
not count as notarization or release acceptance. The broader two-Mac, hardware,
clean-install/lifecycle and accessibility QA remains separately tracked in TODO.md.
