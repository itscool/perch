# Perch 1.1

A native Mac menu bar app for sleep, sound, input controls, and an emergency stop for local AI agents.

Release notes: [1.2 local preview](RELEASE-1.2.md) · [1.1](RELEASE-1.1.md) · [1.0](RELEASE-1.0.md). The whole-app review, broader hardware validation and Homebrew/distribution investigation are tracked in [the 1.2 review](V1.2-REVIEW.md).

Perch is a local Apple Silicon/macOS 26 app. The current [1.2 local preview](RELEASE-1.2.md) includes the grouped Settings, reusable setup overview, multi-monitor switching, and supervised lid grace. The [1.1 release](RELEASE-1.1.md) remains recorded separately. This repository is not yet a notarized, general-purpose installer or Homebrew package. Building currently requires a local signing certificate as described below.

**Keyboard controls** offer independent built-in/external modifier and Fn choices, plus optional external Home/End and Page Up/Down modes. The external heading shows a connected keyboard’s name or a count; absent devices hide their controls and unknown layouts show setup guidance. Twenty-eight bundled layout profiles retain their evidence/confidence labels. Registration does not certify physical event delivery on every device. See [KEYBOARDS.md](KEYBOARDS.md).

**Monitor input switching** lists connected monitors, prefers documented detection, and offers custom inputs, cycle ordering and an optional shortcut. Settings save immediately; unchecked inputs remain available. Restore detected includes Undo. Current-input readback is preferred, with explicit guided identification only when unavailable. The catalog contains 93 monitor profiles, 162 LG firmware-family identities and 23 MSI firmware mappings; these are not claims of universal hardware validation. See [MONITOR-INPUTS.md](MONITOR-INPUTS.md) and [profile provenance](catalog/DEVICE-PROFILES.md).

## Build and run

Each build reserves the next integer `CFBundleVersion` in `Info.plist`; About shows both the release version and build number. Failed builds may leave gaps. Concurrent builds are refused by `build/.build-lock`; remove a stale lock only after confirming no build is running.

This local package targets Apple Silicon and macOS 26+. Building requires Xcode Command Line Tools. This local build also requires the existing **Perch Local Code Signing** certificate in the login Keychain. The build fails if it cannot use that identity; it does not fall back to ad-hoc signing.

```sh
./build.sh
open build/Perch.app
```

To prepare a separate candidate without replacing the app in `build/Perch.app`, use `./build.sh --output /absolute/path/to/Perch.app`. This still reserves the next build number. Building does not launch the app; launching updates outdated Perch helpers and can reapply saved input/awake choices.

Perch installs separate launchd process-monitor and input helpers on first launch. The menu app can quit while the watcher continues to run. **Start at login** controls the menu app; background controls and safety tracking start independently at login.

## Everyday controls

- **Settings → Setup & status:** review setup and missing access in one place, on first use or later when something stops working. Displays, Keyboards, Scrolling, Keep awake, Agent Kill Switch, and App settings each have their own category. Ordinary changes save immediately; editors that commit related changes show Save/Cancel. Back/Close handles navigation without a redundant Done button.
- **Settings → Displays → Switching groups:** choose one display or several, name destination computers, and map their inputs independently on each display. Current-input checks report fresh observations. Mixed or unknown starting inputs require a destination choice; partial switches report each display's result and offer retry for incomplete members.
- **Keep awake:** master switch for Perch’s idle-sleep prevention and supervised lid operation. It queries current assertions and any unowned system sleep override. Turning it off removes lid protection first (administrator authorization when needed), then releases Perch’s assertion and stops your active `/usr/bin/caffeinate` sessions. Cancellation stops the operation; unrelated apps’ assertions are untouched.
- **Including with lid closed:** available while Keep awake is on. Explicit setup installs a supervised privileged helper. A new session can start with the lid open or with the lid closed on confirmed external power. Unknown lid/power state and a closed lid on battery do not allow a new session. Closed on external power stays awake; closing on battery or undocking while closed starts 60 seconds to open the lid. If it remains closed on battery, Perch releases the override and requests sleep. Current lid operation uses a guarded system sleep override with a durable ownership journal and independent recovery. An unowned system override is not adopted or removed by Perch. Quitting Perch ends supervised lid operation. Physical sleep, compatibility, and failure acceptance remain open for this local preview.
- **Turn display off:** turns off the display; moving the mouse or pressing a key wakes it.
- **Mute audio:** queries current output mute and toggles it without changing the volume.
- **Reverse trackpad scroll / Reverse mouse wheel:** independently reverses only the vertical axis. Trackpad gesture/momentum phases distinguish ordinary trackpads from wheels; third-party drivers synthesizing gestures may need hardware testing.
- **Swap Control ↔ Command keys:** separate built-in/external controls, using macOS’s persistent per-keyboard settings. Both sides swap; defaults are unswapped.
- **Use F1–F12 directly:** independent controls under Built-in keyboard and External keyboards. The built-in control updates macOS while preserving connected external modes; supported external keyboards use a native per-device mode or their own firmware Fn Lock. Current modes are queried before any choice is made. See [KEYBOARDS.md](KEYBOARDS.md) for support and persistence details.

