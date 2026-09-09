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
