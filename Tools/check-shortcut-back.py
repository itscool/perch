#!/usr/bin/env python3
"""Compile the exact production shortcut-flow method and shared window, hidden.
Dependency stubs supply status/configuration and collect errors; no helper,
global hotkey registration, native modal loop or desktop presentation runs.
"""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import argparse, subprocess
p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True)
a = p.parse_args(); root = a.output.resolve(); root.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parents[1]
source = (perch_source('PanicUI.swift')).read_text()
flow = source[source.index('    func runShortcutTest('):source.index('    @objc func finishPanicTest()')]
(root/'main.swift').write_text('''import AppKit
import Carbon
enum SettingsResetScope: CaseIterable, Hashable { case settings, keyboardLayouts, appearance, perchPrivacy, sleep, allAppsPrivacy }
struct ProtectionIssue { enum Severity { case critical, warning }; var severity: Severity }
enum StatusColors { static let critical = NSColor.systemRed, warning = NSColor.systemOrange, success = NSColor.systemGreen }
struct SafetyConfiguration { var shortcut = Shortcut(); static func load() -> Self { Self() } }
struct SafetyStatus {
    var locked: Bool; var pendingLaunchJobs: Int; var shortcutActive: Bool
    var inputTrusted: Bool?; var inputActive: Bool; var keepAwakeActive: Bool
    var trackedCount: Int; var targets: [String]; var message: String; var error: String?
    var timestamp = Date(); var testUntil: Date?; var testResultID: String?
    var fresh: Bool { Date().timeIntervalSince(timestamp) < 5 }
}
final class AppDelegate: NSObject {
    @objc func configureSettings() {}
    @objc func configurePanic() {}
    @objc func advancedSafetySettings() {}
    @objc func presentBackgroundSetup() {}
    func showError(_ error: Error) { fatalError("Unexpected fixture error: \\(error)") }
''' + flow + '''
}
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
do { try runShortcutDialogBackTests() }
catch { fputs("FAIL: \\(error)\\n", stderr); exit(1) }
''')
subprocess.run(['xcrun','swiftc',str(perch_source('PerchError.swift')),str(perch_source('MainTimer.swift')),str(perch_source('SettingsWindow.swift')),str(perch_source('SettingsAccessibility.swift')),str(perch_source('SettingsSidebar.swift')),
               str(perch_source('Shortcut.swift')),str(perch_source('ShortcutDialogBackTests.swift')),
               str(root/'main.swift'),'-framework','AppKit','-framework','Carbon',
               '-o',str(root/'shortcut-back')],check=True)
subprocess.run([str(root/'shortcut-back')],check=True)
