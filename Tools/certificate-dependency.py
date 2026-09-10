#!/usr/bin/env python3
"""Build the pinned private-peer certificate library; never reads signing keys."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[1]
package = repo / 'Vendor/PerchCertificates'
try:
    print('Preparing pinned Swift certificate dependencies (downloads missing packages and rebuilds stale artifacts)…', file=sys.stderr)
    subprocess.run(['xcrun', 'swift', 'build', '--package-path', str(package), '-c', 'release', '--disable-automatic-resolution'], stdout=sys.stderr, check=True)
    print(subprocess.check_output(['xcrun', 'swift', 'build', '--package-path', str(package), '-c', 'release', '--disable-automatic-resolution', '--show-bin-path'], text=True).strip())
except (OSError, subprocess.SubprocessError) as error:
    raise SystemExit('Swift dependency preparation failed. Check the compiler/network error above, finish Xcode setup and allow GitHub access, then rerun ./build.sh --check-dependencies. Package.resolved stays pinned; existing source changes are not reset. Details: '+str(error))
