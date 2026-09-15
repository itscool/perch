#!/usr/bin/env python3
"""Compile production dialog ownership and exercise hidden target/action fixtures.
No windows are shown; no native modal loop, picker, helper or hardware is run.
Use the separate native dialog lab / AGENT MODE for physical input acceptance.
"""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import argparse, subprocess
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = args.output.resolve(); root.mkdir(parents=True, exist_ok=True)
(root/'main.swift').write_text('''import AppKit
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message } }
enum SettingsResetScope: CaseIterable, Hashable { case settings, keyboardLayouts, appearance, perchPrivacy, sleep, allAppsPrivacy }
struct ProtectionIssue { enum Severity { case critical, warning }; var severity: Severity }
enum StatusColors { static let critical = NSColor.systemRed, warning = NSColor.systemOrange, success = NSColor.systemGreen }
final class AppDelegate: NSObject {
    @objc func configureSettings() {}
    @objc func configurePanic() {}
    @objc func advancedSafetySettings() {}
    @objc func presentBackgroundSetup() {}
}
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
do { try runDialogOwnershipTests(); try runSettingsAccessibilityTests(); try runSettingsSidebarTests() }
catch { fputs("FAIL: \\(error)\\n", stderr); exit(1) }
''')
subprocess.run(['xcrun','swiftc',str(perch_source('MainTimer.swift')),str(perch_source('SettingsWindow.swift')),str(perch_source('SettingsAccessibility.swift')),str(perch_source('SettingsSidebar.swift')),str(perch_source('DialogOwnershipTests.swift')),str(perch_source('SettingsSidebarTests.swift')),str(perch_source('SettingsAccessibilityTests.swift')),str(perch_source('PermissionDragItem.swift')),str(root/'main.swift'),'-framework','AppKit','-o',str(root/'dialog-ownership')],check=True)
subprocess.run([str(root/'dialog-ownership')],check=True)
