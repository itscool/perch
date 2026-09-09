import AppKit

// A separate, nonactivating indicator: restarting the app under test must not
// remove the notice, and password fields must retain their keyboard focus.
final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct Session: Codable {
    var token: String
    var expires: Double
    var phase: String
}

final class AgentBanner: NSObject, NSApplicationDelegate {
    let directory: URL
    let token: String
    var panels: [BannerPanel] = []
    var labels: [(NSTextField, NSTextField, NSButton)] = []
    var timer: Timer?
    var requested = false
    init(directory: URL, token: String) { self.directory = directory; self.token = token }
    func readSession() -> Session? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("session.json")),
              let value = try? JSONDecoder().decode(Session.self, from: data), value.token == token else { return nil }
        return value
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
        // The controller must see this acknowledgment before touching an app.
        guard !panels.isEmpty, panels.allSatisfy({ $0.isVisible }) else { NSApp.terminate(nil); return }
        try? Data(token.utf8).write(to: directory.appendingPathComponent("ready"), options: .atomic)
    }
    @objc func rebuild() {
        panels.forEach { $0.orderOut(nil) }; panels.removeAll(); labels.removeAll()
        for screen in NSScreen.screens {
            let width = min(CGFloat(580), screen.visibleFrame.width - 24)
            let rect = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - 90, width: width, height: 78)
            let panel = BannerPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.appearance = NSAppearance(named: .darkAqua)
            let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.03, alpha: 0.98).cgColor
            view.layer?.cornerRadius = 12; view.layer?.borderWidth = 3
            view.layer?.borderColor = NSColor(calibratedRed: 1, green: 0.72, blue: 0.18, alpha: 1).cgColor
            let title = NSTextField(labelWithString: "AGENT MODE")
            title.font = .systemFont(ofSize: 20, weight: .heavy)
            title.textColor = NSColor(calibratedRed: 1, green: 0.78, blue: 0.28, alpha: 1)
            title.frame = NSRect(x: 18, y: 43, width: width - 180, height: 25)
            let detail = NSTextField(wrappingLabelWithString: "Agent is testing the UI. Please pause mouse and keyboard use.")
            detail.font = .systemFont(ofSize: 12); detail.textColor = .white
            detail.frame = NSRect(x: 18, y: 9, width: width - 180, height: 32)
            let control = NSButton(title: "Request control", target: self, action: #selector(requestControl))
            control.bezelStyle = .rounded
            control.frame = NSRect(x: width - 155, y: 23, width: 138, height: 32)
            control.setAccessibilityHelp("Ask the agent to stop before its next action. An action already started may finish.")
            [title, detail, control].forEach { view.addSubview($0) }
            panel.contentView = view
            panels.append(panel); labels.append((title, detail, control))
            panel.orderFrontRegardless() // Never activate or make a key window.
        }
        refresh()
    }
    @objc func requestControl() {
        // A separate marker cannot be overwritten by a concurrent heartbeat.
        do {
            try Data(token.utf8).write(to: directory.appendingPathComponent("control-requested"), options: .atomic)
            requested = true
        } catch {
            labels.forEach { $0.1.stringValue = "Couldn’t send the request. Ask the agent to stop in chat." }
            return
        }
        refresh()
    }
    func refresh() {
        guard let session = readSession(), session.phase == "active" else { NSApp.terminate(nil); return }
        let expired = Date().timeIntervalSince1970 >= session.expires
        for (title, detail, button) in labels {
            title.stringValue = requested ? "CONTROL REQUESTED" : expired ? "AGENT MODE PAUSED" : "AGENT MODE"
            detail.stringValue = requested ? "Waiting for the agent to stop. Its current action may finish." : expired ? "Session timed out. The agent must reconnect before continuing." : "Agent is testing the UI. Please pause mouse and keyboard use."
            button.isEnabled = !requested
        }
    }
}

guard CommandLine.arguments.count == 3 else { fputs("Usage: agent-banner SESSION_DIRECTORY TOKEN\n", stderr); exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AgentBanner(directory: URL(fileURLWithPath: CommandLine.arguments[1]), token: CommandLine.arguments[2])
app.delegate = delegate
app.run()
