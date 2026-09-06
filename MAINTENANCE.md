# Maintenance

Review catalog/agents.json monthly against its official vendor sources. Keep reviewedOn and sources current. New catalog targets default to enabled at the user’s request. Preserve every existing explicit on/off choice. Do not silently broaden an existing match. Import with --update-catalog; review changed definitions explicitly in Settings / Advanced.

Before releasing code, build and run --self-test outside the sandbox for native hotkey checks. Tests use synthetic input, mock permission resets, and disposable processes. Never run production panic, reset live privacy grants, or reboot as a test. Verify helper recovery and UI quit persistence independently. Preserve config.json and state.json on upgrades.

GPU statistics are optional driver properties and may change between macOS/hardware versions. Allocation is not physical residency or exclusive GPU memory. No CPU/GPU overlap is claimed. Numerical temperature is unavailable until a reliable sensor is identified. Thermal pressure is not a hardware-damage prediction.

Local releases use the persistent **Perch Local Code Signing** certificate. Compare the app and helper designated requirements before replacing a build; never fall back to ad-hoc signing or weaken signature checks. This preserves local identity across tested updates. Public notarized distribution would require Apple's distribution credentials; that is separate from this local release.

Run `bash Tools/check-release.sh` for the safe regression and app-owned UI workflow checks. Add `--cpu` to check the live CPU sampler. The GUI tests use isolated shortcut requests and render Perch's views directly; they do not synthesize global keys or change permissions. Desktop interaction and physical hotkey delivery are separate from these tests.
