#!/usr/bin/env python3
"""Headless journey checks for the native prototype's model; does not show UI."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from perch_sources import source as perch_source
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='perch-desk-check-') as d:
    binary = str(Path(d) / 'check')
    sources = [perch_source(f) for f in ['PerchError.swift', 'KVMGroup.swift', 'KVMSync.swift', 'DeskModel.swift', 'DeskBackend.swift', 'DeskPageState.swift', 'DeskFixtures.swift', 'DeskCanvasLayout.swift']]
    sources += [repo / 'Tools/kvm-lab' / f for f in ['KVMHandoff.swift', 'DeskSimulation.swift', 'LabSheets.swift', 'check-model.swift']]
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *map(str, sources), '-framework', 'SwiftUI', '-o', binary], check=True)
    subprocess.run([binary], check=True)
