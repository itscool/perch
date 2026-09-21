# Perch release history

## 2.0.283 — Current

- A preset counts as active when the Mac it chose, and only that Mac, can see each screen, for monitors that never report their input.
- Keyboard and mouse sharing follows, since it waits for an active preset.
- Hearing that another Mac is newer looks for the release and says it is available, without installing anything.

## 2.0.278

- A screen's reachability is checked the same way the switch is sent, so working switches are no longer reported as failed.
- A Mac with no screens of its own in a preset drives the Mac that has them.
- A Mac that has updated tells the others at once, and one that is behind fetches the release itself.
- Macs share their reasoning, so one log explains the whole desk.

## 2.0.273

- A switch waits for a reclaimed screen to return, so a switch that worked is no longer reported as failed.
- Dragging from a monitor input picks up a wire only when the preset being edited uses it; otherwise it draws a new one.
- When a switch fails, Macs ask each other what they decided, so one log explains the whole desk.

## 2.0.269

- A screen is switched back from another Mac reliably: Perch takes back its own picture there before commanding it.
- A Mac that cannot see a screen says so, and lists what it can see.
- Macs tell each other which Perch they run, and one that is behind looks for the update itself.

## 2.0.265

- A screen left showing another Mac is switched back reliably, so presets apply fully and sharing starts.

## 2.0.262

- The pointer crosses between Macs and stays there, even through adapters and screens macOS renamed.
- Crossing continues from where you crossed instead of landing mid-screen.
- The pointer hides on leaving a Mac and appears on the next without flicker.
- Monitors are recognised by serial number through replugs, input changes and adapters.

## 2.0.251

- LG 27UP850-W and 27UL850-W screens are recognised by hardware identity and set up with codes tested on real monitors.
- Switches no longer fail while Perch updates its display records, and unconfirmable monitors get the command twice.
- Perch says when no Mac can reach a screen, instead of reporting a failed switch.
- Sharing finds each cable's display by itself, names what is stopping it, and names a sharing version mismatch.
- Screen locks are logged with the idle time and what Perch was doing.

## 2.0.225

- Preset switches no longer stay on Switching when one Mac cannot switch a screen and another cannot take it over.
- The pointer lands where you crossed in both directions.
- The pointer is hidden on the Mac it is not on, as well as parked.
- A wire pulled out of an input is visible in your hand, and your other presets' wires stay on screen.

## 2.0.221

- Crossing to another Mac’s screen carries the pointer on from the edge you crossed instead of jumping to the middle of that screen.
- Dragging a connected input changes the preset you are editing; the cable moves only when it has to.
- The preset being edited is the drawn teal line and what is on the displays now is a green glow behind it.

## 2.0.218

- One shared Desk pointer that any keyboard or mouse on any Mac moves; control moves over faster, and using another Mac’s mouse no longer pulls control away.
- Desk wires draw from either end; a connected input moves by dragging it or disappears when dropped in empty space.
- Clear a preset, or start the whole desk over with Reset desk.
- Changing a screen’s input profile replaces its inputs instead of duplicating ports.
- Screen outlines on the Desk canvas no longer get cut off.

## 2.0.205

- The Desk pointer no longer stays behind on the Mac you left and carries on from where it was when control moves, including when you pick up the other Mac’s mouse.
- Keyboard and mouse sharing only takes over when screens sit next to each other in Desk.
- Old Accessibility and Input Monitoring entries from a differently signed Perch are removed automatically.
- Prevent idle lock says how long the Mac stays unlocked.

## 2.0.204

- Redesigned Desk page, steadier Desk connections and keyboard and mouse sharing that follows the pointer; every Mac on a desk needs this version.
- Quit turns Perch off and first lists what stops; an Agent Kill Switch block stays in place.
- Closed-lid mode no longer ends on its own and resumes by itself on power; the lid helper updates once.
- New Prevent idle lock option.
- Hotkey conflicts name their feature, Desk shortcut problems show on the right shortcut, and held keys no longer repeat panic or preset actions.
- Background helpers repair themselves after a failed restart; Quit works while a Settings dialog is open.

## 2.0.151 — Release history

- Corrected the Sparkle update dialog to show concise version-specific “What’s new” notes.
- Added the complete Release history page under Settings → Updates.
- Includes the direct Desk preset graph, signed packaging and dependency repair improvements.

