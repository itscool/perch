#!/usr/bin/env python3
"""Build a standalone native KVM prototype. Never launches it or touches Perch."""
import argparse
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from perch_sources import source as perch_source
import plistlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
p.add_argument('--installable', action='store_true', help='Use a separate preview identity and per-user Application Support storage')
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
folder = a.output.resolve()
app = folder / ('Perch Desk Preview.app' if a.installable else 'PerchDeskLab.app')
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
info = dict(
    CFBundleIdentifier='local.perch.desk-preview' if a.installable else 'local.perch.desk-lab', CFBundleName='Perch Desk Preview' if a.installable else 'Perch Desk Lab',
    CFBundleExecutable='PerchDeskLab', CFBundlePackageType='APPL', CFBundleVersion='1',
    NSHighResolutionCapable=True)
if not a.installable: info['KVMStorePath'] = str(folder / 'demo-desk.json')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
sources = [perch_source(f) for f in ['PerchError.swift', 'KVMGroup.swift', 'KVMSync.swift', 'DeskModel.swift', 'DeskBackend.swift', 'DeskFixtures.swift', 'InspectorScrollView.swift', 'DeskView.swift', 'DeskPageState.swift', 'DeskHeader.swift', 'DeskPresetStrip.swift', 'DeskCanvas.swift', 'DeskScreenTile.swift', 'DeskPortSocket.swift', 'DeskComputerCard.swift', 'DeskWireController.swift', 'DeskSheets.swift', 'DeskCanvasLayout.swift', 'StatusColors.swift', 'SettingsFeedback.swift', 'PannableSurface.swift', 'DeskTextSetting.swift', 'DeskTextDraft.swift']]
sources += [repo / 'Tools/kvm-lab' / f for f in ['KVMHandoff.swift', 'DeskSimulation.swift', 'LabSheets.swift', 'LabView.swift', 'main.swift']]
subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *map(str, sources), '-framework', 'AppKit', '-framework', 'SwiftUI', '-o', str(app / 'Contents/MacOS/PerchDeskLab')], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
print(app)
