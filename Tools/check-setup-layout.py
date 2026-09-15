#!/usr/bin/env python3
"""Render production setup controls and test disclosure without windows or OS writes."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import argparse, subprocess, tempfile
p=argparse.ArgumentParser(description=__doc__); p.add_argument('--output', type=Path, required=True); args=p.parse_args()
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-setup-layout-') as tmp:
    root=Path(tmp)
    access=(perch_source('LaunchAccessRecovery.swift')).read_text()
    access=access[:access.index('struct StartupKeyboardAccessNotice')] + access[access.index('final class KeyboardAccessPage'):]
    (root/'Access.swift').write_text(access)
    source=(perch_source('PermissionSetup.swift')).read_text()
    constructor=source[:source.index('    func show(')]
    present=source[source.index('    private func present('):source.index('    @objc func openSettings')].replace('private func present(', 'func present(')
    (root/'Permission.swift').write_text(constructor + present + '\n func refresh() {}\n @objc func openSettings() {}\n}\n')
    source=(perch_source('EventSetup.swift')).read_text()
    source=source[:source.index('    func show(')]
    (root/'Events.swift').write_text(source + '\n func refresh() {}\n func installCollector() {}\n @objc func nextStep() {}\n @objc func openPrivacySettings() {}\n}\n')
    (root/'Stubs.swift').write_text('''import AppKit
final class SettingsStatusField: NSTextField {}
final class SettingsActionButton: NSButton {
 let perform: () -> Void
 init(title: String, action: @escaping () -> Void) { perform = action; super.init(frame: .zero); self.title=title; bezelStyle = .rounded; target=self; self.action = #selector(run) }
 required init?(coder: NSCoder) { fatalError() }
 @objc func run() { perform() }
}
final class SettingsWindow {
 static let shared=SettingsWindow()
 struct Poll { init(every: TimeInterval, whileBusy: Bool = false, _ body: @escaping () -> Void) {} }
 struct Page { var title: String; var detail: String; var view: NSView; var leave: (() -> Void)?; var refresh: (() -> Void)?; var poll: Poll? = nil }
 var pages: [Page]=[]; var interactionBusy=false; let testing=false
 func pollTimer(for view: NSView) -> Timer? { nil }
 func afterInteraction(_ body: @escaping () -> Void) { body() }
 func show(_ page: Page) { pages=[page] }
 func display(_ page: Page) {}
 func navigateToSetupStage(_ id: String) { fatalError("No navigation in offscreen fixture") }
 func handoffToExternalApp(_ action: () -> Bool) { fatalError("No OS handoffs in offscreen fixture") }
}
struct LidHelperStartupUpdate { mutating func claim(pending: Bool, available: Bool) -> Bool { false } }
final class LidHelperUpdate { static let shared=LidHelperUpdate(); let busy=false }
final class AppUpdate { static let shared=AppUpdate(); let busy=false }
final class PerchUpdater { static let shared=PerchUpdater(); let busy=false }
enum GuardianInstall { static let inputPermissionApp: URL?=nil }
enum SafetyFiles { static let helperApp=URL(fileURLWithPath:"/fixture/Perch Helper.app") }
struct InputReadiness { var ready: Bool; var title: String; var message: String; var route: String }
enum CollectorIdentity { static let launcher="/Applications/Perch.app/Contents/MacOS/PerchEventLauncher" }
enum ProcessEventStream { static let pipePath="/fixture/pipe" }
enum StatusColors { static let warning=NSColor.systemOrange; static let success=NSColor.systemGreen }
''')
    (root/'main.swift').write_text(r'''
import AppKit
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
func check(_ value: Bool, _ message: String) { precondition(value, message) }
let sidebar=SettingsSidebar(frame:NSRect(x:0,y:0,width:220,height:250))
var sidebarStatus=SettingsSetupStatus.checking, navigations=0
sidebar.readSetupStatus={ ["access":sidebarStatus] }; sidebar.choose={ _ in navigations += 1 }
sidebar.configure([.init(id:"access",title:"Keyboard access",pageTitles:[],depth:1,setupStage:true,open:{})])
sidebar.layoutSubtreeIfNeeded(); sidebar.update(selected:"access",busy:false)
let cell=sidebar.table.view(atColumn:0,row:0,makeIfNecessary:true) as! NSTableCellView
for state: SettingsSetupStatus in [.ready,.attention,.optional,.checking] {
 sidebarStatus=state; sidebar.refreshSetupStatus()
 check(sidebar.table.selectedRow==0 && navigations==0,"Status refresh changed navigation")
 check(sidebar.table.view(atColumn:0,row:0,makeIfNecessary:false) === cell && cell.accessibilityValue() as? String == state.rawValue,"Status replaced its cell or accessible state is wrong")
}
var state=SetupDisclosure()
state.update(ready: false); state.toggle(); check(state.expanded, "Required instructions collapsed")
state.update(ready: true); check(!state.expanded, "Ready instructions did not collapse")
state.toggle(); state.update(ready: true); check(state.expanded, "Unchanged polling lost manual expansion")
state.update(ready: false); state.toggle(); check(state.expanded, "Revocation could be hidden")
state.update(ready: true); check(!state.expanded, "Restored readiness retained required expansion")
var granted=false
let keyboard=KeyboardAccessPage(readAccess:{granted}, recheck:{}, openSettings:{ fatalError("OS action") })
keyboard.show()
let host=SettingsWindow.shared
func top(_ view: NSView, _ child: NSView) -> CGFloat { view.frame.height-child.frame.maxY }
let statusTop=top(keyboard.view, keyboard.status)
let instructionButton=keyboard.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Permission instructions" }!
let buttonTop=top(keyboard.view, instructionButton)
check(!instructionButton.isEnabled && !keyboard.instructions.isHidden, "Required keyboard instructions not fixed open")
granted=true; keyboard.refresh()
check(keyboard.instructions.isHidden && instructionButton.isEnabled, "Ready keyboard instructions not optional")
check(top(keyboard.view,keyboard.status)==statusTop && top(keyboard.view,instructionButton)==buttonTop, "Keyboard status/disclosure moved")
instructionButton.performClick(nil)
check(!keyboard.instructions.isHidden && top(keyboard.view,keyboard.status)==statusTop, "Showing instructions displaced status")
granted=false; keyboard.refresh()
check(!instructionButton.isEnabled, "Lost access left instructions collapsible")
let input=PermissionSetup(helperApp:{ URL(fileURLWithPath:"/fixture/Perch Helper.app") })
input.present(.init(ready:false,title:"",message:"Accessibility needs attention",route:"input"))
let inputTop=top(input.content,input.status), inputButtonTop=top(input.content,input.reviewButton)
input.present(.init(ready:true,title:"",message:"Accessibility ready",route:"input"))
check(top(input.content,input.status)==inputTop && top(input.content,input.reviewButton)==inputButtonTop && input.instructions.isHidden, "Helper status moved on readiness")
let events=EventCollectorSetup()
events.intro.stringValue="Agent tracking"
events.installState.stringValue="✓ Collector installed"
events.accessState.stringValue="⚠ Full Disk Access needs attention"
events.readyState.stringValue="Waiting to receive events"
events.guidance.stringValue="Drag eslogger into Full Disk Access and enable it. If events still do not arrive, add PerchEventLauncher as well.\n\nKeyboard: focus a file below and press Space to copy its path. In System Settings choose +, press ⌘⇧G, paste, then Open."
events.review.title="Permission instructions"; events.review.isEnabled=false; events.primary.isHidden=true
check(events.permissionDrag.frame.minY==events.launcherDrag.frame.minY && events.permissionDrag.frame.height==events.launcherDrag.frame.height, "Collector targets are staggered")
check(!events.permissionDrag.frame.intersects(events.openSettings.frame) && !events.launcherDrag.frame.intersects(events.openSettings.frame), "Collector controls overlap")
let canvas=NSView(frame:NSRect(x:0,y:0,width:620,height:580))
canvas.wantsLayer=true; canvas.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
canvas.appearance=NSAppearance(named:.aqua)
events.content.frame.origin=NSPoint(x:30,y:35); canvas.addSubview(events.content)
canvas.layoutSubtreeIfNeeded()
let bitmap=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds)!
canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
check(NSApp.windows.isEmpty,"Offscreen fixture presented a window")
print("PASS: required/ready/review/lost/restored disclosure, stable status and disclosure anchors, aligned permission targets, no windows or OS writes")
''')
    files=[perch_source('MainTimer.swift'), perch_source('SetupDisclosure.swift'), perch_source('PermissionDragItem.swift'), perch_source('SettingsSidebar.swift')]+list(root.glob('*.swift'))
    subprocess.run(['xcrun','swiftc','-o',str(root/'check')]+[str(f) for f in files],check=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([str(root/'check'),str(args.output.resolve())],check=True)
