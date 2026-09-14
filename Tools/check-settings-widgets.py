#!/usr/bin/env python3
"""Render shared settings widgets offscreen; no app state or live shortcuts."""
from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-settings-widgets-') as folder:
    root = Path(folder)
    (root/'main.swift').write_text(r'''
import AppKit
import SwiftUI
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
func height(_ text: String?, width: CGFloat, kind: SettingsFeedbackKind) -> CGFloat {
    let host = NSHostingView(rootView: SettingsFeedback(text: text, kind: kind).frame(width: width).fixedSize(horizontal: false, vertical: true))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
    host.layoutSubtreeIfNeeded()
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: bitmap) }
    return host.fittingSize.height
}
for width: CGFloat in [280, 640] {
    for kind: SettingsFeedbackKind in [.information, .progress, .warning, .success] {
        let empty = height(nil, width: width, kind: kind)
        let short = height("Ready", width: width, kind: kind)
        let long = height(String(repeating: "A failure with a clear recovery action. ", count: 24), width: width, kind: kind)
        check(empty == 0 && long > short, "Feedback does not size to its current message")
    }
    let editor = NSHostingView(rootView: SettingsShortcutEditor(title: "Fixture", enabled: .constant(true), key: .constant("F1"), choices: [("F1", "F1")], modifiers: .constant(0)).fixedSize(horizontal: false, vertical: true))
    editor.frame = NSRect(x: 0, y: 0, width: width, height: 1000); editor.layoutSubtreeIfNeeded()
    if let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds) { editor.cacheDisplay(in: editor.bounds, to: bitmap) }
    check(editor.fittingSize.height < 130, "Shortcut layout acquired a large empty area")
}
check(SettingsFeedbackKind.progress.color != SettingsFeedbackKind.warning.color, "Progress uses warning color")
check(NSApp.windows.isEmpty, "Fixture opened a window")
print("PASS: shared feedback empty/short/wrapped states and responsive shortcut layout at narrow/wide widths; no windows or live edits")
''')
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *[str(repo/'Sources'/f) for f in ['StatusColors.swift','SettingsFeedback.swift','SettingsShortcutEditor.swift']], str(root/'main.swift'), '-o', str(root/'check')], check=True)
    subprocess.run([str(root/'check')], check=True)