Mute and modifier swaps are system settings. Fn controls use macOS or keyboard firmware; external Apple overrides need Perch running when the keyboard reconnects. Idle-awake/scroll choices are saved and reapplied by the background input helper, including after login. Quitting the menu app does not reset those choices, but it ends the supervised lid session. A restarted lid helper begins disarmed; a remembered preference alone does not re-enable it.

Scroll reversal requires Accessibility access for Perch's signed helper. External Logitech Fn control uses Input Monitoring for Perch itself; Settings → Keyboard settings provides its drag-to-Settings workflow and shows per-keyboard success or failure. Modifier swapping uses native macOS settings and needs no event tap. Settings → Input controls provides its draggable identity and verifies readiness. Certificate signing preserves the designated requirement across updates; existing input access remained granted during tested updates. The certificate is local signing, not Apple notarization or Developer ID distribution. Checkmarks indicate selected settings; the inactive remembered lid preference is explicitly labeled. Controls requiring missing access are disabled.

## System display

The System panel stays at the top with muted, non-actionable labels and live readings for the chip/OS, CPU/GPU activity, memory in GiB with pressure, and macOS thermal pressure.

The Audio heading shows the current output volume while the menu is open, with a separate Muted indicator. Outputs that do not expose a volume control are labeled unavailable; no volume is changed by reading it.

**Settings → Show top process and Perch CPU usage** defaults on. The CPU row adds `top: name percent` and `us: percent`. Perch combines the menu app, both helpers, their completed utilities and the specific eslogger job installed for Perch. If that combined group is largest, the row shows only `top: Perch percent`. Collector identity uses a protected boot/PID/start-time record, not a process-name match or deprecated launchd lookup. An older collector installation needs **Process event collection → Update CPU accounting…** before its combined total is available; event collection itself keeps working.

All displayed CPU percentages use total logical CPU capacity, consistent with the main CPU percentage (100% means all cores). The extra readings refresh every ten seconds while the menu is open; the first interval takes two samples about one second apart, and the result appears as soon as it is ready. Native counters cover readable processes; a bounded background `ps` query covers protected processes without requesting additional permissions. Missing counters are marked unavailable/partial rather than zero. Top compares live user-space processes; kernel_task and processes that exit between samples are not included. Sampling stops when the menu closes or the option is off.

## Agent Kill Switch

Open **Perch → Settings → Agent Kill Switch**.

- **Panic…** in the main menu asks for confirmation, then freezes and force-terminates selected local agents and their observed descendants. Unsaved agent work can be lost.
- **Agents, shortcut & panic actions…** selects agents, privacy-reset scope, and the configurable shortcut. The shortcut acts immediately when enabled. New configurations default to resetting privacy permissions for all apps, with Perch last; existing user selections are preserved.
- **Test shortcut…** waits until harmless test mode is ready, then gives ten seconds to press the combination. It reports the outcome, restores the configured shortcut, and returns to settings. No agents are stopped or permissions reset.
- **Preview panic targets…** shows a current preview and recent outcomes. No full command lines or environment variables are logged.
- **Process event collection…** verifies the optional eslogger collector, permissions and a live probe. See EVENT-COLLECTOR.md for setup and coverage limits.
- **Resume agent activity…** releases relaunch blocking and restores launch eligibility for jobs Perch disabled. It does not reopen apps or restore privacy grants.
- **Advanced…** contains recognition-catalog updates, custom agent additions, optional administrator-owned helper files, and a separate confirmed broad reset action. Repair appears when background protection needs it.

Defaults cover Codex, ChatGPT, Claude desktop, Codex CLI and Claude Code. Additional apps and specific agent executables can be selected. Generic runtimes such as node, Python and shells are deliberately not offered as custom blanket targets.

## How stopping works

The watcher attributes fork/exec/exit events using full audit tokens, including PID versions, and retains descendants after their parents exit. Healthy reconciliation runs every 30 seconds, with five-second snapshots when event coverage is unavailable. Panic always drains available events and takes fresh snapshots; active lockdown checks every 250 ms. On panic it persists the blocked state, sends SIGSTOP to matches, rescans for new children, then sends SIGKILL. Birth time and ownership are rechecked immediately before signaling. It verifies exits afterward and reports failures. The watcher excludes Perch and its helpers.

While blocked, matching relaunches are repeatedly stopped. Exact matching, loaded LaunchAgent jobs are disabled/unloaded where possible, with their prior disabled state respected. Unrecognized wrappers, app login mechanisms and new launchers may still retry; polling is not a pre-execution barrier. The blocked state and live tracked identities survive watcher restarts. A boot-time marker prevents old PID records carrying across reboot.

Guardian maintenance reacts to configuration/catalog changes and request-directory notifications. A one-second revision check preserves recovery from missed notifications, in-place edits and recreated files. Unchanged inputs skip configuration processing and directory scans. Tracked-state checkpoints retain their original write timing, but sorting happens only after membership or process metadata changes. Diagnostic details are formatted only when an authenticated client reads status.

