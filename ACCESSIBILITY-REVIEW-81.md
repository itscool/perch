# Keyboard and accessibility implementation — build 81

September 9, 2026. Scope: finish the settings keyboard/accessibility implementation
so remaining work in this area is release acceptance testing. Build 77 remains
installed. This does not close unrelated KVM, distribution, lid or collector work.

## Findings and implemented changes

- **P2: native Tab did not reach button-only settings on this Mac.** Reproduced
  with actual input in the harmless lab. macOS keyboard navigation was off;
  buttons accepted explicit focus but were excluded from its native key-view
  loop. Perch's shared Settings panel now supplies local Tab/Shift-Tab traversal
  without changing that OS preference. Hidden/disabled controls are skipped,
  group hierarchy and visual order are retained, and offscreen controls scroll
  into view. Static labels do not become unnecessary Tab stops.
- **P2: long explanations lacked a usable keyboard scroll target.** A native
  read-only field/scroll container can refuse first-responder ownership even when
  the assignment reports success. Shared page explanations and monitor status
  now use an explicitly focusable scroll view with arrow/Page/Home/End handling.
- **P2: page and changing-result accessibility signals were incomplete.** The
  shared window identifies the current page in its title and heading role;
  navigation/results post layout and page-announcement notifications. Changing
  status fields expose value-change notifications; unchanged polling is quiet.
  Navigation-key learning announces changes to its requested-key instruction.
  Short repeated monitor actions now name their input and ordering direction;
  report and identification text areas have explicit accessible names.

Keyboard handling is confined to Perch's shared panel. Space activates a focused
button; Return does so when there is no native default button. Default Return,
popups, arrow selection and OS-owned sheets remain native. Text-field editing is
retained. Multiline editors retain literal Tab/Return; Control-Tab and
Control-Shift-Tab provide an exit, described in help. Command and Option chords,
including VoiceOver's Control–Option combinations, are not intercepted. No global
keyboard monitor or permission requirement was introduced.

## Coverage

The 59-site dialog inventory remains the construction coverage gate. Ordinary
settings categories, Setup & status, keyboard/navigation setup, agent settings,
permission/collector pages, monitor/group editors, Maintenance, reset previews,
shared confirmations/results and errors all use the shared host. OS authorization
and file pickers keep their separate native ownership. Existing menu keyboard
routing and accessible state/action tests remain in the suite; menu design and
hardware behavior were not changed.

Names/states were traced through editable fields, selectors, repeated per-item
actions, custom permission controls, report text and custom menu rows. Existing
focus/selection restoration remains covered across alert return, child Back,
page refresh and replacement. High-contrast/color checks remain part of the
functional suite. This is implementation coverage, not physical input on all
59 construction sites or a guarantee of universal accessibility.

## Observed verification

Native lab, with AGENT MODE and no Perch helpers: Tab reached a button; Return
opened a page; a named field accepted typing; Tab/Space toggled a checkbox;
Tab/Space/Down/Return changed a native popup; multiline Tab inserted text;
Control-Tab left the editor; Shift-Tab reversed focus; Return recorded an action.
Escape restored the parent's launching button. Keyboard confirmation completed,
Space activated informational Back, and a native file picker cancelled with
Escape and restored focus to the picker button. Its recorded outcome was cancel.
A transient computer-use pipe error was followed by inspection of the live picker;
no app failure was inferred from that tool interruption.

The final native lab also passed Page Down/Home in a focused long explanation
with a visible blue focus ring, and Return activated a confirmation's native
default action without first tabbing to it.

The native AX tree reported page headings, field names, checkbox values and the
selected popup choice. No VoiceOver preference was changed and spoken VoiceOver
was not run. Hidden production-handler tests additionally cover disabled/hidden
controls, field-editor traversal, multiline escape, default Return preservation,
authorization exclusion, long-explanation focus and Page Down/Home scrolling.

## Remaining release acceptance in this area

- Use VoiceOver through first use, changing settings, setup success/failure, Back,
  status updates and recovery. Confirm actual speech order, concise announcements,
  focus return, name/state accuracy and that polling stays quiet.
- Broaden native keyboard acceptance to each production route, including dynamic
  list add/remove/reorder, invalid drafts, small-window scrolling and reconnects;
  check both macOS keyboard-navigation preference states in a coordinated session.
- Check OS permission/authorization handoffs and other external contexts in their
  already planned safe sessions. Do not reset live permissions to create cases.

No known implementation gap from this pass is being left as a planned feature.
Any defect discovered during release acceptance still needs fixing; implementing
accessibility cannot guarantee that only testing effort will ever remain.

Final verification: 22/22 isolated suites passed. Production build 81 compiled
without warnings; strict executable/app signatures and ZIP integrity/version
checks passed. Build 81 is packaged, not installed. AGENT MODE sessions ended.
