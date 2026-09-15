#!/usr/bin/env python3
"""Exercise production inspector sizing across content and viewport changes, offscreen."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-inspector-check-') as folder:
    root = Path(folder)
    (root / 'main.swift').write_text(r'''
import AppKit
import SwiftUI
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
final class State: ObservableObject { @Published var expanded = false }
final class MarkerView: NSView { var name = "" }
struct Marker: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> MarkerView { let view = MarkerView(); view.name = name; return view }
    func updateNSView(_ view: MarkerView, context: Context) {}
}
struct Fixture: View {
    @ObservedObject var state: State
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Keyboard & mouse").font(.headline).background(Marker(name: "heading"))
                Toggle("Share on this Mac", isOn: .constant(false))
                Text("Turn on here and in Desk on each Mac you want to control. Then select a screen and start control below. Sharing turns off when Perch restarts.").font(.caption)
                Button("Input options…") {}
            }.fixedSize(horizontal: false, vertical: true)
            Divider()
            TextField("Screen", text: .constant("Home LG Old"))
            Button("Monitor setup…") {}
            Button("Physical size & position…") {}
            if state.expanded {
                ForEach(0..<16) { _ in Text("A longer readiness or display-matching explanation that wraps to several lines in a narrow inspector.") }
            }
            Text("HDMI 2 — Computer · Display matching pending")
            Button("Match display…") {}.background(Marker(name: "last"))
        }
    }
}
func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
func check(_ okay: Bool, _ message: String) { if !okay { fputs("FAIL: \(message)\n", stderr); exit(1) } }
var checks = 0
for theme in [NSAppearance.Name.aqua, .darkAqua] {
    let state = State()
    let wrapper = NSHostingView(rootView: InspectorScrollView { Fixture(state: state) })
    wrapper.appearance = NSAppearance(named: theme)
    func settle() {
        for _ in 0..<8 { wrapper.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
    }
    for width: CGFloat in [276, 200, 360, 276] {
        wrapper.frame = NSRect(x: 0, y: 0, width: width, height: 410); settle()
        let scroll = all(wrapper).compactMap { $0 as? InspectorNativeScrollView }.first!
        for expanded in [false, true, false] {
            state.expanded = expanded; settle()
            let document = scroll.documentView!
            let markers = all(document).compactMap { $0 as? MarkerView }
            let heading = markers.first { $0.name == "heading" }!
            let last = markers.first { $0.name == "last" }!
            let top = document.convert(heading.bounds, from: heading)
            let bottom = document.convert(last.bounds, from: last)
            check(top.minY >= -0.5, "Heading clipped above document at width \(width), expanded \(expanded): \(top)")
            check(bottom.maxY <= document.bounds.maxY + 0.5, "Last action extends below document")
            check(abs(document.frame.width - width) < 0.5, "Scroller changed content width")
            check(scroll.scrollerStyle == .overlay, "Scroller consumes the content margin")
            if expanded {
                let origin = scroll.contentView.constrainBoundsRect(NSRect(x: 0, y: 90, width: width, height: 410)).origin
                scroll.contentView.scroll(to: origin); settle()
                check(scroll.documentVisibleRect.minY > 0, "Long content cannot scroll")
                // Same-content refresh must not jump back to the start.
                let old = scroll.documentVisibleRect.minY
                wrapper.rootView = InspectorScrollView { Fixture(state: state) }; settle()
                check(abs(scroll.documentVisibleRect.minY - old) < 0.5, "Refresh reset reading position")
            } else if document.frame.height <= scroll.contentSize.height {
                check(abs(scroll.documentVisibleRect.minY) < 0.5, "Collapsed fitting content retained a hidden heading")
            }
            checks += 1
        }
    }
}
check(NSApp.windows.isEmpty, "Fixture opened a window")
print("PASS: \(checks) inspector states, wrapped heading/last action contained, stable width and scroll position, overflow/collapse across Light/Dark and resize; no windows")
''')
    binary = root / 'check'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', str(perch_source('InspectorScrollView.swift')), str(root / 'main.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
