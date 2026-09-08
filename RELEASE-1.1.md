# Perch 1.1

Local feature release, September 2026. About includes the monotonically incremented build number. This release is source plus the locally signed app; public installer, notarization and Homebrew work remain assigned to 1.2.

## Included

- One consistent custom menu, live system readings, light/dark-aware colors, rainbow section headings, and the Perch bird with an awake coffee badge.
- Keep awake as the master switch, with a remembered Including with lid closed preference. Authorization failures preserve actual-state reporting. Sleep and Display are separate sections.
- Independent built-in/external Control/Command and Fn settings. External controls reflect connected hardware; unknown layouts have a setup route, absent navigation keys are hidden.
- Optional external Home/End and Page Up/Down modes with registered source matching and app exceptions. Built-in Fn+arrows and unknown sources retain native behavior.
- Monitor input cycling, current-input readback, model/firmware profiles, explicit connection setup, and guided identification when detection is unavailable. Input settings save immediately and Restore detected offers Undo.
- Central reset controls for device setup and Perch preferences, plus explicit privacy-only and sleep/audio actions. Device reset forgets learned data for fresh detection; bundled profiles remain. Privacy-only reset does not invoke process killing or relaunch blocking.
- Color and workflow fixes, named setup status, stable local signing and safe automated regression coverage.

## Validation and limits

The release script verifies signing and runs logic plus AppKit workflow tests. Coverage includes keyboard protocol fixtures, source separation, paired events, shortcuts, monitor routing and confirmation, reset isolation, sleep authorization failure sequencing, theme rendering, and helper/status mechanisms. Tests do not reset live permissions or system settings, nor perform physical monitor switches. Disposable test processes are distinct from real agents.

Broader monitor/keyboard hardware compatibility is not certified. MSI USB, USB MCCS and NEC network/serial transport coverage is fixture based. The local LG report confirms USB-C code 209 on the owner's 27UN850-W, not universal LG support.

Privacy resets cover supported macOS privacy decisions, not all privileges or ongoing activity. System reset exposes sleep/audio; original keyboard firmware/macOS values were not recorded and are not claimed restorable. Apple's eslogger remains the dominant process-burst overhead; near-zero overhead under arbitrary load is not promised.

Builds currently require Apple Silicon, macOS 26+, Xcode Command Line Tools and the local Perch Local Code Signing identity. No signing private key or generated app is included in Git. A clean-machine installation and distributable signing/update/uninstall strategy remain 1.2 work.

## Next release

The comprehensive design, usability, flow, accessibility, security, reliability, performance, memory, feature-set and bloat review—and its resulting fixes—belongs to [1.2](V1.2-REVIEW.md), together with Homebrew/distribution investigation. Historical investigation files preserve earlier results; they are not a current 1.1 backlog.
