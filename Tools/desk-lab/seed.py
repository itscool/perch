#!/usr/bin/env python3
"""Build and run the desk seeder: one paired desk, one identity per guest."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import uuid
from pathlib import Path

import lab
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from perch_sources import source as perch_source

REPO = Path(__file__).resolve().parents[2]
SOURCES = ['PerchError.swift', 'SecureFile.swift', 'Subprocess.swift', 'KVMGroup.swift', 'KVMSync.swift',
           'KVMMembership.swift', 'KVMPeerIdentity.swift']


def seed(output: Path, guests: list[dict] | None = None) -> Path:
    """Build a paired desk for these guests, at the size their screens really are."""
    certificates = subprocess.run([sys.executable, str(REPO / 'Tools/certificate-dependency.py')],
                                  env=lab.toolchain_env(),
                                  capture_output=True, text=True, check=True).stdout.strip()
    output.mkdir(parents=True, exist_ok=True)
    binary = output / 'seed-desk'
    search = [certificates] + ([f'{certificates}/Modules'] if Path(f'{certificates}/Modules').is_dir() else [])
    # Where SwiftPM leaves the built modules differs between toolchains.
    includes = [flag for directory in search for flag in ('-I', directory)]
    subprocess.run(['xcrun', 'swiftc', *includes, '-L', certificates, '-lPerchCertificates',
                    *[str(perch_source(name)) for name in SOURCES], str(Path(__file__).with_name('seed') / 'main.swift'),
                    '-o', str(binary)], check=True, env=lab.toolchain_env())
    described = guests or [
        {'name': name,
         # The desk validates a screen's control identity as a UUID.
         'display': str(uuid.uuid5(uuid.NAMESPACE_DNS, f'perch-desk-lab.screen.{name}')),
         'widthMM': 368.9, 'heightMM': 280.7}
        for name in ('perch-a', 'perch-b')]
    subprocess.run([str(binary), str(output), json.dumps(described)], check=True)
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    seed(parser.parse_args().output)
