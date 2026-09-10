#!/usr/bin/env python3
"""Compile and exercise only portable KVM code. No native windows or live devices."""
import argparse
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--output', type=Path)
a = p.parse_args()
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-kvm-') as temporary:
    out = a.output.resolve() if a.output else Path(temporary) / 'check-kvm'
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors',
                    *[str(repo / 'Sources' / f) for f in ['KVMGroup.swift', 'KVMSync.swift', 'KVMHandoff.swift']],
                    str(repo / 'Tools/check-kvm.swift'), '-o', str(out)], check=True)
    subprocess.run([str(out)], check=True)
