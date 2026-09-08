import Foundation

func runLidSettingTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    for before in [true, false] {
        var actual = before
        let result = LidSettingChange.run(read: { actual }, write: { actual = $0 })
        try check(result.enabled == !before && result.error == nil, "Lid success reported the wrong state")
        try check(result.detail.contains("⚠ Keep ventilated") == !before, "Lid result warning disagrees with actual state")
        let cancelled = LidSettingChange.run(read: { actual }, write: { _ in throw AppError(message: "Authorization cancelled") })
        try check(cancelled.enabled == actual && cancelled.error != nil, "Cancelled lid authorization was reported as success")
        try check(cancelled.detail.contains("⚠ Keep ventilated") == actual, "Cancelled change lost the actual ventilation warning")
    }
    let ignored = LidSettingChange.run(read: { false }, write: { _ in })
    try check(ignored.enabled == false && ignored.title.hasSuffix("Off"), "Requested lid mode was mistaken for the actual mode")
    var writes = 0
    let unknown = LidSettingChange.run(read: { throw AppError(message: "Read failed") }, write: { _ in writes += 1 })
    try check(unknown.enabled == nil && writes == 0 && unknown.title.contains("Couldn’t confirm"), "Unknown lid state was treated as off or changed blindly")
    for enabled in [false,true] {
        var lid = !enabled
        var calls: [String] = []
        try SleepMasterChange.run(enabled:enabled,includeLid:true,readLid:{lid},writeLid:{lid=$0;calls.append("lid")},setAwake:{calls.append("awake:\($0)")},stopCaffeinate:{calls.append("stop")})
        try check(lid == enabled && calls == (enabled ? ["lid","awake:true"] : ["lid","awake:false","stop"]), "Master operation ordering or scope incorrect")
        var writesAfterDenial = 0
        do {
            try SleepMasterChange.run(enabled:enabled,includeLid:true,readLid:{!enabled},writeLid:{_ in throw AppError(message:"Cancelled")},setAwake:{_ in writesAfterDenial += 1},stopCaffeinate:{writesAfterDenial += 1})
            throw AppError(message:"Cancellation was swallowed")
        } catch { try check(writesAfterDenial == 0, "Cancellation changed the ordinary keep-awake setting") }
    }
    var followups = 0
    do {
        try SleepMasterChange.run(enabled:false,includeLid:true,readLid:{true},writeLid:{_ in},setAwake:{_ in followups += 1},stopCaffeinate:{followups += 1})
        throw AppError(message:"Unverified write was accepted")
    } catch { try check(followups == 0, "Unverified lid write continued master-off") }
    try check(SettingsResetSelection(sections:["preferences"]).removes(SleepMasterChange.lidPreferenceKey), "Awake reset retained lid preference")
    print("PASS: lid enabled/disabled results, cancellation preserves actual state, ventilation warning follows actual state, unknown state prevents a write; no macOS settings changed")
}
