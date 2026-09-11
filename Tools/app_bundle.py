#!/usr/bin/env python3
"""Verify Sparkle's runtime load path without launching Perch; finish staged builds."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def output(*args):
    return subprocess.check_output(list(map(str, args)), text=True)


def verify(app):
    app = app.resolve(strict=True)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    name = info['CFBundleExecutable']
    if Path(name).name != name:
        raise ValueError('Invalid bundle executable name')
    binary = app/'Contents/MacOS'/name
    dependencies = output('/usr/bin/otool', '-L', binary)
    libraries = re.findall(r'^\s+(@rpath/Sparkle\.framework/\S+) \(', dependencies, re.M)
    if not libraries:
        raise ValueError('Perch does not link the expected Sparkle framework')
    commands = output('/usr/bin/otool', '-l', binary)
    rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', commands)
    if '@executable_path/../Frameworks' not in rpaths:
        raise ValueError('Missing bundled-framework runtime search path (LC_RPATH)')
    for library in libraries:
        target = app/'Contents/Frameworks'/library.removeprefix('@rpath/')
        if not target.is_file() or app not in target.resolve().parents:
            raise ValueError(f'Missing or external runtime dependency: {library}')
        if not set(output('/usr/bin/lipo', '-archs', binary).split()).issubset(
                output('/usr/bin/lipo', '-archs', target).split()):
            raise ValueError(f'Sparkle lacks an architecture required by {name}')
    # Also check framework links used by bundle loading, not just the versioned
    # binary dyld names. Missing/redirected links must not escape the app bundle.
    framework = app/'Contents/Frameworks/Sparkle.framework'
    for relative in ('Sparkle', 'Resources/Info.plist', 'Versions/Current'):
        target = framework/relative
        if not target.exists() or framework not in target.resolve().parents:
            raise ValueError(f'Broken bundled Sparkle layout: {relative}')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)


def finish(app, destination):
    """Replace only after verification; restore the previous build on rename failure."""
    verify(app)
    # Do not resolve the final component: following a destination symlink would
    # unexpectedly replace a different app, possibly the installed one.
    destination = destination.parent.resolve()/destination.name
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError('Build destination must be an app directory, not a file or symlink')
    temporary = Path(tempfile.mkdtemp(prefix='.perch-previous-', dir=destination.parent))
    backup = temporary/destination.name
    try:
        if destination.exists():
            os.replace(destination, backup)
        try:
            os.replace(app, destination)
        except OSError:
            if backup.exists():
                try:
                    os.replace(backup, destination)
                except OSError as error:
                    raise OSError(f'Could not restore the previous build; it is preserved at {backup}') from error
            raise
        shutil.rmtree(temporary)
    finally:
        if temporary.exists() and not backup.exists():
            temporary.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--destination', type=Path, help='Replace this build only after verification')
    args = parser.parse_args()
    try:
        if args.destination:
            finish(args.app, args.destination)
        else:
            verify(args.app)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'App packaging failed: {error}\nNo app was launched.\n')
    print('PASS: bundled Sparkle load path, architecture, layout and nested signatures')


if __name__ == '__main__':
    main()
