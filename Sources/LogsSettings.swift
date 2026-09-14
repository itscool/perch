import AppKit

private final class TextLogPage {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 500))
    let status = NSTextField(wrappingLabelWithString: "Reading log…")
    let text = NSTextView(frame: .zero)
    private let title: String
    private let detail: String
    private let read: () -> String
    private var timer: Timer?
    private lazy var copyButton = SettingsActionButton(title: "Copy log") { [weak self] in
        guard let self else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(self.text.string, forType: .string)
    }
    init(title: String, detail: String, read: @escaping () -> String) {
        self.title = title; self.detail = detail; self.read = read
        status.font = .systemFont(ofSize: 12); status.frame = NSRect(x: 4, y: 448, width: 564, height: 40)
        text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 12); text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor; text.textContainerInset = NSSize(width: 10, height: 10)
        text.isVerticallyResizable = true; text.autoresizingMask = .width; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 42, width: 572, height: 398))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.borderType = .bezelBorder; scroll.documentView = text
        copyButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        [status, scroll, copyButton].forEach { view.addSubview($0) }
    }
    func show() {
        SettingsWindow.shared.show(.init(title: title, detail: detail, view: view, leave: { [weak self] in self?.stop() }))
        refresh()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func stop() { timer?.invalidate(); timer = nil }
    private func refresh() {
        guard SettingsWindow.shared.pages.last?.view === view else { return }
        let value = read(); text.string = value; copyButton.isEnabled = !value.isEmpty
        status.stringValue = value.isEmpty ? "No entries recorded yet." : "Updated (DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        status.textColor = .secondaryLabelColor
    }
}

extension AppDelegate {
    @objc func logsSettings() {
        let page = SettingsTaskPage(title: "Logs", detail: "Review recorded behavior when something is unclear. Logs are local to this Mac and each viewer explains its retention.", height: 300)
        page.add("Lid activity", detail: "Power, lid, helper, countdown and sleep/wake events from the last 24 hours.") { self.lidActivity() }
        page.add("CPU logs", detail: "CPU readings Perch collected while its CPU row was enabled and the menu was open.") { self.cpuLogs() }
        page.add("Agent safety activity", detail: "Recent process protection events recorded by the Agent Kill Switch.") { self.agentSafetyLogs() }
        page.add("Desk connection activity", detail: "Peer connection events from the current Desk, including unexpected disconnects.") {
            self.deskConnectionLogs()
        }
        page.show(delegate: self)
    }
    @objc func cpuLogs() {
        let sampler = systemMonitor.processCPU
        let page = TextLogPage(title: "CPU logs", detail: "Readings collected for the last 24 hours, up to 1,024 entries. Sampling runs only while the menu is open and CPU display is enabled.") {
            sampler.history.reversed().map { "\($0.date.formatted(.iso8601))  \($0.text)" }.joined(separator: "\n")
        }
        page.show()
    }
    @objc func agentSafetyLogs() {
        let page = TextLogPage(title: "Agent safety activity", detail: "Recent process-protection events from the last 24 hours, up to 200 entries. Perch stores these locally; no process names or event history leave this Mac.") {
            guard let raw = try? String(contentsOf: SafetyFiles.history, encoding: .utf8) else { return "" }
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let events = raw.split(separator: "\n").compactMap { try? JSONDecoder().decode(SafetyEvent.self, from: Data($0.utf8)) }
                .filter { $0.timestamp >= cutoff }.suffix(200).reversed()
            return events.map { event in
                let pid = event.pid.map(String.init) ?? "—"
                return "\(event.timestamp.formatted(.iso8601))  \(event.action) · \(event.name) [\(pid)] — \(event.result)"
            }.joined(separator: "\n")
        }
        page.show()
    }
    @objc func deskConnectionLogs() {
        if let runtime = DeskCoordinator.shared.runtime { DeskConnectionLogPage(node: runtime.node).show() }
        else { logsSettings() }
    }
}

private final class DeskConnectionLogPage {
    let node: KVMDeskNode
    init(node: KVMDeskNode) { self.node = node }
    func show() {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 572, height: 470))
        text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 12); text.textContainerInset = NSSize(width: 10, height: 10)
        let events = KVMConnectionEvent.retained(node.connectionEvents).reversed()
        text.string = events.isEmpty ? "No Desk connection events recorded on this Mac in the last 24 hours." : events.map { event in
            let duration = event.duration.map { String(format: " · %.1fs", $0) } ?? ""
            return "\(event.time.formatted(.iso8601))  \(event.peerName) · \(event.detail)\(duration)"
        }.joined(separator: "\n")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 572, height: 500)); scroll.hasVerticalScroller = true; scroll.documentView = text
        SettingsWindow.shared.show(.init(title: "Desk connection activity", detail: "Last 24 hours · up to 1,024 events on this Mac. Unexpected disconnects are marked in the Desk computer details.", view: scroll))
    }
}
