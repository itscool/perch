# Desk direct preset editing — September 13, 2026

## Result

- Device sockets are half-circles anchored to monitor bottom edges and computer top edges. Native tracking and SwiftUI button hover treatments distinguish controls.
- The monitor container owns selection/dragging. Only current monitor control rectangles exclude a drag; passive labels/spacers and the port scroll container do not reserve dead regions. Socket wire gestures are excluded independently. The existing stable canvas coordinates and Shift snap bypass remain.
- Dragging an occupied input previews its cable from the existing computer. The original saved wire is hidden only during the draft. Valid drops atomically clear the source and replace the target; Esc, invalid release, removed endpoints, lost window focus and concurrent source changes cancel. The model checks both source and target snapshots before committing. Moving between physical screens deliberately clears host-local display identity for fresh matching.
- Visible radio-style choices above connectors select inputs directly for the editing preset. Unchanged omits that monitor; it does not power it off. The chosen input, cable and computer are highlighted; the selected monitor's route has additional emphasis. Numbered connectors and the editing heading identify the preset. Port context menus remain secondary cable actions.
- Preset-input dropdowns are removed from the inspector. Empty presets show Not mapped on their cards; other readiness errors show Needs attention with accessible details. Editing heading/Add screen and Computers/Add computer are both inside the desk.
- Monitor requests, observed-preset matching and input handoff accept nonempty subsets. Omitted monitors require no control path, receive no switch commands and cannot acquire shared input. Empty presets cannot execute. Resume focus falls back to an included screen.

## Verification

No live windows, input posting, hardware or permissions were used.

- Offscreen production Desk rendering and direct native socket dispatch: ordinary wires both directions, drag threshold/menu timing, geometry refresh, invalid drop, Esc and removed source.
- Occupied-input fixture: computer-end pickup, replace occupied destination, cancellation, concurrent source/destination edits, same-monitor identity preservation, cross-monitor identity invalidation, unchanged presets/geometry, edge anchor coordinates and hover transitions.
- All 24 combinations of three presets and eight included-screen subsets: edits retain other presets and cables; only empty subsets disable activation.
- 105 portable KVM checks including omitted-screen input exclusion.
- Real TLS loopback with temporary identities: one selected monitor switches while omitted monitor lacks a control path, empty preset rejects, previous two-monitor/delegation/conflict tests, input routing, and 16-peer convergence pass. Hardware adapters and native input are injected.
- 61-route dialog ownership inventory passes; settings skill validates. Updated skill covers visible primary spatial choices, actual control hit regions, atomic rewiring and downstream omission behavior.

## Acceptance boundary

Scott retains desktop control. Real mouse hit testing through the running SwiftUI window, small-window/overflow behavior, physical two-Mac preset switching and hardware identity remain manual acceptance. Both Macs need this version for partial preset execution; older peers may refuse the request. No helpers were changed. Installation and commit are recorded in TODO.md.
