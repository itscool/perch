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
        let view = NSView(frame: NSRect(x: 0,y: 0,width: 572,height: 440))
        status.frame = NSRect(x: 8,y: 390,width: 550,height: 30); view.addSubview(status)
        let actions: [(String, () -> Void)] = [
            ("Ordinary button", { self.record("ordinary action") }),
            ("Confirmation", { self.confirm() }),
            ("Informational result", { let a=NSAlert(); a.messageText="Harmless information"; a.informativeText="Back or Escape should return."; a.addButton(withTitle:"OK"); host.present(a) { self.record("info returned \($0.rawValue)") } }),
            ("File picker", { let p=NSOpenPanel(); p.title="Harmless picker — Cancel"; p.directoryURL=Bundle.main.bundleURL.deletingLastPathComponent(); self.record("picker returned \(host.open(p).rawValue)") }),
            ("Child page", { let child=NSView(frame:NSRect(x:0,y:0,width:572,height:150)); let b=SettingsActionButton(title:"Child button") { self.record("child action") };b.frame=NSRect(x:0,y:70,width:500,height:32);child.addSubview(b);host.show(.init(title:"Harmless child",detail:"Back returns to the lab.",view:child)) })
        ]
        for (index,action) in actions.enumerated() { let b=SettingsActionButton(title:action.0,action:action.1);b.frame=NSRect(x:8,y:330-index*60,width:550,height:36);view.addSubview(b) }
        host.show(.init(title:"Perch dialog lab",detail:"Isolated copies of the production window code. No helpers, permissions, hardware commands, or saved Perch settings.",view:view))
    }
    func confirm() { let a=NSAlert();a.messageText="Harmless confirmation";a.informativeText="Record should finish this dialog without any external action.";a.addButton(withTitle:"Record");a.addButton(withTitle:"Cancel");SettingsWindow.shared.present(a) { self.record("confirmation returned \($0.rawValue)") } }
    @objc func configurePanic() { configureSettings() }
    @objc func advancedSafetySettings() { configureSettings() }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate();app.delegate=delegate
app.run()
