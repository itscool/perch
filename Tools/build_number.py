#!/usr/bin/env python3
"""One always-increasing build number shared by local builds and releases.

Perch's updater only offers a release whose build number is higher than the
running app's, so every build, of either kind, takes a number above everything
before it:

- The tracked Info.plist holds the number of the last release.
- A local build records its number in an untracked counter under build/ and
  stamps it into the built app only, so the working copy stays clean.
- A release takes the next number above the last release, the last local build
  and the app installed on this Mac, then writes it into the tracked Info.plist
  for the release pipeline to commit. Counting the installed app keeps a release
  ahead of it even if the local counter was deleted.

Usage:
  build_number.py next              print the number the next build would take
  build_number.py allocate-local    take and record a number for a local build
  build_number.py reserve-release   take a number and write it into Info.plist
  build_number.py stamp APP NUMBER  write NUMBER into a built app's Info.plist
"""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
PLISTBUDDY = '/usr/libexec/PlistBuddy'


def paths():
    """The files the counter reads, overridable so checks never touch real ones."""
    return (Path(os.environ.get('PERCH_VERSION_PLIST', REPO/'Info.plist')),
            Path(os.environ.get('PERCH_LOCAL_BUILD_COUNTER', REPO/'build/local-build-number')),
            Path(os.environ.get('PERCH_INSTALLED_APP', '/Applications/Perch.app')))


def integer(value, source):
    text = str(value).strip()
    if not text.isdigit():
        raise SystemExit(f'{source} must hold a whole build number, not {text!r}.')
    return int(text)


def tracked(plist):
    return integer(plistlib.loads(Path(plist).read_bytes()).get('CFBundleVersion', ''), plist)


def local(counter):
    counter = Path(counter)
    return integer(counter.read_text(), counter) if counter.exists() else 0


def installed(app):
    """The installed app's number, or 0 when there is none or it cannot be read.

    An unreadable installed app must not block a build; it just cannot raise
    the floor.
    """
    try:
        value = plistlib.loads((Path(app)/'Contents/Info.plist').read_bytes()).get('CFBundleVersion', '')
    except (OSError, plistlib.InvalidFileException, ValueError):
        return 0
    text = str(value).strip()
    return int(text) if text.isdigit() else 0


def next_number(plist, counter, app):
    return max(tracked(plist), local(counter), installed(app)) + 1


def record(counter, number):
    """Write the counter atomically, never moving it backwards."""
    counter = Path(counter)
    number = max(number, local(counter))
    counter.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=counter.parent, delete=False) as handle:
        handle.write(f'{number}\n')
    os.replace(handle.name, counter)
    return number


def stamp(info_plist, number):
    """Set the build number and the matching short version, keeping major.minor.

    PlistBuddy edits in place, so the tracked Info.plist keeps its formatting and
    a release's version commit shows only the two changed values.
    """
    info_plist = str(info_plist)
    short = subprocess.run([PLISTBUDDY, '-c', 'Print :CFBundleShortVersionString', info_plist],
                           capture_output=True, text=True, check=True).stdout.strip()
    major_minor = '.'.join(short.split('.')[:2])
    for key, value in (('CFBundleVersion', str(number)), ('CFBundleShortVersionString', f'{major_minor}.{number}')):
        subprocess.run([PLISTBUDDY, '-c', f'Set :{key} {value}', info_plist], capture_output=True, check=True)


def main(argv):
    plist, counter, app = paths()
    command = argv[1] if len(argv) > 1 else ''
    if command == 'next' and len(argv) == 2:
        print(next_number(plist, counter, app))
    elif command == 'allocate-local' and len(argv) == 2:
        print(record(counter, next_number(plist, counter, app)))
    elif command == 'reserve-release' and len(argv) == 2:
        number = next_number(plist, counter, app)
        stamp(plist, number)
        print(record(counter, number))
    elif command == 'stamp' and len(argv) == 4:
        stamp(Path(argv[2])/'Contents/Info.plist', integer(argv[3], 'The build number'))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
