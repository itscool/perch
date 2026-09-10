#!/usr/bin/env python3
"""Headless journey checks for the native prototype's model; does not show UI."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='perch-desk-check-') as d:
    binary = str(Path(d) / 'check')
    sources = [repo / 'Sources' / f for f in ['KVMGroup.swift', 'KVMSync.swift', 'KVMHandoff.swift', 'DeskModel.swift']]
    sources += [repo / 'Tools/kvm-lab' / f for f in ['check-model.swift']]
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *map(str, sources), '-framework', 'SwiftUI', '-o', binary], check=True)
    subprocess.run([binary], check=True)
