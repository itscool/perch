#!/usr/bin/env python3
"""Check the production AppKit sidebar without windows or live state."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-sidebar-check-') as folder:
    root = Path(folder)
    (root / 'main.swift').write_text(r'''
import AppKit
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
func check(_ value: Bool, _ message: String) {
    if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
var checks = 0
for theme in [NSAppearance.Name.aqua, .darkAqua] {
for scrollerStyle in [NSScroller.Style.overlay, .legacy] {
    let sidebar = SettingsSidebar(frame: NSRect(x: 0, y: 0, width: 220, height: 330))
    sidebar.appearance = NSAppearance(named: theme)
    sidebar.scroll.scrollerStyle = scrollerStyle
    sidebar.scroll.autohidesScrollers = false
    var value: SettingsSetupStatus = .checking
    var navigations = 0
    sidebar.readSetupStatus = { ["access": value] }
    sidebar.choose = { _ in navigations += 1 }
    sidebar.configure([
        .init(id: "setup", title: "Setup", pageTitles: [], open: {}),
        .init(id: "access", title: "Scrolling & navigation", pageTitles: [], depth: 1, setupStage: true, open: {}),
        .init(id: "desk", title: "Desk", pageTitles: [], open: {})
    ] + (0..<30).map { SettingsDestination(id: "extra\($0)", title: "Extra page \($0)", pageTitles: [], open: {}) })
    for width: CGFloat in [sidebar.preferredWidth, sidebar.preferredWidth + 60, sidebar.preferredWidth] {
        sidebar.setFrameSize(NSSize(width: width, height: 330))
        sidebar.needsLayout = true; sidebar.layoutSubtreeIfNeeded()
        sidebar.update(selected: "access", busy: false)
        let cell = sidebar.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as! NSTableCellView
        for state: SettingsSetupStatus in [.ready, .attention, .optional, .checking] {
            value = state; sidebar.refreshSetupStatus(); cell.layoutSubtreeIfNeeded()
            check(sidebar.table.selectedRow == 1 && navigations == 0, "Refresh changed navigation")
            check(sidebar.table.view(atColumn: 0, row: 1, makeIfNecessary: false) === cell, "Refresh replaced the row")
            check(cell.imageView?.image != nil, "Missing status symbol")
            check(cell.imageView?.isHidden == (state == .checking) && cell.bounds.contains(cell.imageView!.frame), "Wrong status presentation or bounds")
            let progress = (cell as! SettingsSidebarCell).progress
            check(progress.isHidden == (state != .checking), "Progress did not replace the static status symbol")
            check(cell.textField!.frame.width >= cell.textField!.intrinsicContentSize.width, "Full destination label is truncated")
            check(cell.bounds.contains(cell.textField!.frame), "Label outside actual cell bounds")
            check(!cell.textField!.frame.intersects(cell.imageView!.frame), "Label overlaps status image")
            check(cell.accessibilityValue() as? String == state.rawValue, "Missing accessible status")
            check(cell.toolTip?.contains(state.rawValue) == true, "Missing status tooltip")
            let visibleIcon = cell.imageView!.convert(cell.imageView!.bounds, to: sidebar.scroll.contentView)
            check(sidebar.scroll.contentView.bounds.insetBy(dx: 4, dy: 0).contains(visibleIcon), "Status clipped by scroll viewport: icon \(visibleIcon), viewport \(sidebar.scroll.contentView.bounds)")
            checks += 1
        }
        let plain = sidebar.table.view(atColumn: 0, row: 2, makeIfNecessary: true) as! NSTableCellView
        plain.layoutSubtreeIfNeeded()
        check(plain.imageView == nil && plain.bounds.contains(plain.textField!.frame), "Ordinary destination layout changed")
    }
}
}
check(NSApp.windows.isEmpty, "Fixture opened a window")
print("PASS: \(checks) production sidebar states across Light/Dark and width changes; visible symbols, contained nonoverlapping labels, stable cells/selection and accessible status; no windows")
''')
    binary = root / 'check'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', str(perch_source('SettingsSidebar.swift')), str(root / 'main.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
