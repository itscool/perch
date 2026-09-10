# KVM implementation contract

September 9, 2026. The first milestone is a native, interactive desk lab and
reusable, headless group/synchronization/handoff code. It is deliberately not
connected to live discovery, permissions, monitor commands or input events.
The installed Perch and its existing monitor controls continue to work.

The next milestone is authenticated computer grouping, synchronized setup and
real monitor-only preset switching. Input sharing is deferred. Production Desk
will replace the old monitor setup/cycling/groups workflow and retire competing
shortcuts while reusing the monitor profile/API/protocol library and command
backends. The user does not need legacy settings migration. See KVM-PLAN.md
for replacement boundaries.

## The experience, before implementation

One **Desk** page has three preset cards, the physical arrangement, a selected
screen inspector and the computers in this group. Selecting a card chooses the
preset being edited; a separate compact **Play** button on that card performs the
switch. Its shortcut is beside Play and an Active badge identifies the running
preset. There is no bottom status/action bar. The Active badge carries routine state; exceptional problems appear contextually.
Editing a name, position, rotation or assignment saves immediately. Editing an
active preset does not silently move input or switch a monitor. Its saved revision
can differ from the currently running arrangement; the page says so.

Screen tiles carry Remove (X) and Rotate, with the remaining tile draggable.
The inspector contains Connections and the three Preset connections together.
Presets select a physical input, optionally mapped to a grouped computer.
Unassigned inputs warn but remain usable for picture-only switching. None is
not an operating mode: incomplete choices prevent activation until every screen
has a selected real connection. Removing a computer preserves its now-unmapped
physical inputs and existing preset choices. Exact size/position remain in a
contextual page for keyboard access. These are the user's September 9 refinements.

Stable settings pages use the existing left sidebar without a redundant Back or
Close button in their content header. Ordinary connection edits expand inline in
the selected screen's connection list. Temporary lab confirmations have a Close
X/Escape and an explicit action; they do not create a Back-button navigation stack.
The production shared host retains scoped exit/cancel for temporary operations
and unfinished drafts, where switching sidebar pages is not a substitute.

| Journey | Action and outcome | Leaving / recovery |
| --- | --- | --- |
| First use | Create a named desk with this Mac; Add computer establishes membership; Add screen confirms a physical screen and its connections. | An incomplete desk is saved, clearly not ready to use; optional setup is skippable. |
| Ordinary use | Select a preset card to edit, or press its Play to switch. Only verified destination readiness allows input handoff. | Active badge and actual input status stay distinct from the editing selection. |
| Adjust | Select a screen, rename, rotate, position or change its computer in this preset. | Save ordinary choices immediately; invalid values preserve the last valid desk. |
| Add / remove | Add computer or screen from the same page. Removing shows the affected mappings before confirmation. | Removing a screen clears its assignments; removing a computer unmaps its still-selectable inputs. Abandoned confirmation changes nothing. |
| Identical screens | Identify physical screen; confirm new or existing shared screen. Serial/model is a suggestion, never an automatic merge. | Correct a connection separately from physical identity; retain other mappings. |
| Offline | Keep named computers and assignments visible with Offline status. | Save edits locally; remote acknowledgement is distinct. No unseen input destination. |
| Failed switch | Show the specific screen that could not be confirmed. Input forwarding stays paused or local. | Retry the intended arrangement; never claim the old picture was restored without evidence. |
| Concurrent edits | Preserve competing signed revisions. Show both choices and require an explicit resolution. | Do not select whichever packet arrived last. |
| Reopen | Restore the saved desk, selection and valid changes. | Live readiness starts unknown; a saved “active” flag cannot authorize input. |

The lab marks all computers, connections and switch outcomes as simulated. Its
scenario controls are outside the proposed product interface. It must allow real
native actions through these journeys, including leaving after completion/error,
closing sheets, reopening, and keyboard access. Screenshots supplement that work.

## Components and boundaries

1. **Portable configuration.** Versioned Codable values represent members,
   physical monitors, input ports with optional host-local mappings, physical geometry, three presets
   and platform-independent shortcut names. Limits and references are validated
   on every import/edit. No permissions, lid settings or live routes are stored
   as shared configuration. A one-member draft is allowed before the second joins.
2. **Signed configuration graph.** Each paired device signs a bounded revision
   containing its parent revisions and complete configuration. Exact payload
   bytes are signed; their hash identifies the revision. Descendants supersede
   ancestors; concurrent heads remain a conflict until explicitly merged. This
   conservative first implementation also surfaces simultaneous unrelated edits
   as conflicts. A future field merge must not weaken identity/route safeguards.
3. **Trust is outside configuration.** An already-established membership roster
   supplies device public keys and an epoch. Configuration cannot grant trust.
   Old epochs, unknown signers, missing parents, altered payloads and stale
   acknowledgements are rejected. Roster installation must come from the future
   authenticated membership protocol, never from a peer's self-asserted snapshot.
   Epoch changes rebase a reviewed configuration; old history cannot restore a
   removed member. Offline edits across an epoch change require explicit review.
4. **Live coordinator.** One authenticated session coordinates a handoff at a
   time. A request freezes its intended routes and required input sources.
   Participants prepare, release held input, switch screens, and report fresh
   verified-visible routes before input can commit. An unassigned input can commit
   a verified picture change with no remote input owner. Failure, expiry, disconnect
   or local recovery fences that transaction; late messages cannot revive it.
   This local state machine does not itself implement distributed leader election.
5. **Physical edges.** The desk uses physical millimetres and explicit rotation.
   Only a unique, touching screen edge may transfer the pointer. Gaps and corners
   block remote handoff; overlapping screens are invalid. The destination point
   is normalized then rotated into the destination's unrotated pixel space.
   Same-computer traversal remains native.
6. **Adapters still to build.** Keychain device identity; paired TLS connections;
   Bonjour + Network.framework peer-to-peer discovery; explicit address entry;
   membership/epoch authority and recovery; durable production sync and receipts;
   leader/session fencing; monitor observations/readback; event tap suppression,
   forwarding, tagging, held-input release and local recovery. None is activated
   just by compiling the first milestone.

Use Network.framework rather than deprecated MultipeerConnectivity. Bonjour
doesn't imply trust or reachability; Apple peer-to-peer Wi-Fi isn't a portable
Windows/Linux transport. Authenticated TLS and explicit pairing are required
before network traffic can carry monitor identity or control messages. Do not
invent an unauthenticated six-digit pairing protocol or silently trust discovery.

References: [Apple networking API selection](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api),
[local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[CryptoKit signing](https://developer.apple.com/documentation/cryptokit/curve25519/signing).

## Completion gates

- Headless: 16/17 limits, identical monitors, rotation/edges, malformed imports,
  signed messages, offline catch-up, concurrent resolution, revocation boundary,
  wrong-session/late handoffs, partial monitor failure and local recovery.
- Native lab: complete table above where implemented, named simulation gaps,
  immediate save, reopening, small window, keyboard and sheet dismissal.
- Production integration: trust/network/input adapters above, Settings entry and
  replacement of old monitor entry points. Do not expose a lab success as a production-ready KVM control.
- Physical acceptance: two and three Macs, different network paths, real
  visible-picture/input-recipient checks, held keys, sleep/disconnect and failure.
  Coordinate this separately with the user; never manufacture it on the live desk.