## 2.0.149 — Desk graph

- Direct Desk preset graph with three numbered preset connectors per computer.
- Preset routes can be assigned by dragging to physical monitor inputs or using the connector menu.
- Selected-for-editing and active-now routing states are shown separately.
- Duplicate monitor preset controls were removed; physical cable ownership stays independent.
- Signed Sparkle release packaging and automatic dependency repair remain enabled.

## 2.0.96 — Release foundation

- Settings and Setup were consolidated around clear readiness, recovery and reset flows.
- Sparkle update identity, guarded restart handoff and signed release packaging were added.
- Desk gained monitor groups, presets, monitor control paths, desktop reconciliation and shared input foundations.
- Lid activity logging, countdown recovery and helper maintenance became automatic and bounded.

## 1.2.87 — Local preview

- Persistent Settings navigation, multi-monitor Desk setup, monitor input profiles and menu appearance controls.
- Supervised closed-lid sleep protection with a bounded undocking grace period.
- Reusable setup checks and recovery paths for permissions, helpers and keyboard layouts.

## 1.1 — Local feature release

- Agent Kill Switch, keyboard/navigation support, background helpers and system controls.
- About, setup guidance and the first reusable recovery actions.

## 1.0 — Initial release

- Perch menu-bar controls for process safety, keyboard behavior, display/audio choices and supervised sleep behavior.

## Detailed 2.0 development history

Settings fits full sidebar labels and distinguishes neutral checking progress from actionable warnings. Shortcut editors share the Desk control layout; repeated feedback uses content-sized status areas that grow for errors and shrink afterward.

Hotkeys removes the emergency editor’s fixed empty status area and places countdown shortcuts side by side. Actual errors grow the editor as needed. Recognition shows pending matching-rule changes beneath Import, with explicit Apply confirmation and inline success feedback.

Menu appearance adds normalized fade distance (0–1), aligned area selectors and a single grey-highlight toggle/shade row. Titles begins with spacing for colored sections or Show System title for System; System no longer adds a title gap. Ribbon uses short 12% edge fades; Horizon uses a broad 65% right fade. Perch original, Quiet, Signal, Soft tiles and Outline keep their compositions in both themes.

Keyboard layouts now match hardware model and layout metadata independently of editable device names. Renamed MX Keys keyboards retain bundled and learned navigation mappings in both setup and the input helper. Permission setup keeps its direct drag/copy target and removes redundant Finder-reveal actions.

Restart handoff isolates its claim connection from status polling and fences delayed pre-restart responses before adopting the session.

Background-helper recovery runs automatically after a sustained outage; cancelled or failed authorization is not repeatedly requested. Background setup reports progress instead of offering generic repair and duplicate privacy-reset controls. Helper-file protection has a Security page. Start at login opens macOS Login Items directly when registration fails or needs approval. The reset destination is now named Reset Settings.

Saved lid protection resumes automatically once setup is ready, and after opening the lid or reconnecting power following a stopped session. Active countdowns and battery deadlines are preserved; an expired session cannot repeatedly restart while closed on battery. Setup no longer has a Resume button or an enabled update action for a current helper. Installed collector configuration updates are offered automatically after lid maintenance; optional new components remain optional. Automatic release checks default on, preserving existing user choices.

On launch, Perch brings an outdated installed lid helper into Setup and requests administrator authorization automatically. Cancellation or failure leaves a retry action without repeatedly prompting in the same run. Guarded replacement waits for both launchd unloading and exact old-helper process exit before transferring ownership.

Lid-helper updates can hold sleep protection through replacement with the lid closed. A separate update guard preserves existing countdown/battery deadlines and ends the temporary allowance after handoff, failure or a fixed 60-second limit. Recovery survives replacement and reboot; unrelated system overrides are not taken over. Administrator authorization is still required.

App settings removes repeated login, About, Setup and Reset controls. Its CPU preference and always-available restart remain; the main-menu restart continues to appear for a changed installed app.

Desk desktop handoff now uses fresh monitor input evidence to remove a screen from the losing Mac’s desktop, with saved configuration and independent guardian recovery. Unknown inputs, offline destinations, mirrored targets and the last usable screen remain connected. Requires the matching background helper. LG monitors that cannot report their selected input remain unconfirmed and connected.

