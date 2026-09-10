import Foundation

@main struct DeskModelChecks {
    static func main() throws {
        var count = 0
        func check(_ yes: @autoclosure () -> Bool, _ message: String) throws {
            guard yes() else { throw KVMError("FAIL: " + message) }; count += 1
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-desk-model-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("desk.json")
        let m = DeskModel(store: store)
        try check(m.canUse, "initial configured demo is ready")
        m.usePreset(); try check(m.activeFocus == "Mac Studio", "simulated handoff names actual destination")
        let studioPort = m.group.connections.first { $0.inputCode == 15 }!
        m.mapConnection(studioPort.id, computer: studioPort.computer)
        try check(m.group.connections.first { $0.id == studioPort.id } == studioPort && !m.changedSinceUse, "unchanged dropdown selection preserves live binding")
        m.changeConnection(studioPort.id, input: "Work input")
        try check(m.group.connections.first { $0.id == studioPort.id }?.inputCode == 15 && !m.changedSinceUse, "input label rename preserves physical input and active state")
        m.changeConnection(studioPort.id, input: "DisplayPort")
        m.edit { $0.name = "Renamed desk" }
        try check(!m.changedSinceUse, "name changes don't require routing activation")
        let original = m.group
        let originalBytes = try Data(contentsOf: store)
        m.move(m.group.monitors[0].id, x: 100, y: 30)
        try check(m.problem != nil && m.group == original, "invalid overlapping edit preserves valid desk")
        let stillSaved = try Data(contentsOf: store)
        try check(stillSaved == originalBytes, "invalid edit does not overwrite durable data")
        let reopened = DeskModel(store: store)
        try check(reopened.group == original && reopened.active == nil, "reopen retains configuration but doesn't invent live ownership")
        m.selected = m.group.monitors[0].id
        let unknown = m.group.connections.first { $0.computer == nil }!
        m.assign(unknown.id, preset: 0)
        try check(m.canUse && m.unassignedWarning != nil, "unassigned physical input warns but remains usable")
        m.usePreset()
        try check(m.active != nil && m.activeFocus == nil && m.notice.contains("input stays local"), "picture-only preset doesn't invent input recipient")
        let preview = m.presetIndex
        m.assign(unknown.id, preset: 2)
        try check(m.presetIndex == preview && m.group.presets[2].assignments.contains { $0.connection == unknown.id }, "edit any preset without navigating away")
        m.failNextSwitch = true; m.usePreset()
        try check(m.active == nil && m.problem?.contains("did not confirm") == true, "partial switch failure clears active claim")
        m.usePreset(); try check(m.active != nil && m.problem == nil, "failure can retry without reconstructing desk")
        let studio = m.group.computers[1].id
        m.toggleOnline(studio)
        try check(!m.canUse && m.readinessIssue?.contains("offline") == true, "offline availability is correct before click")
        m.toggleOnline(studio)
        try check(m.canUse, "reconnect restores action without erasing mappings")
        m.simulateConflict(); let beforeConflict = m.group
        m.renameMonitor("Should not commit")
        try check(m.group == beforeConflict && !m.canUse, "conflict blocks accidental overwrite")
        m.resolve(useOther: false)
        try check(m.conflict == nil && m.canUse, "explicit resolution restores editing")
        m.removeComputer(studio)
        try check(m.group.connections.contains { $0.inputName == "DisplayPort" && $0.computer == nil }, "removed computer leaves input choices available")
        try check(m.active == nil, "membership removal drops live input claim")
        let previous = m.group
        m.removeComputer(m.group.computers[0].id)
        try check(m.group == previous && m.online.contains(m.group.computers[0].id), "rejected removal does not alter availability")
        m.newDesk("First use")
        try check(m.group.computers.count == 1 && m.group.monitors.isEmpty && !m.canUse, "first-use draft is saved and incomplete")
        m.addScreen("Screen", computer: m.group.computers[0].id)
        try check(!m.canUse && m.group.presets.allSatisfy { $0.assignments.isEmpty }, "new screen doesn't silently join switching actions")
        for i in 0..<3 { m.assign(m.group.connections[0].id, preset: i) }
        try check(m.canUse, "all required connection choices complete setup")
        m.addComputer("Third Mac")
        try check(m.group.computers.count == 2 && m.unsent == 0 && m.saveStatus == "Saved in this demo", "adding online member does not leave stale pending-sync status")
        let port = m.group.connections[0].id
        m.correctConnection(port, physicalScreen: nil)
        try check(m.group.monitors.count == 2 && m.group.presets.allSatisfy { $0.assignments.isEmpty }, "split mistaken shared identity clears affected ownership")
        let corrupt = dir.appendingPathComponent("corrupt.json"), bad = Data("bad data".utf8)
        try bad.write(to: corrupt)
        let broken = DeskModel(store: corrupt); broken.edit { $0.name = "Overwrite" }
        let preserved = try Data(contentsOf: corrupt)
        try check(preserved == bad && !broken.canUse, "failed load does not overwrite original")
        print("PASS: \(count) desk-model journey checks — immediate save, reopen, readiness, picture-only inputs, failure/retry, removal and correction. No windows shown.")
    }
}
