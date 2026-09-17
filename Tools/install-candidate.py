#!/usr/bin/env python3
"""Install a verified Perch build over the copy this Mac runs, safely.

This replaces hand-typed install steps that went wrong twice on September 16,
2026: one deleted the bundle a running Perch still executed from, and several
local builds went in without update settings, silently switching off update
checks.

Before touching anything it refuses a build that fails its signature, lacks the
update settings in Release/config.json, is signed with a different designated
requirement from the installed app, or does not move the build number forward.
It then stages a copy beside the target, verifies it, and swaps by rename so no
running executable is overwritten, keeping the previous copy. An older copy is
removed only when every running Perch's executable can be located and none of
them lives inside it. It never quits or restarts Perch.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
STASH_PREFIX = '.Perch.previous-'
STAGED = '.Perch.staged.app'


def run(*args, check=True):
    return subprocess.run(list(map(str, args)), capture_output=True, text=True, check=check)


def info(app):
    return plistlib.loads((Path(app)/'Contents/Info.plist').read_bytes())


def number(values):
    text = str(values.get('CFBundleVersion', '')).strip()
    return int(text) if text.isdigit() else -1


def version(values):
    return f"{values.get('CFBundleShortVersionString', '?')}, build {values.get('CFBundleVersion', '?')}"


def verify(app):
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)


def requirement(app, runner=run):
    output = runner('/usr/bin/codesign', '-d', '-r-', app)
    for line in (output.stdout + '\n' + output.stderr).splitlines():
        if line.startswith('designated => '):
            return line[len('designated => '):].strip()
    raise SystemExit(f'Could not read the designated requirement of {app}.')


def digest(app):
    hasher = hashlib.sha256()
    with (Path(app)/'Contents/MacOS/Perch').open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            hasher.update(block)
    return hasher.hexdigest()


def problems(source, target, config, source_requirement, target_requirement, allow_downgrade):
    """Every reason to refuse, decided before anything on disk changes."""
    found = []
    if source.get('SUFeedURL') != config['feedURL'] or source.get('SUPublicEDKey') != config['publicKey']:
        found.append('The build lacks Perch\'s update settings, so installing it would switch off update checks. '
                     'Build it with ./build.sh.')
    if target is not None:
        if source_requirement != target_requirement:
            found.append('The build is signed differently from the installed Perch, so macOS would treat it as a '
                         'new app and ask for its permissions again.')
        if number(source) <= number(target) and not allow_downgrade:
            found.append(f'The build number does not move forward: installed {version(target)}; this build '
                         f'{version(source)}. Build with ./build.sh, not --no-bump, or pass --allow-downgrade.')
    return found


def running_executables(folder, runner=run):
    """Where each running Perch that could be in `folder` executes from, and whether all were found.

    Only a Perch launched from inside `folder` can be running from a copy there,
    because the installer only ever renames within that folder. Anything launched
    elsewhere is skipped, including the root lid helper, which lsof cannot
    inspect and which would otherwise block every cleanup. lsof reports each
    executable's current path, so a bundle renamed while Perch runs shows its new
    name. If a candidate cannot be located, callers must remove nothing.
    """
    folder = str(folder).rstrip('/') + '/'
    listed = runner('/usr/bin/pgrep', '-x', 'Perch', check=False)
    if listed.returncode == 1:
        return [], True
    if listed.returncode != 0:
        return [], False
    paths, resolved = [], True
    for pid in listed.stdout.split():
        launched = runner('/bin/ps', '-o', 'comm=', '-p', pid, check=False).stdout.strip()
        if not launched.startswith(folder):
            continue
        found = runner('/usr/sbin/lsof', '-a', '-d', 'txt', '-Fn', '-p', pid, check=False)
        executables = [line[1:] for line in found.stdout.splitlines()
                       if line.startswith('n') and line.endswith('/Contents/MacOS/Perch')]
        if found.returncode != 0 or not executables:
            resolved = False
        paths.extend(executables)
    return paths, resolved


def stash_time(path):
    """When a copy was set aside: the time in its name, else its modification time."""
    stem = path.name[len(STASH_PREFIX):-len('.app')]
    tail = stem.rsplit('-', 1)[-1]
    return int(tail) if tail.isdigit() else int(path.stat().st_mtime)


def prunable(stashes, running, resolved, keep):
    """Older copies safe to delete: beyond the newest `keep`, and used by no running Perch."""
    if not resolved:
        return []
    ordered = sorted(stashes, key=stash_time, reverse=True)
    return [stash for stash in ordered[keep:]
            if not any(path.startswith(str(stash) + '/') for path in running)]


def ditto(source, destination):
    run('/usr/bin/ditto', source, destination)


def install(source, target, verify, copy=ditto, now=None):
    """Stage and verify a copy, then swap it in by rename. Returns the previous copy's path."""
    parent = Path(target).parent
    staged = parent/STAGED
    if staged.exists():
        shutil.rmtree(staged)
    copy(source, staged)
    try:
        verify(staged)
    except BaseException:
        shutil.rmtree(staged, ignore_errors=True)
        raise
    stash = None
    if Path(target).exists():
        moment = now if now is not None else int(time.time())
        stash = parent/f'{STASH_PREFIX}{number(info(target))}-{moment}.app'
        os.rename(target, stash)
    try:
        os.rename(staged, target)
    except BaseException:
        if stash is not None and not Path(target).exists():
            os.rename(stash, target)
        shutil.rmtree(staged, ignore_errors=True)
        raise
    return stash


