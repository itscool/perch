# What Perch is and how it behaves

Scott owns this page. Every session reads it first and checks each change
against it. Rules are added or changed only with Scott's approval. Where
something here disagrees with older documents or code, this page wins.

## What Perch is

One desk, several computers. A menu bar app for Scott's own Macs that:

- switches the shared monitors between the computers on the desk, Windows PCs included
- shares the keyboard, mouse and clipboard between the Macs
- keeps a Mac awake, also with the lid closed
- adds keyboard, scroll and display controls, and shows what the Mac is doing (CPU, disk)

## Scott's desk

Every change is checked against this desk, not an idealised one.

- **MacBook Pro**: goes to work and back. At the desk its lid is usually closed.
  It often runs a local build that is newer than any release.
- **Mac Studio** (HQ-KP40Y76PT6): stays home. Usually on a published release.
- **Home monitors**: an LG UltraFine and an LG HDR 4K. Neither reports which
  input it is on. MacBook on USB-C, Studio on DisplayPort, the PC on HDMI.
- **A Windows PC** at home and one at work. No Perch on them.
- The Macs reach each other over Wi-Fi, sometimes over a Thunderbolt cable.

## How it behaves

1. **Perch controls what it finds.** If something was set outside Perch, such
   as sleep disabled with pmset, Perch says who set it and still lets you change
   it. It never greys out a control because it did not make the state.
2. **Facts, not guesses.** Each Mac knows which screens it is showing; together
   they are the desk. The active preset is the one the screens show. Every status
   names its source: "On by Perch", "On outside Perch", "only the MacBook sees it".
3. **Nothing silently does nothing.** When Perch will not or cannot do something,
   it says why where you are (the menu or a popup) and writes it to the log.
4. **Recovery is automatic.** A button appears only when you alone can do the
   thing, and it is named for what it does. No "try this" buttons.
5. **Plain words, short.** Features, not helper names or internals. No walls of
   text.
6. **One pointer.** It belongs to one Mac at a time; any mouse on the desk moves
   it, with no handover you can feel.
7. **Copy here, paste there.** Text you copy is on every Mac at once. ⌃⌥⌘V pastes
   the newest copy on the desk into the app in front, bringing it over first if
   needed. Passwords never leave the Mac.
8. **Macs can run different versions.** Perch says which Mac runs what, and offers
   only updates that can actually happen.
9. **Changing Perch never strands you.** Restart and updates work with the lid
   closed. A new build is installed alongside and used at the next restart.

## When working on Perch

- When an ask could mean two things, say in one line what will be built, and wait.
- A refusal or safety rule found in old code is not one of Scott's rules unless it
  is on this page. When one blocks him, make Perch handle the case instead.
- Every bug gets a fast test that would have caught it, run against Scott's desk.
