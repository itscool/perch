#!/usr/bin/env python3
"""Render the production SwiftUI Desk canvas with simulated devices and no windows."""
from pathlib import Path
import argparse
import subprocess
import tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
args.output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='perch-canvas-render-') as folder:
    root = Path(folder)
    (root/'main.swift').write_text(r'''
import AppKit
import SwiftUI
try MainActor.assumeIsolated {
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let model = DeskModel(store: URL(fileURLWithPath: CommandLine.arguments[2]))
let canvas = DeskCanvas(model: model, remove: { _ in }, dimensions: { _ in }, cable: { _, _ in }, editPort: { _ in }, addPort: { _ in }, computerDetails: { _ in }, removeComputer: { _ in }, addComputer: {})
let content = VStack(alignment: .leading, spacing: 14) {
    Text("Perch · Desk cables").font(.system(size: 26, weight: .semibold))
    Text("Production canvas · Simulated devices · No live desktop interaction").foregroundStyle(.secondary)
    canvas.frame(width: 950, height: 560)
}.padding(24).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)
let host = NSHostingView(rootView: content)
host.frame = NSRect(x: 0, y: 0, width: 998, height: 682)
host.layoutSubtreeIfNeeded()
if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
    host.cacheDisplay(in: host.bounds, to: bitmap)
    if let data = bitmap.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    } else { fatalError("PNG encoding failed") }
} else { fatalError("Offscreen canvas did not render") }
precondition(NSApp.windows.isEmpty, "Renderer presented a window")
print("PASS: production Desk canvas rendered without windows or live settings")
}
''')
    sources = ['KVMGroup.swift', 'KVMSync.swift', 'KVMHandoff.swift', 'DeskModel.swift', 'InspectorScrollView.swift', 'DeskView.swift', 'DeskCanvasLayout.swift', 'DeskTextSetting.swift', 'DeskTextDraft.swift']
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *[str(repo/'Sources'/s) for s in sources], str(root/'main.swift'), '-o', str(root/'render')], check=True)
    subprocess.run([str(root/'render'), str(args.output.resolve()), str(root/'demo.json')], check=True)
