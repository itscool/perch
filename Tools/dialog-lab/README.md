# Native dialog smoke test

Build with `python3 Tools/dialog-lab/build.py --output /absolute/task/work/dialog-lab`.
Build does not launch. This app uses production SettingsWindow with harmless
callbacks, a separate bundle identity, and no Perch helpers or settings.

Before launching, announce the scope and start/check AGENT MODE. Launch via
LaunchServices. Follow the computer-use skill for all actual mouse/keyboard
operations. If the Mac is locked or UI access is unavailable, stop the lab and
banner and record the native test as blocked; do not substitute injected success.

Replay Ordinary button → Confirmation → Record → Ordinary button; repeat
confirmation with Back, Escape and X. Open Informational result and return.
Open File picker, cancel it, then use Ordinary button again. Open Child page,
use Child button, Back, then repeat. Close/reopen the lab and repeat from a fresh
window. Record the selected response and parent action count in dialog-results.txt
beside the lab. Use coordinates if accessibility activation appears successful
but ordinary mouse clicks do not. Test Return/default activation and Tab/Space too.

These cover shared native routing. Also replay the affected actual product page
and every new route's relevant states in the isolated functional app, with
external effects injected. A five-button harness does not prove every page.

Stop only this disposable app, then stop AGENT MODE. Never restart installed
Perch or change the active lid session to test this harness.

Keyboard/accessibility implementation checks: open Keyboard controls using Tab
and Return. Edit the named field, Tab/Space the checkbox, Tab/Space/Down/Return
the popup, and type a literal Tab in the multiline editor. Control-Tab must
leave that editor; Shift-Tab goes back. Return on the harmless action records a
result; Escape returns to the parent with its launching button focused. Enter
Long explanation, Tab to Page explanation, and use Page Down/Home before Escape.
On a confirmation, Return retains the native default action; Space activates
the focused Back button. Native sheets keep their own keyboard behavior.

Use `--bundle-id local.perch.unique-lab-name` for a separate test copy when an
older lab process may still exist. AX roles/names and key dispatch are observable
here; spoken VoiceOver acceptance still requires VoiceOver itself.
