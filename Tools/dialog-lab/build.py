#!/usr/bin/env python3
"""Build only. Never launches the native dialog lab."""
from pathlib import Path
import argparse,plistlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
app=a.output.resolve()/'PerchDialogLab.app';(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.perch.dialog-lab',CFBundleName='PerchDialogLab',CFBundleExecutable='PerchDialogLab',CFBundlePackageType='APPL',CFBundleVersion='1')))
subprocess.run(['xcrun','swiftc',str(repo/'Sources/SettingsWindow.swift'),str(repo/'Tools/dialog-lab/main.swift'),'-framework','AppKit','-o',str(app/'Contents/MacOS/PerchDialogLab')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