Keyboards now has one page for device readiness and layout learning, with App exceptions beneath it. Repeated modifier, function-key and navigation switches are removed from Settings and remain in the Perch menu. Lid activity replaces the redundant Keep awake category; stopped-session recovery stays in Setup → Lid protection. Helper-update messages explain the guarded replacement and administrator authorization.

Monitor reads now reject LG’s alternate write channel and permit only the specific standard-channel queries used by Perch. This prevents a supposed input read from issuing a vendor command with unrelated hardware effects. LG alternate input switching remains available, but unreadable current input stays unconfirmed.

Setup sidebar readiness badges stay inside the visible sidebar at narrow widths and with either scrollbar style. Labels leave room for the status icon.

When a monitor switch cannot provide current-input evidence, Desk now says that
the local display remains connected for safety and names the affected screen so
the user knows exactly what to check before retrying.

Desk computer details now include Connection activity with recent authenticated connections, closure causes and durations. Unexpected losses remain available for diagnosis after reconnecting; expected local shutdowns and redundant routes are identified separately.

Monitor detection recognizes the UP850K model token reported by LG capabilities, accepts usable ports beside a reserved zero entry, and preserves the correct protocol for those port codes. A model report that contradicts a firmware-family lookup prevents automatic use of the conflicting profile. Exact reported 27UP850-W names now reach the existing profile matcher. Unreadable monitors and unverified K-W input codes still need investigation.

Active lid protection now reports setup readiness instead of an impossible-to-resolve Unverified status. Current helper failures and queued updates still need attention; stale helper errors do not masquerade as current observations. The macOS forced-sleep limitation remains explicit. Idle sharing similarly distinguishes readiness from active control.

Desk input recovery names the disconnected coordinator or the actual conflicting setup. Healthy replies clear old remote failures, expired readiness is discarded, and Retry desk connection touches only missing trusted links. Refresh sharing status does not start control or change permissions. Monitor failures name the affected screens and offer per-screen review, read-only input checks through paired computers, and a separate retry of the requested input. Fresh reads can resolve prior failures; old-configuration or pre-attempt reads cannot.

Keyboard and mouse computer-button following share illustrated examples, three short setup steps, per-Mac matching and a visible control destination. Mouse attachment observations use passive device properties, while ambiguous devices remain unmatched. Physical receiver/Bluetooth behavior still needs hardware acceptance. Preset warnings and In use now share the existing count/status line so cards keep their height.

Desk inspector content is measured at its actual width, fixing the clipped Keyboard & mouse heading and keeping wrapped explanations and final actions inside the scrolling document. Narrowing, expanding and collapsing preserve usable scrolling.

Desk connectors show every assigned preset number separately from the editing highlight. Redundant selection circles are removed, and monitor summaries combine preset, input and computer on one line. A separate In use badge marks the confirmed preset. Preset cards select across their surface, with hover feedback on cards, Play and rename controls. Monitor names are edited using a pencil on the monitor itself; the inspector keeps a read-only heading.

Setup sidebar status indicators now lay out inside their actual row bounds. AppKit's cell resizing previously pushed correctly populated icons beyond the visible edge. Light/Dark and resize checks cover each readiness state without rebuilding rows or changing selection.

Keep awake and other task pages grow to contain all their rows, fixing enabled Lid activity and setup buttons drawn outside their clickable bounds. Resume shows when protection is updating or running; the saved lid choice stays separate from the current session.

Keyboard and mouse sharing starts directly in Desk, with a local session switch, per-computer readiness and a control action for the selected screen and editing preset. Input options holds pointer speed and optional keyboard computer-button following; adding a connected keyboard matches this Mac immediately and shows which other Macs still need matching. Setup links return to Desk.

Monitor port menus offer Switch to this input. It changes only that monitor, keeps presets intact, and returns shared input locally. The same paired switch leases and fresh read-before-write policy apply, including unassigned ports. Changed setup cancels stale commands and cannot leave a lease occupied by an invalid fallback request. Both Macs need this version for the new one-off command.

