#!/usr/bin/env python3
"""Exercise production read-before-write policy without hardware or real waits."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="perch-monitor-command-") as folder:
    root = Path(folder)
    (root/"main.swift").write_text(r'''import Foundation
var checks = 0
func check(_ condition: Bool) { precondition(condition); checks += 1 }
struct Failure: Error {}
for first in [nil, UInt16(17), UInt16(18)] {
    for last in [nil, UInt16(17), UInt16(18)] {
        var reads = 0, writes = 0, waits = 0
        let result = try DeskMonitorCommand.run(input: 17, permitted: { true }, read: {
            reads += 1; return reads == 1 ? first : last
        }, write: { writes += 1 }, settle: { waits += 1 })
        if first == 17 { check(result == .alreadySelected && reads == 1 && writes == 0 && waits == 0) }
        // A monitor that cannot say which input it shows gets the command once more;
        // one that reports another input contradicted it and is not sent it again.
        else { check(reads == 2 && writes == (last == nil ? 2 : 1) && waits == 1 && result == (last == 17 ? .switched : .unverified)) }
    }
}
var valid = true, writes = 0
var cancelled = false
do { _ = try DeskMonitorCommand.run(input: 17, permitted: { valid }, read: { valid = false; return 17 }, write: { writes += 1 }, settle: {}) } catch { cancelled = true }
check(cancelled && writes == 0)
let unavailable = try DeskMonitorCommand.run(input: 17, permitted: { true }, read: { throw Failure() }, write: { writes += 1 }, settle: {})
check(unavailable == .unverified && writes == 2)
var pauses = 0, repeated = 0
_ = try DeskMonitorCommand.run(input: 17, permitted: { true }, read: { nil }, write: { repeated += 1 }, settle: {}, pause: { pauses += 1 })
check(repeated == 2 && pauses == 1)
var stillValid = true, stopped = 0
_ = try DeskMonitorCommand.run(input: 17, permitted: { stillValid }, read: { nil }, write: { stopped += 1 }, settle: {}, pause: { stillValid = false })
check(stopped == 1)
var failed = false
do { _ = try DeskMonitorCommand.run(input: 17, permitted: { true }, read: { 18 }, write: { throw Failure() }, settle: { fatalError("Failed write must not settle") }) } catch { failed = true }
check(failed)
valid = true
let expired = try DeskMonitorCommand.run(input: 17, permitted: { valid }, read: { 18 }, write: { valid = false }, settle: {})
check(expired == .unverified)
var forcedWrites = 0, forcedWaits = 0
let forced = try DeskMonitorCommand.run(input: 17, permitted: { true }, read: { 17 }, write: { forcedWrites += 1 }, settle: { forcedWaits += 1 }, force: true)
check(forced == .switched && forcedWrites == 1 && forcedWaits == 1)
print("PASS: \(checks) monitor command checks; already-selected input sends no write and incurs no settle wait; unknown/read failures, cancelled lease, write failure and post-write expiry; an unconfirmable command is sent once more, never after the lease ends")
''')
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(perch_source('DeskMonitorCommand.swift')), str(root/"main.swift"), "-o", str(root/"check")], check=True)
    subprocess.run([str(root/"check")], check=True)
