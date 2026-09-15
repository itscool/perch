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
        let simulation = DeskSimulation(store: store)
        let m = simulation.makeModel()
        try check(m.canUse, "initial configured demo is ready")
        m.usePreset(); try check(m.activeFocus == "Mac Studio", "simulated handoff names actual destination")
        let studioPort = m.group.connections.first { $0.inputCode == 15 }!
        simulation.mapComputer(port: studioPort.id, computer: studioPort.computer!)
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
        let reopened = DeskSimulation(store: store).makeModel()
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
        simulation.failNextSwitch = true; m.usePreset()
        try check(m.active == nil && m.problem?.contains("did not confirm") == true, "partial switch failure clears active claim")
        m.usePreset(); try check(m.active != nil && m.problem == nil, "failure can retry without reconstructing desk")
        let studio = m.group.computers[1].id
        simulation.toggleOnline(studio)
        try check(!m.canUse && m.readinessIssue?.contains("offline") == true, "offline availability is correct before click")
        simulation.toggleOnline(studio)
        try check(m.canUse, "reconnect restores action without erasing mappings")
        simulation.simulateConflict(); let beforeConflict = m.group
        m.renameMonitor("Should not commit")
        try check(m.group == beforeConflict && !m.canUse, "conflict blocks accidental overwrite")
        simulation.resolve(useOther: false)
        try check(m.conflict == nil && m.canUse, "explicit resolution restores editing")
        m.removeComputer(studio)
        try check(m.group.connections.contains { $0.inputName == "DisplayPort" && $0.computer == nil }, "removed computer leaves input choices available")
        try check(m.active == nil, "membership removal drops live input claim")
        let previous = m.group
        m.removeComputer(m.group.computers[0].id)
        try check(m.group == previous && m.online.contains(m.group.computers[0].id), "rejected removal does not alter availability")
        simulation.newDesk("First use")
        try check(m.group.computers.count == 1 && m.group.monitors.isEmpty && !m.canUse, "first-use draft is saved and incomplete")
        simulation.addScreen("Screen", computer: m.group.computers[0].id)
        try check(!m.canUse && m.group.presets.allSatisfy { $0.assignments.isEmpty }, "new screen doesn't silently join switching actions")
        for i in 0..<3 { m.assign(m.group.connections[0].id, preset: i) }
        try check(m.canUse, "all required connection choices complete setup")
        simulation.addComputer("Third Mac")
        try check(m.group.computers.count == 2 && m.unsent == 0 && m.saveStatus == "Saved", "adding online member does not leave stale pending-sync status")
        let port = m.group.connections[0].id
        m.correctConnection(port, physicalScreen: nil)
        try check(m.group.monitors.count == 2 && m.group.presets.allSatisfy { $0.assignments.isEmpty }, "split mistaken shared identity clears affected ownership")
        let corrupt = dir.appendingPathComponent("corrupt.json"), bad = Data("bad data".utf8)
        try bad.write(to: corrupt)
        let broken = DeskSimulation(store: corrupt).makeModel(); broken.edit { $0.name = "Overwrite" }
        let preserved = try Data(contentsOf: corrupt)
        try check(preserved == bad && !broken.canUse, "failed load does not overwrite original")
        // Cable and profile edits never manufacture/move physical screen identities.
        var cables = KVMGroup.sample()
        let screenID = cables.monitors[0].id, computerID = cables.computers[0].id
        let source = cables.connections.first { $0.monitor == screenID && $0.computer == computerID }!
        let target = cables.connections.first { $0.monitor == screenID && $0.computer == nil }!
        let geometry = cables.monitors.map(\.geometry), assignments = cables.presets.map(\.assignments)
        try DeskCableBinding.apply(connection: target.id, computer: computerID, display: source.localDisplay, to: &cables)
        try check(cables.connections.first { $0.id == source.id }?.computer == nil && cables.connections.first { $0.id == target.id }?.computer == computerID, "moving cable clears prior port atomically")
        try check(cables.monitors.map(\.geometry) == geometry && cables.presets.map(\.assignments) == assignments, "cable edits preserve physical geometry and preset input choices")
        let otherPort = cables.connections.first { $0.monitor != screenID }!
        let cableSnapshot = cables
        do { try DeskCableBinding.apply(connection: otherPort.id, computer: computerID, display: source.localDisplay, to: &cables); throw KVMError("accepted duplicate physical display") } catch {
            try check(cables == cableSnapshot, "rejected duplicate display preserves the entire desk")
        }
        cables.monitors[0].control = .init(computer: computerID, localDisplay: source.localDisplay!)
        let savedPorts = cables.connections.filter { $0.monitor == screenID }
        try DeskMonitorConfiguration.apply(monitor: screenID, profile: "Fixture LG", ports: [.init(name: "USB-C", code: 209), .init(name: "DisplayPort", code: 208), .init(name: "HDMI 1", code: 144), .init(name: "HDMI 2", code: 145)], mode: "lg", to: &cables)
        try check(cables.monitors[0].inputProfile == "Fixture LG" && cables.monitors[0].control?.mode == "lg", "profile saves alongside monitor control")
        try check(savedPorts.allSatisfy { old in cables.connections.contains { $0.id == old.id && $0.computer == old.computer && $0.localDisplay == old.localDisplay } } && cables.presets.map(\.assignments) == assignments, "profile changes preserve cable/port identity and all presets")
        let configured = cables
        do { try DeskMonitorConfiguration.apply(monitor: screenID, profile: "Bad", ports: [.init(name: "Wrong port", code: 209)], mode: "lg", to: &cables); throw KVMError("accepted duplicate input code") } catch {
            try check(cables == configured, "invalid profile does not partially change working configuration")
        }
        try DeskCableBinding.apply(connection: target.id, computer: nil, display: nil, to: &cables)
        try check(cables.connections.first { $0.id == target.id }?.computer == nil && cables.presets.map(\.assignments) == assignments, "disconnect preserves physical input and preset choice")
        var identification = DeskIdentificationState()
        let first = identification.toggle("screen")
        try check(first.showing, "Identify starts")
        let cancelled = identification.toggle("screen")
        try check(!cancelled.showing && cancelled.token == first.token && identification.active.isEmpty, "same Identify cancels")
        let restarted = identification.toggle("screen")
        try check(restarted.showing && restarted.token != first.token, "Identify starts afresh after cancellation")
        try check(!identification.expire("screen", token: first.token) && identification.active["screen"] == restarted.token, "old timer cannot cancel a restarted identification")
        _ = identification.toggle("other")
        try check(identification.expire("screen", token: restarted.token) && identification.active["other"] != nil, "timeout affects only its own identification")
        try check(identification.toggle("screen").showing, "Identify restarts after timeout")
        let shared = UUID()
        identification.apply("monitor:shared", token: shared, showing: true)
        try check(identification.active["monitor:shared"] == shared, "peer identification start shares its session token")
        identification.apply("monitor:shared", token: UUID(), showing: false)
        try check(identification.active["monitor:shared"] == shared, "stale peer stop cannot cancel a newer identification")
        identification.apply("monitor:shared", token: shared, showing: false)
        try check(identification.active["monitor:shared"] == nil, "peer stop cancels the shared identification")
        let fixed = CGRect(x: 0, y: 0, width: 600, height: 340)
        let leftDrop = CGRect(x: -561, y: 10, width: 550, height: 310)
        let snapped = DeskScreenPlacement.place(leftDrop, among: [fixed], scale: 1)
        try check(snapped.maxX == fixed.minX && snapped.midY == fixed.midY, "right monitor docks left and previews the nearest center alignment")
        let free = CGRect(x: -750, y: 0, width: 550, height: 310)
        try check(DeskScreenPlacement.place(free, among: [fixed], scale: 1) == free, "intentional large gaps remain available")
        let overlapping = CGRect(x: 100, y: 0, width: 550, height: 310)
        let rescued = DeskScreenPlacement.place(overlapping, among: [fixed], scale: 1)
        try check(rescued.maxX <= fixed.minX || rescued.minX >= fixed.maxX || rescued.maxY <= fixed.minY || rescued.minY >= fixed.maxY, "overlapping drop docks instead of jumping to old location")
        for scale in [0.05, 0.1, 0.5, 1.0, 2.0] {
            for step in 1...40 {
                let gap = Double(step) / 4
                let proposed = CGRect(x: fixed.maxX + gap / scale, y: 13, width: 310, height: 550)
                let placed = DeskScreenPlacement.place(proposed, among: [fixed], scale: scale)
                try check(placed.minX == fixed.maxX && placed.minY == (13 * scale <= 18 ? 0 : 13) && placed.size == proposed.size, "snap uses screen-point tolerance with rotated physical dimensions")
            }
        }
        for (y, expected, label) in [(3.0, 0.0, "Top"), (28.0, 30.0, "Bottom"), (14.0, 15.0, "Center")] {
            let proposed = CGRect(x: 608, y: y, width: 550, height: 310)
            let preview = DeskScreenPlacement.preview(proposed, among: [fixed], scale: 1)
            try check(preview.rectangle.minY == expected && preview.guides.contains { $0.horizontal && $0.label == label }, "snap preview identifies the chosen " + label)
            let free = DeskScreenPlacement.preview(proposed, among: [fixed], scale: 1, bypass: true)
            try check(free.rectangle == proposed && free.guides.isEmpty, "Shift bypasses both docking and alignment")
        }
        let aligned = DeskScreenPlacement.preview(CGRect(x: 605, y: 2, width: 600, height: 340), among: [fixed], scale: 1)
        try check(Set(aligned.guides.filter(\.horizontal).map(\.label)) == ["Top", "Center", "Bottom"], "show simultaneous alignment guides")
        var wire = DeskWireGesture()
        wire.begin("port:a", at: .zero); wire.move(to: CGPoint(x: 2, y: 0))
        try check(wire.finish(insideSource: true, target: nil) == .click, "a small movement remains a release-triggered click")
        wire.begin("port:a", at: .zero); wire.move(to: CGPoint(x: 3, y: 0)); wire.move(to: .zero)
        try check(wire.finish(insideSource: true, target: nil) == .cancel, "returning to the source after dragging never opens its menu")
        for (source, target) in [("port:a", "computer:b"), ("computer:b", "port:a")] {
            wire.begin(source, at: .zero); wire.move(to: CGPoint(x: 20, y: 0))
            try check(wire.finish(insideSource: false, target: target) == .connect(source, target), "wire connects in either direction")
        }
        wire.begin("port:a", at: .zero); wire.move(to: CGPoint(x: 20, y: 0))
        try check(wire.finish(insideSource: false, target: "port:b") == .cancel, "same-side targets do not connect")
        wire.begin("port:a", at: .zero); wire.move(to: CGPoint(x: 20, y: 0)); wire = DeskWireGesture()
        try check(wire.finish(insideSource: true, target: "computer:b") == .cancel, "Esc cancellation consumes the later mouse-up")
        wire.begin("port:a", at: .zero)
        try check(wire.finish(insideSource: false, target: nil) == .cancel, "release outside the source cancels even before the threshold")
        var pending = KVMGroup.sample()
        let pendingIndex = pending.connections.firstIndex { $0.computer != nil }!
        let pendingCable = pending.connections[pendingIndex], pendingComputer = pendingCable.computer!
        let counterpart = pending.connections.first { $0.monitor == pendingCable.monitor && $0.computer != nil && $0.computer != pendingComputer }!
        pending.connections[pendingIndex].localDisplay = nil
        try check((try? pending.validated()) != nil, "a known cable can save before its display identity arrives")
        let originalPending = pending
        let reports = [KVMDisplayObservation(computer: counterpart.computer!, localDisplay: counterpart.localDisplay!, vendor: 7789, model: 1, numericSerial: 42, textSerial: nil),
                       KVMDisplayObservation(computer: pendingComputer, localDisplay: "new-display", vendor: 7789, model: 1, numericSerial: 42, textSerial: nil)]
        let resolved = DeskPendingCableResolver.resolve(pending, observations: reports)
        try check(resolved.connections[pendingIndex].localDisplay == "new-display" && resolved.presets == pending.presets && resolved.monitors == pending.monitors, "paired observations complete the chosen cable without changing the desk or presets")
        var duplicate = reports[1]; duplicate.localDisplay = "identical-other-display"
        try check(DeskPendingCableResolver.resolve(pending, observations: reports + [duplicate]) == originalPending, "identical reports with colliding serials remain pending")
        var different = reports[1]; different.numericSerial = 99
        try check(DeskPendingCableResolver.resolve(pending, observations: [reports[0], different]) == originalPending, "unrelated identities cannot complete a cable")
        try check(DeskPendingCableResolver.resolve(pending, observations: []) == originalPending, "missing remote reports preserve the saved cable")
        let fit = DeskCanvasLayout(rectangles: [fixed, snapped], viewport: CGSize(width: 400, height: 250))
        try check(abs((600 * fit.scale) / (550 * fit.scale) - 600 / 550.0) < 0.0001, "auto-fit preserves physical proportions")
        print("PASS: \(count) desk-model journey checks — immediate save, reopen, readiness, picture-only inputs, failure/retry, removal and correction. No windows shown.")
    }
}
