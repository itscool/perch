#!/usr/bin/env python3
"""Fast checks for the shared build counter. Temporary files only."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import build_number as b


def plist(path, build, short=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps({'CFBundleVersion': str(build), 'CFBundleShortVersionString': short or f'2.0.{build}'}))


def refused(action):
    try:
        action()
    except SystemExit:
        return True
    return False


with tempfile.TemporaryDirectory(prefix='perch-build-number-') as directory:
    root = Path(directory)
    tracked, counter, app = root/'Info.plist', root/'build/local-build-number', root/'Applications/Perch.app'
    plist(tracked, 205)

    # With nothing local or installed, the next build follows the last release.
    assert b.next_number(tracked, counter, app) == 206
    # A local build records its number privately and leaves the tracked file alone.
    assert b.record(counter, b.next_number(tracked, counter, app)) == 206
    assert b.tracked(tracked) == 205 and b.next_number(tracked, counter, app) == 207
    # The counter never moves backwards.
    assert b.record(counter, 100) == 206
    # An installed app above both raises the floor, so a lost counter cannot reuse its number.
    counter.unlink()
    plist(app/'Contents/Info.plist', 209)
    assert b.next_number(tracked, counter, app) == 210
    # An unreadable installed app does not block a build.
    (app/'Contents/Info.plist').write_text('not a plist')
    assert b.installed(app) == 0
    # Stamping keeps major.minor and writes the matching build number.
    plist(tracked, 205, '2.1.205')
    b.stamp(tracked, 211)
    values = plistlib.loads(tracked.read_bytes())
    assert values['CFBundleVersion'] == '211' and values['CFBundleShortVersionString'] == '2.1.211', values
    # A malformed tracked number is refused rather than guessed.
    plist(tracked, 'abc')
    assert refused(lambda: b.tracked(tracked))

    # The command line as build.sh uses it.
    plist(tracked, 205)
    plist(app/'Contents/Info.plist', 205)
    env = dict(os.environ, PERCH_VERSION_PLIST=str(tracked), PERCH_LOCAL_BUILD_COUNTER=str(counter),
               PERCH_INSTALLED_APP=str(app))
    cli = [sys.executable, str(TOOLS/'build_number.py')]
    output = lambda *args: subprocess.check_output(cli + list(args), env=env, text=True).strip()
    assert output('allocate-local') == '206' and b.tracked(tracked) == 205
    assert output('next') == '207' and b.local(counter) == 206
    assert output('reserve-release') == '207' and b.tracked(tracked) == 207 and b.local(counter) == 207
    # The next local build after a release outranks that release.
    assert output('allocate-local') == '208'
    built = root/'Built.app'
    plist(built/'Contents/Info.plist', 205)
    output('stamp', str(built), '209')
    stamped = plistlib.loads((built/'Contents/Info.plist').read_bytes())
    assert stamped['CFBundleVersion'] == '209' and stamped['CFBundleShortVersionString'] == '2.0.209', stamped

print('PASS: local builds and releases share one increasing build number; local builds leave Info.plist alone; '
      'a release outranks the last local build and the installed app; temporary files only')
