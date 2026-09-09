#!/usr/bin/env python3
"""Exercise production row tooltip routing without showing a menu or window."""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=True)
(root / 'main.swift').write_text('''import AppKit
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message } }
enum StatusColors { static let perchPink = NSColor.systemPink }
final class AppDelegate: NSObject {
    let menu = NSMenu()
    var menuOpen = false
    var menuTitleSources: [NSMenuItem: NSAttributedString] = [:]
    var menuKeyMonitor: Any?
    @objc func quit() {}
}
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
do { try runMenuTooltipTests(); try runMenuBoundaryTests() }
catch { fputs("FAIL: \\(error)\\n", stderr); exit(1) }
''')
subprocess.run(['xcrun', 'swiftc', str(repo/'Sources/MenuRowView.swift'),
                str(repo/'Sources/MenuPresentation.swift'), str(repo/'Sources/MenuBoundaryTests.swift'),
                str(repo/'Sources/MenuTooltipTests.swift'), str(root/'main.swift'),
                '-framework', 'AppKit', '-o', str(root/'menu-tooltips')], check=True)
subprocess.run([str(root/'menu-tooltips')], check=True)
