#!/usr/bin/env python3
"""Nonpresenting value-model tests. No app/helper launch, windows, devices or settings writes."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-settings-models-') as directory:
    root = Path(directory)
    (root / 'main.swift').write_text(r'''
import Foundation
func check(_ value: Bool, _ message: String) {
    guard value else { fatalError(message) }
}
var draft = DeskTextDraft("Office")
draft.receive("Studio")
check(draft.text == "Studio" && !draft.dirty && !draft.conflict, "Remote edit did not refresh pristine field")
draft.text = ""
draft.receive("Shared screen")
check(draft.text.isEmpty && draft.dirty && draft.conflict && draft.baseline == "Shared screen", "Remote edit erased the invalid local draft")
draft.receive("Renamed again")
check(draft.text.isEmpty && draft.baseline == "Renamed again" && draft.conflict, "Second remote edit lost conflict")
draft.accept(draft.baseline)
check(draft.text == "Renamed again" && !draft.dirty && !draft.conflict, "Use saved did not resolve conflict")
draft.text = "My screen"
draft.receive("My screen")
check(!draft.dirty && !draft.conflict, "Own save acknowledgement created conflict")
var code = DeskTextDraft("17")
code.text = ""
check(code.dirty && code.baseline == "17", "Clearing a code changed its saved value")
code.text = "2"
check(code.baseline == "17", "Partial numeric edit escaped its draft")
code.text = "209"; code.accept(code.text)
check(!code.dirty && code.baseline == "209", "Completed code did not settle")
let computer = KVMComputer(name: "Mac")
let screen = KVMMonitor(name: "Screen", geometry: .init(x: 0, y: 0, width: 600, height: 340))
var group = KVMGroup(name: "Desk", computers: [computer], monitors: [screen])
let display = UUID().uuidString
group.connections = [.init(monitor: screen.id, computer: computer.id, localDisplay: display, inputName: "USB-C", inputCode: 209)]
group.presets[0].assignments = [.init(monitor: screen.id, connection: group.connections[0].id)]
let original = group.reviewDetails
func difference(_ change: (inout KVMGroup) -> Void, _ description: String) {
    var changed = group; change(&changed)
    check(changed.reviewDetails != original, "Conflict review hides " + description)
}
difference({ $0.monitors[0].geometry.width = 601 }, "panel dimensions")
difference({ $0.monitors[0].geometry.x = 10 }, "position")
difference({ $0.monitors[0].geometry.rotation = .clockwise }, "rotation")
difference({ $0.connections[0].inputCode = 27 }, "protocol input code")
difference({ $0.connections[0].localDisplay = UUID().uuidString }, "host display mapping")
difference({ $0.connections[0].computer = nil; $0.connections[0].localDisplay = nil }, "unassigned input")
difference({ $0.presets[0].shortcut.shift = true }, "shortcut modifiers")
difference({ $0.presets[0].assignments = [] }, "cleared preset selection")
difference({ $0.sharedKeyboards = [.init(name: "MX", bindings: [computer.id: "attachment"], follow: true)] }, "shared keyboard")
var routed = group
routed.monitors[0].control = .init(computer: computer.id, localDisplay: display, mode: MonitorConnection(kind: "nec-lan", endpoint: "192.0.2.3", address: 2, model: "Example").argument)
let details = routed.reviewDetails.joined(separator: "\n")
for value in ["nec-lan", "192.0.2.3", "address 2", "Example", display, "Code 209", "F1"] {
    check(details.contains(value), "Missing review value: " + value)
}
var keyboard = group
keyboard.sharedKeyboards = [.init(name: "MX", bindings: [computer.id: "one"], follow: false)]
let beforeKeyboard = keyboard.reviewDetails
keyboard.sharedKeyboards![0].follow = true
check(keyboard.reviewDetails != beforeKeyboard, "Review hides follow behavior")
let beforeBinding = keyboard.reviewDetails
keyboard.sharedKeyboards![0].bindings[computer.id] = "two"
check(keyboard.reviewDetails != beforeBinding, "Review hides keyboard attachment")
print("PASS: pristine/dirty/concurrent draft transitions and complete Desk conflict value coverage; no UI or live state")
''')
    sources = ['DeskTextDraft.swift', 'KVMGroup.swift', 'KVMReviewDetails.swift', 'MonitorConnection.swift']
    subprocess.run(['xcrun', 'swiftc', *[str(repo / 'Sources' / name) for name in sources], str(root / 'main.swift'), '-o', str(root / 'check')], check=True)
    subprocess.run([str(root / 'check')], check=True)
