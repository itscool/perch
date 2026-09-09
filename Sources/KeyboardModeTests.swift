import Foundation

func runKeyboardModeTests() throws {
    try runKeyboardRefreshTests()
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    // A mock multi-host keyboard. Real hardware and system settings are untouched.
    for standard in [true,false] {
        var inversion: UInt8 = standard ? 1 : 0
        var writes = 0
        let request: KeyboardFnProtocol.Request = { feature, function, data in
            if feature == 0 { return [data == [0x40,0xA3] ? 7 : data == [0x18,0x15] ? 9 : 0] }
            if feature == 9 { return [0,0,0,2] }
            guard feature == 7, data.first == 2 else { throw AppError(message: "Request changed the wrong host") }
            if function == 0x10 { inversion = data[1]; writes += 1 }
            return [2,inversion]
        }
        try check(try KeyboardFnProtocol.apply(standard: standard, request: request), "Fn inversion was not updated")
        try check(inversion == (standard ? 0 : 1) && writes == 1, "Fn primary-mode polarity wrong")
        try check(try !KeyboardFnProtocol.apply(standard: standard, request: request), "Matching Fn mode was needlessly rewritten")
        try check(writes == 1, "Unnecessary firmware write")
    }
    for id: UInt16 in [0x40A0,0x40A2] {
        var state: UInt8 = 1
        _ = try KeyboardFnProtocol.apply(standard: true) { feature,function,data in
            if feature == 0 { return data == [UInt8(id >> 8),UInt8(id & 255)] ? [6] : [0] }
            if function == 0x10 { state = data[0] }
            return [state]
        }
        try check(state == 0,"Older Fn inversion feature failed")
    }
    var failedReadback = false
    do {
        _ = try KeyboardFnProtocol.apply(standard: true) { feature,_,data in feature == 0 ? (data == [0x40,0xA0] ? [5] : [0]) : [1] }
    } catch { failedReadback = true }
    try check(failedReadback,"Keyboard that ignored a write falsely appeared ready")
    var unsupported = false
    do { _ = try KeyboardFnProtocol.apply(standard: true) { _,_,_ in [0] } } catch { unsupported = true }
    try check(unsupported,"Unsupported keyboard falsely appeared ready")
    var invalidHost = false
    do { _ = try KeyboardFnProtocol.apply(standard: true) { feature,_,_ in feature == 0 ? [7] : [0,0,0,255] } } catch { invalidHost = true }
    try check(invalidHost,"Unknown host accepted for an Fn write")

    for current in [true, false] {
        var writes = 0
        let mode = try KeyboardFnProtocol.configure(standard: nil) { feature, function, data in
            if feature == 0 { return data == [0x40,0xA0] ? [5] : [0] }
            if function == 0x10 { writes += 1 }
            return [current ? 0 : 1]
        }
        try check(mode.standard == current && !mode.changed && writes == 0, "Reading firmware imposed a default mode")
    }
    let suite = "local.scott.perch.fn-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try check(NativeFunctionKeys.externalIntent(in: defaults) == nil, "External Fn invents a default")
    defaults.set(false, forKey: NativeFunctionKeys.externalIntentKey)
    try check(NativeFunctionKeys.externalIntent(in: defaults) == false, "Explicit media-first external mode was lost")
    for original in [true, false] {
        for externalBefore in [true, false] {
            var builtin = original, external = externalBefore
            var writes = 0
            try NativeFunctionKeys.changeBuiltIn(!original, readGlobal: { builtin }, writeGlobal: { value in
                builtin = value; external = value; writes += 1
            }, restoreExternal: { external = externalBefore })
            try check(builtin != original && external == externalBefore && writes == 1, "Built-in Fn changed external Fn")
            try NativeFunctionKeys.changeBuiltIn(!original, readGlobal: { builtin }, writeGlobal: { _ in writes += 1 }, restoreExternal: {})
            try check(writes == 1, "Matching built-in mode was rewritten")
        }
    }
    var builtin = false, external = true, restores = 0, failed = false
    do {
        try NativeFunctionKeys.changeBuiltIn(true, readGlobal: { builtin }, writeGlobal: { value in builtin = value; external = value }, restoreExternal: {
            restores += 1
            if restores == 1 { throw AppError(message: "Simulated external restore failure") }
            external = true
        })
    } catch { failed = true }
    try check(failed && !builtin && external && restores == 2, "Failed isolation didn't restore both keyboard groups")
    print("PASS: read-only firmware startup, no implicit Fn default, independent built-in/external modes, idempotence and failed-change rollback; mock hardware only")

    let packet: [UInt8] = [0x11,0xff,7,0x14] + Array(repeating:0,count:16)
    func parse(_ bytes: [UInt8], device: UInt8 = 0xff, feature: UInt8 = 7, function: UInt8 = 0x14) -> Result<[UInt8],AppError>? {
        bytes.withUnsafeBufferPointer { KeyboardFnProtocol.response($0,reportID:0x11,device:device,feature:feature,function:function) }
    }
    try check(parse(packet) != nil && parse(Array(packet.dropFirst())) != nil,"HID report framing failed")
    try check(parse(Array(packet.prefix(10))) == nil && parse(packet,device:1) == nil && parse(packet,function:0x15) == nil && parse(packet,feature:8) == nil,"Unrelated/truncated HID report accepted")
    var error = packet; error[2] = 0xff; error[3] = 7; error[4] = 0x14; error[5] = 3
    guard case .failure? = parse(error) else { throw AppError(message:"HID error wasn't matched") }
    try check(parse(error,function:0x15) == nil,"Other software's HID error accepted")

    let caps: [String:UInt64] = [ModifierKeyMap.source:0x700000039,ModifierKeyMap.destination:0x700000029]
    let option: [String:UInt64] = [ModifierKeyMap.source:0x7000000E2,ModifierKeyMap.destination:0x7000000E1]
    let original = [caps,option]
    let swapped = ModifierKeyMap.setting(true,in:original)
    try check(ModifierKeyMap.swapped(original) == false && ModifierKeyMap.swapped(swapped) == true,"Modifier swap doesn't cover both sides")
    try check(ModifierKeyMap.setting(false,in:swapped) == original,"Modifier unswap removed unrelated mappings")
    try check(ModifierKeyMap.setting(true,in:swapped) == swapped,"Repeated modifier application changes mappings")
    try check(ModifierKeyMap.swapped([swapped.last!]) == nil,"Partial modifier mapping appeared complete")
    print("PASS: Fn host selection, all three inversion features, readback, idempotence, unsupported/invalid/error replies, report framing/isolation; native Control/Command pairs preserve unrelated keys")
}
