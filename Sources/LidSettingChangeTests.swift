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
    print("PASS: lid enabled/disabled results, cancellation preserves actual state, ventilation warning follows actual state, unknown state prevents a write; no macOS settings changed")
}
