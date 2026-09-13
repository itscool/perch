#!/usr/bin/env python3
"""Deterministic keypad state and panel-size tests; no devices, taps or windows."""
from pathlib import Path
import subprocess, tempfile
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-keypad-tests-') as folder:
 root=Path(folder)
 (root/'main.swift').write_text(r'''
import Foundation
var checks=0
func check(_ value: Bool, _ message: String) { checks += 1; precondition(value,message) }
let engine=KeypadNavigation(); engine.enabled=true; engine.setDevices([10,20])
func key(_ code: Int64, sender: UInt64=10, down: Bool=true, repeatKey: Bool=false, modifiers: Bool=false) -> KeypadNavigation.Output {
 engine.event(sender:sender,key:code,down:down,repeating:repeatKey,commandModifiers:modifiers)
}
func toggle(_ sender: UInt64=10) {
 check(key(71,sender:sender) == .suppress,"Num Lock down not consumed")
 check(key(71,sender:sender,repeatKey:true) == .suppress,"Repeat Num Lock escaped")
 check(key(71,sender:sender,down:false) == .suppress,"Num Lock up not consumed")
}
for sender: UInt64 in [0,30] { check(key(71,sender:sender) == .original,"Unknown/built-in toggled mode") }
check(engine.navigationSenders.isEmpty,"Num Lock should begin on")
check(key(83) == .original,"Number mode changed keypad")
toggle()
check(key(83,repeatKey:true) == .original && key(83,down:false) == .original,"Mode toggle split a held number")
check(engine.navigationSenders == [10],"Num Lock repeat toggled more than once or affected another device")
let expected: [(Int64,KeypadNavigation.Output)] = [(89,.key(115,0xF729)),(91,.key(126,0xF700)),(92,.key(116,0xF72C)),(86,.key(123,0xF702)),(87,.suppress),(88,.key(124,0xF703)),(83,.key(119,0xF72B)),(84,.key(125,0xF701)),(85,.key(121,0xF72D)),(82,.key(114,0xF727)),(65,.key(117,0xF728))]
for (source,target) in expected {
 check(key(source) == target,"Wrong navigation key")
 check(key(source,repeatKey:true) == target && key(source,down:false) == target,"Unbalanced navigation repeat/release")
 check(key(source,sender:20) == .original && key(source,sender:20,down:false) == .original,"Another keypad changed")
}
for code: Int64 in [0,18,19,36,53,67,69,75,76,78,81,123] { check(key(code) == .original,"Unrelated key/operator changed") }
check(key(71,modifiers:true) == .original && key(71,down:false) == .original,"Modified Clear shortcut intercepted")
check(engine.navigationSenders == [10],"Modified Clear toggled mode")
check(key(91) == .key(126,0xF700),"Up mapping missing")
engine.enabled=false; engine.navigationDisabled(); engine.setDevices([])
check(key(91,repeatKey:true) == .key(126,0xF700) && key(91,down:false) == .key(126,0xF700),"Disable/disconnect split held navigation")
check(key(91) == .original,"Disabled feature transforms keys")
engine.enabled=true; engine.setDevices([10,20]); toggle()
engine.reset(keepingMode:true); check(engine.navigationSenders == [10],"Rebuilding scroll tap lost Num Lock mode")
engine.setDevices([10,20,30]); check(engine.navigationSenders == [10],"Unrelated connection reset Num Lock")
engine.setDevices([20]); check(engine.navigationSenders.isEmpty,"Disconnected keypad mode retained")
engine.setDevices([10,20]); toggle(); engine.reset(); check(engine.navigationSenders.isEmpty && !engine.hasHeldKeys,"Wake reset retained mode/held keys")
for enabled in [false,true] { for nav in [false,true] { for sender: UInt64 in [0,10,20,30] { for (source,mapping) in expected {
 engine.reset(); engine.enabled=true; engine.setDevices([10,20]); if nav { toggle() }; engine.enabled=enabled
 let down=key(source,sender:sender)
 check(down == (enabled && nav && sender==10 ? mapping : .original),"State combination failed")
 engine.enabled.toggle()
 check(key(source,down:false,sender:sender) == down,"Preference change split down/up")
}}}}
for (inches,ratio) in [(27.0,16.0/9.0),(32.0,16.0/9.0),(34.0,21.0/9.0),(49.0,32.0/9.0)] {
 let size=DeskPhysicalSize.estimate(inches:inches,aspect:ratio)!
 check(abs(hypot(size.width,size.height)/25.4-inches)<0.00001 && abs(size.width/size.height-ratio)<0.00001,"Physical estimate lost diagonal or aspect")
}
check(abs(DeskPhysicalSize.estimate(inches:27,aspect:16.0/9.0)!.width-597.7275)<0.01,"27-inch panel width incorrect")
for bad in [0.0,-1,Double.infinity,Double.nan,301] { check(DeskPhysicalSize.estimate(inches:bad,aspect:16.0/9.0)==nil,"Invalid diagonal accepted") }
print("PASS: \(checks) keypad isolation/toggle/repeat/release/lifecycle and panel-size checks; no devices or event posting")
'''.replace('key(source,down:false,sender:sender)','key(source,sender:sender,down:false)'))
 subprocess.run(['xcrun','swiftc',str(repo/'Sources/KeypadNavigation.swift'),str(repo/'Sources/DeskCanvasLayout.swift'),str(root/'main.swift'),'-o',str(root/'check')],check=True)
 subprocess.run([str(root/'check')],check=True)
