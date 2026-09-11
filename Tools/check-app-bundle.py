#!/usr/bin/env python3
"""Compile disposable Mach-O fixtures; never launch Perch or any fixture."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from unittest.mock import patch
import app_bundle

REPO = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(list(map(str, args)), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def rejects(action, message):
    try:
        action()
    except (ValueError, OSError, subprocess.SubprocessError):
        return
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix='perch-packaging-tests-') as directory:
    root = Path(directory)
    # Exercise the actual production argument construction on macOS Bash 3.2.
    source = (REPO/'build.sh').read_text()
    options = source[source.index('\nSIGN_IDENTITY='):source.index('\n[[ "$(uname -s)"')]
    shell = root/'arguments.sh'
    shell.write_text('''set -euo pipefail
APP=/fixture/Perch.app
CHECK_DEPENDENCIES=0
set -- --output "$APP"
python3() { printf '%s\\n' "$@"; }
codesign() { printf '%s\\n' "$@"; }
''' + options + '\n' + '\n'.join(line for line in source.splitlines()
        if line.startswith('"${SPARKLE_COMMAND[@]}"') or line.startswith('codesign --force --sign')))
    for release in (False, True):
        env = dict(os.environ, PERCH_RELEASE_BUILD='1' if release else '0',
                   PERCH_SIGN_IDENTITY='Developer ID Application: Fixture' if release else 'Local Fixture',
                   PERCH_UPDATE_FEED_URL='https://example.invalid/feed', PERCH_UPDATE_PUBLIC_KEY='fixture')
        result = subprocess.check_output(['/bin/bash', str(shell)], env=env, text=True).splitlines()
        assert result.count('Tools/embed-sparkle.py') == 1
        assert ('--release' in result) == release
        assert ('--entitlements' in result) == release
        assert result.count('--sign') == 3 and '' not in result
    print('PASS: actual local/release embedding and signing arguments on /bin/bash', flush=True)

    sparkle = REPO/'build/dependencies/sparkle-2.9.6'
    if not (sparkle/'Sparkle.framework/Sparkle').is_file():
        raise SystemExit('Prepare the pinned Sparkle dependency before running this test.')
    app = root/'Original.app'
    binary = app/'Contents/MacOS/Perch'
    binary.parent.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'Perch', 'CFBundleIdentifier': 'local.perch.packaging-fixture',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}))
    code = root/'main.c'
    code.write_text('int main(void) { return 0; }\n')
    run('xcrun', 'clang', code, '-o', binary, '-F', sparkle,
        '-Wl,-needed_framework,Sparkle', '-Wl,-rpath,@executable_path/../Frameworks')
    # Real pinned framework, relative symlinks and nested ad-hoc signatures.
    run('python3', REPO/'Tools/embed-sparkle.py', app, '--identity', '-')
    run('/usr/bin/codesign', '--force', '--sign', '-', app)
    app_bundle.verify(app)

    def clone(name):
        destination = root/(name+'.app')
        shutil.copytree(app, destination, symlinks=True)
        return destination

    # Verification remains valid after relocation, with no build-cache rpath.
    moved = clone('Relocated')
    app_bundle.verify(moved)
    broken = clone('Missing framework')
    shutil.rmtree(broken/'Contents/Frameworks')
    rejects(lambda: app_bundle.verify(broken), 'Missing Sparkle accepted')
    broken = clone('Missing rpath')
    run('/usr/bin/install_name_tool', '-delete_rpath', '@executable_path/../Frameworks', broken/'Contents/MacOS/Perch')
    run('/usr/bin/codesign', '--force', '--sign', '-', broken)
    rejects(lambda: app_bundle.verify(broken), 'Missing runtime search path accepted')
    broken = clone('Broken link')
    (broken/'Contents/Frameworks/Sparkle.framework/Versions/Current').unlink()
    rejects(lambda: app_bundle.verify(broken), 'Broken framework link accepted')
    broken = clone('External framework')
    shutil.rmtree(broken/'Contents/Frameworks/Sparkle.framework')
    (broken/'Contents/Frameworks/Sparkle.framework').symlink_to(app/'Contents/Frameworks/Sparkle.framework')
    rejects(lambda: app_bundle.verify(broken), 'External framework accepted')
    broken = clone('Damaged signature')
    with (broken/'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle').open('ab') as stream:
        stream.write(b'damaged')
    rejects(lambda: app_bundle.verify(broken), 'Damaged nested signature accepted')
    print('PASS: relocated real Mach-O bundle; reject absent framework/rpath, broken/external links and damaged nested signature', flush=True)

    # Failed checks and failed final rename both preserve the old build.
    destination = clone('Previous')
    marker = destination/'old-build-marker'
    marker.write_text('previous app')
    rejects(lambda: app_bundle.finish(broken, destination), 'Invalid bundle replaced previous build')
    assert marker.read_text() == 'previous app'
    candidate = clone('Candidate')
    rename = os.replace
    def fail_candidate(source, target):
        if source == candidate:
            raise OSError('Simulated final rename failure')
        return rename(source, target)
    with patch.object(app_bundle.os, 'replace', side_effect=fail_candidate):
        rejects(lambda: app_bundle.finish(candidate, destination), 'Final rename failure not reported')
    assert marker.read_text() == 'previous app' and candidate.exists()
    # Even a failed rollback must leave the old app recoverable, not clean it up.
    def fail_move_and_restore(source, target):
        if source == candidate or source.parent.name.startswith('.perch-previous-'):
            raise OSError('Simulated destination failure')
        return rename(source, target)
    with patch.object(app_bundle.os, 'replace', side_effect=fail_move_and_restore):
        rejects(lambda: app_bundle.finish(candidate, destination), 'Rollback failure not reported')
    backups = list(root.glob('.perch-previous-*/Previous.app'))
    assert len(backups) == 1 and (backups[0]/'old-build-marker').read_text() == 'previous app'
    rename(backups[0], destination)
    app_bundle.finish(candidate, destination)
    assert not marker.exists() and not candidate.exists()
    app_bundle.verify(destination)
    print('PASS: invalid build preserves output; failed replacement restores it; failed rollback preserves recovery copy; successful replacement removes stale files', flush=True)

print('PASS: no app or fixture launched; no installed apps, permissions, keys, hardware or release services changed')
