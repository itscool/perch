# Desk cable editor — September 13, 2026

## Findings and changes

- **P2: the Computer picker actually selected computer + detected display.**
  Duplicate-looking Mac choices and physical-screen reassignment leaked internal
  identities into routine cable editing. Monitor cards now contain ports;
  computer cards below can be dragged to a port. The same port menu supports
  ordinary click/keyboard selection, disconnect and port editing. Ambiguous
  detected displays get a scoped Identify/Connect step. A display already bound
  to another physical screen cannot silently create a second screen identity.
- **P2: monitor configuration had no clear return path.** Monitor setup now owns
  the saved input profile and advanced control connection. Matching port names
  retain their IDs, cables and Desk preset assignments when input codes change;
  extra configured ports remain. Atomic validation preserves the old setup on
  conflicting codes. The inspector keeps the three Desk preset input choices.
- **P2: moving-view coordinates and repeated snap candidates destabilized drag.**
  Dragging uses a fixed parent coordinate space and a frozen physical transform.
  One nearest valid edge wins; overlap drops dock, intentional gaps remain.
  Fractional millimetre coordinates are preserved instead of rounded into a
  neighbour. Auto-fit proportions use physical panel dimensions, not resolution.
- **P2: Identify only timed out.** Repeating Identify stops the same operation.
  Tokens distinguish restart from an older timeout/cancellation. Each destination
  also expires locally. Monitor and per-display entry points share the toggle.
- **P2: guessed ports looked detected, and inspection errors disappeared.**
  Unknown screens no longer get generic invented input lists. Reported ports,
  matched profiles and firmware suggestions are distinct. Exact discovery
  matches survive into setup; inspection failures are shown with retry.

## Evidence boundary

- 243 nonpresenting model journey checks passed, including cable reassignment,
  cross-screen identity refusal, profile persistence, preset/cable preservation,
  invalid transactions, identification cancellation/restart/old timeout, and
  docking across zoom factors and portrait dimensions.
- Real TLS loopback and existing 16-peer suites passed after extending the saved
  monitor schema. All physical monitor and input operations were injected.
- The production Desk canvas was rendered offscreen with NSHostingView and
  simulated devices, asserting that no windows existed. This caught and fixed
  an extra centring offset. The inspected image does not prove drag/drop,
  popups, accessibility or hardware acceptance on the live desktop.
- Full compilation is repeated for the final signed candidate. No native GUI
  suite or live hardware test was run while Scott owned the desktop.

## Still open

The actual 27UP850-W / 27UP850K-W recognition failure needs the Mac's display
identity and monitor inspection result. The catalog includes an evidenced
27UP850-W input profile, not a verified exact K-W profile. No retail suffix or
protocol compatibility was invented. LG's official K-W product information
confirms physical connectors but does not establish DDC input codes:
https://www.lg.com/uk/monitors/uhd-4k-5k/27up850k-w/

Physical two-Mac identification cancellation, actual Bonjour roles, cable
selection, small-window drag/scroll and monitor-control readback remain QA.

## Port label refinement

Port menu arrows are hidden; vertical names sit above each clickable socket.
Cable anchors remain on the socket rather than the label. Monitor titles move
to the upper left, and unassigned presets no longer repeat an instruction inside
every screen. Port menus, drag targets and accessible names remain available.
The production canvas was rendered offscreen to verify label/socket alignment.

## Direct wires, alignment and cooperative display reporting

- Connector mouse-down does not open a menu. A 3-point threshold starts a draft
  wire; release over an opposite connector commits, empty release/Esc cancels,
  and a click menu opens only on release before any drag. Both directions work.
  Native socket callbacks were exercised on unattached views, including Esc,
  source removal and invalid release, without windows or posted events.
- Screen drag has a dashed placement preview plus named top/center/bottom and
  left/center/right guides. Simultaneous matches are shown. Shift bypasses both
  docking and alignment. Preview and drop use the same pure placement function.
- Cable intent can save while the other computer's display identity is pending.
  Peer arrival and cable setup request remote refresh; remote discovery errors
  reach the setup page. Unique serial-based cross-peer observations complete the
  user's already chosen cable. Ambiguous/unknown identities stay pending with a
  Match display entry on this Mac. Input forwarding is gated on a matched display.
- Some monitors disappear from a Mac's display list when its input is inactive.
  Refresh alone cannot manufacture that identity. Use the explicit preset Play
  to show that input, then refresh from the configuring Mac. No automatic input
  probe/switch-and-restore operation has been added or tested in this revision.

262 model checks and 102 portable KVM checks pass; native connector dispatch and
real TLS fixture checks are separate from live two-Mac/hardware acceptance.
Both Macs need the new build to exchange pending cable configurations.
