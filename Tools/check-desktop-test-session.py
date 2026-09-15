#!/usr/bin/env python3
"""Check the desktop-session guard alone; never launch or authorize a UI test."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-session-guard-') as directory:
    root = Path(directory)
    (root / 'main.swift').write_text('''import Foundation
do { try DesktopTestSession.check(); print("accepted") }
catch { print(error.localizedDescription); exit(1) }
''')
    binary = root / 'guard-check'
    subprocess.run(['xcrun', 'swiftc', str(perch_source('PerchError.swift')), str(perch_source('Subprocess.swift')), str(perch_source('DesktopTestSession.swift')),
                    str(root / 'main.swift'), '-o', str(binary)], check=True)
    environment = {key: value for key, value in os.environ.items()
                   if key not in ('PERCH_AGENT_MODE_CHECKER', 'PERCH_AGENT_MODE_SESSION')}
    def check(expected, text):
        result = subprocess.run([str(binary)], env=environment, capture_output=True,
                                text=True, timeout=8)
        assert result.returncode == expected and text in result.stdout, result
    check(1, 'require an announced')
    checker = root / 'checker.py'
    environment.update(PERCH_AGENT_MODE_CHECKER=str(checker), PERCH_AGENT_MODE_SESSION=str(root))
    checker.write_text('raise SystemExit(1)\n')
    check(1, 'not active or control was requested')
    # This is a subprocess-contract test, not an AGENT MODE session. The binary
    # contains only the guard and cannot present a window or run app code.
    checker.write_text('raise SystemExit(0)\n')
    check(0, 'accepted')
    checker.write_text('import time\ntime.sleep(30)\n')
    check(1, 'check timed out')
    print('PASS: missing session, refusal, success and bounded timeout; no UI or app launch')