Monitor setup now offers Detect input profile directly, with fresh local or request-matched remote inspection. It applies a verified named profile or monitor-reported ports; unknown results keep the current setup. Control through lists only this monitor’s mapped video paths, labeled by computer and port. Independent USB/network/serial protocols choose their controller computer and explicit endpoint. Protocol override marks and preserves the default; serial identity stays in Detection details.

Already-selected monitor inputs are confirmed by a fresh read without a switch command or settling delay. Read-before-write behavior now has direct regression coverage and rechecks cancellation after the initial read.

Desk now places half-circle cable connectors on device edges, with hover feedback and monitor-body dragging outside actual controls. Dragging an occupied input picks up its cable; a valid drop rewires atomically, while Esc or an invalid drop preserves the original.

Preset inputs are chosen directly above each connector. The editing preset highlights its inputs, wires and computers, with stronger emphasis on the selected screen’s route. Unchanged excludes a screen from switching and shared input. Preset warnings stay on their cards; Add screen and Add computer both live inside the desk.

External keyboards gain an opt-in Num Lock navigation mode. Num Lock/Clear toggles each identified external keypad independently; operators and number-mode punctuation stay native. Unknown and built-in senders pass through. This needs the matching input helper; hardware LEDs are not synchronized.

Desk wires refresh their target geometry during layout and scrolling. Physical-size editing accepts a diagonal in inches and automatically uses the display’s reported panel ratio when available, retaining exact millimetre editing.

Settings now shows readiness icons beside Setup stages. Permission instructions expand beneath a stable status, remain open when needed, and can be reviewed optionally once ready. Agent tracking uses aligned file targets and one Full Disk Access action.

Hotkeys under App settings brings emergency, countdown and shared Desk shortcuts together. Desk is a top-level Settings destination, with pencil buttons beside desk and preset names. Redundant Scrolling, Displays and Desk settings pages are removed; the main-menu section is named Displays. New Desk preset shortcuts remain Ctrl–Option–Command–F1/F2/F3.

Appearance now groups controls under Border, Fill and Titles, with radius beside border controls, independently adjustable icon tint, and equal-width Colored sections/System choices. All built-ins were reviewed; Soft tiles and Outline use the new icon tint, while Perch original stays unchanged.

Desk wires draw directly between connectors in either direction. Port menus open on release without dragging; invalid drops and Esc cancel. Screen dragging previews edge and center alignment with guides; Shift bypasses snapping. Cables can save before the other Mac reports a display, and paired identity reports resolve unambiguous matches. Appearance checkbox groups and the title-tint slider keep stable horizontal positions when resizing.

Desk monitor cards place vertical port labels above arrow-free sockets, with the monitor title at the top. Empty preset assignments no longer repeat “Choose connection” inside every screen.

Menu previews focus on the section being edited: full System readings or their final row above the colored sections. A contrasting backdrop, rounded menu edge and shadow make margins visible in either theme.

Built-in appearance presets are reviewed whenever styling options change. Ribbon now uses fading full-width title bands; Horizon adds greyscale section fills with overlines and a fading right edge. Perch original remains unchanged.

Desk now shows computers wired to ports inside the monitor cards. Drag a computer to a port, or choose it from the port menu. Monitor setup revisits input profiles independently from cables and Desk presets. Screen dragging uses a stable coordinate space and nearest-edge snapping, with physical sizes in millimetres. Identify can be stopped with the same button. Unknown monitor ports are no longer presented as detected, and inspection failures are visible.

Appearance controls are grouped more compactly. Edge-to-edge decorations support independent left/right fades; title text remains crisp. Side borders and corner rounding resume when edge-to-edge is turned off.

Desk joining now shows Mac names and explicit Invite/Join actions, labels the comparison code, and explains the step on each Mac. Recovered connection warnings clear independently; a failed redundant route no longer marks a working peer as broken.

Perch countdown adds five minutes per shortcut press, subtracts five with the paired shortcut, and caps the time remaining at 20 minutes. Cancel finishes at 0:00. Opening the lid finishes the manual countdown and leaves a frozen result; power changes preserve its deadline. Shortcuts are configurable in App settings → Hotkeys. This feature requires the updated lid helper.

Menu Appearance now has independent light/dark styles, named saved presets, seven distinct built-in treatments and eight independently selectable palettes, clickable Light/Dark previews, Edit both with mixed values, and an optional System title. Desk arrangements scale to fit smaller windows.

