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
// Exercise native mouse/key dispatch on unattached views: no windows or posted events.
let interaction = DeskWireController()
let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
let port = DeskWireSocketView(frame: NSRect(x: 10, y: 10, width: 24, height: 22))
let computer = DeskWireSocketView(frame: NSRect(x: 110, y: 10, width: 24, height: 22))
let portID = UUID(), computerID = UUID()
port.socketID = "port:" + portID.uuidString; computer.socketID = "computer:" + computerID.uuidString
for socket in [port, computer] { socket.controller = interaction; container.addSubview(socket); interaction.register(socket) }
var connections = 0
interaction.connect = { p, c in precondition(p == portID && c == computerID); connections += 1 }
func mouse(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 21), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
}
port.mouseDown(with: mouse(.leftMouseDown, 22)); port.mouseDragged(with: mouse(.leftMouseDragged, 122))
precondition(connections == 0 && interaction.target == computer.socketID, "Wire must preview before committing")
computer.setFrameOrigin(CGPoint(x: 180, y: 10)); container.layoutSubtreeIfNeeded(); interaction.geometryDidChange()
precondition(interaction.target == nil, "Resizing/moving a connector left a stale target")
computer.setFrameOrigin(CGPoint(x: 110, y: 10)); container.layoutSubtreeIfNeeded(); interaction.geometryDidChange()
precondition(interaction.target == computer.socketID, "Layout returning beneath the pointer did not restore target")
port.mouseUp(with: mouse(.leftMouseUp, 122)); precondition(connections == 1)
port.mouseDown(with: mouse(.leftMouseDown, 22)); port.mouseDragged(with: mouse(.leftMouseDragged, 250)); port.mouseUp(with: mouse(.leftMouseUp, 250))
precondition(connections == 1 && interaction.gesture.source == nil, "Release over empty canvas must cancel")
port.mouseDown(with: mouse(.leftMouseDown, 22)); port.mouseDragged(with: mouse(.leftMouseDragged, 122))
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
port.keyDown(with: escape); port.mouseUp(with: mouse(.leftMouseUp, 122)); precondition(connections == 1)
computer.mouseDown(with: mouse(.leftMouseDown, 122)); computer.mouseDragged(with: mouse(.leftMouseDragged, 22)); computer.mouseUp(with: mouse(.leftMouseUp, 22)); precondition(connections == 2)
port.mouseDown(with: mouse(.leftMouseDown, 22)); interaction.remove(port); port.mouseUp(with: mouse(.leftMouseUp, 122)); precondition(connections == 2)
interaction.cancel()
print("PASS: native socket dispatch previews and commits both directions, cancels invalid drops/Esc/source removal; no event posting or windows")
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
