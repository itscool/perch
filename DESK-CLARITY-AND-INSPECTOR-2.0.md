# Desk clarity and inspector sizing — September 13, 2026

Scope: Scott's clipped inspector screenshot, redundant preset selection circles,
missing all-preset membership numbers, unclear active preset, monitor rename
location and inconsistent card/control hit areas. Static and offscreen work only.

## Findings and corrections

- P1: Setup sidebar image data was correct, but initial zero-width AppKit cells
  plus table-relative coordinates and autoresizing placed symbols beyond the
  actual cell bounds. The shared cell now lays out from its own bounds.
- P2: Desk's Keyboard & mouse heading was clipped even at scroll position zero.
  Reproduced with the production inspector scroller and representative wrapped
  content, without a window. Ideal-width intrinsic sizing allocated 294 points
  while the constrained content needed 336. A width-constrained hosting root now
  measures the document correctly; the entire content has its natural height.
- P2: Preset membership and editing selection were conflated. Every assigned
  preset number is now visible outside its connector; only the editing route is
  highlighted. Remove the redundant circle/checkmark from the input selector.
- P2: Confirmed runtime use needs a separate cue. A green In use badge identifies
  the confirmed preset independently of the teal editing card. Edited simulation
  snapshots say changes are not applied. Unknown/unconfirmed state has no badge.
- P2: Preset cards had only narrow selection targets; cards now select across
  their body, retaining their child rename and Play actions and keyboard actions.
  Cards, pencils and Play use hover feedback; existing sockets retain native hover.
- P2: Monitor names were editable only in the inspector. Put a pencil beside the
  name on the monitor, opening an autosaving name popover. The inspector heading
  is read-only. Monitor drag exclusion includes the pencil's measured hit area.
- Compact monitor summaries combine preset, connection and computer on one line.
  Unassigned inputs explicitly say No computer assigned. Port rows were resized
  to keep their half circles at the screen edge after removing the selector icon.

## Evidence and limits

- Tools/check-settings-sidebar.py: 32 Light/Dark, resize and readiness states;
  symbols and labels contained and nonoverlapping; stable selection and cells.
- Tools/check-inspector-scroll.py: 24 Light/Dark/width/expanded-content states;
  heading and final action inside the document, stable width, actual scrolling,
  unchanged-content reading position and collapse recovery. Same test fails on
  the previous production scroller with a heading above the document origin.
- Tools/render-desk-canvas.py: production canvas rendering, native socket dispatch,
  cancellation, rewiring and 24 preset/subset combinations pass offscreen. The
  active-preset fixture shows editing preset 1 and confirmed preset 2 separately.
- Settings flow skill updated for actual-cell geometry, width-constrained native
  hosting and comparing repeated card affordances; structural validator passed.
- Live card clicks, popover focus, current-session sidebar rendering and hardware
  switching remain user acceptance. No desktop control or event posting occurred.

## Network report

Scott reports the Desk connection suddenly behaving better. This is an observed
improvement, not a proven fix. Read-only logs previously showed ready connections
being cancelled quickly and other connections resetting/timing out; those logs
cannot establish which application decision or network condition caused it. No
network code changed in this pass. Keep the real-Mac churn defect open until its
cause and recovery are established. Do not attribute it to traffic visibility.

## Delivery

Developer ID 2.0.118 built and bundle verification passed. Installed the entire
verified /Applications/Perch.app bundle, retaining the previous one at
/Applications/.perch-previous-99rwj_ho/Perch.app. The running process was left
untouched; the user's next restart loads 2.0.118. No helper changes, permissions,
hardware changes, notarization or publication.
