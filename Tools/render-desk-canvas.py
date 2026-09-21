#!/usr/bin/env python3
"""Render the production SwiftUI Desk canvas with simulated devices and no windows."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import argparse
import subprocess
import tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--full', action='store_true', help='Render the entire Desk page rather than only the canvas')
parser.add_argument('--active-preset', type=int, choices=[1, 2, 3], help='Simulate a confirmed preset independently of the editing selection')
parser.add_argument('--scenario', choices=['default', 'busy', 'empty'], default='default', help='busy: status, caution, conflict, failure and switching states; empty: first-use desk')
parser.add_argument('--width', type=int, default=1200, help='Full-page render width in points')
parser.add_argument('--height', type=int, default=860, help='Full-page render height in points')
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
port.socketID = "port:" + portID.uuidString; computer.socketID = "preset:" + computerID.uuidString + ":2"
for socket in [port, computer] { socket.controller = interaction; container.addSubview(socket); interaction.register(socket) }
var connections = 0
interaction.draw = { slot, c, p in precondition(slot == 2 && p == portID && c == computerID); connections += 1 }
interaction.moveWire = { _, _ in preconditionFailure("A free input has no wire to move") }
interaction.removeWire = { _ in preconditionFailure("A free input has no wire to remove") }
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
precondition(connections == 1 && interaction.gesture.source == nil, "A new wire released over empty canvas draws nothing")
port.mouseDown(with: mouse(.leftMouseDown, 22)); port.mouseDragged(with: mouse(.leftMouseDragged, 122))
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
port.keyDown(with: escape); port.mouseUp(with: mouse(.leftMouseUp, 122)); precondition(connections == 1)
computer.mouseDown(with: mouse(.leftMouseDown, 122)); computer.mouseDragged(with: mouse(.leftMouseDragged, 22)); computer.mouseUp(with: mouse(.leftMouseUp, 22)); precondition(connections == 2)
port.mouseDown(with: mouse(.leftMouseDown, 22)); interaction.remove(port); port.mouseUp(with: mouse(.leftMouseUp, 122)); precondition(connections == 2)
interaction.cancel()
print("PASS: native socket dispatch draws new wires in both directions, previews before committing, draws nothing on empty drops/Esc/source removal; no event posting or windows")
let simulation = DeskSimulation(store: URL(fileURLWithPath: CommandLine.arguments[2]))
let model = simulation.makeModel()
// A connected input detaches its monitor end when dragged, without changing
// storage until release: onto another input it moves, into space it goes.
// Exercise native dispatch rather than only assigning state.
let rewireController = DeskWireController()
let rewires = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
let oldPort = DeskWireSocketView(frame: NSRect(x: 10, y: 10, width: 24, height: 22))
let newPort = DeskWireSocketView(frame: NSRect(x: 110, y: 10, width: 24, height: 22))
let hostSocket = DeskWireSocketView(frame: NSRect(x: 210, y: 10, width: 24, height: 22))
var desk = KVMGroup.sample()
let original = desk.connections[0], targetCable = desk.connections[1]
oldPort.socketID = "port:" + original.id.uuidString
newPort.socketID = "port:" + targetCable.id.uuidString
hostSocket.socketID = "preset:" + original.computer!.uuidString + ":1"
for socket in [oldPort, newPort, hostSocket] { socket.controller = rewireController; rewires.addSubview(socket); rewireController.register(socket) }
rewireController.connection = { id in desk.connections.first { "port:" + $0.id.uuidString == id } }
var rewired = 0, removed = 0
rewireController.draw = { _, _, _ in preconditionFailure("Dragging a connected input must move it, not draw another wire") }
rewireController.moveWire = { from, to in
    try! DeskCableBinding.rewire(desk.connections.first { $0.id == from }!, to: desk.connections.first { $0.id == to }!, in: &desk); rewired += 1
}
rewireController.removeWire = { port in try! DeskCableBinding.apply(connection: port, computer: nil, display: nil, to: &desk); removed += 1 }
// Only a wire the person can see is picked up: an input connected for other
// presets, or connected with no wire drawn here, starts a new wire instead.
rewireController.routed = { _ in false }
oldPort.mouseDown(with: mouse(.leftMouseDown, 22)); oldPort.mouseDragged(with: mouse(.leftMouseDragged, 122))
precondition(rewireController.detachedPort == nil && rewireController.cableSource == oldPort.socketID, "A connected input with no wire in this preset was picked up instead of drawing a new one")
rewireController.cancel()
rewireController.routed = { _ in true }
let before = desk
oldPort.mouseDown(with: mouse(.leftMouseDown, 22))
precondition(rewireController.end(oldPort.socketID, at: CGPoint(x: 23, y: 21)), "An occupied input still clicks without rewiring")
oldPort.mouseDown(with: mouse(.leftMouseDown, 22)); oldPort.mouseDragged(with: mouse(.leftMouseDragged, 122))
// The wire in hand hangs from that computer's connector for the preset being
// edited, so the drag looks like the cable it picked up.
precondition(rewireController.cableSource == hostSocket.socketID && rewireController.target == newPort.socketID && rewireController.detachedPort == original.id && desk == before)
oldPort.keyDown(with: escape); oldPort.mouseUp(with: mouse(.leftMouseUp, 122))
precondition(desk == before && rewired == 0 && removed == 0, "Esc must restore the picked-up cable")
oldPort.mouseDown(with: mouse(.leftMouseDown, 22)); oldPort.mouseDragged(with: mouse(.leftMouseDragged, 350)); oldPort.mouseUp(with: mouse(.leftMouseUp, 350))
precondition(removed == 1 && rewired == 0 && desk.connections[0].computer == nil && desk.connections[1] == before.connections[1], "A detached end dropped in space removes that wire only")
desk = before
oldPort.mouseDown(with: mouse(.leftMouseDown, 22)); oldPort.mouseDragged(with: mouse(.leftMouseDragged, 122)); oldPort.mouseUp(with: mouse(.leftMouseUp, 122))
precondition(rewired == 1 && desk.connections[0].computer == nil && desk.connections[1].computer == original.computer && desk.connections[1].localDisplay == original.localDisplay)
precondition(desk.monitors == before.monitors, "Rewiring must not change physical screens")
desk = before
oldPort.mouseDown(with: mouse(.leftMouseDown, 22)); oldPort.mouseDragged(with: mouse(.leftMouseDragged, 122))
desk.connections[0].computer = nil; desk.connections[0].localDisplay = nil
let concurrent = desk
oldPort.mouseUp(with: mouse(.leftMouseUp, 122))
precondition(desk == concurrent && rewired == 1 && removed == 1, "Concurrent cable edits must cancel a stale gesture")
var failed = before; failed.connections[1].computer = nil; failed.connections[1].localDisplay = nil
let failedBefore = failed
var rejected = false
do { try DeskCableBinding.rewire(original, to: targetCable, in: &failed) } catch { rejected = true }
precondition(rejected && failed == failedBefore, "Stale destination must reject atomically")
var cross = before
try DeskCableBinding.rewire(original, to: cross.connections[2], in: &cross)
precondition(cross.connections[0].computer == nil && cross.connections[2].computer == original.computer && cross.connections[2].localDisplay == nil, "Different physical screen requires fresh display identity")
oldPort.mouseEntered(with: mouse(.mouseMoved, 22)); precondition(oldPort.hovered)
oldPort.mouseExited(with: mouse(.mouseMoved, 22)); precondition(!oldPort.hovered)
precondition(oldPort.attachmentPoint.y == oldPort.bounds.minY && hostSocket.attachmentPoint.y == hostSocket.bounds.maxY, "Wire anchors must meet opposite device edges")
rewireController.cancel()
// Every subset of this three-monitor desk, across all three presets. Editing
// another monitor must not depend on the selected inspector or affect cables.
let sample = model.group
for presetIndex in 0..<3 {
    for mask in 0..<8 {
        model.group = sample; model.presetIndex = presetIndex
        for (index, monitor) in sample.monitors.enumerated() {
            let input = mask & (1 << index) == 0 ? nil : sample.connections.first { $0.monitor == monitor.id }?.id
            model.assign(input, monitor: monitor.id)
        }
        precondition(model.group.connections == sample.connections && model.active == nil)
        for index in 0..<3 where index != presetIndex { precondition(model.group.presets[index] == sample.presets[index]) }
        precondition(model.preset.assignments.count == mask.nonzeroBitCount)
        precondition((model.readinessIssue == nil) == (mask != 0), "Only completely empty presets should be unavailable")
    }
}
model.group = sample; model.presetIndex = 0
if let active = Int(CommandLine.arguments[4]), (1...3).contains(active) { model.active = sample.presets[active - 1]; model.activeGroup = sample }
switch CommandLine.arguments[7] {
case "busy":
    model.status = "Controlling Main screen on Mac Studio."
    model.caution = "Perch accepted the switch for Main screen (DisplayPort) but the monitor cannot report its input. The picture usually changed; if it did not, choose the input again."
    model.active = sample.presets[1]; model.activeGroup = sample; model.activeUnconfirmed = true
    model.switchingPreset = sample.presets[2].id
    model.monitorProblems = [sample.monitors[2].id]
    simulation.simulateConflict()
case "empty":
    simulation.newDesk("New desk")
default: break
}
print("PASS: connected inputs move or disappear when dropped, cancellation, concurrent edits, edge anchors, hover and all 24 preset/subset combinations")
let canvas = DeskCanvas(model: model, remove: { _ in }, dimensions: { _ in }, identify: { _ in }, hardware: { _ in }, cable: { _, _ in }, editPort: { _ in }, addPort: { _ in }, computerDetails: { _ in }, removeComputer: { _ in }, addComputer: {})
let content = VStack(alignment: .leading, spacing: 14) {
    Text("Perch · Desk cables").font(.system(size: 26, weight: .semibold))
    Text("Production canvas · Simulated devices · No live desktop interaction").foregroundStyle(.secondary)
    canvas.frame(width: 950, height: 560)
}.padding(24).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)
let full = CommandLine.arguments[3] == "full"
let rootView = full ? AnyView(DeskView(model: model).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)) : AnyView(content)
let host = NSHostingView(rootView: rootView)
host.frame = NSRect(x: 0, y: 0, width: full ? CGFloat(Int(CommandLine.arguments[5]) ?? 1200) : 998, height: full ? CGFloat(Int(CommandLine.arguments[6]) ?? 860) : 682)
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
    sources = ['PerchError.swift', 'KVMGroup.swift', 'KVMSync.swift', 'DeskModel.swift', 'DeskBackend.swift', 'DeskFixtures.swift', 'InspectorScrollView.swift', 'StatusColors.swift', 'SettingsFeedback.swift', 'DeskView.swift', 'DeskPageState.swift', 'DeskHeader.swift', 'DeskPresetStrip.swift', 'DeskCanvas.swift', 'DeskScreenTile.swift', 'DeskPortSocket.swift', 'DeskComputerCard.swift', 'DeskWireController.swift', 'DeskSheets.swift', 'DeskCanvasLayout.swift', 'PannableSurface.swift', 'DeskTextSetting.swift', 'DeskTextDraft.swift']
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', *[str(perch_source(s)) for s in sources], *[str(repo / 'Tools/kvm-lab' / s) for s in ['KVMHandoff.swift', 'DeskSimulation.swift', 'LabSheets.swift']], str(root/'main.swift'), '-o', str(root/'render')], check=True)
    subprocess.run([str(root/'render'), str(args.output.resolve()), str(root/'demo.json'), 'full' if args.full else 'canvas', str(args.active_preset or 0), str(args.width), str(args.height), args.scenario], check=True)
