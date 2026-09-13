#!/usr/bin/env python3
"""Run windowless Sparkle fault/retry fixtures built by check-sparkle.py --headless.
Only a disposable fixture is launched/replaced. Production lid transport is mocked.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--root', type=Path, required=True)
p.add_argument('--port', type=int, required=True)
a = p.parse_args(); root = a.root.resolve()
app = root/'installed/Perch.app'; executable = str(app/'Contents/MacOS/Perch')
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'].startswith('local.perch.sparkle-fixture.') and info.get('LSUIElement') is True
assert info['FixtureRoot'] == str(root) and info['CFBundleVersion'] == '1'
assert info['SUFeedURL'] == f'http://127.0.0.1:{a.port}/appcast.xml'
assert app.stat().st_uid == root.stat().st_uid
repo = Path(__file__).resolve().parents[1]
backup = root/'original.app'
if backup.exists(): raise SystemExit('Use a fresh fixture root')
shutil.copytree(app, backup, symlinks=True)
zipfile = root/'feed/Perch-1.2.2.zip'; archive = zipfile.read_bytes()
control = root/'server-mode'; results = []
def pids():
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines()
    return [int(f[0]) for row in rows if len(f := row.strip().split(None, 1)) == 2 and f[1] == executable]
def wait_exit():
    deadline = time.monotonic()+10
    while pids() and time.monotonic() < deadline: time.sleep(.2)
    assert not pids(), 'Fixture did not exit'
with (root/'server.log').open('w') as out:
    server = subprocess.Popen(['python3', str(repo/'Tools/sparkle-test-server.py'), '--root', str(root/'feed'), '--port', str(a.port), '--control', str(control)], stdout=out, stderr=out)
    try:
        for _ in range(50):
            try:
                with socket.create_connection(('127.0.0.1', a.port), timeout=.2): break
            except OSError: time.sleep(.1)
        else: raise RuntimeError('Loopback server did not start')
        for scenario in ('dismiss', 'cancel', 'disconnect', 'tamper', 'retry'):
            assert not pids()
            for name in ('result', 'completed', 'events.log', 'fail-prepare'):
                (root/name).unlink(missing_ok=True)
            (root/'scenario').write_text(scenario)
            control.write_text({'cancel':'slow', 'disconnect':'disconnect'}.get(scenario, 'normal'))
            zipfile.write_bytes(archive + b'invalid appended data' if scenario == 'tamper' else archive)
            if scenario == 'retry': (root/'fail-prepare').touch()
            subprocess.run(['/usr/bin/open', '-g', '-j', '-n', str(app)], check=True)
            deadline = time.monotonic()+100
            while time.monotonic() < deadline:
                if (root/'result').exists() or (root/'completed').exists(): break
                time.sleep(.25)
            else: raise RuntimeError('Fixture timed out in '+scenario)
            wait_exit()
            events = (root/'events.log').read_text()
            result = (root/'result').read_text() if (root/'result').exists() else 'completed'
            build = plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']
            if scenario == 'retry':
                assert result == 'completed' and build == '2', (result, build, events)
                assert events.count('prepare exact identity') == 2 and 'Injected fixture transport failure' in events
                assert 'claim exact identity' in events and 'termination allowed' in events
                prepared = [s.split()[-1] for s in events.splitlines() if s.startswith('prepare exact identity')]
                claimed = [s.split()[-1] for s in events.splitlines() if s.startswith('claim exact identity')]
                assert prepared[0] == prepared[1] == claimed[0]
                assert not (root/'storage/Updates/network-restart.json').exists()
            else:
                assert build == '1' and 'prepare exact identity' not in events, (result, events)
                assert result == {'dismiss':'dismissed', 'cancel':'cancelled'}.get(scenario, result)
                if scenario in ('disconnect', 'tamper'): assert result.startswith('error:'), result
            (root/(scenario+'-events.log')).write_text(events)
            results.append({'scenario':scenario, 'result':result, 'installedBuild':build})
            print('PASS: '+json.dumps(results[-1]), flush=True)
        (root/'results.json').write_text(json.dumps(results, indent=2)+'\n')
    finally:
        server.terminate(); server.wait(timeout=5)
        # Stop only this test's exact executable if a failed case left it behind.
        for pid in pids():
            subprocess.run(['/bin/kill', '-TERM', str(pid)], check=False)
        zipfile.write_bytes(archive)