def main(argv=None):
    parser = argparse.ArgumentParser(description='Install a verified Perch build over the copy this Mac runs.')
    parser.add_argument('--app', type=Path, default=REPO/'build/Perch.app', help='built app to install')
    parser.add_argument('--target', type=Path, default=Path('/Applications/Perch.app'), help='installed app to replace')
    parser.add_argument('--keep', type=int, default=2, help='previous copies to keep; at least 1')
    parser.add_argument('--allow-downgrade', action='store_true',
                        help='install even when the build number does not move forward')
    parser.add_argument('--dry-run', action='store_true', help='run every check and change nothing')
    a = parser.parse_args(argv)
    if a.keep < 1:
        parser.error('--keep must be at least 1.')
    source, target = a.app.resolve(), a.target
    if not (source/'Contents/Info.plist').is_file():
        raise SystemExit(f'No built app at {source}. Run ./build.sh first.')
    config = json.loads((REPO/'Release/config.json').read_text())
    try:
        verify(source)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'The build fails its signature check: {error.stderr.strip()}')
    source_info = info(source)
    target_info = info(target) if (target/'Contents/Info.plist').is_file() else None
    if target_info is not None and number(source_info) == number(target_info) and digest(source) == digest(target):
        print(f'Already installed: Perch {version(target_info)} at {target}.')
        return 0
    refusals = problems(source_info, target_info, config, requirement(source),
                        requirement(target) if target_info is not None else None, a.allow_downgrade)
    if refusals:
        raise SystemExit('Not installed:\n- ' + '\n- '.join(refusals))
    replacing = f'Perch {version(target_info)}' if target_info else 'nothing'
    print(f'Installing Perch {version(source_info)} over {replacing} at {target}.')
    if a.dry_run:
        print('Dry run: every check passed and nothing changed.')
        return 0
    stash = install(source, target, verify)
    installed = info(target)
    if installed.get('SUFeedURL') != config['feedURL'] or number(installed) != number(source_info):
        raise SystemExit(f'The installed copy does not match the build. The previous copy is at {stash}.')
    verify(target)
    # Locate running Perch only now, after the swap, so a copy renamed a moment
    # ago under a running Perch shows up under its new name before any removal.
    home = target.parent.resolve()
    running, resolved = running_executables(home)
    removed = prunable(list(home.glob(STASH_PREFIX + '*.app')), running, resolved, a.keep)
    for old in removed:
        shutil.rmtree(old)
    for path in running:
        bundle = Path(path).parents[2]
        if bundle.parent == home and (bundle.name == target.name or bundle.name.startswith(STASH_PREFIX)):
            label = f'Perch {version(info(bundle))}' if (bundle/'Contents/Info.plist').is_file() else 'an earlier Perch'
            print(f'Running now: {label}, from {bundle.name}.')
    print(f'Installed on disk: Perch {version(installed)}. It takes effect when Perch next restarts; nothing was restarted.')
    if stash is not None:
        print(f'Previous copy kept: {stash.name}.')
    if removed:
        print('Removed older copies: ' + ', '.join(p.name for p in removed) + '.')
    elif not resolved:
        print('Kept every older copy: a running Perch could not be located, so none is safe to remove.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