Normal closed-lid battery timeout now stays in Lid activity without a wake dialog. Unexpected sleep during expected protection uses a standalone notice; Settings keeps its current page unless you choose View lid activity.

Settings, including Setup, can now be resized and remembers your chosen size. Resets shows a single checklist with each scope explained inline, an inline keyboard selector, explicit confirmation, and per-area results/retry. Repair links highlight the relevant unchecked row and retain the return to your setup step. All-app privacy remains a separate action.

Repair links now open the specific reset option and return to the same setup step or feature page. Lid repair exposes sleep-only recovery; background repair targets Perch-only permissions. Cancelling or completing the reset retains a labeled return, while sidebar navigation ends that temporary journey.

Resets now collects saved settings, keyboard layouts, menu appearance, privacy permissions, and sleep/audio recovery in one clearly scoped page. Setup and feature links name their destinations; ready permission pages offer optional Show/Hide instructions.

Setup now owns permissions, helper installation and recovery in one place. Keyboard, scrolling, sharing, sleep and agent pages keep their behavior controls and link directly to the relevant Setup stage when attention is needed. Setup stages share one checklist and a consistent return; ready access stops asking you to grant it again.

Recent corrections also fix local Sparkle packaging/launch failures, reopening saved Desk and restart-handoff files, and input interruptions during sustained Desk synchronization. Pending lid-helper updates are clearly marked as needing attention.

Perch 2.0 adds shared keyboard and mouse control to Desk. It also brings shared monitor presets and configurable menu styling to the Mac menu bar.

Desk groups your Perch computers, arranges up to 16 physical screens and saves three monitor presets. The default shortcuts are Ctrl–Option–Command–F1/F2/F3. Editing saves the setup; Play switches physical inputs. Shared screens are explicitly matched, including identical models. Offline changes are preserved, and conflicting arrangements can be reviewed before switching.

Desk screen setup now suggests evidenced LG input profiles from firmware identification, while retaining manual choices and explicit physical-screen matching.

Menu Appearance provides separate controls for System and the colored sections: borders, highlights, corner shape, title styling and spacing, with an immediate preview. Settings uses persistent navigation on the left. About opens its own window.

Settings now supplies native text-editing shortcuts throughout hosted fields and child dialogs. Shared-keyboard additions update immediately, and Setup & status scrolls as its checks grow.

Fixes since the 1.2.87 preview: default Desk function-key shortcuts can be enabled; failed shortcut setup leaves no partially active preset set; About no longer blocks Settings navigation; lid-helper installation accepts Sparkle's expected framework links and identifies incompatible helper publishers.

Requires Apple silicon and macOS 26 or later. Install the official DMG by dragging Perch into Applications, then open that copy from Finder and review Setup & status. The first Developer ID release needs normal installation from development copies; a helper update or contextual permission review may be required. Sparkle uses signed feeds and update archives; public downloads become available only after release verification and publication.

Input sharing is opt-in on each Mac for the current session. Choose a confirmed screen in Keyboard & mouse sharing; moving across touching screen edges transfers control. Ctrl–Opt–Esc returns control locally. The desk owner coordinates input and must remain connected. Confirm the same physical keyboard's attachment on each Mac to follow its host switch. Pointer speed saves immediately on the source Mac. Secure password entry and locked sessions require a local keyboard. Windows/Linux members and VM adapters remain backlog work. Monitor compatibility depends on the device, firmware, cable and control protocol. Results distinguish confirmed, unverified and failed; command acceptance alone does not prove a visible switch. The guarded lid mode blocks all system sleep while active; saved intent is distinct from active protection.

Acceptance status: input routing, visibility loss, release-before-handoff and a 16-member/16-screen desk pass isolated real-TLS tests with injected hardware. Native event values pass without posting. Real two-Mac/hardware, broader accessibility, clean-install/lifecycle and lid edge-case QA remain tracked separately. This candidate is not a claim that those tests have passed. See SUPPORT.md for setup, recovery and reporting, and THIRD-PARTY-NOTICES.md for dependencies and catalog provenance. Public release is also pending the LG table redistribution decision recorded in Release/DEPENDENCY-REVIEW.md.
