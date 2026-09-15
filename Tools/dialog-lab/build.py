#!/usr/bin/env python3
"""Build only. Never launches the native dialog lab."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from perch_sources import source as perch_source
import argparse,plistlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--bundle-id',default='local.perch.dialog-lab');a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
app=a.output.resolve()/'PerchDialogLab.app';(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=a.bundle_id,CFBundleName='PerchDialogLab',CFBundleExecutable='PerchDialogLab',CFBundlePackageType='APPL',CFBundleVersion='1')))
subprocess.run(['xcrun','swiftc',str(perch_source('SettingsWindow.swift')),str(perch_source('SettingsAccessibility.swift')),str(perch_source('SettingsSidebar.swift')),str(repo/'Tools/dialog-lab/main.swift'),'-framework','AppKit','-o',str(app/'Contents/MacOS/PerchDialogLab')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
