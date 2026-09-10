#!/usr/bin/env python3
"""Fetch the pinned upstream binary; never execute an unverified download."""
import hashlib
from pathlib import Path
import subprocess
import urllib.request

VERSION = '2.9.6'
SHA256 = '52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192'
ROOT = Path(__file__).resolve().parents[1] / 'build/dependencies'

def dependency():
    ROOT.mkdir(parents=True, exist_ok=True)
    archive = ROOT / f'Sparkle-{VERSION}.tar.xz'
    if not archive.exists():
        request = urllib.request.Request(f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{archive.name}', headers={'User-Agent': 'Perch-build'})
        with urllib.request.urlopen(request, timeout=60) as response:
            archive.write_bytes(response.read(40 * 1024 * 1024))
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit(f'Sparkle checksum mismatch: remove {archive} and retry.')
    destination = ROOT / f'sparkle-{VERSION}'
    # Extract each time so an edited cached framework cannot silently enter a build.
    destination.mkdir(exist_ok=True)
    subprocess.run(['tar', '-xf', str(archive), '-C', str(destination)], check=True)
    return destination

if __name__ == '__main__':
    print(dependency())
