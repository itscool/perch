#!/usr/bin/env python3
"""Build the pinned private-peer certificate library; never reads signing keys."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[1]
package = repo / 'Vendor/PerchCertificates'
subprocess.run(['swift', 'build', '--package-path', str(package), '-c', 'release', '--disable-automatic-resolution'], stdout=sys.stderr, check=True)
print(subprocess.check_output(['swift', 'build', '--package-path', str(package), '-c', 'release', '--show-bin-path'], text=True).strip())
