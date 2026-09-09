import AppKit
struct ProtectionIssue { enum Severity { case critical, warning }; var severity: Severity }
enum StatusColors { static let critical = NSColor.systemRed, warning = NSColor.systemOrange, success = NSColor.systemGreen }
final class AppDelegate: NSObject, NSApplicationDelegate {
    var count = 0
    let status = NSTextField(labelWithString: "No actions yet")
    func applicationDidFinishLaunching(_ note: Notification) { configureSettings() }
    func record(_ text: String) { count += 1; status.stringValue = "\(count): \(text)"; try? status.stringValue.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("dialog-results.txt"), atomically: true, encoding: .utf8) }
    @objc func configureSettings() {
        let host = SettingsWindow.shared
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 500))
        status.frame = NSRect(x: 8,y: 450,width: 550,height: 30); view.addSubview(status)
        let actions: [(String, () -> Void)] = [
            ("Keyboard controls", { self.keyboardControls() }),
            ("Long explanation", { host.show(.init(title: "Long explanation", detail: String(repeating: "This harmless explanation can be read and scrolled with the keyboard. ", count: 160), view: NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 100)))) }),
            ("Ordinary button", { self.record("ordinary action") }),
            ("Confirmation", { self.confirm() }),
            ("Informational result", { let a=NSAlert(); a.messageText="Harmless information"; a.informativeText="Back or Escape should return."; a.addButton(withTitle:"OK"); host.present(a) { self.record("info returned \($0.rawValue)") } }),
            ("File picker", { let p=NSOpenPanel(); p.title="Harmless picker — Cancel"; p.directoryURL=Bundle.main.bundleURL.deletingLastPathComponent(); self.record("picker returned \(host.open(p).rawValue)") }),
            ("Child page", { let child=NSView(frame:NSRect(x:0,y:0,width:572,height:150)); let b=SettingsActionButton(title:"Child button") { self.record("child action") };b.frame=NSRect(x:0,y:70,width:500,height:32);child.addSubview(b);host.show(.init(title:"Harmless child",detail:"Back returns to the lab.",view:child)) })
        ]
        for (index,action) in actions.enumerated() { let b=SettingsActionButton(title:action.0,action:action.1);b.frame=NSRect(x:8,y:390-index*60,width:550,height:36);view.addSubview(b) }
        host.show(.init(title:"Perch dialog lab",detail:"Isolated copies of the production window code. No helpers, permissions, hardware commands, or saved Perch settings.",view:view))
    }
    func keyboardControls() {
        let host = SettingsWindow.shared
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 572, height: 360))
        let name = NSTextField(string: "Practice text"); name.identifier = .init("lab.name")
        name.setAccessibilityLabel("Practice name"); name.frame = NSRect(x: 8, y: 295, width: 540, height: 28)
        let toggle = SettingsActionButton(title: "Harmless checkbox") { self.record("checkbox activated") }
        toggle.setButtonType(.switch); toggle.frame = NSRect(x: 8, y: 245, width: 540, height: 28)
        let popup = SettingsActionPopup(frame: NSRect(x: 8, y: 195, width: 540, height: 28), pullsDown: false)
        popup.setAccessibilityLabel("Practice choice"); popup.addItems(withTitles: ["First choice", "Second choice"])
        popup.callback = { self.record("popup changed") }
        let text = NSTextView(frame: NSRect(x: 8, y: 55, width: 540, height: 115)); text.string = "Multiline practice"
        text.setAccessibilityLabel("Practice notes"); text.setAccessibilityHelp("Control-Tab leaves this editor.")
        let done = SettingsActionButton(title: "Record harmless action") { self.record("keyboard page action") }
        done.frame = NSRect(x: 8, y: 5, width: 540, height: 32)
        [name, toggle, popup, text, done].forEach { view.addSubview($0) }
        host.show(.init(title: "Keyboard practice", detail: "Tab and Shift-Tab visit controls. Space toggles. Return activates buttons. In multiline text, Control-Tab moves on. No changes leave this lab.", view: view))
    }
    func confirm() { let a=NSAlert();a.messageText="Harmless confirmation";a.informativeText="Record should finish this dialog without any external action.";a.addButton(withTitle:"Record");a.addButton(withTitle:"Cancel");SettingsWindow.shared.present(a) { self.record("confirmation returned \($0.rawValue)") } }
    @objc func configurePanic() { configureSettings() }
    @objc func advancedSafetySettings() { configureSettings() }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate();app.delegate=delegate
app.run()
