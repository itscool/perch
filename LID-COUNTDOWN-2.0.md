# Perch countdown and settings acceptance

September 13, 2026. Signed candidate 2.0.105; not installed, notarized or published.

## Countdown contract

A deliberate increase starts five minutes or adds five to the current remainder.
Decrease subtracts five, clamped at zero. `LidCountdownLimits.maximum` is the
single 20-minute cap. Power changes do not change the deadline. A close then open
finishes the manual timer and freezes its remainder; expiry and Cancel finish at 0:00. The
finished overlay has Close. Increase after finishing creates a new identity and
five minutes. Starting with an already open lid does not immediately finish.
Normal undocking grace remains one minute. Normal saved choices are unchanged.

The helper owns the absolute continuous-clock deadline and sends it to its
independent watchdog. Normal heartbeat, crash recovery and restart-ticket limits
remain in force. On completion, a prior normal lid session resumes only when safe;
a timer-only session ends. Closed battery completion requests sleep. Sleep is
never described as guaranteed. The app displays confirmed helper state, preserves
finished results, serializes deliberate adjustments, ignores held-key repeats,
and does not retry an ambiguous adjustment as another add command.

Default shortcuts are Ctrl–Opt–Cmd plus (the +/= physical key, without Shift) and
minus. Keep awake contains the launcher and immediate-save shortcut editor;
registration conflicts preserve previous shortcuts. The overlay uses the Perch
bird, a restrained indigo accent and a monospaced countdown. It defers visibility
while Settings owns an authorization/modal interaction.

Helper and protocol versions increase to 3. An existing active helper must use
the normal coordinated helper-update path; this work does not replace it live.
Expected manual expiry/cancellation stay in Lid activity; a later new countdown
cannot borrow an old completion to suppress an unexpected-sleep notice.

## Appearance and Desk

Appearance has separately editable light/dark themes, paired selectable
previews using the real menu renderer (sample items remain inert), built-in and named user presets. Presets
save both themes including System. Deletion has inline confirmation and does not
change the active style. Menu appearance reset restores both themes and retains
saved presets. The introductory explanation is removed, including its empty
layout allocation. Perch original matches the specified rainbow/title-only/all-
sides 0.7pt/30%, 7% highlight, 45% text tint, icons, 2.5pt radius and 3pt gap;
System has no border/highlight/icons/tint/gap. Its title is optional. Hidden
icons do not reserve indentation. Graphite, Coast and Dusk are optional palettes
and complete built-in presets. The Settings sidebar stays text-only.

Desk no longer enforces a 0.32 minimum canvas scale or a 960pt page minimum.
It fits the actual bounds, including negative coordinates and rotated panels.
Dragging uses the inverse transform. Small screens use numbered labels with
full accessible names/tooltips and context actions; geometry is not inflated to
make room for labels. The connection editor retains a fixed readable width.

## Evidence

The headless suite passes 378,504 normal-policy and 47,988 countdown generated
transitions plus explicit boundaries/failures, in approximately one second after
compilation. Tests cover frozen completion, additive adjustments, cap, restart,
power changes, repeat filtering, cancel and helper/watchdog agreement. Additional
app tests cover stale RPC replies, malformed authority, notice suppression,
light/dark persistence, preset preservation, hidden titles/icons and fit geometry.
The earlier combined isolated suite passed 23/23. After the Cancel refinement,
native clicks confirm Cancel → Finished 0:00 with Close. Earlier native acceptance
covered +/−, fresh restart and frozen lid-open completion using simulated time.
Native appearance checks applied the exact Perch original values, saved a named
preset, and changed Dark to Coast while Light retained Rainbow. Clicking the Dark
preview now selects that theme; Edit both marks different palettes and checkbox
states as mixed. A Left-border change preserves the mixed Right-border value;
clicking mixed Right enables it in both themes. Empty explanation/hint and sample
menu accessibility controls are removed. The generated batch-edit tests preserve
unrelated fields, other border sides, System settings and the opposite theme.

Desk fits two simulated screens in a reduced window, including a rotated screen.
Sidebar navigation works when clicking the visible row; earlier unsuccessful
attempts targeted offscreen accessibility rows, not a confirmed product defect.
The final native suite exposed a test's nested-scroll reveal bug in Agent settings:
scrolling only the inner list left the checkbox outside the outer page viewport.
The visible checkbox passes a real click; the test now reveals through every
ancestor before verifying the actual hit target. The corrected AppKit suite passes 1/1. Together with the 22 other suites that
passed the preceding combined run, all 23 suites have passing coverage; the
nested-scroll test fix and final mixed-picker presentation were checked in the
focused rerun. The signed 2.0.105 candidate passes nested-signature and Sparkle
packaging checks, with all 273 release source inputs matching its snapshot.

No real sleep, power writes, helper installation, panic, privacy reset or monitor
switch occurred. The countdown fixture uses simulated time and injected actions;
physical shortcut delivery and updated-helper integration remain release QA.

User refinement: Cancel finishes at 0:00 immediately; opening retains the remaining time. Plus from a cancelled result creates a fresh five minutes. Light/Dark previews now select editing scope; Edit both marks mixed values and writes only the touched property (including individual border sides). Toggling Edit both never changes stored appearance.
