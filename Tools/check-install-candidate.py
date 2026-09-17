#!/usr/bin/env python3
"""Fast checks for the installer: no codesign, no /Applications, no process touched."""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('install_candidate', Path(__file__).with_name('install-candidate.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

CONFIG = {'feedURL': 'https://example.invalid/appcast.xml', 'publicKey': 'fixture-key'}


def values(build, updates=True):
    result = {'CFBundleVersion': str(build), 'CFBundleShortVersionString': f'2.0.{build}'}
    if updates:
        result.update(SUFeedURL=CONFIG['feedURL'], SUPublicEDKey=CONFIG['publicKey'])
    return result


def refusals(source, target, source_requirement='R', target_requirement='R', allow=False):
    return ' '.join(m.problems(source, target, CONFIG, source_requirement, target_requirement, allow))


# Every refusal is decided before anything on disk changes.
assert refusals(values(206), values(205)) == ''
assert refusals(values(206), None, target_requirement=None) == ''
assert 'update settings' in refusals(values(206, updates=False), values(205))
assert 'update settings' in refusals(values(206, updates=False), values(205), allow=True)
assert 'signed differently' in refusals(values(206), values(205), target_requirement='other')
assert 'does not move forward' in refusals(values(205), values(205))
assert 'does not move forward' in refusals(values(204), values(205))
assert refusals(values(204), values(205), allow=True) == ''


def runner(pgrep, processes):
    """processes: pid -> (launch path, lsof exit code, lsof output)."""
    def fake(*args, check=True):
        args = list(map(str, args))
        if args[0].endswith('pgrep'):
            return SimpleNamespace(returncode=pgrep[0], stdout=pgrep[1], stderr='')
        launched, code, out = processes[args[-1]]
        if args[0].endswith('/ps'):
            return SimpleNamespace(returncode=0, stdout=launched + '\n', stderr='')
        return SimpleNamespace(returncode=code, stdout=out, stderr='')
    return fake


APPS = '/Applications'
MAIN = '/Applications/Perch.app/Contents/MacOS/Perch'
STASHED = '/Applications/.Perch.previous-205-1.app/Contents/MacOS/Perch'
# Locating running Perch: no process is fine.
assert m.running_executables(APPS, runner((1, ''), {})) == ([], True)
# A Perch launched from the install folder is located where it runs now, even after a rename.
# Helpers launched elsewhere are skipped, including a root lid helper lsof cannot inspect.
paths, resolved = m.running_executables(APPS, runner((0, '10 11 12\n'), {
    '10': (MAIN, 0, f'p10\nftxt\nn{STASHED}\nn/usr/lib/dyld\n'),
    '11': ('/Users/x/Library/Perch Helper.app/Contents/MacOS/Perch', 0, 'p11\nftxt\nn/Users/x/Perch Helper.app/Contents/MacOS/Perch\n'),
    '12': ('/Library/PrivilegedHelperTools/Perch Lid Helper.app/Contents/MacOS/Perch', 1, '')}))
assert resolved and paths == [STASHED], (paths, resolved)
# A Perch from the install folder that cannot be located blocks every removal.
assert m.running_executables(APPS, runner((0, '10\n'), {'10': (MAIN, 1, '')}))[1] is False
assert m.running_executables(APPS, runner((0, '10\n'), {'10': (MAIN, 0, 'p10\nftxt\nn/usr/lib/dyld\n')}))[1] is False
assert m.running_executables(APPS, runner((2, ''), {}))[1] is False
# A folder whose name merely starts the same is not the install folder.
assert m.running_executables(APPS, runner((0, '10\n'), {'10': ('/ApplicationsX/Perch.app/Contents/MacOS/Perch', 1, '')})) == ([], True)

with tempfile.TemporaryDirectory(prefix='perch-install-check-') as directory:
    root = Path(directory)
    stashes = [root/f'.Perch.previous-{build}-{moment}.app' for build, moment in ((203, 100), (204, 200), (205, 300))]
    stashes.append(root/'.Perch.previous-50.app')
    for stash in stashes:
        stash.mkdir()
    names = lambda paths: {path.name for path in paths}
    # Nothing is removed while any running Perch is unlocated.
    assert m.prunable(stashes, [], False, 1) == []
    # The newest copies by the time in their names are kept.
    assert names(m.prunable(stashes, [], True, 2)) == {'.Perch.previous-203-100.app', '.Perch.previous-50.app'}
    # A copy a running Perch executes from is never removed, however old.
    in_use = str(root/'.Perch.previous-50.app') + '/Contents/MacOS/Perch'
    assert '.Perch.previous-50.app' not in names(m.prunable(stashes, [in_use], True, 1))
    # A path that merely starts with the same characters is not inside the copy.
    lookalike = str(root/'.Perch.previous-50.app') + 'x/Contents/MacOS/Perch'
    assert '.Perch.previous-50.app' in names(m.prunable(stashes, [lookalike], True, 1))


def make_app(path, build):
    (path/'Contents/MacOS').mkdir(parents=True)
    (path/'Contents/MacOS/Perch').write_text(f'binary {build}')
    (path/'Contents/Info.plist').write_bytes(plistlib.dumps(values(build)))


copy = lambda source, destination: shutil.copytree(source, destination, symlinks=True)
accept = lambda app: None
with tempfile.TemporaryDirectory(prefix='perch-install-swap-') as directory:
    root = Path(directory)
    target = root/'Applications/Perch.app'
    make_app(root/'build/Perch.app', 206)
    make_app(target, 205)
    # A successful install swaps by rename and keeps the previous copy intact.
    stash = m.install(root/'build/Perch.app', target, accept, copy=copy, now=1000)
    assert stash.name == '.Perch.previous-205-1000.app' and m.number(m.info(target)) == 206
    assert (stash/'Contents/MacOS/Perch').read_text() == 'binary 205' and not (target.parent/m.STAGED).exists()
    # A staged copy that fails verification changes nothing and leaves no staging behind.
    make_app(root/'build/Next.app', 207)
    def reject(app):
        raise subprocess.CalledProcessError(1, 'codesign')
    try:
        m.install(root/'build/Next.app', target, reject, copy=copy, now=2000)
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError('A failed verification was not reported')
    assert m.number(m.info(target)) == 206 and not (target.parent/m.STAGED).exists()
    # A failed final rename puts the previous copy back where Perch expects it.
    real_rename = os.rename
    def failing(source, destination):
        if Path(source).name == m.STAGED:
            raise OSError('simulated rename failure')
        return real_rename(source, destination)
    m.os.rename = failing
    try:
        try:
            m.install(root/'build/Next.app', target, accept, copy=copy, now=3000)
        except OSError:
            pass
        else:
            raise AssertionError('A failed swap was not reported')
    finally:
        m.os.rename = real_rename
    assert m.number(m.info(target)) == 206 and not (target.parent/'.Perch.previous-206-3000.app').exists()
    assert not (target.parent/m.STAGED).exists()

print('PASS: refuses builds without update settings, differently signed or not moving forward; never removes a copy '
      'a running Perch uses or anything while one is unlocated; swaps by rename with rollback; no real apps touched')