The helper is managed with launchd KeepAlive, separately from Codex and the menu process. The shortcut uses Carbon registration rather than the Accessibility event tap. Readiness shows whether the watcher is live, whether the shortcut is registered, how many processes are tracked, test mode, and errors.

## Coverage limits

This is an emergency brake, **not containment**:

- Current-user local processes only. Root/admin agents, remote jobs, SSH jobs already detached remotely, managed services and cloud tasks are not stopped.
- Events lost before Perch starts or during collection gaps cannot be reconstructed. Snapshot fallback can miss children that detach between snapshots. Runtime wrappers outside the recognized launch patterns may need a custom target.
- Relaunched processes may execute briefly before the next sample. A same-user process can disable the launch job, modify user configuration or interfere with Perch. Administrator-owned helper files improve accidental-edit resistance but do not fix that trust boundary.
- A swallowed shortcut, stopped watcher, secure input or frozen OS can defeat software controls. Test the shortcut from the apps you use. Retain a physical shutdown fallback.
- Privacy resets use `/usr/bin/tccutil`; a successful exit means macOS accepted the reset, not independent proof that all ongoing access stopped. CLI permissions may belong to their terminal host. No private TCC database is edited. Admin rights, system extensions, remote sharing and every setting in Privacy & Security are not covered.
- No network isolation, remote cancellation, automatic reboot, permission restoration or rollback of prior file/network actions is attempted.

## Files and removal

User jobs: `~/Library/LaunchAgents/local.scott.perch.guardian.plist` and `local.scott.perch.input.plist`. The optional root eslogger collector is described in EVENT-COLLECTOR.md.

Configuration, tracked identities, bounded JSONL event history and helper bundle: `~/Library/Application Support/Perch/Safety/`.

Live helper status stays in memory and is queried asynchronously over authenticated local XPC connections. No periodic helper status files are published. Persistent configuration, ancestry checkpoints, panic requests and the temporary shortcut-test lease retain their existing file storage.

Permission reset command logs: `~/Library/Application Support/Perch/Panic/`.

Lid activity: **Settings → Keep awake → Lid activity**, with live updates and Copy log. The root helper and watchdog share `/var/db/local.scott.perch.lid-activity/events.json`, retaining at most 1,024 events from the last 24 hours. Events describe observed lid/power changes, elapsed countdowns, command outcomes and separate macOS sleep/wake notifications. History remains readable when the helper is offline; gaps in observation and command acknowledgment alone do not prove physical sleep behavior.

To stop the background helper deliberately:

```sh
launchctl bootout gui/$(id -u)/local.scott.perch.guardian
launchctl bootout gui/$(id -u)/local.scott.perch.input
```

Remove those specific LaunchAgent plists to prevent it starting at login. This stops background awake/input controls and safety tracking; it does not reset persistent lid/mute/Fn settings. Reopening Perch repairs a missing helper. If you used the protected installation, its optional copy is under `/Library/Application Support/Perch/Perch Helper.app`.

## Verification

```sh
build/Perch.app/Contents/MacOS/Perch --self-test
build/Perch.app/Contents/MacOS/Perch --settings-self-test
build/Perch.app/Contents/MacOS/Perch --safety-preview
```

Self-tests use synthetic ancestry and disposable local shell/sleep processes. They check descendant selection, detached history, PID reuse, exclusions, freeze/termination, preservation of unrelated processes, hotkey conflicts, reset sequencing with a mock executor, input transformations and system-state reads. No live agents are stopped and no real privacy reset is performed by tests. The preview prints only target-group counts.

`bash Tools/check-release.sh` verifies signing and runs both safe suites. AppKit checks exercise live menu updates during tracking, Settings navigation, light/dark rendering, input-readiness states, and shortcut-test cancellation/success/timeout/cleanup using isolated requests. They do not prove physical keyboard delivery or a real system-wide privacy reset.

See `V1-NOTES.md` for measured performance and validation limits, and `EVENT-COLLECTOR.md` for the collector architecture. `REVIEW.md` is an earlier implementation review. The whole-app review and its resulting changes are assigned to **1.2**; its pending scope is recorded in [V1.2-REVIEW.md](V1.2-REVIEW.md).


### Central reset controls

Settings → Reset settings has two in-app groups: Device setup (detected monitor configuration, learned keyboard profiles, mappings and confirmations) and Perch preferences (feature choices, shortcuts and agent settings). Neither is preselected. Device reset quits Perch after forgetting setup; the next launch starts with fresh detection. Bundled profiles remain, and unknown keyboards require setup again. Preferences-only reset preserves device setup.

The same area offers explicit Perch-only privacy reset and system sleep/audio changes. System changes are not claimed as an undo of Perch-owned values: previous keyboard firmware/system values were not recorded and are left alone. All-app privacy reset is also directly available in Agent Kill Switch. It invokes tccutil without calling panic, stopping agents, or disabling launch jobs. Its scope is privacy decisions for the current account, not every permission or system setting. Perch-only reset uses its bundle identity, shared by its helpers; eslogger is a separate system tool and is not reset as part of that scope.
