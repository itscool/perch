import AppKit
import SwiftUI

final class LabDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: URL
        if let path = Bundle.main.object(forInfoDictionaryKey: "KVMStorePath") as? String { store = URL(fileURLWithPath: path) }
        else {
            guard Bundle.main.bundleIdentifier == "local.perch.desk-preview" else { fatalError("The lab requires isolated storage") }
            store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch Desk Preview/demo-desk.json")
        }
        let model = DeskModel(store: store)
        let view = NSHostingView(rootView: DeskView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Perch Desk Preview") — simulated KVM"; window.contentView = view
        window.minSize = NSSize(width: 960, height: 768); window.center()
        self.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = LabDelegate(); app.delegate = delegate
let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Perch Desk Preview")", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = appMenu; menu.addItem(item)
let edit = NSMenuItem(), editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
edit.submenu = editMenu; menu.addItem(edit); app.mainMenu = menu
app.run()
